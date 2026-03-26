extends RefCounted

# Add all new commands here — both C++ and Python update automatically

const COMMANDS := [
	{ "name": "move",        "cmd": "MOVE"        },
	{ "name": "turn_left",   "cmd": "TURN_LEFT"   },
	{ "name": "turn_right",  "cmd": "TURN_RIGHT"  },
	{ "name": "pick_object", "cmd": "PICK_OBJECT" },
	{ "name": "put_object",  "cmd": "PUT_OBJECT"  },
]

func get_python_api() -> String:
	var lines := []
	for command in COMMANDS:
		lines.append(
			"def %s():\n    import traceback\n    frame = traceback.extract_stack()[-2]\n    print('[CMD] %s [LINE] ' + str(frame.lineno))"
			% [command.name, command.cmd]
		)
	return "\n\n".join(lines)

func get_cpp_header() -> String:
	var lines := ["#pragma once\n"]
	for command in COMMANDS:
		lines.append("void %s(int __src_line = 0);" % command.name)
	return "\n".join(lines)

func get_cpp_source() -> String:
	var lines := ["#include \"robot.hpp\"\n#include <iostream>\n"]
	for command in COMMANDS:
		lines.append(
			"void %s(int __src_line) {\n\tstd::cout << \"[CMD] %s [LINE] \" << __src_line << std::endl;\n}"
			% [command.name, command.cmd]
		)
	return "\n\n".join(lines)
	
func get_cpp_macros() -> String:
	var lines := []
	for command in COMMANDS:
		lines.append("#define %s() %s(__LINE__)" % [command.name, command.name])
	return "\n".join(lines)
