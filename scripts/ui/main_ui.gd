extends Control

# UI element references
@onready var editor: CodeEdit = $RootMargin/MainColumn/WorkspaceSplit/EditorOutputSplit/EditorSection/EditorPanel/EditorMargin/Editor
@onready var game_view: SubViewportContainer = $RootMargin/MainColumn/WorkspaceSplit/GameViewPanel/GameView
@onready var game_subviewport: SubViewport = $RootMargin/MainColumn/WorkspaceSplit/GameViewPanel/GameView/SubViewport
@onready var output_box: RichTextLabel = $RootMargin/MainColumn/WorkspaceSplit/EditorOutputSplit/OutputSection/OutputPanel/OutputMargin/Output
@onready var status_label: Label = $RootMargin/MainColumn/TopBarPanel/TopBar/StatusLabel
@onready var validate_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/ValidateButton
@onready var run_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/RunButton
@onready var step_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/StepButton
@onready var reset_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/ResetButton
@onready var language_selector: OptionButton = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/LanguageSelector

# Pipeline components
var validator = preload("res://scripts/pipeline/student_validator.gd").new()
var generator = preload("res://scripts/pipeline/source_generator.gd").new()
var compiler = preload("res://scripts/pipeline/compiler_driver.gd").new()
var translator = preload("res://scripts/pipeline/command_translator.gd").new()
var executor = preload("res://scripts/pipeline/command_executor.gd").new()

# World loading
var world_loader = preload("res://scripts/worlds/world_loader.gd").new()

# Game scene
var game_test_scene = preload("res://scenes/GameTest.tscn")
var game_instance: Node = null
var player_node: Node = null

# Step mode state
var step_mode: bool = false
var step_queue: Array = []
var compiled_ok: bool = false

func _ready() -> void:
	_set_status("Ready", "")
	editor.text = "int main() {\n    move();\n}\n"
	editor.grab_focus()

	_setup_editor()
	_setup_syntax_highlighting()
	_setup_language_selector()

	validate_button.pressed.connect(_on_validate_button_pressed)
	run_button.pressed.connect(_on_run_button_pressed)
	step_button.pressed.connect(_on_step_button_pressed)
	reset_button.pressed.connect(_on_reset_button_pressed)

	await get_tree().process_frame
	_load_game_test_scene()

func _load_game_test_scene() -> void:
	for child in game_subviewport.get_children():
		child.queue_free()

	game_instance = game_test_scene.instantiate()
	game_subviewport.add_child(game_instance)

	if not game_instance.has_node("WorldRoot/Player"):
		push_error("GameTest scene is missing node path: WorldRoot/Player")
		return

	player_node = game_instance.get_node("WorldRoot/Player")

	var raw: Dictionary = world_loader.load_world("res://scripts/worlds/levels/test.json")
	if not raw.ok:
		push_error("World load failed: %s" % raw.error)
		return

	if game_instance.has_method("load_world_data"):
		game_instance.load_world_data(raw.world)

func _setup_editor() -> void:
	editor.highlight_current_line = true
	editor.draw_control_chars = false
	editor.indent_automatic = true
	editor.indent_use_spaces = true
	editor.indent_size = 4

func _setup_language_selector() -> void:
	language_selector.add_item("C++")
	language_selector.add_item("Python (coming soon)")
	language_selector.select(0)
	language_selector.get_popup().set_item_disabled(1, true)

func _setup_syntax_highlighting() -> void:
	var highlighter := CodeHighlighter.new()

	var keywords := [
		"int", "double", "float", "bool", "char", "void",
		"if", "else", "while", "for", "return",
		"true", "false", "break", "continue"
	]
	for word in keywords:
		highlighter.add_keyword_color(word, Color(0.40, 0.70, 1.00))

	var robot_funcs := [
		"move", "turn_left", "turn_right", "front_is_clear",
		"pick_object", "put_object", "print"
	]
	for func_name in robot_funcs:
		highlighter.add_keyword_color(func_name, Color(0.80, 0.60, 1.00))

	highlighter.number_color = Color(0.95, 0.65, 0.30)
	highlighter.symbol_color = Color(0.85, 0.85, 0.85)
	highlighter.function_color = Color(0.95, 0.85, 0.45)
	highlighter.member_variable_color = Color(0.85, 0.85, 0.85)
	highlighter.add_color_region("\"", "\"", Color(0.60, 0.90, 0.60), false)
	highlighter.add_color_region("'", "'", Color(0.60, 0.90, 0.60), false)
	highlighter.add_color_region("//", "", Color(0.50, 0.50, 0.50), true)
	highlighter.add_color_region("/*", "*/", Color(0.50, 0.50, 0.50), false)

	editor.syntax_highlighter = highlighter

# --- Button handlers ---

func _on_validate_button_pressed() -> void:
	_set_status("Validating...", "")
	output_box.clear()
	log_header("validation")
	await get_tree().process_frame

	var validation: Dictionary = validator.validate(editor.text)
	if not validation.ok:
		for err in validation.errors:
			log_error("line %d: %s" % [err.line, err.message])
		_set_status("Validation failed", "error")
		return

	var generated: Dictionary = generator.generate(editor.text)
	compiler.prepare_build_files(generated.generated_source)

	var build: Dictionary = compiler.compile_program()
	if not build.ok:
		log_error(compiler.remap_diagnostics(build.output, generated.line_offset))
		_set_status("Compile failed", "error")
		compiled_ok = false
		return

	compiled_ok = true
	log_success("no errors found — ready to run")
	_set_status("Ready to run", "ok")

func _on_run_button_pressed() -> void:
	step_mode = false
	_run_pipeline(false)

func _on_step_button_pressed() -> void:
	if step_mode and step_queue.size() > 0:
		# Execute one command at a time
		var next = step_queue.slice(0, 1)
		step_queue = step_queue.slice(1)
		executor.execute(next, player_node)
		log_line("▶ step: %s" % next[0].get("type", "?"))
		if step_queue.is_empty():
			_set_status("Done", "ok")
			step_mode = false
		else:
			_set_status("Step mode — %d left" % step_queue.size(), "")
		return

	# First press: compile and load queue
	step_mode = true
	_run_pipeline(true)

func _on_reset_button_pressed() -> void:
	step_mode = false
	step_queue = []
	compiled_ok = false
	output_box.clear()
	log_header("reset")
	log_line("World reloaded.")
	_set_status("Ready", "")
	_load_game_test_scene()

# --- Pipeline ---

func _run_pipeline(step_only: bool) -> void:
	_set_status("Running..." if not step_only else "Compiling...", "")
	output_box.clear()
	log_header("run" if not step_only else "step mode")
	await get_tree().process_frame

	var validation: Dictionary = validator.validate(editor.text)
	if not validation.ok:
		for err in validation.errors:
			log_error("line %d: %s" % [err.line, err.message])
		_set_status("Validation failed", "error")
		step_mode = false
		return

	var generated: Dictionary = generator.generate(editor.text)
	compiler.prepare_build_files(generated.generated_source)

	var build: Dictionary = compiler.compile_program()
	if not build.ok:
		log_error(compiler.remap_diagnostics(build.output, generated.line_offset))
		_set_status("Compile failed", "error")
		step_mode = false
		return

	var run_result: Dictionary = compiler.run_program()
	if not run_result.ok:
		log_error(run_result.output)
		_set_status("Runtime error", "error")
		step_mode = false
		return

	var result: Dictionary = translator.translate_runtime_output(run_result.output)
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
		log_success("%d commands loaded — press Step to execute one at a time" % commands.size())
		_set_status("Step mode — %d commands" % commands.size(), "")
	else:
		log_header("executing")
		log_line(JSON.stringify(commands, "\t"))
		executor.execute(commands, player_node)
		_set_status("Done", "ok")

# --- Status helper ---

func _set_status(text: String, state: String) -> void:
	status_label.text = text
	match state:
		"ok":
			status_label.add_theme_color_override("font_color", Color(0.47, 0.87, 0.58))
		"error":
			status_label.add_theme_color_override("font_color", Color(0.88, 0.47, 0.47))
		_:
			status_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.81))

# --- Logging ---

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
