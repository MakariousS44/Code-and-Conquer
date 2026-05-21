extends Control

# === UI references ===
# all the workspace pieces live here: editor, output, controls, and level viewport
@onready var editor: CodeEdit = $RootMargin/MainColumn/WorkspaceSplit/EditorOutputSplit/EditorSection/EditorPanel/EditorMargin/Editor
@onready var game_subviewport: SubViewport = $RootMargin/MainColumn/WorkspaceSplit/GameViewPanel/GameView/SubViewport
@onready var output_box: RichTextLabel = $RootMargin/MainColumn/WorkspaceSplit/EditorOutputSplit/OutputSection/OutputPanel/OutputMargin/Output
@onready var status_label: Label = $RootMargin/MainColumn/TopBarPanel/TopBar/StatusLabel
@onready var run_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/RunButton
@onready var prev_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/PrevButton
@onready var step_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/StepButton
@onready var reset_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/LeftButtons/ResetButton
@onready var rotate_left_btn: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/LeftRotateButton
@onready var rotate_right_btn: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/RightRotateButton
@onready var language_selector: OptionButton = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/LanguageSelector
@onready var menu_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/MainMenuButton
@onready var speed_slider: HSlider = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/SpeedContainer/SpeedSlider
@onready var speed_value_label: Label = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/SpeedContainer/SpeedValueLabel
@onready var grid_2d_button: Button = $RootMargin/MainColumn/TopBarPanel/TopBar/RightButtons/Grid2DButton

# Compass HUD - Index order matches player.gd DIRS
@onready var compass: TextureRect = $Compass
const COMPASS_TEXTURES: Array[Texture2D] = [
	preload("res://assets/images/compass_east.png"),	# 0 = east
	preload("res://assets/images/compass_south.png"),	# 1 = south
	preload("res://assets/images/compass_west.png"),	# 2 = west
	preload("res://assets/images/compass_north.png"),	# 3 = north
]

# Popups -------------------------------------------+
# Lose overlay
@onready var lose_overlay: Control = $LoseOverlay
@onready var lose_message: Label = $LoseOverlay/LoseCard/LoseContent/LoseMessage
@onready var lose_retry_button: Button = $LoseOverlay/LoseCard/LoseContent/LoseButtons/LoseRetryButton
@onready var lose_menu_button: Button = $LoseOverlay/LoseCard/LoseContent/LoseButtons/LoseMenuButton
@onready var lose_report_button: Button = $LoseOverlay/LoseCard/LoseContent/LoseButtons/ReportButtons/PrintButton
@onready var lose_clipboard_button: Button = $LoseOverlay/LoseCard/LoseContent/LoseButtons/ReportButtons/CopyButton

# Win overlay
@onready var win_overlay: Control = $WinOverlay
@onready var win_retry_button: Button = $WinOverlay/WinCard/WinContent/WinButtons/WinRetryButton
@onready var win_menu_button: Button = $WinOverlay/WinCard/WinContent/WinButtons/WinMenuButton
@onready var win_report_button: Button = $WinOverlay/WinCard/WinContent/WinButtons/ReportButtons/PrintButton
@onready var win_clipboard_button: Button = $WinOverlay/WinCard/WinContent/WinButtons/ReportButtons/CopyButton
@onready var report_save_dialog: FileDialog = $WinOverlay/ReportSaveDialog
var pending_report_text: String = ""
@onready var win_screenshot_button: Button = $WinOverlay/WinCard/WinContent/WinButtons/ReportButtons/WinScreenshotButton
@onready var lose_screenshot_button: Button = $LoseOverlay/LoseCard/LoseContent/LoseButtons/ReportButtons/LoseScreenshotButton
@onready var screenshot_save_dialog: FileDialog = $ScreenshotSaveDialog
var _pending_screenshot: Image = null

# Done overlay (for levels without a win condition)
@onready var done_overlay: Control = $DoneOverlay
@onready var done_retry_button: Button = $DoneOverlay/DoneCard/DoneContent/DoneButtons/DoneRetryButton
@onready var done_menu_button: Button = $DoneOverlay/DoneCard/DoneContent/DoneButtons/DoneMenuButton
@onready var done_screenshot_button: Button = $DoneOverlay/DoneCard/DoneContent/DoneScreenshotRow/DoneScreenshotButton


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

# === step history for step back ===
var _cmd_history: Array = []	# [{cmd, src_line, snap}] - snap is state before the cmd ran
var _step_index: int = 0		# how many commands the user has seen
var _in_replay: bool = false	# true when replaying from history

# === pause state ===
var _paused: bool = false
signal _resume

var current_line_offset: int = 0
var _is_handling_lose: bool = false

var global_level_name := ""
var exec_speed: float = 0.5
var _run_outcome: String = "incomplete"  # "win" | "lose" | "incomplete" | "move_limit"
var _run_had_error: bool = false  # set when the subprocess emits [ERROR]
const MOVE_LIMIT := 999

func _ready() -> void:
	# Kill any subprocess left over from a previous session that was force-closed.
	# auto_accept_quit disabled so _notification can clean up before Godot exits.
	get_tree().set_auto_accept_quit(false)		# required for _notification to intercept window close
	if OS.get_name() == "Windows":
		OS.execute("taskkill", ["/F", "/IM", "student_program.exe"], [], true)
	else:
		OS.execute("pkill", ["-f", "student_program"], [], true)

	_set_status("Ready", "")
	editor.text = "#include \"robot.hpp\"\n\nint main() {\n    move();\n}\n"
	editor.grab_focus()

	_setup_editor()
	_setup_syntax_highlighting()
	_setup_language_selector()

	# compass updates whenever the player's logical facing changes
	EventManager.player_facing_changed.connect(_on_player_facing_changed)
	
	run_button.text = "▶ Run"
	run_button.pressed.connect(_on_run_button_pressed)
	step_button.pressed.connect(_on_step_button_pressed)
	prev_button.pressed.connect(_on_prev_button_pressed)
	prev_button.disabled = true
	reset_button.pressed.connect(_on_reset_button_pressed)
	lose_retry_button.pressed.connect(_on_lose_retry)
	win_retry_button.pressed.connect(_on_win_retry)
	lose_menu_button.pressed.connect(_on_go_to_menu)
	win_menu_button.pressed.connect(_on_go_to_menu)
	win_report_button.pressed.connect(_on_win_report_save)
	win_clipboard_button.pressed.connect(_on_win_report_copy)
	lose_report_button.pressed.connect(_on_win_report_save)
	lose_clipboard_button.pressed.connect(_on_win_report_copy)
	
	report_save_dialog.hide()
	report_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	report_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	report_save_dialog.clear_filters()
	report_save_dialog.add_filter("*.txt ; Text Report")
	if not report_save_dialog.file_selected.is_connected(_on_report_save_selected):
		report_save_dialog.file_selected.connect(_on_report_save_selected)

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
	if not screenshot_save_dialog.file_selected.is_connected(_on_screenshot_save_selected):
		screenshot_save_dialog.file_selected.connect(_on_screenshot_save_selected)

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


func _load_level_scene(load_editor_text: bool = true, preserve_camera: bool = false) -> void:
	var saved_camera_state: Dictionary = {}
	if preserve_camera and game_instance and game_instance.has_method("get_camera_state"):
		saved_camera_state = game_instance.get_camera_state()

	# clear out any existing level scene from the viewport
	for child in game_subviewport.get_children():
		child.queue_free()
	flat_grid_node = null

	# create and attach the playable level scene
	game_instance = level_scene_resource.instantiate()
	game_subviewport.add_child(game_instance)

	if preserve_camera and not saved_camera_state.is_empty() \
			and game_instance.has_method("set_pending_camera_restore"):
		game_instance.set_pending_camera_restore(saved_camera_state)

	# grab the player node so runtime systems can control it later
	if not game_instance.has_node("WorldRoot/Player"):
		push_error("Level scene is missing node path: WorldRoot/Player")
		return

	player_node = game_instance.get_node("WorldRoot/Player")
	if player_node.has_signal("lose_triggered") and not player_node.lose_triggered.is_connected(_on_player_lose):
		player_node.lose_triggered.connect(_on_player_lose)
	if game_instance.has_signal("level_complete") and not game_instance.level_complete.is_connected(_on_level_complete):
		game_instance.level_complete.connect(_on_level_complete)
	if game_instance.has_signal("level_incomplete") and not game_instance.level_incomplete.is_connected(_trigger_incomplete_lose):
		game_instance.level_incomplete.connect(_trigger_incomplete_lose)

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

	# (re)create the 2D flat grid view alongside the isometric scene
	var FlatGridScript = load("res://map/scripts/flat_grid_view.gd")
	flat_grid_node = FlatGridScript.new()
	game_subviewport.add_child(flat_grid_node)
	flat_grid_node.setup(game_instance, player_node)
	flat_grid_node.visible = _is_2d_mode
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
		editor.text = "#include \"robot.hpp\"\n\nint main()\n{\n\tmove();\n\n\treturn 0;\n}\n"
	else:
		editor.text = "from robot import *\n\nmove()\n"


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
	_cmd_history.clear()
	_step_index = 0
	_in_replay = false
	output_box.clear()
	_clear_editor_highlights()

	run_button.text = "▶ Run"
	run_button.disabled = false
	step_button.disabled = false
	prev_button.disabled = true
	reset_button.disabled = false
	rotate_left_btn.disabled = false
	rotate_right_btn.disabled = false

	if current_language == Language.CPP:
		_setup_syntax_highlighting()
		_load_editor_template_for_current_language()
		_set_status("Ready", "")
	elif current_language == Language.PYTHON:
		_setup_python_highlighting()
		_load_editor_template_for_current_language()
		_set_status("Ready", "")
	
	_load_level_scene(false, true)


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
	highlighter.add_keyword_color("include", Color(0.95, 0.45, 0.75))
	highlighter.add_color_region("<", ">", Color(1.0, 0.6, 0.25), true)

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

	highlighter.add_keyword_color("from", Color(0.95, 0.45, 0.75))
	highlighter.add_keyword_color("import", Color(0.95, 0.45, 0.75))
	highlighter.add_color_region("*", "", Color(0.95, 0.45, 0.75), true)
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
	if _ipc_active:
		if _paused:
			if _step_index < _cmd_history.size():
				await _resume_after_step_back()
			else:
				_paused = false
				run_button.text = "❚❚ Pause"
				_set_status("Running...", "")
				_resume.emit()
		else:
			_paused = true
			run_button.text = "▶ Resume"
			_set_status("Paused", "")
		return

	_paused = false
	_run_pipeline()


# The subprocess is held at the original pause position; the world is at the stepped-back position. 
# Replay cached commands at the user's selected speed to catch the world up,
# so it looks like seamless continuation, then unblock the IPC loop.
# Pause check between commands so the user can interrupt the catch-up.
func _resume_after_step_back() -> void:
	_in_replay = false
	_paused = false
	run_button.text = "❚❚ Pause"
	prev_button.disabled = true
	step_button.disabled = true
	_set_status("Running...", "")

	while _step_index < _cmd_history.size() and _ipc_active:
		var entry = _cmd_history[_step_index]
		_step_index += 1
		await _execute_cmd(entry.cmd, entry.src_line)
		if not _ipc_active:
			return
		if _paused:
			# User pressed Pause mid-replay. Stop catching up.
			# If there are still cached commands left, stay in replay mode so
			# Step continues via _replay_step_forward; otherwise drop to live ste
			_in_replay = _step_index < _cmd_history.size()
			run_button.text = "▶ Resume"
			_set_status("Paused", "")
			step_button.disabled = false
			prev_button.disabled = _step_index <= 0
			return
	
	_resume.emit()


func _on_step_button_pressed() -> void:
	# Running: pause first
	if _ipc_active and not _paused:
		_paused = true
		run_button.text = "▶ Resume"
		_set_status("Paused", "")
		return

	# Paused: single step forward
	if _ipc_active and _paused:
		step_button.disabled = true
		prev_button.disabled = true
		if _in_replay:
			await _replay_step_forward()
		else:
			_resume.emit()	# loop executes one cmd then re-pauses
		return

	# start a fresh run, but begin paused so the first command is a single step
	_paused = true
	_run_pipeline()


func _on_prev_button_pressed() -> void:
	if not _ipc_active or _step_index <= 0 or not _paused:
		return

	_step_index -= 1
	_in_replay = true
	_restore_snapshot(_cmd_history[_step_index].snap)
	if flat_grid_node != null and is_instance_valid(flat_grid_node):
		# Build path: every snapshot up to and including the restored one is a
		# (gx, gy, facing) point the player has actually stood at, oldest first.
		var positions: Array = []
		for i in range(_step_index + 1):
			var s = _cmd_history[i].snap
			positions.append({gx = s.grid_x, gy = s.grid_y, facing = s.facing})
		flat_grid_node.rebuild_trail(positions)
	step_button.disabled = false
	prev_button.disabled = _step_index <= 0


func _take_snapshot() -> Dictionary:
	var obj_copy: Dictionary = {}

	for key in game_instance.object_data:
		obj_copy[key] = game_instance.object_data[key].duplicate()

	return {
		grid_x = player_node.grid_x,
		grid_y = player_node.grid_y,
		facing = player_node.facing,
		carried_object = player_node.carried_object,
		object_data = obj_copy
	}


func _restore_snapshot(snap: Dictionary) -> void:
	if player_node == null or game_instance == null:
		return

	player_node.grid_x = snap.grid_x
	player_node.grid_y = snap.grid_y
	player_node.facing = snap.facing
	player_node.carried_object = snap.carried_object
	player_node.position = game_instance.player_grid_position(snap.grid_x, snap.grid_y)

	player_node.update_animation(false)
	game_instance.restore_object_data(snap.object_data)

	if _step_index > 0:
		_highlight_editor_line(_cmd_history[_step_index - 1].src_line)
	else:
		_clear_editor_highlights()


func _replay_step_forward() -> void:
	var entry = _cmd_history[_step_index]
	_step_index += 1
	await _execute_cmd(entry.cmd, entry.src_line)
	if not _ipc_active:
		return

	log_line("✓ %s" % entry.cmd.to_lower())
	if _step_index >= _cmd_history.size():
		# Caught up to live position; next step will be a real live step via _resume.
		_in_replay = false

	_set_status("Paused", "")
	step_button.disabled = false
	prev_button.disabled = _step_index <= 0


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
	_cmd_history.clear()
	_step_index = 0
	_in_replay = false
	run_button.text = "▶ Run"
	run_button.disabled = false
	step_button.disabled = false
	reset_button.disabled = false
	rotate_left_btn.disabled = false
	rotate_right_btn.disabled = false
	prev_button.disabled = true

	output_box.clear()
	log_header("reset")
	log_line("Level reloaded.")
	_set_status("Ready", "")
	_load_level_scene(false, true)

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
	prev_button.disabled = disabled
	step_button.disabled = disabled
	reset_button.disabled = disabled
	language_selector.disabled = disabled
	editor.editable = not disabled
	rotate_left_btn.disabled = disabled or _is_2d_mode
	rotate_right_btn.disabled = disabled or _is_2d_mode


func _get_funny_lose_message() -> String:
	return LOSE_MESSAGES[randi() % LOSE_MESSAGES.size()]


func _trigger_move_limit_lose() -> void:
	if _is_handling_lose:
		return
	_is_handling_lose = true
	_run_outcome = "move_limit"
	_stop_execution()

	log_header("lose")
	log_error("Move Limit Reached")
	_set_status("You lost", "error")

	lose_message.text = "Move Limit Reached"
	lose_overlay.visible = true
	_set_controls_disabled(true)


# Shared handler for both "incomplete" lose conditions:
#   - Player code finished without winning or crashing
#   - player landed on the goal tile but objectives weren't satisfied
func _trigger_incomplete_lose(reason: String) -> void:
	if _is_handling_lose:
		return
	_is_handling_lose = true
	_run_outcome = "incomplete"
	_stop_execution()

	log_header("lose")
	log_error(reason)
	_set_status("You lost", "error")

	lose_message.text = reason
	lose_overlay.visible = true
	_set_controls_disabled(true)


func _on_player_lose(reason: String) -> void:
	if _is_handling_lose:
		return
	_is_handling_lose = true
	_run_outcome = "lose"
	_stop_execution()

	log_header("lose")
	log_error(reason)
	_set_status("You lost", "error")

	lose_message.text = _get_funny_lose_message()
	lose_overlay.visible = true
	_set_controls_disabled(true)


func _on_level_complete() -> void:
	_run_outcome = "win"
	_stop_execution()

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
	_paused = false
	_ipc_active = false
	_ipc_loop_running = false

	if _ipc_server != null:
		_ipc_server.stop()
		_ipc_server = null
	if _subprocess_pid != -1:
		OS.kill(_subprocess_pid)
		_subprocess_pid = -1

	# If IPC loop is paused waiting for a step, unblock it so it can exit cleanly
	_resume.emit()


func _run_pipeline() -> void:
	# Capture caller's intent BEFORE _stop_execution wipes _paused.
	var start_paused: bool = _paused
	_stop_execution()
	reset_button.disabled = false
	run_button.disabled = true
	step_button.disabled = true
	rotate_left_btn.disabled = true
	rotate_right_btn.disabled = true

	_set_status("Compiling...", "")
	output_box.clear()
	log_header("run")
	_cmd_history.clear()
	_step_index = 0
	_in_replay = false
	_run_outcome = "incomplete"
	_run_had_error = false
	await get_tree().process_frame

	# Python path
	if current_language == Language.PYTHON:
		var v: Dictionary = py_pipeline.validate(editor.text)
		if not v.ok:
			for err in v.errors:
				log_error("line %d: %s" % [err.line, err.message])
			_set_status("Validation failed", "error")
			_re_enable_buttons()
			return
	else:
		var v: Dictionary = validator.validate(editor.text)
		if not v.ok:
			for err in v.errors:
				log_error("line %d: %s" % [err.line, err.message])
			_set_status("Validation failed", "error")
			_re_enable_buttons()
			return

	# start IPC server
	var IPCServer = preload(Paths.IPC_SERVER)
	_ipc_server = IPCServer.new()
	if not _ipc_server.start():
		log_error("Could not open a local TCP port for IPC. Is the port range 27015-27115 blocked?")
		_set_status("IPC failed", "error")
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
	_paused = start_paused
	log_header("executing")

	run_button.disabled = false
	if _paused:
		run_button.text = "▶ Resume"
		_set_status("Paused", "")
	else:
		run_button.text = "❚❚ Pause"
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

			var snap = _take_snapshot()
			_cmd_history.append({cmd = cmd, src_line = src_line, snap = snap})
			_step_index = _cmd_history.size()

			await _execute_cmd(cmd, src_line)

			if not _ipc_active:
				break

			if _paused:
				log_line("✓ %s" % cmd.to_lower())
				_set_status("Paused", "")
				step_button.disabled = false
				prev_button.disabled = false
				await _resume
				if not _ipc_active:
					break
			_ipc_server.send("OK")

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
			_run_had_error = true

		elif line == "[DONE]":
			break

	_ipc_loop_running = false
	if _ipc_active:
		# Loop exited naturally (subprocess sent [DONE] or disconnected) without a
		# win or crash.
		if _run_outcome == "incomplete" and not _is_handling_lose and not _run_had_error:
			if _level_has_win_condition():
				_trigger_incomplete_lose("Did not reach the goal.")
			else:
				_on_execution_done()
				return
		else:
			_stop_execution()

			run_button.text = "▶ Run"
			run_button.disabled = true
			step_button.disabled = true
			if _run_had_error:
				_set_status("Error", "error")
			else:
				_set_status("Done", "ok")


func _on_execution_done() -> void:
	_stop_execution()
	run_button.text = "▶ Run"
	run_button.disabled = true
	step_button.disabled = true
	_set_status("Done", "ok")
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


# Intercepts window close so the subprocess is killed before Godot exits
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_execution()
		get_tree().quit()

func _execute_cmd(cmd: String, src_line: int) -> void:
	_highlight_editor_line(src_line)
	if not _paused:
		log_line("▶ %s" % cmd.to_lower())
	if player_node == null:
		return
	match cmd:
		"MOVE":
			var moves_so_far := 0
			for i in range(min(_step_index, _cmd_history.size())):
				if _cmd_history[i].cmd == "MOVE":
					moves_so_far += 1
			if moves_so_far > MOVE_LIMIT:
				_trigger_move_limit_lose()
				return
			await player_node.move_forward(exec_speed)
		"TURN_LEFT":
			player_node.turn_left()
			await get_tree().create_timer(exec_speed * 0.2).timeout
		"TURN_RIGHT":
			player_node.turn_right()
			await get_tree().create_timer(exec_speed * 0.2).timeout
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
			status_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.81))


func _re_enable_buttons() -> void:
	_paused = false
	run_button.text = "▶ Run"
	run_button.disabled = false
	step_button.disabled = false
	prev_button.disabled = true
	reset_button.disabled = false
	rotate_left_btn.disabled = _is_2d_mode
	rotate_right_btn.disabled = _is_2d_mode


func _on_grid_2d_button_pressed() -> void:
	_is_2d_mode = not _is_2d_mode

	if flat_grid_node != null and is_instance_valid(flat_grid_node):
		flat_grid_node.visible = _is_2d_mode

	if game_instance != null and is_instance_valid(game_instance):
		game_instance.camera.enabled = not _is_2d_mode
		if not _is_2d_mode:
			game_instance.camera.make_current()

	if _is_2d_mode and flat_grid_node != null and is_instance_valid(flat_grid_node):
		flat_grid_node.activate()
	elif not _is_2d_mode and flat_grid_node != null and is_instance_valid(flat_grid_node):
		flat_grid_node.deactivate()

	rotate_left_btn.disabled = _is_2d_mode
	rotate_right_btn.disabled = _is_2d_mode
	grid_2d_button.text = "3D View" if _is_2d_mode else "2D View"


func _take_screenshot() -> void:
	var was_2d := _is_2d_mode
	if not was_2d and flat_grid_node != null:
		game_instance.visible = false
		game_instance.camera.enabled = false
		flat_grid_node.visible = true
		flat_grid_node.activate()
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

func _build_win_report() -> String:
	var cols := int(current_level_definition.get("cols", 0))
	var rows := int(current_level_definition.get("rows", 0))
	var walls: Dictionary = current_level_definition.get("walls", {})

	var start_x := 1
	var start_y := 1
	var start_facing := "north"
	var robots: Array = current_level_definition.get("robots", [])
	if not robots.is_empty():
		var r: Dictionary = robots[0]
		start_x = int(r.get("x", 1))
		start_y = int(r.get("y", 1))
		var ori := int(r.get("_orientation", 3))
		var dirs := ["east", "south", "west", "north"]
		if ori >= 0 and ori < dirs.size():
			start_facing = dirs[ori]

	var end_x := start_x
	var end_y := start_y
	var end_facing := start_facing
	if player_node != null:
		end_x = player_node.grid_x
		end_y = player_node.grid_y
		end_facing = player_node.facing

	var cmd_letters: Array = []
	var move_count := 0
	for entry in _cmd_history:
		var letter := _cmd_to_report_letter(entry.cmd)
		if letter == "":
			continue
		cmd_letters.append(letter)
		if entry.cmd == "MOVE":
			move_count += 1
	cmd_letters.append(_run_outcome_marker())

	var level_name := global_level_name.get_file().get_basename()
	var lang_name := "C++" if current_language == Language.CPP else "Python"
	var date := Time.get_date_string_from_system()

	var report := "=== CODE & CONQUER - LEVEL REPORT ===\n"
	report += "Level:    %s\n" % level_name
	report += "Language: %s\n" % lang_name
	report += "Date:     %s\n" % date
	report += "\n"
	report += "Starting position: (%d, %d) - %s\n" % [start_x, start_y, start_facing]
	report += "Starting world state:\n\n"
	report += _render_world_text(cols, rows, walls, start_x, start_y, start_facing)
	report += "\n\n"
	report += "Ending position: (%d, %d) - %s\n" % [end_x, end_y, end_facing]
	report += "Ending world state:\n\n"
	report += _render_world_text(cols, rows, walls, end_x, end_y, end_facing)
	report += "\n\n"
	report += "Sequence: " + "".join(cmd_letters) + "\n"
	report += "Move Count: %d\n" % move_count
	report += "Key: M=move  T=turn left  U=pick up  D=put down  !=win  #=lose  ?=incomplete\n"
	return report


func _cmd_to_report_letter(cmd: String) -> String:
	match cmd:
		"MOVE":
			return "M"
		"TURN_LEFT":
			return "T"
		"PICK_OBJECT":
			return "U"
		"PUT_OBJECT":
			return "D"
	return ""


func _run_outcome_marker() -> String:
	match _run_outcome:
		"win":
			return "!"
		"lose":
			return "#"
		"move_limit":
			return "$"
		_:
			return "?"


func _facing_arrow(facing: String) -> String:
	match facing:
		"north":
			return "^"
		"south":
			return "v"
		"east":
			return ">"
		"west":
			return "<"
	return "?"


func _wall_at(walls: Dictionary, x: int, y: int, dir: String) -> bool:
	var key := "%d,%d" % [x, y]
	if not walls.has(key):
		return false
	for d in walls[key]:
		if str(d).to_lower() == dir:
			return true
	return false


# Sparse-wall ASCII grid. Outer edges always drawn, '+' at every corner,
# interior walls only where they exist.
func _render_world_text(cols: int, rows: int, walls: Dictionary, px: int, py: int, facing: String) -> String:
	if cols <= 0 or rows <= 0:
		return ""

	var arrow := _facing_arrow(facing)
	var lines: Array = []

	var outer := "   +"
	for c in range(cols):
		outer += "---+"
	lines.append(outer)

	for row in range(rows, 0, -1):
		var row_line := "%2d |" % row
		for col in range(1, cols + 1):
			var glyph := "."
			if col == px and row == py:
				glyph = arrow
			row_line += " %s " % glyph
			if col < cols:
				row_line += "|" if _wall_at(walls, col, row, "east") else " "
		row_line += "|"
		lines.append(row_line)

		if row > 1:
			var sep := "   +"
			for col in range(1, cols + 1):
				sep += "---+" if _wall_at(walls, col, row - 1, "north") else "   +"
			lines.append(sep)

	lines.append(outer)

	var label := "     "
	var parts: Array = []
	for col in range(1, cols + 1):
		parts.append(str(col))
	label += "   ".join(parts)
	lines.append(label)

	return "\n".join(lines)

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


func _on_player_facing_changed(facing_index: int) -> void:
	compass.texture = COMPASS_TEXTURES[facing_index]
