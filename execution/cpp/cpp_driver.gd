extends RefCounted

const BUILD_DIR := "user://build"
const Paths = preload("res://execution/shared/paths.gd")

var _commands = preload(Paths.ROBOT_COMMANDS).new()
var _runtime_assets = preload(Paths.RUNTIME_ASSETS).new()
var _active_build_dir: String = ""
var _prepare_error: String = ""
var _prepare_reason: String = ""
static var _compiler: String = ""
static var _compiler_probed := false
static var _compiler_version_output: Array = []


func _get_exe_path() -> String:
	var base := _active_build_dir.path_join("student_program")
	return base + ".exe" if OS.get_name() == "Windows" else base


func prepare_build_files(source: String, sandbox_path: String = "", ipc_endpoint: String = "") -> bool:
	_prepare_error = ""
	_prepare_reason = ""
	_active_build_dir = ""
	var tag := _runtime_assets.platform_tag()
	if tag.is_empty():
		_prepare_error = "C++ execution is not supported on this OS or architecture."
		_prepare_reason = "unsupported_platform"
		return false

	var runtime_source := ""
	match OS.get_name():
		"Windows":
			runtime_source = _commands.get_cpp_pipe_source()
		"Linux", "macOS":
			runtime_source = _commands.get_cpp_unix_source()
		_:
			_prepare_error = "C++ execution is not supported on this OS."
			_prepare_reason = "unsupported_platform"
			return false

	var build_dir := sandbox_path if not sandbox_path.is_empty() else ProjectSettings.globalize_path(BUILD_DIR)
	_active_build_dir = build_dir
	DirAccess.make_dir_recursive_absolute(build_dir)
	var files := {
		"student_code.cpp": source,
		"robot.hpp": _commands.get_cpp_header(),
		"robot_runtime.cpp": runtime_source,
	}
	for name in files:
		if not _write_file(build_dir.path_join(name), files[name]):
			_prepare_error = "Failed to write C++ build files."
			_prepare_reason = "prepare_error"
			return false
	return true


func get_prepare_error() -> String:
	return _prepare_error


func get_prepare_reason() -> String:
	return _prepare_reason


func is_platform_supported() -> bool:
	return not _runtime_assets.platform_tag().is_empty()


func detect_compiler() -> bool:
	return _find_compiler() != ""


func is_available() -> bool:
	return is_platform_supported() and detect_compiler()


func compile_program() -> Dictionary:
	var output: Array = []
	if not _prepare_error.is_empty():
		return {
			"ok": false,
			"output": _prepare_error,
			"reason": _prepare_reason if not _prepare_reason.is_empty() else "prepare_error",
			"exe_path": ""
		}
	if _active_build_dir.is_empty():
		return {
			"ok": false,
			"output": "No build directory was prepared.",
			"reason": "internal_error",
			"exe_path": ""
		}

	var compiler := _find_compiler()
	if compiler.is_empty():
		return {
			"ok": false,
			"output": "A C++ compiler was not found.",
			"reason": "no_compiler",
			"exe_path": ""
		}

	var student_cpp := _active_build_dir.path_join("student_code.cpp")
	var robot_cpp := _active_build_dir.path_join("robot_runtime.cpp")
	var exe := _get_exe_path()

	var args := ["-std=c++17", "-Wall", "-Wextra"]
	if OS.get_name() == "Windows":
		args.append("-static")
	var runtime_key := (compiler + str(_compiler_version_output) + str(args) + FileAccess.get_file_as_string(robot_cpp)
		+ FileAccess.get_file_as_string(_active_build_dir.path_join("robot.hpp"))).sha256_text()
	var build_key := (runtime_key + FileAccess.get_file_as_string(student_cpp)).sha256_text()
	var cache_path := _active_build_dir.path_join("compile_cache.cfg")
	var cache := ConfigFile.new()
	cache.load(cache_path)
	var exe_hash := FileAccess.get_sha256(exe)
	if cache.get_value("build", "key", "") == build_key and exe_hash != "" \
			and cache.get_value("build", "exe_hash", "") == exe_hash:
		return {"ok": true, "output": "", "exe_path": exe, "cached": true}

	# Student edits reuse the compiled robot runtime.
	var runtime_object := _active_build_dir.path_join("robot_runtime.o")
	var runtime_reused := false
	if cache.get_value("runtime", "key", "") == runtime_key and FileAccess.file_exists(runtime_object):
		runtime_reused = cache.get_value("runtime", "object_hash", "") == FileAccess.get_sha256(runtime_object)
	if not runtime_reused:
		var runtime_args := args.duplicate()
		runtime_args.append_array(["-c", robot_cpp, "-o", runtime_object])
		if OS.execute(compiler, runtime_args, output, true) != 0:
			return {"ok": false, "output": "\n".join(output), "reason": "compile_error", "exe_path": ""}
		var runtime_object_hash := FileAccess.get_sha256(runtime_object)
		if runtime_object_hash.is_empty():
			return {
				"ok": false,
				"output": "Compiled robot runtime could not be hashed.",
				"reason": "internal_error",
				"exe_path": ""
			}
		cache.set_value("runtime", "key", runtime_key)
		cache.set_value("runtime", "object_hash", runtime_object_hash)
		cache.save(cache_path)

	# Failed builds must not reuse an older successful executable.
	if cache.has_section("build"):
		cache.erase_section("build")
	cache.save(cache_path)
	if FileAccess.file_exists(exe):
		DirAccess.remove_absolute(exe)
	args.append_array([student_cpp, runtime_object, "-o", exe])
	if OS.get_name() == "Windows":
		args.append("-lws2_32")

	# Discard runtime compile output so its warnings aren't misattributed to student code.
	output.clear()

	var exit_code := OS.execute(compiler, args, output, true)
	var diagnostics := "\n".join(output)
	if exit_code == 0:
		cache.set_value("build", "key", build_key)
		cache.set_value("build", "exe_hash", FileAccess.get_sha256(exe))
	cache.save(cache_path)
	return {
		"ok": exit_code == 0,
		"output": diagnostics,
		"reason": "" if exit_code == 0 else "compile_error",
		"cached": false,
		"exe_path": exe if exit_code == 0 else ""
	}


func remap_diagnostics(raw_text: String, line_offset: int) -> String:
	var result: Array[String] = []

	for line in raw_text.split("\n"):
		if line.strip_edges() == "":
			continue

		# Skip compiler context lines not useful to the student
		if "In function" in line or "In member" in line or "note:" in line:
			continue

		# Skip g++ code context lines: "6 | move()" / "| ^" / "| ~" / "| ;"
		var trimmed := line.strip_edges()
		if trimmed.begins_with("| ") or trimmed == "|":
			continue
		if trimmed.length() > 2 and trimmed[0].is_valid_int() and " | " in trimmed:
			continue

		if "undefined reference" in trimmed or "multiple definition" in trimmed or "Permission denied" in trimmed:
			result.append(trimmed)
			continue

		var parts := line.split(":")
		# Determine path offset for Windows drive letters
		var offset := 0
		if parts.size() > 1 and parts[0].length() == 1 and parts[0][0].to_upper() == parts[0][0]:
			offset = 1

		if parts.size() >= (4 + offset) and parts[1 + offset].strip_edges().is_valid_int():
			var line_num := int(parts[1 + offset].strip_edges())
			var severity_and_msg := ":".join(parts.slice(3 + offset)).strip_edges()
			var student_line : int = max(1, line_num - line_offset)
			result.append("%s (line %d)" % [severity_and_msg, student_line])
		else:
			if trimmed.begins_with("/") or (trimmed.length() > 1 and trimmed[1] == ":"):
				continue
			result.append(line)

	return "\n".join(result)


func _find_compiler() -> String:
	if not _compiler.is_empty():
		return _compiler
	if _compiler_probed:
		return ""
	_compiler_probed = true
	for candidate in ["g++", "clang++", "c++"]:
		var output: Array = []
		if OS.execute(candidate, ["--version"], output, true) == 0:
			_compiler_version_output = output
			_compiler = candidate
			return _compiler
	return ""


func _write_file(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open file for writing: " + path)
		return false
	if not f.store_string(text):
		f.close()
		push_error("Failed to write file: " + path)
		return false
	f.close()
	return true
