extends SceneTree

const Driver = preload("res://execution/cpp/cpp_driver.gd")

const VALID_SOURCE := "#include \"robot.hpp\"\n\nint main() {\n\treturn 0;\n}\n"
const INVALID_SOURCE := "#include \"robot.hpp\"\n\nint main() {\n\treturn missing_identifier\n}\n"

var failures := 0
var build_dir := ""


func _initialize() -> void:
	call_deferred("run_tests")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func run_tests() -> void:
	var driver = Driver.new()
	if not driver.is_available():
		print("CPP DRIVER CACHE TESTS: skipped (C++ toolchain unavailable)")
		quit(0)
		return

	build_dir = ProjectSettings.globalize_path("user://cpp_driver_cache_test")
	_remove_dir_recursive(build_dir)

	_prepare(driver, VALID_SOURCE)
	var first := driver.compile_program()
	check(bool(first.get("ok", false)), "Initial C++ compile should succeed: " + str(first.get("output", "")))
	if not bool(first.get("ok", false)):
		_finish()
		return

	var cache_before := _runtime_cache_values()
	check(not str(cache_before["key"]).is_empty(), "Runtime cache key should be stored")
	check(not str(cache_before["hash"]).is_empty(), "Runtime object hash should be stored")
	check(_runtime_object_hash_matches(), "Stored runtime object hash should match robot_runtime.o")

	_prepare(driver, INVALID_SOURCE)
	var failed := driver.compile_program()
	check(not bool(failed.get("ok", true)), "Invalid C++ should fail compilation")
	check(str(failed.get("reason", "")) == "compile_error", "Invalid C++ should report a compile error")
	var cache_after_failure := _runtime_cache_values()
	check(cache_after_failure["key"] == cache_before["key"] and cache_after_failure["hash"] == cache_before["hash"],
		"Failed student compile must preserve the runtime cache")
	check(FileAccess.file_exists(_runtime_object_path()), "Runtime object should remain after failed student compile")

	var object_file := FileAccess.open(_runtime_object_path(), FileAccess.WRITE)
	check(object_file != null, "Test should be able to corrupt robot_runtime.o")
	if object_file != null:
		object_file.store_string("corrupted")
		object_file.close()

	_prepare(driver, VALID_SOURCE)
	var recovered := driver.compile_program()
	check(bool(recovered.get("ok", false)), "Valid C++ should recover after runtime object corruption: " + str(recovered.get("output", "")))
	check(_runtime_cache_populated(), "Runtime cache should contain a fresh object hash")
	check(_runtime_object_hash_matches(), "Rebuilt runtime object hash should match cache")

	_finish()


func _prepare(driver, source: String) -> void:
	if not driver.prepare_build_files(source, build_dir):
		check(false, "Failed to prepare C++ build files: " + driver.get_prepare_error())


func _runtime_cache_values() -> Dictionary:
	var cache := ConfigFile.new()
	cache.load(build_dir.path_join("compile_cache.cfg"))
	return {
		"key": str(cache.get_value("runtime", "key", "")),
		"hash": str(cache.get_value("runtime", "object_hash", "")),
	}


func _runtime_cache_populated() -> bool:
	var values := _runtime_cache_values()
	return not str(values["key"]).is_empty() and not str(values["hash"]).is_empty()


func _runtime_object_hash_matches() -> bool:
	var object_hash := FileAccess.get_sha256(_runtime_object_path())
	return not object_hash.is_empty() and object_hash == str(_runtime_cache_values()["hash"])


func _runtime_object_path() -> String:
	return build_dir.path_join("robot_runtime.o")


func _remove_dir_recursive(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(path):
		_remove_dir_recursive(path.path_join(dir_name))
	DirAccess.remove_absolute(path)


func _finish() -> void:
	_remove_dir_recursive(build_dir)
	print("CPP DRIVER CACHE TESTS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
