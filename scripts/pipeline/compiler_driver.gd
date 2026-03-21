extends RefCounted

const BUILD_DIR := "user://build"
const STUDENT_CPP := "user://build/student_code.cpp"
const ROBOT_HPP := "user://build/robot.hpp"
const ROBOT_CPP := "user://build/robot_runtime.cpp"
const OUTPUT_EXE := "user://build/student_program"

func prepare_build_files(source: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BUILD_DIR))
	_write_file(STUDENT_CPP, source)
	_write_robot_files()

func compile_program() -> Dictionary:
	var output: Array = []

	var student_cpp := ProjectSettings.globalize_path(STUDENT_CPP)
	var robot_cpp := ProjectSettings.globalize_path(ROBOT_CPP)
	var exe := ProjectSettings.globalize_path(OUTPUT_EXE)

	var exit_code := OS.execute(
		"g++",
		[
			"-std=c++17",
			"-Wall",
			"-Wextra",
			student_cpp,
			robot_cpp,
			"-o",
			exe
		],
		output,
		true
	)

	return {
		"ok": exit_code == 0,
		"output": "" if output.is_empty() else str(output[0])
	}

func run_program() -> Dictionary:
	var output: Array = []
	var exe := ProjectSettings.globalize_path(OUTPUT_EXE)

	var exit_code := OS.execute(exe, [], output, true)

	return {
		"ok": exit_code == 0,
		"output": "" if output.is_empty() else str(output[0])
	}

func remap_diagnostics(raw_text: String, line_offset: int) -> String:
	var result: Array[String] = []

	for line in raw_text.split("\n"):
		if line.strip_edges() == "":
			continue

		var parts := line.split(":")
		if parts.size() >= 4 and parts[1].is_valid_int():
			var line_num := int(parts[1])
			var col_num := parts[2]
			var message := ":".join(parts.slice(3))

			var student_line := line_num - line_offset
			if student_line < 1:
				student_line = 1

			result.append("Line %d, Col %s:%s" % [student_line, col_num, message])
		else:
			result.append(line)

	return "\n".join(result)

func _write_file(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open file for writing: " + path)
		return
	f.store_string(text)

func _write_robot_files() -> void:
	_write_file(ROBOT_HPP, """#pragma once

void move();
void turn_left();
void turn_right();
bool front_is_clear();
void pick_object();
void put_object();
""")

	_write_file(ROBOT_CPP, """#include "robot.hpp"
#include <iostream>

void move() {
	std::cout << "[CMD] MOVE" << std::endl;
}

void turn_left() {
	std::cout << "[CMD] TURN_LEFT" << std::endl;
}

void turn_right() {
	std::cout << "[CMD] TURN_RIGHT" << std::endl;
}

bool front_is_clear() {
	std::cout << "[CMD] FRONT_IS_CLEAR" << std::endl;
	std::cout.flush();
	int result = 0;
	std::cin >> result;
	return result == 1;
}

void pick_object() {
	std::cout << "[CMD] PICK_OBJECT" << std::endl;
}

void put_object() {
	std::cout << "[CMD] PUT_OBJECT" << std::endl;
}
""")
