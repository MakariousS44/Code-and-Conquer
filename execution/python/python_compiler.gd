## python_compiler.gd
## Generates student Python code for the platform IPC transport.
## The sandbox worker owns interpreter selection and process launch.

extends RefCounted

const Paths = preload("res://execution/shared/paths.gd")
var _commands = preload(Paths.ROBOT_COMMANDS).new()
var _runtime_assets = preload(Paths.RUNTIME_ASSETS).new()

func prepare_sandbox_files(
	player_code: String,
	sandbox_path: String,
	ipc_endpoint: String
) -> Dictionary:
	var bootstrap := ""
	match OS.get_name():
		"Windows":
			bootstrap = _commands.get_python_pipe_bootstrap(ipc_endpoint)
		"Linux", "macOS":
			bootstrap = _commands.get_python_unix_bootstrap(ipc_endpoint)
		_:
			return {
				"ok": false,
				"message": "Python execution is not supported on this OS."
			}

	var script := bootstrap + "\n" + _commands.get_python_runner(player_code)
	var script_path := sandbox_path.path_join("student_program.py")
	var file := FileAccess.open(script_path, FileAccess.WRITE)

	if file == null:
		return {
			"ok": false,
			"message": "Could not write the secure Python program."
		}

	file.store_string(script)
	file.close()

	return {
		"ok": true,
		"script_path": script_path
	}


func is_available() -> bool:
	var tag := _runtime_assets.platform_tag()
	if tag.is_empty():
		return false
	var runtime_path := _runtime_assets.python_payload_path()
	if runtime_path.is_empty():
		return false
	if OS.get_name() == "Windows":
		return FileAccess.file_exists(runtime_path.path_join("python.exe"))
	return DirAccess.dir_exists_absolute(runtime_path.path_join("bin"))
