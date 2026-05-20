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
@onready var rotate_left_btn: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/LeftRotateButton
@onready var rotate_right_btn: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/RightRotateButton
@onready var language_selector: OptionButton = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/LanguageSelector
@onready var menu_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/MainMenuButton
@onready var speed_slider: HSlider = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/SpeedContainer/SpeedSlider
@onready var speed_value_label: Label = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/SpeedContainer/SpeedValueLabel
@onready var grid_2d_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/Grid2DButton

# Popups -------------------------------------------+
# Lose overlay
@onready var lose_overlay: Control = $LoseOverlay
@onready var lose_message: Label = $LoseOverlay/LoseCard/LoseContent/LoseMessage
@onready var lose_retry_button: Button = $LoseOverlay/LoseCard/LoseContent/LoseButtons/LoseRetryButton
@onready var lose_menu_button: Button = $LoseOverlay/LoseCard/LoseContent/LoseButtons/LoseMenuButton

# Win overlay
@onready var win_overlay: Control = $WinOverlay
@onready var win_retry_button: Button = $WinOverlay/WinCard/WinContent/WinButtons/WinRetryButton
@onready var win_menu_button: Button = $WinOverlay/WinCard/WinContent/WinButtons/WinMenuButton
@onready var win_report_button: Button = $WinOverlay/WinCard/WinContent/WinButtons/ReportButtons/PrintButton
@onready var win_clipboard_button: Button = $WinOverlay/WinCard/WinContent/WinButtons/ReportButtons/CopyButton
@onready var win_screenshot_button: Button = $WinOverlay/WinCard/WinContent/WinButtons/ReportButtons/WinScreenshotButton
@onready var report_save_dialog: FileDialog = $WinOverlay/ReportSaveDialog
var pending_report_text: String = ""

# Done overlay (no-condition levels)
@onready var done_overlay: Control = $DoneOverlay
@onready var done_retry_button: Button = $DoneOverlay/DoneCard/DoneContent/DoneButtons/DoneRetryButton
@onready var done_menu_button: Button = $DoneOverlay/DoneCard/DoneContent/DoneButtons/DoneMenuButton
@onready var done_screenshot_button: Button = $DoneOverlay/DoneCard/DoneContent/DoneScreenshotRow/DoneScreenshotButton

# Lose screenshot
@onready var lose_screenshot_button: Button = $LoseOverlay/LoseCard/LoseContent/LoseButtons/LoseScreenshotButton

# Screenshot dialog
@onready var screenshot_save_dialog: FileDialog = $ScreenshotSaveDialog
var _pending_screenshot: Image = null


# Library overlay
@onready var library_overlay: Control = $LibraryOverlay
@onready var library_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/LibraryButton

# === execution components ===
# these turn student code into command output the game can actually use
const Paths = preload("res://execution/shared/paths.gd")

var validator = preload(Paths.CPP_VALIDATOR).new()
var generator = preload(Paths.CPP_GENERATOR).new()
var compiler = preload(Paths.CPP_DRIVER).new()
var py_pipeline = preload(Paths.PYTHON_PIPELINE).new()
var _commands = preload(Paths.ROBOT_COMMANDS).new()

# === language state ===
enum Language { CPP, PYTHON }
var current_language: Language = Language.CPP

# === level bootstrap ===
# this screen now loads the level definition and instantiates the playable level scene directly
var level_definition = preload(Paths.MAP_LOADER).new()
var level_scene_resource = preload(Paths.MAP_VIEW_SCENE)
var current_level_definition: Dictionary = {}

# cached runtime refs so this screen can hand commands to the live player
var game_instance: Node = null
var player_node: Node = null

# 2D flat grid view toggle
var flat_grid_node: Node2D = null
var _is_2d_mode: bool = false

# === IPC state ===
var _ipc_server = null
var _subprocess_pid: int = -1
var _ipc_active: bool = false
var _ipc_loop_running: bool = false

# === step mode state ===
var step_mode: bool = false
signal _step_continue

var current_line_offset: int = 0
var _is_handling_lose: bool = false

var global_level_name := ""
var exec_speed: float = 0.5

var _move_sequence: String = ""
var _sequence_ended: bool = false
var _start_gx: int = 0
var _start_gy: int = 0
var _start_facing: String = ""
var _start_obj_data: Dictionary = {}

func _ready() -> void:
	# Kill any subprocess left over from a previous session that was force-closed.
	# auto_accept_quit disabled so _notification can clean up before Godot exits.
	get_tree().set_auto_accept_quit(false)		# required for _notification to intercept window close
	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/F", "/IM", "student_program.exe"], [], true)
	else:
		OS.execute("pkill", ["-f", "student_program"], [], true)

	_set_status("Ready", "")
	editor.text = "int main() {\n    move();\n}\n"
	editor.grab_focus()

	_setup_editor()
	_setup_syntax_highlighting()
	_setup_language_selector()
		
	run_button.pressed.connect(_on_run_button_pressed)
	step_button.pressed.connect(_on_step_button_pressed)
	reset_button.pressed.connect(_on_reset_button_pressed)
	lose_retry_button.pressed.connect(_on_lose_retry)
	win_retry_button.pressed.connect(_on_win_retry)
	lose_menu_button.pressed.connect(_on_go_to_menu)
	win_menu_button.pressed.connect(_on_go_to_menu)
	win_report_button.pressed.connect(_on_win_report_save)
	win_clipboard_button.pressed.connect(_on_win_report_copy)
	win_screenshot_button.pressed.connect(_take_screenshot)
	lose_screenshot_button.pressed.connect(_take_screenshot)
	done_retry_button.pressed.connect(_on_done_retry)
	done_menu_button.pressed.connect(_on_go_to_menu)
	done_screenshot_button.pressed.connect(_take_screenshot)

	screenshot_save_dialog.hide()
	screenshot_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	screenshot_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	screenshot_save_dialog.clear_filters()
	screenshot_save_dialog.add_filter("*.png ; PNG Image")
	var level_name := global_level_name.get_file().get_basename()
	screenshot_save_dialog.current_file = "%s screenshot.png" % level_name
	if not screenshot_save_dialog.file_selected.is_connected(_on_screenshot_save_selected):
		screenshot_save_dialog.file_selected.connect(_on_screenshot_save_selected)

	report_save_dialog.hide()
	report_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	report_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	report_save_dialog.clear_filters()
	report_save_dialog.add_filter("*.txt ; Text Report")
	if not report_save_dialog.file_selected.is_connected(_on_report_save_selected):
		report_save_dialog.file_selected.connect(_on_report_save_selected)

	if rotate_left_btn != null and not rotate_left_btn.pressed.is_connected(l_rotate_button_up):
		rotate_left_btn.pressed.connect(l_rotate_button_up)

	if rotate_right_btn != null and not rotate_right_btn.pressed.is_connected(r_rotate_button_up):
		rotate_right_btn.pressed.connect(r_rotate_button_up)

	if menu_button != null and not menu_button.pressed.is_connected(_on_main_menu_button_pressed):
		menu_button.pressed.connect(_on_main_menu_button_pressed)

	speed_slider.value_changed.connect(_on_speed_change)

	if grid_2d_button != null:
		grid_2d_button.pressed.connect(_on_grid_2d_button_pressed)

	library_overlay.visible = false

	await get_tree().process_frame
	_load_level_scene(true)


func _load_level_scene(load_editor_text: bool = true) -> void:
	# clear out any existing level scene from the viewport
	for child in game_subviewport.get_children():
		child.queue_free()
	flat_grid_node = null

	# create and attach the playable level scene
	game_instance = level_scene_resource.instantiate()
	game_subviewport.add_child(game_instance)

	# grab the player node so runtime systems can control it later
	if not game_instance.has_node("WorldRoot/Player"):
		push_error("Level scene is missing node path: WorldRoot/Player")
		return

	player_node = game_instance.get_node("WorldRoot/Player")
	if player_node.has_signal("lose_triggered") and not player_node.lose_triggered.is_connected(_on_player_lose):
		player_node.lose_triggered.connect(_on_player_lose)
	if game_instance.has_signal("level_complete") and not game_instance.level_complete.is_connected(_on_level_complete):
		game_instance.level_complete.connect(_on_level_complete)

	# === LOAD PATH ===
	var level_path := ""


	if SelectedLevel.path.strip_edges() != "":
		level_path = SelectedLevel.path
	else:
		push_error("No level path available.")
		log_error("NO LEVEL PATH FOUND")
		return

	if not FileAccess.file_exists(level_path):
		push_error("Level file does not exist: " + level_path)
		log_error("FILE NOT FOUND")
		return

	global_level_name = level_path
	var raw: Dictionary = level_definition.load(level_path)

	if not raw.ok:
		push_error("Level load failed: %s" % raw.error)
		log_error("LOAD FAILED: " + raw.error)
		return

	current_level_definition = raw.definition

	# preload starter code into editor only when requested
	if load_editor_text:
		_load_editor_template_for_current_language()

	# build level
	if game_instance.has_method("build_level"):
		game_instance.build_level(raw.definition)
	_capture_start_state()

	# (re)create the 2D flat grid view alongside the isometric scene
	var FlatGridScript = load("res://map/scripts/flat_grid_view.gd")
	flat_grid_node = FlatGridScript.new()
	game_subviewport.add_child(flat_grid_node)
	flat_grid_node.setup(game_instance, player_node)
	flat_grid_node.visible = _is_2d_mode
	game_instance.visible = not _is_2d_mode
	if _is_2d_mode:
		game_instance.camera.enabled = false
		flat_grid_node.activate()
	else:
		game_instance.camera.enabled = true
		game_instance.camera.make_current()


func _load_editor_template_for_current_language() -> void:
	if current_level_definition.is_empty():
		_load_default_editor_template()
		return

	if not current_level_definition.has("editor"):
		_load_default_editor_template()
		return

	var editor_data = current_level_definition["editor"]

	# === OLD FORMAT SUPPORT ===
	if editor_data is String:
		editor.text = editor_data
		return

	if editor_data is Array:
		var old_lines: PackedStringArray = []
		for line in editor_data:
			old_lines.append(str(line))
		editor.text = "\n".join(old_lines)
		return

	# === NEW FORMAT SUPPORT ===
	if editor_data is Dictionary:
		var key := "cpp" if current_language == Language.CPP else "python"

		if editor_data.has(key):
			var starter = editor_data[key]

			if starter is String:
				editor.text = starter
				return

			if starter is Array:
				var lines: PackedStringArray = []
				for line in starter:
					lines.append(str(line))
				editor.text = "\n".join(lines)
				return

	_load_default_editor_template()


func _load_default_editor_template() -> void:
	if current_language == Language.CPP:
		editor.text = "int main() {\n    move();\n}\n"
	else:
		editor.text = "move()\n"


# === editor setup ===
func _setup_editor() -> void:
	editor.highlight_current_line = true
	editor.draw_control_chars = false
	editor.indent_automatic = true
	editor.indent_use_spaces = true
	editor.indent_size = 4


# === language selector ===
func _setup_language_selector() -> void:
	language_selector.clear()
	language_selector.add_item("C++")
	language_selector.add_item("Python")
	language_selector.select(0)

	if not language_selector.item_selected.is_connected(_on_language_changed):
		language_selector.item_selected.connect(_on_language_changed)


func _on_language_changed(index: int) -> void:
	_stop_execution()
	current_language = Language.CPP if index == 0 else Language.PYTHON
	step_mode = false
	output_box.clear()
	_clear_editor_highlights()

	if current_language == Language.CPP:
		_setup_syntax_highlighting()
		_load_editor_template_for_current_language()
		_set_status("Ready", "")
	elif current_language == Language.PYTHON:
		_setup_python_highlighting()
		_load_editor_template_for_current_language()
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

	for sensor in _commands.SENSORS:
		highlighter.add_keyword_color(sensor.name, Color(0.60, 0.90, 1.00))

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

	for sensor in _commands.SENSORS:
		highlighter.add_keyword_color(sensor.name, Color(0.60, 0.90, 1.00))

	highlighter.number_color = Color(0.95, 0.65, 0.30)
	highlighter.symbol_color = Color(0.85, 0.85, 0.85)
	highlighter.function_color = Color(0.95, 0.85, 0.45)
	highlighter.add_color_region("\"", "\"", Color(0.60, 0.90, 0.60), false)
	highlighter.add_color_region("'", "'", Color(0.60, 0.90, 0.60), false)
	highlighter.add_color_region("#", "", Color(0.50, 0.50, 0.50), true)
	highlighter.add_color_region("\"\"\"", "\"\"\"", Color(0.60, 0.90, 0.60), false)

	editor.syntax_highlighter = highlighter


# === button handlers ===

func _on_run_button_pressed() -> void:
	step_mode = false
	_run_pipeline(false)


func _on_step_button_pressed() -> void:
	if _ipc_active and step_mode:
		if not _ipc_loop_running:
			# Second click: begin executing
			_ipc_loop_running = true
			step_button.disabled = true
			_run_ipc_loop()
		else:
			# Subsequent clicks: advance one step
			step_button.disabled = true
			_step_continue.emit()
		return
	step_mode = true
	_run_pipeline(true)


func _highlight_editor_line(line: int) -> void:
	_clear_editor_highlights()

	var adjusted := line - 1
	if current_language == Language.CPP:
		adjusted = line - current_line_offset - 1

	if adjusted >= 0 and adjusted < editor.get_line_count():
		editor.set_line_background_color(adjusted, Color(0.30, 0.60, 0.30, 0.25))
		editor.set_caret_line(adjusted)
		editor.center_viewport_to_caret()


func _clear_editor_highlights() -> void:
	for i in range(editor.get_line_count()):
		editor.set_line_background_color(i, Color(0, 0, 0, 0))


func _on_reset_button_pressed() -> void:
	_stop_execution()
	_clear_editor_highlights()
	run_button.disabled = false
	step_button.disabled = false
	reset_button.disabled = false
	rotate_left_btn.disabled = false
	rotate_right_btn.disabled = false

	step_mode = false
	output_box.clear()
	log_header("reset")
	log_line("Level reloaded.")
	_set_status("Ready", "")
	_load_level_scene(false)

func _on_speed_change(value: float) -> void:
	exec_speed = value
	speed_value_label.text = "%.2fs" % value


# === funny lose messages ===
const LOSE_MESSAGES := [
	"The robot has left the chat.",
	"Have you tried turning it off and on again?",
	"Your robot took an unscheduled vacation.",
	"The robot says: I quit.",
	"404: Success not found.",
	"Instructions unclear. Robot now in another dimension.",
	"Your robot walked into a wall. Impressive dedication.",
	"The robot has filed a complaint with HR.",
	"Maybe try fewer walls next time?",
	"Your robot called in sick.",
	"The matrix has rejected your code.",
	"Skill issue detected. Try again.",
	"Your robot tripped over its own code.",
	"The robot is on strike. Have you tried negotiating?",
	"Oops! Your robot is now a wall decoration.",
]

func _set_controls_disabled(disabled: bool) -> void:
	run_button.disabled = disabled
	step_button.disabled = disabled
	reset_button.disabled = disabled
	language_selector.disabled = disabled
	editor.editable = not disabled
	rotate_left_btn.disabled = disabled or _is_2d_mode
	rotate_right_btn.disabled = disabled or _is_2d_mode


func _get_funny_lose_message() -> String:
	return LOSE_MESSAGES[randi() % LOSE_MESSAGES.size()]


func _on_player_lose(reason: String) -> void:
	if _is_handling_lose:
		return
	_is_handling_lose = true
	_move_sequence += "?"
	_sequence_ended = true
	_stop_execution()

	log_header("lose")
	log_error(reason)
	_set_status("You lost", "error")

	lose_message.text = _get_funny_lose_message()
	lose_overlay.visible = true
	_set_controls_disabled(true)


func _on_level_complete() -> void:
	_move_sequence += "!"
	_sequence_ended = true
	_stop_execution()
	step_mode = false

	log_header("level complete")
	log_success("Your robot reached the goal!")
	_set_status("Level Complete!", "ok")

	win_overlay.visible = true
	_set_controls_disabled(true)


func _on_lose_retry() -> void:
	lose_overlay.visible = false
	_is_handling_lose = false
	_set_controls_disabled(false)
	_on_reset_button_pressed()


func _on_win_retry() -> void:
	win_overlay.visible = false
	_set_controls_disabled(false)
	_on_reset_button_pressed()


func _on_win_next() -> void:
	win_overlay.visible = false
	_set_controls_disabled(false)
	log_header("info")
	log_line("Next level coming soon!")


func _on_execution_done() -> void:
	if not _sequence_ended:
		_move_sequence += "."
	run_button.disabled = true
	step_button.disabled = true
	_set_status("Done", "ok")
	if not _level_has_win_condition():
		done_overlay.visible = true
		_set_controls_disabled(true)


func _level_has_win_condition() -> bool:
	if not current_level_definition.has("goal"):
		return false
	var goal = current_level_definition["goal"]
	if goal is Dictionary and goal.is_empty():
		return false
	return true


func _on_done_retry() -> void:
	done_overlay.visible = false
	_set_controls_disabled(false)
	_on_reset_button_pressed()


func _take_screenshot() -> void:
	# Always capture the 2D flat view — switch to it temporarily if needed
	var was_2d := _is_2d_mode
	if not was_2d and flat_grid_node != null:
		game_instance.visible = false
		game_instance.camera.enabled = false
		flat_grid_node.visible = true
		flat_grid_node.activate()

	# Two frames: one to process visibility, one to actually render
	await get_tree().process_frame
	await get_tree().process_frame

	_pending_screenshot = game_subviewport.get_texture().get_image()

	if not was_2d and flat_grid_node != null:
		flat_grid_node.deactivate()
		flat_grid_node.visible = false
		game_instance.visible = true
		game_instance.camera.enabled = true
		game_instance.camera.make_current()

	var level_name := global_level_name.get_file().get_basename()
	screenshot_save_dialog.current_file = "%s screenshot.png" % level_name
	screenshot_save_dialog.popup_centered()


func _on_screenshot_save_selected(path: String) -> void:
	if _pending_screenshot == null:
		return
	_pending_screenshot.save_png(path)
	_pending_screenshot = null
	log_line("Screenshot saved: " + path)


func _on_go_to_menu() -> void:
	get_tree().change_scene_to_file("res://main_menu/scenes/main_menu.tscn")


# === pipeline execution ===

func _stop_execution() -> void:
	_ipc_active = false
	_ipc_loop_running = false

	if _ipc_server != null:
		_ipc_server.stop()
		_ipc_server = null
	if _subprocess_pid != -1:
		OS.kill(_subprocess_pid)
		_subprocess_pid = -1

	# If IPC loop is paused waiting for a step, unblock it so it can exit cleanly
	_step_continue.emit()


func _run_pipeline(step_only: bool) -> void:
	reset_button.disabled = false
	run_button.disabled = true
	step_button.disabled = true

	if not step_only:
		rotate_left_btn.disabled = true
		rotate_right_btn.disabled = true

	_set_status("Running..." if not step_only else "Compiling...", "")
	output_box.clear()
	log_header("run" if not step_only else "step mode")
	await get_tree().process_frame

	# Python path
	if current_language == Language.PYTHON:
		var v: Dictionary = py_pipeline.validate(editor.text)
		if not v.ok:
			for err in v.errors:
				log_error("line %d: %s" % [err.line, err.message])
			_set_status("Validation failed", "error")
			step_mode = false
			_re_enable_buttons()
			return
	else:
		var v: Dictionary = validator.validate(editor.text)
		if not v.ok:
			for err in v.errors:
				log_error("line %d: %s" % [err.line, err.message])
			_set_status("Validation failed", "error")
			step_mode = false
			_re_enable_buttons()
			return

	# start IPC server
	var IPCServer = preload(Paths.IPC_SERVER)
	_ipc_server = IPCServer.new()
	if not _ipc_server.start():
		log_error("Could not open a local TCP port for IPC. Is the port range 27015-27115 blocked?")
		_set_status("IPC failed", "error")
		step_mode = false
		_re_enable_buttons()
		return

	# C++ path
	if current_language == Language.CPP:
		var generated: Dictionary = generator.generate(editor.text)
		current_line_offset = generated.line_offset
		compiler.prepare_build_files(generated.generated_source, _ipc_server.port)

		var build: Dictionary = compiler.compile_program()
		if not build.ok:
			log_error(compiler.remap_diagnostics(build.output, generated.line_offset))
			_set_status("Compile failed", "error")
			step_mode = false
			_ipc_server.stop()
			_ipc_server = null
			_re_enable_buttons()
			return
		_set_status("Compiled - launching...", "")
		_subprocess_pid = compiler.start_program()
	else:
		current_line_offset = 0
		_subprocess_pid = py_pipeline.start(editor.text, _ipc_server.port)

	if _subprocess_pid == -1:
		log_error("Failed to launch subprocess.")
		_set_status("Launch failed", "error")
		step_mode = false
		_ipc_server.stop()
		_ipc_server = null
		_re_enable_buttons()
		return

	_set_status("Running...", "")
	if not await _ipc_server.wait_for_connection(get_tree()):
		log_error("Subprocess did not connect within 5 seconds.")
		_set_status("Timeout", "error")
		_stop_execution()
		_re_enable_buttons()
		return

	_ipc_active = true
	log_header("executing")

	if step_mode:
		_set_status("Step mode - press Step to begin", "")
		step_button.disabled = false
	else:
		await _run_ipc_loop()


func _run_ipc_loop() -> void:
	while _ipc_active:
		var line: String = await _ipc_server.read_line(get_tree())

		if not _ipc_active:
			break

		if line == "[CANCELLED]" or line == "[DISCONNECT]":
			break

		if line.begins_with("[CMD]"):
			var cmd := line.trim_prefix("[CMD] ")
			var src_line := -1
			if " [LINE] " in cmd:
				var parts := cmd.split(" [LINE] ")
				cmd = parts[0].strip_edges()
				src_line = int(parts[1].strip_edges())

			await _execute_cmd(cmd, src_line)

			if not _ipc_active:
				break

			_ipc_server.send("OK")

			if step_mode:
				log_line("✓ %s" % cmd.to_lower())
				_set_status("Step mode - press Step", "")
				step_button.disabled = false
				await _step_continue
				if not _ipc_active:
					break

		elif line.begins_with("[QUERY]"):
			var query := line.trim_prefix("[QUERY] ")
			if " [LINE] " in query:
				query = query.split(" [LINE] ")[0].strip_edges()
			var answer := _answer_query(query)
			_ipc_server.send(answer)

		elif line.begins_with("[PRINT]"):
			log_line(line.trim_prefix("[PRINT] "))

		elif line.begins_with("[ERROR]"):
			log_error(line.trim_prefix("[ERROR] "))

		elif line == "[DONE]":
			break

	_ipc_loop_running = false
	if _ipc_active:
		_stop_execution()
		_on_execution_done()

# Intercepts window close so the subprocess is killed before Godot exits
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_execution()
		get_tree().quit()

func _execute_cmd(cmd: String, src_line: int) -> void:
	_highlight_editor_line(src_line)
	if not step_mode:
		log_line("▶ %s" % cmd.to_lower())
	if player_node == null:
		return
	match cmd:
		"MOVE":
			_move_sequence += "M"
			await player_node.move_forward(exec_speed)
		"TURN_LEFT":
			_move_sequence += "L"
			player_node.turn_left()
			await get_tree().create_timer(exec_speed * 0.2).timeout
		"TURN_RIGHT":
			_move_sequence += "R"
			player_node.turn_right()
			await get_tree().create_timer(exec_speed * 0.2).timeout
		"PICK_OBJECT":
			_move_sequence += "U"
			player_node.pick_object()
		"PUT_OBJECT":
			_move_sequence += "D"
			player_node.put_object()


func _answer_query(query: String) -> String:
	if player_node == null or game_instance == null:
		return "false"
	var facing: String = player_node.facing
	match query:
		"FRONT_IS_CLEAR":
			return _bool(_is_clear(facing))
		"RIGHT_IS_CLEAR":
			return _bool(_is_clear(_right_of(facing)))
		"LEFT_IS_CLEAR":
			return _bool(_is_clear(_left_of(facing)))
		"WALL_IN_FRONT":
			return _bool(not _is_clear(facing))
		"WALL_ON_RIGHT":
			return _bool(not _is_clear(_right_of(facing)))
		"WALL_ON_LEFT":
			return _bool(not _is_clear(_left_of(facing)))
		"IS_FACING_NORTH":
			return _bool(facing == "north")
		"IS_FACING_EAST":
			return _bool(facing == "east")
		"IS_FACING_WEST":
			return _bool(facing == "west")
		"AT_GOAL":
			return _bool(game_instance.is_at_goal(player_node.grid_x, player_node.grid_y))
		"OBJECT_HERE":
			return _bool(game_instance.tile_has_any_object(player_node.grid_x, player_node.grid_y))
		"CARRIES_OBJECT":
			return _bool(player_node.carried_object != "")
	return "false"


func _bool(value: bool) -> String:
	return "true" if value else "false"


func _is_clear(dir: String) -> bool:
	var gx: int = player_node.grid_x
	var gy: int = player_node.grid_y
	var next := _next_pos(gx, gy, dir)
	var wall_blocked: bool = game_instance.is_move_blocked(gx, gy, dir)
	var in_bounds: bool = game_instance.is_in_bounds(next.x, next.y)
	return not wall_blocked and in_bounds


func _next_pos(gx: int, gy: int, dir: String) -> Vector2i:
	match dir:
		"north":
			return Vector2i(gx, gy + 1)
		"south":
			return Vector2i(gx, gy - 1)
		"east":
			return Vector2i(gx + 1, gy)
		"west":
			return Vector2i(gx - 1, gy)
	return Vector2i(gx, gy)


func _right_of(facing: String) -> String:
	match facing:
		"north":
			return "east"
		"east":
			return "south"
		"south":
			return "west"
		"west":
			return "north"
	return facing


func _left_of(facing: String) -> String:
	match facing:
		"north":
			return "west"
		"west":
			return "south"
		"south":
			return "east"
		"east":
			return "north"
	return facing


func _set_status(text: String, state: String) -> void:
	status_label.text = text
	match state:
		"ok":
			status_label.add_theme_color_override("font_color", Color(0.47, 0.87, 0.58))
		"error":
			status_label.add_theme_color_override("font_color", Color(0.88, 0.47, 0.47))
		_:
			status_label.add_theme_color_override("font_color", Color(0.11, 0.85, 1.0))


func _re_enable_buttons() -> void:
	run_button.disabled = false
	step_button.disabled = false
	reset_button.disabled = false
	rotate_left_btn.disabled = _is_2d_mode
	rotate_right_btn.disabled = _is_2d_mode


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


func _on_grid_2d_button_pressed() -> void:
	_is_2d_mode = not _is_2d_mode

	if flat_grid_node != null and is_instance_valid(flat_grid_node):
		flat_grid_node.visible = _is_2d_mode

	if game_instance != null and is_instance_valid(game_instance):
		game_instance.visible = not _is_2d_mode
		game_instance.camera.enabled = not _is_2d_mode
		if not _is_2d_mode:
			game_instance.camera.make_current()

	if _is_2d_mode and flat_grid_node != null and is_instance_valid(flat_grid_node):
		flat_grid_node.activate()
	elif not _is_2d_mode and flat_grid_node != null and is_instance_valid(flat_grid_node):
		flat_grid_node.deactivate()

	# rotate buttons only apply to the isometric view
	rotate_left_btn.disabled = _is_2d_mode
	rotate_right_btn.disabled = _is_2d_mode
	grid_2d_button.text = "3D View" if _is_2d_mode else "2D View"


func l_rotate_button_up() -> void:
	EventManager.rotate_camera_right.emit()


func r_rotate_button_up() -> void:
	EventManager.rotate_camera_left.emit()

# toggle library_overlay between visible and invisible when library_button is pressed
func _on_library_button_pressed() -> void:
	library_overlay.visible = not library_overlay.visible

# switches the library_overlay to invisible when clicked outside the the overlay
func _input(event) -> void:
	# filter for left click only
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# run the logic only if the overlay is visible
		if library_overlay.visible:
			# var to hold the overlay's position
			var clicked_overlay = library_overlay.get_global_rect().has_point(event.position)
			# var to hold the oberlay button's position
			var clicked_button = library_button.get_global_rect().has_point(event.position)
			# if the click is outside the overlay and the button's position
			if not clicked_overlay and not clicked_button:
				# toggle the overlay to invisible
				library_overlay.hide()

func _on_main_menu_button_pressed() -> void:
	_on_go_to_menu()

func _capture_start_state() -> void:
	if player_node == null or game_instance == null:
		return
	_start_gx = player_node.grid_x
	_start_gy = player_node.grid_y
	_start_facing = player_node.facing
	_move_sequence = ""
	_sequence_ended = false
	_start_obj_data = {}
	for key in game_instance.object_data:
		_start_obj_data[key] = game_instance.object_data[key].duplicate()


func _build_report() -> String:
	var lang_name := "C++" if current_language == Language.CPP else "Python"
	var level_name := global_level_name.get_file().get_basename()
	var date := Time.get_date_string_from_system()

	var max_moves := 999
	if current_level_definition.has("max_moves"):
		max_moves = int(current_level_definition["max_moves"])

	var report := "=== CODE & CONQUER - LEVEL REPORT ===\n"
	report += "Level: %s\n" % level_name
	report += "Language: %s\n" % lang_name
	report += "Date: %s\n" % date
	report += "\n"

	report += "--- ROBOT START ---\n"
	report += "Position: (%d, %d)  Facing: %s\n" % [_start_gx - 1, _start_gy - 1, _facing_char(_start_facing)]
	report += "\n"

	report += "--- WORLD START ---\n"
	report += "Max Moves: %d\n" % max_moves
	report += "\n"
	report += _render_map(_start_gx, _start_gy, _start_facing, _start_obj_data)
	report += "\n"

	var end_gx := _start_gx
	var end_gy := _start_gy
	var end_facing := _start_facing
	if player_node != null:
		end_gx = player_node.grid_x
		end_gy = player_node.grid_y
		end_facing = player_node.facing

	report += "--- ROBOT END ---\n"
	report += "Position: (%d, %d)  Facing: %s\n" % [end_gx - 1, end_gy - 1, _facing_char(end_facing)]
	report += "\n"

	report += "--- WORLD END ---\n"
	report += "\n"
	var end_obj_data: Dictionary = {}
	if game_instance != null:
		for key in game_instance.object_data:
			end_obj_data[key] = game_instance.object_data[key]
	report += _render_map(end_gx, end_gy, end_facing, end_obj_data)
	report += "\n"

	var move_count := _count_moves(_move_sequence)
	report += "--- MOVES ---\n"
	report += "Sequence: %s\n" % _move_sequence
	report += "Move Count: %d\n" % move_count

	return report


func _has_wall(gx: int, gy: int, dir: String) -> bool:
	var cols: int = current_level_definition.get("cols", 0)
	var rows: int = current_level_definition.get("rows", 0)
	match dir:
		"north":
			if gy >= rows: return true
		"south":
			if gy <= 1: return true
		"east":
			if gx >= cols: return true
		"west":
			if gx <= 1: return true

	var walls = current_level_definition.get("walls", {})
	var key := "%d,%d" % [gx, gy]
	if walls.has(key):
		for d in walls[key]:
			if str(d).to_lower() == dir:
				return true

	var opp_key := ""
	var opp_dir := ""
	match dir:
		"north": opp_key = "%d,%d" % [gx, gy + 1]; opp_dir = "south"
		"south": opp_key = "%d,%d" % [gx, gy - 1]; opp_dir = "north"
		"east":  opp_key = "%d,%d" % [gx + 1, gy]; opp_dir = "west"
		"west":  opp_key = "%d,%d" % [gx - 1, gy]; opp_dir = "east"
	if walls.has(opp_key):
		for d in walls[opp_key]:
			if str(d).to_lower() == opp_dir:
				return true
	return false


func _get_goal_positions() -> Array:
	var positions := []
	if not current_level_definition.has("goal"):
		return positions
	var goal = current_level_definition["goal"]
	if goal.has("possible_final_positions"):
		for pos in goal["possible_final_positions"]:
			if typeof(pos) == TYPE_ARRAY and pos.size() >= 2:
				positions.append(Vector2i(int(pos[0]), int(pos[1])))
	if goal.has("position") and typeof(goal["position"]) == TYPE_DICTIONARY:
		var pos = goal["position"]
		positions.append(Vector2i(int(pos.get("x", -1)), int(pos.get("y", -1))))
	return positions


func _get_deposit_positions() -> Dictionary:
	var deposits: Dictionary = {}
	if not current_level_definition.has("goal"):
		return deposits
	var goal = current_level_definition["goal"]
	if not goal.has("objects"):
		return deposits
	for key in goal["objects"]:
		var parts = key.split(",")
		if parts.size() != 2:
			continue
		var gx := int(parts[0])
		var gy := int(parts[1])
		var obj_dict = goal["objects"][key]
		if obj_dict is Dictionary:
			for obj_name in obj_dict:
				deposits[Vector2i(gx, gy)] = str(obj_name)
				break
	return deposits


func _cell_content(gx: int, gy: int, robot_gx: int, robot_gy: int, robot_facing: String,
		obj_data: Dictionary, deposits: Dictionary, goal_positions: Array) -> String:
	if gx == robot_gx and gy == robot_gy:
		return " %s " % _facing_arrow(robot_facing)

	var pos := Vector2i(gx, gy)
	var key := "%d,%d" % [gx, gy]

	if deposits.has(pos):
		var obj_name: String = deposits[pos]
		var letter := obj_name[0].to_upper()
		var has_obj := false
		if obj_data.has(key):
			var tile_objs = obj_data[key]
			if tile_objs is Dictionary and tile_objs.has(obj_name) and int(tile_objs[obj_name]) > 0:
				has_obj = true
		return "[%s]" % letter if has_obj else "(%s)" % letter

	if obj_data.has(key):
		var tile_objs = obj_data[key]
		if tile_objs is Dictionary:
			for obj_name in tile_objs:
				if int(tile_objs[obj_name]) > 0:
					return " %s " % str(obj_name)[0].to_upper()

	if goal_positions.has(pos):
		return " * "

	return "   "


func _render_map(robot_gx: int, robot_gy: int, robot_facing: String, obj_data: Dictionary) -> String:
	var cols: int = current_level_definition.get("cols", 0)
	var rows: int = current_level_definition.get("rows", 0)
	if cols == 0 or rows == 0:
		return "(no map data)\n"

	var deposits := _get_deposit_positions()
	var goal_positions := _get_goal_positions()

	var max_row_digits := len(str(rows - 1))
	var label_pad := " ".repeat(max_row_digits + 1)

	var result := ""
	for gy in range(rows, 0, -1):
		var sep := label_pad + "+"
		for gx in range(1, cols + 1):
			sep += ("---" if _has_wall(gx, gy, "north") else "   ") + "+"
		result += sep + "\n"

		var row_label := str(gy - 1).rpad(max_row_digits) + " "
		var row := row_label + "|"
		for gx in range(1, cols + 1):
			row += _cell_content(gx, gy, robot_gx, robot_gy, robot_facing, obj_data, deposits, goal_positions)
			row += "|" if _has_wall(gx, gy, "east") else " "
		result += row + "\n"

	var bot := label_pad + "+"
	for _gx in range(cols):
		bot += "---+"
	result += bot + "\n"

	var col_labels := label_pad + "  "
	for gx in range(1, cols + 1):
		col_labels += str(gx - 1).rpad(4)
	result += col_labels + "\n"

	return result


func _facing_char(facing: String) -> String:
	match facing:
		"north": return "N"
		"south": return "S"
		"east":  return "E"
		"west":  return "W"
	return "?"


func _facing_arrow(facing: String) -> String:
	match facing:
		"north": return "^"
		"south": return "v"
		"east":  return ">"
		"west":  return "<"
	return "?"


func _count_moves(seq: String) -> int:
	var count := 0
	for c in seq:
		if c in ["M", "L", "R", "U", "D"]:
			count += 1
	return count


func _on_win_report_copy() -> void:
	var report := _build_report()
	DisplayServer.clipboard_set(report)
	log_success("Report copied to clipboard.")


func _on_win_report_save() -> void:
	pending_report_text = _build_report()
	var level_name := global_level_name.get_file().get_basename()
	report_save_dialog.current_file = "%s report.txt" % level_name
	report_save_dialog.popup_centered_ratio(0.75)


func _on_report_save_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		log_error("Could not save report to: " + path)
		return
	file.store_string(pending_report_text)
	file.close()
	log_success("Report saved to: " + path)
