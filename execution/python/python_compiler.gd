## python_compiler.gd
## Generates and launches student Python code as a non-blocking subprocess.
## All protocol communication goes through the TCP socket, not stdout.

extends RefCounted

const Paths = preload("res://execution/shared/paths.gd")
var _commands = preload(Paths.ROBOT_COMMANDS).new()

## Write the generated script and launch it. Returns OS PID or -1 on failure.
func start(player_code: String, port: int) -> int:
	var python_info := _find_python()
	if python_info.is_empty():
		return -1

	var python_exe: String = str(python_info.get("exe", ""))
	var python_args: Array = python_info.get("args", [])

	var script := _commands.get_python_bootstrap(port) \
				+ "\n" + _commands.get_python_runner(player_code)

	var tmp_path := OS.get_temp_dir().path_join("_player_code.py")
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return -1
	f.store_string(script)
	f.close()

	var run_args: Array = python_args.duplicate()
	run_args.append(tmp_path)
	return OS.create_process(python_exe, run_args)

func _find_python() -> Dictionary:
	var candidates: Array[Dictionary] = [
		{ "exe": "python3", "args": [] },
		{ "exe": "python",  "args": [] },
		{ "exe": "py",      "args": ["-3"] },
		{ "exe": "py",      "args": [] },
	]
	for candidate in candidates:
		var out: Array = []
		var args: Array = candidate.get("args", []).duplicate()
		args.append("--version")
		if OS.execute(str(candidate.get("exe", "")), args, out, true) == 0:
			return candidate
	return {}
