extends RefCounted

const Paths = preload("res://execution/shared/paths.gd")

var _commands = preload(Paths.ROBOT_COMMANDS).new()

func generate(student_source: String) -> Dictionary:
	var macros: String = _commands.get_cpp_macros()

	# Move the student's #include lines above the macros. The macros rewrite
	# identifiers like move() — if robot.hpp were included AFTER the macros, its
	# forward declarations would be mangled. We blank the include lines in the
	# student source (rather than deleting them) so compile error line numbers
	# still line up with what the student sees in the editor.
	var hoisted: Array = []
	var student_lines: Array = []
	for raw_line in student_source.split("\n"):
		var line: String = raw_line
		var trimmed := line.strip_edges()
		var is_include := false
		if trimmed.begins_with("#"):
			var rest := trimmed.substr(1).lstrip(" \t")
			if rest.begins_with("include"):
				is_include = true
		if is_include:
			hoisted.append(line)
			student_lines.append("")
		else:
			student_lines.append(line)

	var hoisted_block := ""
	if not hoisted.is_empty():
		hoisted_block = "\n".join(hoisted) + "\n\n"

	var header := hoisted_block + macros + "\n"
	var line_offset: int = header.count("\n")
	var rewritten_source := "\n".join(student_lines)

	return {
		"generated_source": header + rewritten_source,
		"line_offset": line_offset
	}
