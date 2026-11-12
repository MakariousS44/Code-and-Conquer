extends RefCounted

const BUILD_DIR := "user://build"
const Paths = preload("res://execution/shared/paths.gd")

var _commands = preload(Paths.ROBOT_COMMANDS).new()
var _runtime_assets = preload(Paths.RUNTIME_ASSETS).new()
var _active_build_dir: String = ""
var _prepare_error: String = ""
var _compiler: String = ""


func _get_exe_path() -> String:
	var base := _active_build_dir.path_join("student_program")
	return base + ".exe" if OS.get_name() == "Windows" else base


func prepare_build_files(source: String, sandbox_path: String = "", ipc_endpoint: String = "") -> bool:
	_prepare_error = ""
	_active_build_dir = ""
	var tag := _runtime_assets.platform_tag()
	if tag.is_empty():
		_prepare_error = "C++ execution is not supported on this OS or architecture."
		return false

	var runtime_source := ""
	match OS.get_name():
		"Windows":
			runtime_source = _commands.get_cpp_pipe_source()
		"Linux", "macOS":
			runtime_source = _commands.get_cpp_unix_source()
		_:
			_prepare_error = "C++ execution is not supported on this OS."
			return false

	var build_dir := sandbox_path if not sandbox_path.is_empty() else ProjectSettings.globalize_path(BUILD_DIR)
	_active_build_dir = build_dir
	DirAccess.make_dir_recursive_absolute(build_dir)
	_write_file(build_dir.path_join("student_code.cpp"), source)
	_write_file(build_dir.path_join("robot.hpp"), _commands.get_cpp_header())
	_write_file(build_dir.path_join("robot_runtime.cpp"), runtime_source)
	return true


func is_available() -> bool:
	return not _runtime_assets.platform_tag().is_empty() and _find_compiler() != ""


func compile_program() -> Dictionary:
	var output: Array = []
	if not _prepare_error.is_empty():
		return {
			"ok": false,
			"output": _prepare_error,
			"exe_path": ""
		}
	if _active_build_dir.is_empty():
		return {
			"ok": false,
			"output": "No build directory was prepared.",
			"exe_path": ""
		}

	var compiler := _find_compiler()
	if compiler.is_empty():
		return {
			"ok": false,
			"output": "A C++ compiler was not found.",
			"exe_path": ""
		}

	var student_cpp := _active_build_dir.path_join("student_code.cpp")
	var robot_cpp := _active_build_dir.path_join("robot_runtime.cpp")
	var exe := _get_exe_path()

	if FileAccess.file_exists(exe):
		DirAccess.remove_absolute(exe)

	var args := ["-std=c++17", "-Wall", "-Wextra"]
	if OS.get_name() == "Windows":
		args.append("-static")
	args.append_array([student_cpp, robot_cpp, "-o", exe])
	if OS.get_name() == "Windows":
		args.append("-lws2_32")

	var exit_code := OS.execute(compiler, args, output, true)
	return {
		"ok": exit_code == 0,
		"output": "" if output.is_empty() else str(output[0]),
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
	for candidate in ["g++", "clang++", "c++"]:
		var output: Array = []
		if OS.execute(candidate, ["--version"], output, true) == 0:
			_compiler = candidate
			return _compiler
	return ""


func _write_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open file for writing: " + path)
		return
	f.store_string(text)
