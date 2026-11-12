extends RefCounted

const CACHE_VERSION := 2
const WORKER_DIR := "sandbox_worker/bin"
const PYTHON_DIR := "sandbox_worker/runtime"


func platform_tag() -> String:
	var os_name := OS.get_name()
	var arch := ""
	if OS.has_feature("arm64"):
		arch = "arm64"
	elif OS.has_feature("x86_64"):
		arch = "x86_64"

	match os_name:
		"Windows":
			if arch == "x86_64":
				return "windows-x86_64"
		"Linux":
			if arch == "x86_64":
				return "linux-x86_64"
		"macOS":
			if arch == "arm64":
				return "macos-arm64"
	return ""


func worker_file_name() -> String:
	return "sandbox_runner.exe" if OS.get_name() == "Windows" else "sandbox_runner"


func worker_payload_path() -> String:
	var tag := platform_tag()
	if tag.is_empty():
		return ""
	var res_path := "res://%s/%s/%s" % [WORKER_DIR, tag, worker_file_name()]
	if not OS.has_feature("template"):
		return ProjectSettings.globalize_path(res_path)
	var staged := ensure_worker()
	if not staged.get("ok", false):
		push_warning("Sandbox worker unavailable: " + str(staged.get("message", "unknown error")))
		return ""
	return str(staged.get("path", ""))


func python_payload_path() -> String:
	var tag := platform_tag()
	if tag.is_empty():
		return ""
	var res_path := "res://%s/%s/python" % [PYTHON_DIR, tag]
	if not OS.has_feature("template"):
		return ProjectSettings.globalize_path(res_path)
	var staged := ensure_python_runtime()
	if not staged.get("ok", false):
		push_warning("Python runtime unavailable: " + str(staged.get("message", "unknown error")))
		return ""
	return str(staged.get("path", ""))


func ensure_worker() -> Dictionary:
	var tag := platform_tag()
	if tag.is_empty():
		return _error("Unsupported OS or architecture for the sandbox worker.")
	var src := "res://%s/%s" % [WORKER_DIR, tag]
	var dst := "user://runtime/v%d/bin/%s" % [CACHE_VERSION, tag]
	var marker := dst.path_join(".complete")
	if not FileAccess.file_exists(marker):
		var copy_result := _copy_directory(src, dst)
		if not copy_result.ok:
			return copy_result
		var marker_file := FileAccess.open(marker, FileAccess.WRITE)
		if marker_file == null:
			return _error("Could not finalize the sandbox worker cache: " + marker)
		marker_file.store_string("ok")
		marker_file.close()
	var exe := dst.path_join(worker_file_name())
	if not FileAccess.file_exists(exe):
		return _error("Sandbox worker executable was not found in the payload: " + exe)
	if OS.get_name() != "Windows":
		_make_executable(exe)
	return {"ok": true, "path": ProjectSettings.globalize_path(exe), "message": ""}


func ensure_python_runtime() -> Dictionary:
	var tag := platform_tag()
	if tag.is_empty():
		return _error("Unsupported OS or architecture for the Python runtime.")
	var src := "res://%s/%s/python" % [PYTHON_DIR, tag]
	var dst := "user://runtime/v%d/python/%s/python" % [CACHE_VERSION, tag]
	var marker := dst.path_join(".complete")
	if not FileAccess.file_exists(marker):
		var copy_result := _copy_directory(src, dst)
		if not copy_result.ok:
			return copy_result
		var marker_file := FileAccess.open(marker, FileAccess.WRITE)
		if marker_file == null:
			return _error("Could not finalize the Python runtime cache: " + marker)
		marker_file.store_string("ok")
		marker_file.close()
	if OS.get_name() == "Windows":
		if not FileAccess.file_exists(dst.path_join("python.exe")):
			return _error("Bundled python.exe was not found in the Python runtime payload.")
	else:
		if not DirAccess.dir_exists_absolute(dst.path_join("bin")):
			return _error("Bundled Python bin directory was not found in the Python runtime payload.")
		_make_tree_executable(dst)
		_make_executable_dir(dst.path_join("bin"))
	return {"ok": true, "path": ProjectSettings.globalize_path(dst), "message": ""}


func _copy_directory(src: String, dst: String) -> Dictionary:
	var src_dir := DirAccess.open(src)
	if src_dir == null:
		return _error("Payload directory was not found: " + src)

	var dst_absolute := ProjectSettings.globalize_path(dst)
	var make_error := DirAccess.make_dir_recursive_absolute(dst_absolute)
	if make_error != OK and not DirAccess.dir_exists_absolute(dst_absolute):
		return _error("Could not create runtime cache directory: " + dst_absolute)

	for file_name in src_dir.get_files():
		if file_name.ends_with(".gdignore") or file_name.ends_with(".import"):
			continue
		var copy_error := _copy_file(src.path_join(file_name), dst.path_join(file_name))
		if copy_error != OK:
			return _error("Could not copy runtime payload file: " + file_name)

	for dir_name in src_dir.get_directories():
		var copy_result := _copy_directory(src.path_join(dir_name), dst.path_join(dir_name))
		if not copy_result.get("ok", false):
			return copy_result

	return {"ok": true}


func _copy_file(src: String, dst: String) -> int:
	var input := FileAccess.open(src, FileAccess.READ)
	if input == null:
		return ERR_FILE_NOT_FOUND
	var bytes := input.get_buffer(input.get_length())
	input.close()
	var output := FileAccess.open(dst, FileAccess.WRITE)
	if output == null:
		return ERR_FILE_CANT_WRITE
	output.store_buffer(bytes)
	output.close()
	return OK


func _make_executable(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	OS.execute("chmod", ["+x", absolute], [], true)


func _make_executable_dir(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	OS.execute("chmod", ["-R", "u+x", absolute], [], true)


func _make_tree_executable(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	OS.execute("chmod", ["-R", "u+rwX,go-rwx", absolute], [], true)


func _error(message: String) -> Dictionary:
	return {"ok": false, "path": "", "message": message}
