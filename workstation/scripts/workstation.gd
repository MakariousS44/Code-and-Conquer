extends Control

# === UI references ===
# all the workspace pieces live here: editor, output, controls, and level viewport
@onready var editor: CodeEdit = $RootMargin/MainColumn/WorkspaceSplit/EditorOutputSplit/EditorSection/EditorPanel/EditorMargin/Editor
@onready var game_subviewport: SubViewport = $RootMargin/MainColumn/WorkspaceSplit/GameViewPanel/GameView/SubViewport
@onready var output_box: RichTextLabel = $RootMargin/MainColumn/WorkspaceSplit/EditorOutputSplit/OutputSection/OutputPanel/OutputMargin/Output
@onready var status_label: Label = $RootMargin/MainColumn/TopBarPanel/TopBar/StatusLabel
@onready var run_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/RunButton
@onready var step_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/StepButton
@onready var reset_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/ResetButton
@onready var language_selector: OptionButton = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/LanguageSelector

# === execution components ===
# these turn student code into command output the game can actually use
const Paths = preload("res://execution/shared/paths.gd")

var validator  = preload(Paths.CPP_VALIDATOR).new()
var generator  = preload(Paths.CPP_GENERATOR).new()
var compiler   = preload(Paths.CPP_DRIVER).new()
var translator = preload(Paths.COMMAND_TRANSLATOR).new()
var executor   = preload(Paths.COMMAND_EXECUTOR).new()
var py_pipeline = preload(Paths.PYTHON_PIPELINE).new()
var _commands  = preload(Paths.ROBOT_COMMANDS).new()

# === language state ===
enum Language { CPP, PYTHON }
var current_language: Language = Language.CPP

# === level bootstrap ===
# this screen now loads the level definition and instantiates the playable level scene directly
var level_definition   = preload(Paths.MAP_LOADER).new()
var level_scene_resource = preload(Paths.MAP_VIEW_SCENE)

# cached runtime refs so this screen can hand commands to the live player
var game_instance: Node = null
var player_node: Node = null

# === step mode state ===
var step_mode: bool = false
var step_queue: Array = []

var has_run: bool = false
var current_line_offset: int = 0
var _is_handling_lose: bool = false


func _ready() -> void:
	_set_status("Ready", "")
	editor.text = "int main() {\n    move();\n}\n"
	editor.grab_focus()

	_setup_editor()
	_setup_syntax_highlighting()
	_setup_language_selector()

	run_button.pressed.connect(_on_run_button_pressed)
	step_button.pressed.connect(_on_step_button_pressed)
	reset_button.pressed.connect(_on_reset_button_pressed)
	executor.execution_finished.connect(_on_execution_finished)

	await get_tree().process_frame
	_load_level_scene()

# only enable reset button after execution
func _on_execution_finished() -> void:
	reset_button.disabled = false
	_clear_editor_highlights()
	if step_mode and step_queue.size() > 0:
		step_button.disabled = false
		return
	
	run_button.disabled = true
	step_button.disabled = true
	has_run = true
	_set_status("Done", "ok")

# === level loading ===
# creates the playable level scene, loads the level definition, and asks the scene to build itself
func _load_level_scene() -> void:
	# clear out any existing level scene from the viewport
	for child in game_subviewport.get_children():
		child.queue_free()

	# create and attach the playable level scene
	game_instance = level_scene_resource.instantiate()
	game_subviewport.add_child(game_instance)

	# grab the player node so runtime systems can control it later
	if not game_instance.has_node("WorldRoot/Player"):
		push_error("Level scene is missing node path: WorldRoot/Player")
		return

	player_node = game_instance.get_node("WorldRoot/Player")
	if player_node.has_signal("lose_triggered"):
		player_node.lose_triggered.connect(_on_player_lose)

	# load the level definition from disk
	var raw: Dictionary = level_definition.load(CampaignLevels.TEST_LEVEL)
	if not raw.ok:
		push_error("Level load failed: %s" % raw.error)
		return

	# hand the definition to the level scene so it can build itself
	if game_instance.has_method("build_level"):
		game_instance.build_level(raw.definition)


# === editor setup ===
func _setup_editor() -> void:
	editor.highlight_current_line = true
	editor.draw_control_chars = false
	editor.indent_automatic = true
	editor.indent_use_spaces = true
	editor.indent_size = 4


# === language selector ===
func _setup_language_selector() -> void:
	language_selector.add_item("C++")
	language_selector.add_item("Python")
	language_selector.select(0)
	language_selector.item_selected.connect(_on_language_changed)


func _on_language_changed(index: int) -> void:
	current_language = Language.CPP if index == 0 else Language.PYTHON
	step_mode = false
	step_queue = []
	output_box.clear()
	_clear_editor_highlights()

	if current_language == Language.CPP:
		editor.text = "int main() {\n    move();\n}\n"
		_setup_syntax_highlighting()
		_set_status("Ready", "")
	elif current_language == Language.PYTHON:
		editor.text = "move()\n"
		_setup_python_highlighting()
		_set_status("Ready", "")


# === syntax highlighting ===

func _setup_syntax_highlighting() -> void:
	var highlighter := CodeHighlighter.new()

	var keywords := [
		"int", "double", "float", "bool", "char", "void",
		"if", "else", "while", "for", "return",
		"true", "false", "break", "continue"
	]
	for word in keywords:
		highlighter.add_keyword_color(word, Color(0.40, 0.70, 1.00))

	for command in _commands.COMMANDS:
		highlighter.add_keyword_color(command.name, Color(0.80, 0.60, 1.00))

	highlighter.number_color = Color(0.95, 0.65, 0.30)
	highlighter.symbol_color = Color(0.85, 0.85, 0.85)
	highlighter.function_color = Color(0.95, 0.85, 0.45)
	highlighter.member_variable_color = Color(0.85, 0.85, 0.85)
	highlighter.add_color_region("\"", "\"", Color(0.60, 0.90, 0.60), false)
	highlighter.add_color_region("'", "'", Color(0.60, 0.90, 0.60), false)
	highlighter.add_color_region("//", "", Color(0.50, 0.50, 0.50), true)
	highlighter.add_color_region("/*", "*/", Color(0.50, 0.50, 0.50), false)

	editor.syntax_highlighter = highlighter


func _setup_python_highlighting() -> void:
	var highlighter := CodeHighlighter.new()

	var keywords := [
		"def", "if", "elif", "else", "while", "for", "in",
		"return", "True", "False", "None", "and", "or", "not",
		"pass", "break", "continue"
	]
	for word in keywords:
		highlighter.add_keyword_color(word, Color(0.40, 0.70, 1.00))

	for command in _commands.COMMANDS:
		highlighter.add_keyword_color(command.name, Color(0.80, 0.60, 1.00))

	highlighter.number_color = Color(0.95, 0.65, 0.30)
	highlighter.symbol_color = Color(0.85, 0.85, 0.85)
	highlighter.function_color = Color(0.95, 0.85, 0.45)
	highlighter.add_color_region("\"", "\"", Color(0.60, 0.90, 0.60), false)
	highlighter.add_color_region("'",  "'",  Color(0.60, 0.90, 0.60), false)
	highlighter.add_color_region("#",  "",   Color(0.50, 0.50, 0.50), true)
	highlighter.add_color_region("\"\"\"", "\"\"\"", Color(0.60, 0.90, 0.60), false)

	editor.syntax_highlighter = highlighter


# === button handlers ===

func _on_run_button_pressed() -> void:
	step_mode = false
	_run_pipeline(false)


func _on_step_button_pressed() -> void:
	if step_mode and step_queue.size() > 0:
		step_button.disabled = true
		_clear_editor_highlights()
		# execute one command at a time
		var next = step_queue.slice(0, 1)
		step_queue = step_queue.slice(1)
		executor.execute(next, player_node)
		log_line("▶ step: %s" % next[0].get("type", "?"))
		_highlight_editor_line(next[0].get("source_line", -1))
		
		if step_queue.is_empty():
			_set_status("Done", "ok")
			step_mode = false
			step_button.disabled = true
		else:
			_set_status("Step mode — %d left" % step_queue.size(), "")
		return

	# first press compiles/runs and fills the queue
	step_mode = true
	_run_pipeline(true)

func _highlight_editor_line(line: int) -> void:
	var adjusted := line
	if current_language == Language.CPP:
		adjusted = line - current_line_offset - 1
	if adjusted >= 0:
		editor.set_line_background_color(adjusted, Color(0.30, 0.60, 0.30, 0.25))

func _clear_editor_highlights() -> void:
	for i in range(editor.get_line_count()):
		editor.set_line_background_color(i, Color(0, 0, 0, 0))

func _on_reset_button_pressed() -> void:
	executor.cancel()
	_clear_editor_highlights()
	has_run = false
	run_button.disabled = false
	step_button.disabled = false
	reset_button.disabled = false
	step_mode = false
	step_queue = []
	output_box.clear()
	log_header("reset")
	log_line("Level reloaded.")
	_set_status("Ready", "")
	_load_level_scene()


func _on_player_lose(reason: String) -> void:
	if _is_handling_lose:
		return
	_is_handling_lose = true

	step_mode = false
	step_queue = []
	compiled_ok = false
	if executor.has_method("stop"):
		executor.stop()

	log_header("lose")
	log_error(reason)
	_set_status("You lose", "error")

	await get_tree().create_timer(0.8).timeout
	_load_level_scene()
	_set_status("Ready", "")
	_is_handling_lose = false


# === pipeline execution ===

func _run_pipeline(step_only: bool) -> void:
	reset_button.disabled = false
	run_button.disabled = true
	step_button.disabled = true
	
	_set_status("Running..." if not step_only else "Compiling...", "")
	output_box.clear()
	log_header("run" if not step_only else "step mode")
	await get_tree().process_frame

	# Python path
	if current_language == Language.PYTHON:
		var python_validation: Dictionary = py_pipeline.validate(editor.text)
		if not python_validation.ok:
			for err in python_validation.errors:
				log_error("line %d: %s" % [err.line, err.message])
			_set_status("Validation failed", "error")
			step_mode = false
			_re_enable_buttons()
			return

		var python_run_result: Dictionary = py_pipeline.run(editor.text)
		if not python_run_result.ok:
			log_error(python_run_result.output)
			_set_status("Runtime error", "error")
			step_mode = false
			_re_enable_buttons()
			return

		_finish_pipeline(python_run_result.output, step_only)
		return

	# C++ path
	var cpp_validation: Dictionary = validator.validate(editor.text)
	if not cpp_validation.ok:
		for err in cpp_validation.errors:
			log_error("line %d: %s" % [err.line, err.message])
		_set_status("Validation failed", "error")
		step_mode = false
		_re_enable_buttons()
		return

	var generated: Dictionary = generator.generate(editor.text)
	current_line_offset = generated.line_offset
	compiler.prepare_build_files(generated.generated_source)

	var build: Dictionary = compiler.compile_program()
	if not build.ok:
		log_error(compiler.remap_diagnostics(build.output, generated.line_offset))
		_set_status("Compile failed", "error")
		step_mode = false
		_re_enable_buttons()
		return

	var cpp_run_result: Dictionary = compiler.run_program()
	if not cpp_run_result.ok:
		log_error(cpp_run_result.output)
		_set_status("Runtime error", "error")
		step_mode = false
		_re_enable_buttons()
		return

	_finish_pipeline(cpp_run_result.output, step_only)


func _finish_pipeline(raw_output: String, step_only: bool) -> void:
	var result: Dictionary = translator.translate_runtime_output(raw_output)
	var commands: Array = result.commands
	var normal_lines: Array = result.normal_output_lines
	var warnings: Array = result.warnings

	if normal_lines.size() > 0:
		log_header("console output")
		for line in normal_lines:
			log_line(line)

	if warnings.size() > 0:
		log_header("warnings")
		for w in warnings:
			log_warning(w)

	if step_only:
		step_queue = commands
		run_button.disabled = true
		step_button.disabled = false
		log_success("%d commands loaded — press Step to execute one at a time" % commands.size())
		_set_status("Step mode — %d commands" % commands.size(), "")
	else:
		log_header("executing")
		for cmd in commands:
			log_line("▶ %s" % cmd.get("type", "?"))
		executor.execute(commands, player_node)


# === status helper ===

func _set_status(text: String, state: String) -> void:
	status_label.text = text
	match state:
		"ok":
			status_label.add_theme_color_override("font_color", Color(0.47, 0.87, 0.58))
		"error":
			status_label.add_theme_color_override("font_color", Color(0.88, 0.47, 0.47))
		_:
			status_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.81))

func _re_enable_buttons() -> void:
	run_button.disabled = false
	step_button.disabled = false
	reset_button.disabled = false

# === logging ===

func log_line(text: String) -> void:
	output_box.append_text(text + "\n")


func log_header(title: String) -> void:
	output_box.append_text("[color=#5b8dd9]── %s ──[/color]\n" % title.to_upper())


func log_success(text: String) -> void:
	output_box.append_text("[color=#78d897]✓[/color]  %s\n" % text)


func log_warning(text: String) -> void:
	output_box.append_text("[color=#e5b567]⚠[/color]  %s\n" % text)


func log_error(text: String) -> void:
	output_box.append_text("[color=#e17777]✗[/color]  %s\n" % text)
