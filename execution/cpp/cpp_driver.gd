extends RefCounted

const BUILD_DIR := "user://build"
const STUDENT_CPP := "user://build/student_code.cpp"
const ROBOT_HPP := "user://build/robot.hpp"
const ROBOT_CPP := "user://build/robot_runtime.cpp"
const OUTPUT_EXE := "user://build/student_program"

const Paths = preload("res://execution/shared/paths.gd")

var _commands = preload(Paths.ROBOT_COMMANDS).new()

func _get_exe_path() -> String:
	var base := ProjectSettings.globalize_path(OUTPUT_EXE)
	if OS.get_name() == "Windows":
		return base + ".exe"
	return base


func prepare_build_files(source: String, port: int) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BUILD_DIR))
	_write_file(STUDENT_CPP, source)
	_write_file(ROBOT_HPP,   _commands.get_cpp_header())
	_write_file(ROBOT_CPP,   _commands.get_cpp_source(port))


func compile_program() -> Dictionary:
	var output: Array = []
	var student_cpp := ProjectSettings.globalize_path(STUDENT_CPP)
	var robot_cpp   := ProjectSettings.globalize_path(ROBOT_CPP)
	var exe         := _get_exe_path()
	
	if FileAccess.file_exists(exe):
		DirAccess.remove_absolute(exe)
	
	var args := ["-std=c++17", "-Wall", "-Wextra", student_cpp, robot_cpp, "-o", exe]
	
	if OS.get_name() == "Windows":
		args.append("-lws2_32")
	var exit_code := OS.execute("g++", args, output, true)
	return {
		"ok":     exit_code == 0,
		"output": "" if output.is_empty() else str(output[0])
	}


func start_program() -> int:
	return OS.create_process(_get_exe_path(), [])

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

func _write_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open file for writing: " + path)
		return
	f.store_string(text)
