extends SceneTree

var failures := 0
var editor: CodeEdit
var highlighter: SyntaxHighlighter

func _initialize() -> void:
	call_deferred("run_tests")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func color_at(line: int, column: int) -> Color:
	var spans: Dictionary = highlighter.get_line_syntax_highlighting(line)
	var color := editor.get_theme_color("font_color")
	var positions := spans.keys()
	positions.sort()
	for position in positions:
		if position > column:
			break
		color = spans[position].color
	return color

func run_tests() -> void:
	editor = CodeEdit.new()
	root.add_child(editor)
	highlighter = load("res://workstation/scripts/cpp_highlighter.gd").new()
	highlighter.add_keyword_color("bool", Color.CYAN)
	editor.syntax_highlighter = highlighter
	var samples := [
		'const char* raw = R"(raw string with "quotes" and \\backslashes)";',
		'const char* rawd = R"delim(content with )" inside)delim";',
		'const char* raw = u8R"tag(first line\n"quotes" and )wrong"\nlast)tag";',
		'char quote = \'\\\'\'; char slash = \'\\\\\';',
		'const char* text = "escaped \\"quote\\" and \\\\";',
		"int number = 1'000'000;",
		'if (value < 3) move();',
		'auto text = "continued\\\nstring";',
		'const char* unfinished = "oops;',
		'// R"fake( ignored\n/* " and R"tag( */',
	]
	for sample in samples:
		editor.text = sample + "\nbool after = true;"
		highlighter.clear_highlighting_cache()
		check(color_at(editor.get_line_count() - 1, 0) == Color.CYAN, "Following code must recover after: " + sample)
	editor.text = 'auto raw = R"tag(first\n"inside" )wrong"\nlast)tag"; bool after;'
	highlighter.clear_highlighting_cache()
	check(color_at(1, 2) == highlighter.string_color, "Quotes inside multiline raw strings stay string-colored")
	check(color_at(2, 11) == Color.CYAN, "Code after raw delimiter returns to keyword colors")
	editor.text = 'auto raw = R"tag(unclosed\nbool inside;'
	highlighter.clear_highlighting_cache()
	check(color_at(1, 0) == highlighter.string_color, "Unclosed raw strings genuinely span lines")
	editor.set_line(0, 'auto raw = R"tag(closed)tag";')
	await process_frame
	check(color_at(1, 0) == Color.CYAN, "Editing a delimiter must invalidate cached string state")
	editor.text = '/* multi-line\n"quoted" comment */ bool after;'
	highlighter.clear_highlighting_cache()
	check(color_at(1, 1) == highlighter.comment_color, "Quotes inside block comments stay comments")
	check(color_at(1, 20) == Color.CYAN, "Code after a block comment resumes normal highlighting")
	editor.text = 'bool old;\nbool old;\nbool old;'
	highlighter.clear_highlighting_cache()
	color_at(2, 0)
	editor.select_all()
	editor.insert_text_at_caret('bool ready;\nauto raw = R"delim(content with )" inside)delim";\nbool after;')
	check(color_at(1, 25) == highlighter.string_color, "Pasting must replace cached colors with raw-string colors")
	check(color_at(2, 0) == Color.CYAN, "Pasting must preserve following keyword colors")
	await process_frame
	check(color_at(1, 25) == highlighter.string_color, "Raw-string colors must remain correct after the edit signal")
	editor.queue_free()
	await process_frame
	print("CPP HIGHLIGHTER TESTS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
