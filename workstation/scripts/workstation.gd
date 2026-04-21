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
@onready var report_save_dialog: FileDialog = $WinOverlay/ReportSaveDialog
var pending_report_text: String = ""


# Library overlay
@onready var library_overlay: Control = $LibraryOverlay

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

# cached runtime refs so this screen can hand commands to the live player
var game_instance: Node = null
var player_node: Node = null

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
	lose_retry_button.pressed.connect(_on_lose_retry)
	win_retry_button.pressed.connect(_on_win_retry)
	lose_menu_button.pressed.connect(_on_go_to_menu)
	win_menu_button.pressed.connect(_on_go_to_menu)
	win_report_button.pressed.connect(_on_win_report_save)
	win_clipboard_button.pressed.connect(_on_win_report_copy)
	
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

	library_overlay.visible = false

	await get_tree().process_frame
	_load_level_scene()


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
	if player_node.has_signal("lose_triggered") and not player_node.lose_triggered.is_connected(_on_player_lose):
		player_node.lose_triggered.connect(_on_player_lose)
	if game_instance.has_signal("level_complete") and not game_instance.level_complete.is_connected(_on_level_complete):
		game_instance.level_complete.connect(_on_level_complete)

	# load the level definition from disk
	var level_path := ""


	if SelectedLevel.path.strip_edges() != "":
		level_path = SelectedLevel.path
		print("Using SelectedLevel.path: ", level_path)
	elif SelectedLevel.level.strip_edges() != "":
		level_path = SelectedLevel.level
		print("Using LevelToLoad.level: ", level_path)
	else:
		push_error("No level path available.")
		return

	if not FileAccess.file_exists(level_path):
		push_error("Level file does not exist: " + level_path)
		return

	global_level_name = level_path
	var raw: Dictionary = level_definition.load(level_path)

	# Old level loader line for testing
	# var raw: Dictionary = level_definition.load(CampaignLevels.TEST_LEVEL)
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
	_load_level_scene()


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
	rotate_left_btn.disabled = disabled
	rotate_right_btn.disabled = disabled


func _get_funny_lose_message() -> String:
	return LOSE_MESSAGES[randi() % LOSE_MESSAGES.size()]


func _on_player_lose(reason: String) -> void:
	if _is_handling_lose:
		return
	_is_handling_lose = true
	_stop_execution()

	log_header("lose")
	log_error(reason)
	_set_status("You lost", "error")

	lose_message.text = _get_funny_lose_message()
	lose_overlay.visible = true
	_set_controls_disabled(true)


func _on_level_complete() -> void:
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

		run_button.disabled = true
		step_button.disabled = true
		_set_status("Done", "ok")


func _execute_cmd(cmd: String, src_line: int) -> void:
	_highlight_editor_line(src_line)
	if not step_mode:
		log_line("▶ %s" % cmd.to_lower())
	if player_node == null:
		return
	match cmd:
		"MOVE":
			await player_node.move_forward()
		"TURN_LEFT":
			player_node.turn_left()
			await get_tree().create_timer(0.1).timeout
		"TURN_RIGHT":
			player_node.turn_right()
			await get_tree().create_timer(0.1).timeout
		"PICK_OBJECT":
			player_node.pick_object()
		"PUT_OBJECT":
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
			status_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.81))


func _re_enable_buttons() -> void:
	run_button.disabled = false
	step_button.disabled = false
	reset_button.disabled = false
	rotate_left_btn.disabled = false
	rotate_right_btn.disabled = false


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


func l_rotate_button_up() -> void:
	EventManager.rotate_camera_right.emit()


func r_rotate_button_up() -> void:
	EventManager.rotate_camera_left.emit()


func _on_library_button_pressed() -> void:
	library_overlay.visible = not library_overlay.visible


func _on_main_menu_button_pressed() -> void:
	_on_go_to_menu()

func _build_win_report() -> String:
	var lang_name := "C++" if current_language == Language.CPP else "Python"
	var level_name := global_level_name
	var report := ""
	report += "Code & Conquer - Win Report\n"
	report += "Language: %s\n" % lang_name
	report += "Level: %s\n" % level_name
	report += "Time: %s\n\n" % Time.get_datetime_string_from_system()
	report += "Player Code:\n"
	report += editor.text
	return report
	
func _on_win_report_copy() -> void:
	var report := _build_win_report()
	DisplayServer.clipboard_set(report)
	log_success("Report copied to clipboard.")
	
func _on_win_report_save() -> void:
	pending_report_text = _build_win_report()
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "")
	report_save_dialog.current_file = "report%s.txt" % stamp
	report_save_dialog.popup_centered_ratio(0.75)
	
func _on_report_save_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		log_error("Could not save report to: " + path)
		return
	file.store_string(pending_report_text)
	file.close()
	log_success("Report saved to: " + path)
