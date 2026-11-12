extends SceneTree

const Commands = preload("res://execution/shared/robot_commands.gd")
const Assets = preload("res://execution/shared/runtime_assets.gd")

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run_tests")


func run_tests() -> void:
	var commands = Commands.new()
	var assets = Assets.new()
	var tag := assets.platform_tag()

	check(not tag.is_empty(), "Current OS/architecture should resolve to a supported runtime tag")
	check(assets.worker_file_name() in ["sandbox_runner", "sandbox_runner.exe"], "Worker file name should be platform-aware")
	check(not assets.worker_payload_path().is_empty(), "Worker payload path should resolve")
	check(not assets.python_payload_path().is_empty(), "Python payload path should resolve")

	var unix_cpp := commands.get_cpp_unix_source()
	check(unix_cpp.contains("AF_UNIX"), "POSIX C++ runtime should use AF_UNIX")
	check(not unix_cpp.contains("windows.h"), "POSIX C++ runtime must not include windows.h")
	check(unix_cpp.contains("connection.txt"), "POSIX C++ runtime should read connection.txt")

	var unix_python := commands.get_python_unix_bootstrap("/tmp/cnc-test/student.sock")
	check(unix_python.contains("AF_UNIX"), "POSIX Python bootstrap should use AF_UNIX")
	check(unix_python.contains("/tmp/cnc-test/student.sock"), "POSIX Python bootstrap should embed the socket path")
	check(not unix_python.contains("CreateFile"), "POSIX Python bootstrap must not use Windows pipe APIs")

	var pipe_cpp := commands.get_cpp_pipe_source()
	check(pipe_cpp.contains("windows.h"), "Windows C++ runtime should still target named pipes")
	check(pipe_cpp.contains("connection.txt"), "Windows C++ runtime should read connection.txt")

	var pipe_python := commands.get_python_pipe_bootstrap("\\\\.\\pipe\\CodeAndConquer-test")
	check(pipe_python.contains("CodeAndConquer-test"), "Windows Python bootstrap should embed the pipe name")
	check(pipe_python.contains("open("), "Windows Python bootstrap should open the pipe path")

	print("PORTABILITY TESTS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
