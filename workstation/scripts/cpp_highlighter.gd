extends SyntaxHighlighter

var number_color := Color.WHITE
var symbol_color := Color.WHITE
var function_color := Color.WHITE
var member_variable_color := Color.WHITE
var string_color := Color("99e699")
var comment_color := Color("808080")
var keywords := {}
var _lines: Array[Dictionary] = []
var _source_lines: Array[String] = []
var _end := ""
var _kind := ""

func _update_cache() -> void:
	var editor := get_text_edit()
	if editor != null and not editor.text_changed.is_connected(clear_highlighting_cache):
		editor.text_changed.connect(clear_highlighting_cache)
	_clear_highlighting_cache()

func add_keyword_color(word: String, color: Color) -> void:
	keywords[word] = color

func _clear_highlighting_cache() -> void:
	_lines.clear()
	_source_lines.clear()
	_end = ""
	_kind = ""

func _get_line_syntax_highlighting(line: int) -> Dictionary:
	# TextEdit can request colors during an edit, before text_changed arrives.
	for previous in range(mini(_source_lines.size(), line + 1)):
		if _source_lines[previous] != get_text_edit().get_line(previous):
			_clear_highlighting_cache()
			break
	while _lines.size() <= line:
		var source := get_text_edit().get_line(_lines.size())
		_lines.append(_scan(source))
		_source_lines.append(source)
	return _lines[line]

func _word_char(c: String) -> bool:
	return c == "_" or c.to_lower() >= "a" and c.to_lower() <= "z" or c >= "0" and c <= "9"

func _paint(result: Dictionary, start: int, end: int, color: Color) -> void:
	result[start] = {"color": color}
	result[end] = {"color": get_text_edit().get_theme_color("font_color")}

func _scan(line: String) -> Dictionary:
	var result := {}
	var i := 0
	while i < line.length():
		var start := i
		if not _end.is_empty():
			if _kind in ["raw", "comment"]:
				var closing := line.find(_end, i)
				i = line.length() if closing < 0 else closing + _end.length()
				_paint(result, start, i, comment_color if _kind == "comment" else string_color)
				if closing >= 0:
					_end = ""
					_kind = ""
				continue
			# Ordinary literals only continue onto another line after a backslash.
			var continued := false
			while i < line.length():
				if line[i] == "\\":
					if i == line.length() - 1:
						continued = true
					i = mini(i + 2, line.length())
				elif line[i] == _end:
					i += 1
					_end = ""
					break
				else:
					i += 1
			_paint(result, start, i, string_color)
			if not continued:
				_end = ""
			continue
		if line.substr(i, 2) == "//":
			_paint(result, i, line.length(), comment_color)
			break
		if line.substr(i, 2) == "/*":
			_end = "*/"
			_kind = "comment"
			_paint(result, i, i + 2, comment_color)
			i += 2
			continue
		# Raw strings close with their exact delimiter, not the next quote.
		var raw_prefix := ""
		if i == 0 or not _word_char(line[i - 1]):
			for prefix in ['u8R"', 'uR"', 'UR"', 'LR"', 'R"']:
				if line.substr(i).begins_with(prefix):
					raw_prefix = prefix
					break
		if not raw_prefix.is_empty():
			var delimiter_start := i + raw_prefix.length()
			var opening := line.find("(", delimiter_start)
			var delimiter := line.substr(delimiter_start, opening - delimiter_start)
			var valid := opening >= 0 and delimiter.length() <= 16
			for c in delimiter:
				if c in [" ", "\t", "\r", "\\", ")"]:
					valid = false
			if valid:
				_end = ")" + delimiter + '"'
				_kind = "raw"
				_paint(result, i, opening + 1, string_color)
				i = opening + 1
				continue
		if line[i] in ['"', "'"]:
			_end = line[i]
			_kind = "quoted"
			_paint(result, i, i + 1, string_color)
			i += 1
			# An opening quote at EOL must not poison the following lines.
			if i == line.length():
				_end = ""
			continue
		if line[i] >= "0" and line[i] <= "9":
			i += 1
			while i < line.length() and (_word_char(line[i]) or line[i] == "." or (line[i] == "'" and i + 1 < line.length() and _word_char(line[i + 1]))):
				i += 1
			_paint(result, start, i, number_color)
			continue
		if _word_char(line[i]):
			i += 1
			while i < line.length() and _word_char(line[i]):
				i += 1
			var word := line.substr(start, i - start)
			var next := i
			while next < line.length() and line[next] in [" ", "\t"]:
				next += 1
			if keywords.has(word):
				_paint(result, start, i, keywords[word])
			elif next < line.length() and line[next] == "(":
				_paint(result, start, i, function_color)
			continue
		if line[i] not in [" ", "\t"]:
			_paint(result, i, i + 1, symbol_color)
		i += 1
	return result
