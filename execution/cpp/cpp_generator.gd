extends RefCounted

const Paths = preload("res://execution/shared/paths.gd")

var _commands = preload(Paths.ROBOT_COMMANDS).new()

func generate(student_source: String) -> Dictionary:
	var macros: String = _commands.get_cpp_macros()
	var header := "#include <iostream>\n#include <string>\n#include \"robot.hpp\"\n\n" + macros + "\n\n"
	var line_offset: int = 4 + _commands.COMMANDS.size()

	return {
		"generated_source": header + student_source,
		"line_offset": line_offset
	}
