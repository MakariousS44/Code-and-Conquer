extends Control

# References to UI elements in the scene.
@onready var editor: CodeEdit = $RootMargin/MainColumn/WorkspaceSplit/EditorOutputSplit/EditorPanel/Editor
@onready var game_view: SubViewportContainer = $RootMargin/MainColumn/WorkspaceSplit/GameViewPanel/GameView
@onready var game_subviewport: SubViewport = $RootMargin/MainColumn/WorkspaceSplit/GameViewPanel/GameView/SubViewport
@onready var output_box: RichTextLabel = $RootMargin/MainColumn/WorkspaceSplit/EditorOutputSplit/OutputPanel/OutputMargin/Output
@onready var status_label: Label = $RootMargin/MainColumn/TopBarPanel/TopBar/StatusLabel
@onready var validate_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/ValidateButton
@onready var run_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/RunButton

# Pipeline components.
var validator = preload("res://scripts/pipeline/student_validator.gd").new()
var generator = preload("res://scripts/pipeline/source_generator.gd").new()
var compiler = preload("res://scripts/pipeline/compiler_driver.gd").new()
var translator = preload("res://scripts/pipeline/command_translator.gd").new()
var executor = preload("res://scripts/pipeline/command_executor.gd").new()

# World loading.
var world_loader = preload("res://scripts/worlds/world_loader.gd").new()

# Game preview scene and references.
var game_test_scene = preload("res://scenes/GameTest.tscn")
var game_instance: Node = null
var player_node: Node = null

func _ready() -> void:
	status_label.text = "Ready"
	editor.text = "int main() {\n    move();\n}\n"
	editor.grab_focus()

	_setup_editor()
	_setup_syntax_highlighting()

	if not validate_button.pressed.is_connected(_on_validate_button_pressed):
		validate_button.pressed.connect(_on_validate_button_pressed)

	if not run_button.pressed.is_connected(_on_run_button_pressed):
		run_button.pressed.connect(_on_run_button_pressed)

	_load_game_test_scene()

func _load_game_test_scene() -> void:
	print("Loading GameTest...")

	# Clear any previous preview scene before loading a new one.
	for child in game_subviewport.get_children():
		child.queue_free()

	game_instance = game_test_scene.instantiate()
	game_subviewport.add_child(game_instance)

	# Make sure the scene actually has the structure we expect.
	if not game_instance.has_node("WorldRoot/Player"):
		push_error("GameTest scene is missing node path: WorldRoot/Player")
		return

	player_node = game_instance.get_node("WorldRoot/Player")

	var raw: Dictionary = world_loader.load_world("res://scripts/worlds/levels/test.json")
	if not raw.ok:
		push_error("World load failed: %s" % raw.error)
		return

	# Make sure the GameTest root script exposes the expected method.
	if not game_instance.has_method("load_world_data"):
		push_error("GameTest scene does not implement load_world_data(data)")
		return

	game_instance.load_world_data(raw.world)

	print("Loaded: ", game_instance)
	print("Player: ", player_node)

func _setup_editor() -> void:
	editor.highlight_current_line = true
	editor.draw_control_chars = false
	editor.indent_automatic = true
	editor.indent_use_spaces = true
	editor.indent_size = 4

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
		"move", "turn_left", "pick_beeper", "put_beeper",
		"front_is_clear", "beepers_present", "print"
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

func _on_validate_button_pressed() -> void:
	status_label.text = "Validating..."
	output_box.clear()
	log_header("validation")
	await get_tree().process_frame

	var validation: Dictionary = validator.validate(editor.text)

	if not validation.ok:
		for err in validation.errors:
			log_error("line %d: %s" % [err.line, err.message])
		status_label.text = "❌ Validation Failed"
		return

	var generated: Dictionary = generator.generate(editor.text)
	compiler.prepare_build_files(generated.generated_source)

	var build: Dictionary = compiler.compile_program()
	if not build.ok:
		log_error(compiler.remap_diagnostics(build.output, generated.line_offset))
		status_label.text = "❌ Compile Failed"
		return

	log_success("no validation or compile errors found")
	status_label.text = "✅ Ready to Run"

func _on_run_button_pressed() -> void:
	status_label.text = "▶ Running..."
	output_box.clear()
	log_header("run")
	await get_tree().process_frame

	var validation: Dictionary = validator.validate(editor.text)

	if not validation.ok:
		for err in validation.errors:
			log_error("line %d: %s" % [err.line, err.message])
		status_label.text = "❌ Validation Failed"
		return

	var generated: Dictionary = generator.generate(editor.text)
	compiler.prepare_build_files(generated.generated_source)

	var build: Dictionary = compiler.compile_program()
	if not build.ok:
		log_error(compiler.remap_diagnostics(build.output, generated.line_offset))
		status_label.text = "❌ Compile Failed"
		return

	var run_result: Dictionary = compiler.run_program()
	if not run_result.ok:
		log_error(run_result.output)
		status_label.text = "❌ Runtime Error"
		return

	if run_result.output.strip_edges() == "":
		log_line("(program finished with no output)")
	else:
		log_line(run_result.output)

	status_label.text = "✅ Done"
	_process_command_output(run_result.output)

func _process_command_output(raw_output: String) -> void:
	var result: Dictionary = translator.translate_runtime_output(raw_output)

	var commands: Array = result.commands
	var normal_output_lines: Array = result.normal_output_lines
	var warnings: Array = result.warnings

	if normal_output_lines.size() > 0:
		log_header("console output")
		for normal_line in normal_output_lines:
			log_line(normal_line)

	if warnings.size() > 0:
		log_header("translator warnings")
		for warning in warnings:
			log_warning(warning)

	log_header("translated ir")
	log_line(JSON.stringify(commands, "\t"))

	executor.execute(commands, player_node, get_tree())

func _append_section_header(title: String) -> void:
	log_header(title.to_lower())

func log_line(text: String) -> void:
	output_box.append_text(text + "\n")

func log_header(title: String) -> void:
	output_box.append_text("[color=#9FB3C8][" + title + "][/color]\n")

func log_success(text: String) -> void:
	output_box.append_text("[color=#7CCF92]ok:[/color] " + text + "\n")

func log_warning(text: String) -> void:
	output_box.append_text("[color=#E5B567]warning:[/color] " + text + "\n")

func log_error(text: String) -> void:
	output_box.append_text("[color=#E17777]error:[/color] " + text + "\n")
