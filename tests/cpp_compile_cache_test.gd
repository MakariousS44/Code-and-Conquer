extends SceneTree

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func timed_compile(driver, label: String) -> Dictionary:
	var start := Time.get_ticks_msec()
	var result: Dictionary = driver.compile_program()
	print("%s: %d ms" % [label, Time.get_ticks_msec() - start])
	return result

func _initialize() -> void:
	var driver = load("res://execution/cpp/cpp_driver.gd").new()
	var generator = load("res://execution/cpp/cpp_generator.gd").new()
	var folder := OS.get_temp_dir().path_join("cpp-cache-test-%d" % OS.get_process_id())
	var source: String = generator.generate('#include "robot.hpp"\nint main() { move(); return 0; }').generated_source
	driver.prepare_build_files(source, 0, "", folder)
	var output: Array = []
	var start := Time.get_ticks_msec()
	var baseline := OS.execute("g++", ["-std=c++17", "-Wall", "-Wextra", "-static", folder.path_join("student_code.cpp"), folder.path_join("robot_runtime.cpp"), "-o", folder.path_join("baseline.exe"), "-lws2_32"], output, true)
	print("Previous full build: %d ms" % (Time.get_ticks_msec() - start))
	check(baseline == 0, "Baseline must compile: " + str(output))
	var cold := timed_compile(driver, "First cached build")
	check(cold.ok, "Cold compile must succeed: " + cold.output)
	var repeated := timed_compile(driver, "Unchanged code")
	check(repeated.ok and repeated.cached, "Unchanged source must reuse the executable")
	var object_hash := FileAccess.get_sha256(folder.path_join("robot_runtime.o"))
	driver.prepare_build_files(source.replace("return 0", "turn_left(); return 0"), 0, "", folder)
	var edited := timed_compile(driver, "Edited student code")
	check(edited.ok and not edited.cached, "Edited source must be compiled")
	check(FileAccess.get_sha256(folder.path_join("robot_runtime.o")) == object_hash, "Student edits must reuse the robot runtime")
	driver.prepare_build_files(source.replace("return 0", "return missing_name"), 0, "", folder)
	var invalid := timed_compile(driver, "Invalid code")
	check(not invalid.ok and "missing_name" in invalid.output, "Errors must be reported instead of reusing a previous executable")
	driver.prepare_build_files(source, 0, "", folder)
	check(timed_compile(driver, "Corrected code").ok, "Corrected source must compile again")
	var header_path := folder.path_join("robot.hpp")
	var header := FileAccess.get_file_as_string(header_path)
	var file := FileAccess.open(header_path, FileAccess.WRITE)
	file.store_string(header + "\n#error header_changed\n")
	file.close()
	var changed_header := timed_compile(driver, "Changed runtime header")
	check(not changed_header.ok and "header_changed" in changed_header.output, "Header changes must invalidate the runtime cache")
	for name in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	print("CPP CACHE TESTS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
