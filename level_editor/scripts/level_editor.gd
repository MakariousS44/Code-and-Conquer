extends Control

const SIDEBAR_WIDTH := 280.0
const TOOLBAR_WIDTH := 300.0
const PROJECT_CUSTOM_LEVELS_DIR := "res://data/custom_levels/"
const PLAYER_CUSTOM_LEVELS_DIR := "user://custom_levels/"

var document := LevelDocument.new()
var pan_mode := false
var is_panning := false
var _carry_requirements_dialog: ConfirmationDialog = null
var _carry_requirement_rows := {}
var _saved_signature := ""
var _auto_accept_quit_before := true

@onready var grid: EditorGridView = $GridClip/EditorGrid as EditorGridView
@onready var grid_clip: Control = $GridClip
@onready var robot_button: Button = $RightToolbar/PlacementGrid/RobotButton
@onready var goal_button: Button = $RightToolbar/PlacementGrid/GoalButton
@onready var wall_button: Button = $RightToolbar/WallsGrid/WallButton
@onready var east_wall_button: Button = $RightToolbar/WallsGrid/EastWallButton
@onready var load_button: Button = $SidebarScroll/VBoxContainer/LoadButton
@onready var description_input: TextEdit = $SidebarScroll/VBoxContainer/DescriptionInput
@onready var save_button: Button = $SidebarScroll/VBoxContainer/SaveButton
@onready var level_name_input: LineEdit = $SidebarScroll/VBoxContainer/LevelNameInput
@onready var apple_button: Button = $RightToolbar/ObjectsGrid/AppleButton
@onready var banana_button: Button = $RightToolbar/ObjectsGrid/BananaButton
@onready var carrot_button: Button = $RightToolbar/ObjectsGrid/CarrotButton
@onready var star_button: Button = $RightToolbar/ObjectsGrid/StarButton
@onready var token_button: Button = $RightToolbar/ObjectsGrid/TokenButton
@onready var erase_button: Button = $RightToolbar/EraseButton
@onready var void_button: Button = $RightToolbar/VoidButton
@onready var new_button: Button = $SidebarScroll/VBoxContainer/NewButton
@onready var columns_input: SpinBox = $SidebarScroll/VBoxContainer/ColumnsInput
@onready var rows_input: SpinBox = $SidebarScroll/VBoxContainer/RowsInput
@onready var resize_button: Button = $SidebarScroll/VBoxContainer/ResizeButton
@onready var back_button: Button = $SidebarScroll/VBoxContainer/BackButton
@onready var status_label: Label = $ActiveToolLabel
@onready var object_count_input: SpinBox = $SidebarScroll/VBoxContainer/ObjectCountInput
@onready var goal_objects_button: Button = $SidebarScroll/VBoxContainer/GoalObjectsButton
@onready var carry_requirements_button: Button = $SidebarScroll/VBoxContainer/CarryRequirementsButton
@onready var move_limit_input: SpinBox = $SidebarScroll/VBoxContainer/MoveLimitInput
@onready var cmd_limit_input: SpinBox = $SidebarScroll/VBoxContainer/CmdLimitInput
@onready var time_limit_input: SpinBox = $SidebarScroll/VBoxContainer/TimeLimitInput
@onready var move_limit_default_checkbox: CheckBox = $SidebarScroll/VBoxContainer/MoveLimitDefaultCheckbox
@onready var cmd_limit_default_checkbox: CheckBox = $SidebarScroll/VBoxContainer/CmdLimitDefaultCheckbox
@onready var time_limit_default_checkbox: CheckBox = $SidebarScroll/VBoxContainer/TimeLimitDefaultCheckbox
func _ready() -> void:
	_arrange_sidebar()
	document.create_blank(10, 10)

	grid.set_document(document)
	grid.view_changed.connect(_layout_grid)
	grid.objects_changed.connect(_on_grid_objects_changed)
	resized.connect(_layout_grid)
	call_deferred("_layout_grid")

	robot_button.pressed.connect(_on_robot_button_pressed)
	goal_button.pressed.connect(_on_goal_button_pressed)
	wall_button.pressed.connect(_on_wall_button_pressed)
	east_wall_button.pressed.connect(_on_east_wall_button_pressed)
	load_button.pressed.connect(_on_load_button_pressed)
	save_button.pressed.connect(_on_save_button_pressed)
	apple_button.pressed.connect(_on_apple_button_pressed)
	banana_button.pressed.connect(_on_banana_button_pressed)
	carrot_button.pressed.connect(_on_carrot_button_pressed)
	star_button.pressed.connect(_on_star_button_pressed)
	token_button.pressed.connect(_on_token_button_pressed)
	erase_button.pressed.connect(_on_erase_button_pressed)
	void_button.pressed.connect(func(): _select_tool(EditorGridView.Tool.VOID, void_button, "Void (Erase restores floor; start and goal stay solid)"))
	new_button.pressed.connect(_request_new_level)
	resize_button.pressed.connect(_on_resize_button_pressed)
	back_button.pressed.connect(_request_exit)
	level_name_input.text_changed.connect(_on_level_name_changed)
	_update_save_button_availability()
	for tool_button in [robot_button, goal_button, wall_button, east_wall_button, apple_button, banana_button, carrot_button, star_button, token_button, erase_button, void_button]:
		tool_button.toggle_mode = true
	robot_button.button_pressed = true
	object_count_input.value_changed.connect(_on_object_count_changed)
	goal_objects_button.pressed.connect(_on_goal_objects_button_pressed)
	carry_requirements_button.pressed.connect(_open_carry_requirements_dialog)
	move_limit_default_checkbox.toggled.connect(_on_move_limit_default_toggled)
	cmd_limit_default_checkbox.toggled.connect(_on_cmd_limit_default_toggled)
	time_limit_default_checkbox.toggled.connect(_on_time_limit_default_toggled)

	_auto_accept_quit_before = get_tree().auto_accept_quit
	get_tree().set_auto_accept_quit(false)
	_saved_signature = _current_signature()


func _exit_tree() -> void:
	get_tree().set_auto_accept_quit(_auto_accept_quit_before)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready():
		if _has_unsaved_changes():
			_show_unsaved_changes_dialog("You have unsaved changes. Close without saving?", get_tree().quit)
		else:
			get_tree().quit()


## JSON of the level exactly as Save would write it, including sidebar fields.
func _current_signature() -> String:
	_sync_auto_carry_requirements()
	var state: Dictionary = document.data.duplicate(true)
	state["name"] = level_name_input.text.strip_edges()
	state["description"] = [description_input.text]
	var limits := {}
	if not move_limit_default_checkbox.button_pressed:
		limits["move_limit"] = int(move_limit_input.value)
	if not cmd_limit_default_checkbox.button_pressed:
		limits["cmd_limit"] = int(cmd_limit_input.value)
	if not time_limit_default_checkbox.button_pressed:
		limits["time_limit_seconds"] = float(time_limit_input.value)
	if not limits.is_empty():
		state["limits"] = limits
	elif state.has("limits"):
		state.erase("limits")
	return JSON.stringify(state)


func _has_unsaved_changes() -> bool:
	return _current_signature() != _saved_signature


func _request_exit() -> void:
	if _has_unsaved_changes():
		_show_unsaved_changes_dialog("You have unsaved changes. Leave without saving?", _on_back_button_pressed)
	else:
		_on_back_button_pressed()


func _request_new_level() -> void:
	if _has_unsaved_changes():
		_show_unsaved_changes_dialog("You have unsaved changes. Start a new level and discard them?", _on_new_button_pressed)
	else:
		_on_new_button_pressed()


func _show_unsaved_changes_dialog(message: String, on_confirm: Callable, on_cancel: Callable = Callable()) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Unsaved Changes"
	dialog.dialog_text = message
	dialog.ok_button_text = "Discard Changes"
	dialog.cancel_button_text = "Keep Editing"
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
		on_confirm.call()
	)
	var cancel := func() -> void:
		dialog.queue_free()
		if on_cancel.is_valid():
			on_cancel.call()
	dialog.canceled.connect(cancel)
	dialog.close_requested.connect(cancel)
	add_child(dialog)
	dialog.popup_centered()


func _arrange_sidebar() -> void:
	var sidebar := $SidebarScroll/VBoxContainer
	var order := [
		"TitleLabel", "LevelNameLabel", "LevelNameInput", "DescriptionLabel", "DescriptionInput",
		"GridSetupLabel", "ColumnsLabel", "ColumnsInput", "RowsLabel", "RowsInput", "ResizeButton",
		"ObjectCountLabel", "ObjectCountInput",
		"GoalConfigLabel", "GoalObjectsButton", "GoalCarryLabel", "CarryRequirementsButton",
		"LimitsLabel", "MoveLimitLabel", "MoveLimitDefaultCheckbox", "MoveLimitInput", "CmdLimitLabel", "CmdLimitDefaultCheckbox", "CmdLimitInput", "TimeLimitLabel", "TimeLimitDefaultCheckbox", "TimeLimitInput",
		"ActionsLabel", "NewButton", "LoadButton", "SaveButton", "StatusLabel", "Spacer", "BackButton"
	]
	for index in range(order.size()):
		var item := sidebar.get_node_or_null(order[index]) as Control
		if item != null:
			sidebar.move_child(item, index)
			if order[index].ends_with("Label") and order[index] != "TitleLabel" and order[index] != "ColumnsLabel" and order[index] != "RowsLabel" and order[index] != "LevelNameLabel" and order[index] != "DescriptionLabel":
				item.add_theme_color_override("font_color", Color("#55b9e8"))
				item.add_theme_font_size_override("font_size", 14)
		if item is Button:
			item.custom_minimum_size.y = 34


func _layout_grid() -> void:
	if document.data.is_empty():
		return
	var grid_size := Vector2(
		int(document.data["cols"]) * EditorGridView.CELL_SIZE,
		int(document.data["rows"]) * EditorGridView.CELL_SIZE
	)
	var available_size := grid_clip.size
	if not grid.zoom_initialized:
		var fit := maxf(0.05, minf((available_size.x - 48.0) / grid_size.x, (available_size.y - 48.0) / grid_size.y))
		grid.zoom_level = minf(fit, 1.5)
		grid.zoom_initialized = true
	grid.apply_layout(available_size, grid_size)
	
func _on_robot_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.ROBOT, robot_button, "Robot")


func _on_goal_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.GOAL, goal_button, "Goal")

func _on_wall_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.WALL, wall_button, "North Wall")


func _on_east_wall_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.EAST_WALL, east_wall_button, "East Wall")


func _select_tool(tool: int, selected_button: Button, tool_name: String) -> void:
	pan_mode = false
	is_panning = false
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	grid_clip.mouse_default_cursor_shape = Control.CURSOR_ARROW
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

	grid.set_tool(tool)
	for tool_button in [robot_button, goal_button, wall_button, east_wall_button, apple_button, banana_button, carrot_button, star_button, token_button, erase_button, void_button]:
		tool_button.button_pressed = tool_button == selected_button
	status_label.text = "Active tool: %s" % tool_name


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			pan_mode = true
			is_panning = false
			mouse_default_cursor_shape = Control.CURSOR_DRAG
			grid_clip.mouse_default_cursor_shape = Control.CURSOR_DRAG
			Input.set_default_cursor_shape(Input.CURSOR_DRAG)
			for tool_button in [robot_button, goal_button, wall_button, east_wall_button, apple_button, banana_button, carrot_button, star_button, token_button, erase_button, void_button]:
				tool_button.button_pressed = false
			status_label.text = "Pan mode: drag with left-click. Select a tool to place tiles again."
			get_viewport().set_input_as_handled()
			return

		if pan_mode and event.button_index == MOUSE_BUTTON_LEFT:
			var inside_map: bool = event.position.x > SIDEBAR_WIDTH and event.position.x < size.x - TOOLBAR_WIDTH
			if event.pressed:
				is_panning = inside_map
				if inside_map:
					grid.begin_map_click()
					get_viewport().set_input_as_handled()
			elif is_panning:
				grid.end_map_click()
				is_panning = false
				if inside_map:
					get_viewport().set_input_as_handled()
			return

	if pan_mode and is_panning and event is InputEventMouseMotion:
		grid.pan_by(event.relative)
		get_viewport().set_input_as_handled()

func _on_save_button_pressed() -> void:
	var level_name := level_name_input.text.strip_edges()
	if level_name.is_empty():
		return
	_sync_auto_carry_requirements()
	document.data["name"] = level_name
	document.data["description"] = [description_input.text]
	# Save limits
	var limits_data := {}
	if not move_limit_default_checkbox.button_pressed:
		limits_data["move_limit"] = int(move_limit_input.value)
	if not cmd_limit_default_checkbox.button_pressed:
		limits_data["cmd_limit"] = int(cmd_limit_input.value)
	if not time_limit_default_checkbox.button_pressed:
		limits_data["time_limit_seconds"] = float(time_limit_input.value)
	if not limits_data.is_empty():
		document.data["limits"] = limits_data
	elif document.data.has("limits"):
		document.data.erase("limits")

	# Project levels stay in the repository while developing in Godot. Exported games
	# cannot write to res://, so player-created levels use the writable user:// folder.
	var folder_path := PROJECT_CUSTOM_LEVELS_DIR if OS.has_feature("editor") else PLAYER_CUSTOM_LEVELS_DIR
	var full_folder_path := ProjectSettings.globalize_path(folder_path)

	DirAccess.make_dir_recursive_absolute(full_folder_path)

	var file_name := _make_level_filename(level_name) + ".json"
	var save_path := folder_path.path_join(file_name)
	if FileAccess.file_exists(save_path):
		var existing := FileAccess.open(save_path, FileAccess.READ)
		var existing_json := JSON.new()
		if existing == null or existing_json.parse(existing.get_as_text()) != OK or typeof(existing_json.data) != TYPE_DICTIONARY or str(existing_json.data.get("name", "")) != level_name:
			status_label.text = "Choose a different name; this filename is already used."
			return

	var temporary_path := folder_path.path_join(file_name + ".tmp")
	var backup_path := folder_path.path_join(file_name + ".bak")
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)

	if file == null:
		push_error("Could not save level.")
		return

	file.store_string(JSON.stringify(document.data, "\t"))
	file.close()
	# Keep a recoverable copy until the completed temporary file replaces it.
	if FileAccess.file_exists(save_path):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup_path))
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(save_path))
	if rename_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(save_path))
		status_label.text = "Could not finish saving level."
		return
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))

	save_button.text = "Saved!"
	status_label.text = "Saved: %s" % level_name
	print("Level saved to: ", ProjectSettings.globalize_path(save_path))
	_saved_signature = _current_signature()


func _on_level_name_changed(_new_name: String) -> void:
	_update_save_button_availability()


func _update_save_button_availability() -> void:
	save_button.disabled = level_name_input.text.strip_edges().is_empty()
	if not save_button.disabled:
		save_button.text = "Save Level"


func _on_load_button_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_dir = ProjectSettings.globalize_path(PROJECT_CUSTOM_LEVELS_DIR if OS.has_feature("editor") else PLAYER_CUSTOM_LEVELS_DIR)
	dialog.add_filter("*.json ; Level files")
	add_child(dialog)
	dialog.file_selected.connect(_load_level_from_path.bind(dialog))
	dialog.popup_centered_ratio(0.75)


func _load_level_from_path(path: String, dialog: FileDialog) -> void:
	if _has_unsaved_changes():
		_show_unsaved_changes_dialog("You have unsaved changes. Load this level and discard them?", func() -> void: _apply_level_load(path, dialog), dialog.queue_free)
		return
	_apply_level_load(path, dialog)


func _apply_level_load(path: String, dialog: FileDialog) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		dialog.queue_free()
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		var result := document.load_level(json.data)
		if not result.get("ok", false):
			status_label.text = "Could not load level: %s" % result.get("error", "Invalid level")
			dialog.queue_free()
			return
		level_name_input.text = str(document.data.get("name", path.get_file().get_basename()))
		_update_save_button_availability()
		description_input.text = "\n".join(PackedStringArray(document.data.get("description", [])))
		columns_input.value = int(document.data.get("cols", 10))
		rows_input.value = int(document.data.get("rows", 10))
		# Load limits
		var limits_data = document.data.get("limits", {})
		if limits_data.has("move_limit"):
			move_limit_default_checkbox.button_pressed = false
			move_limit_input.value = limits_data.get("move_limit", 0)
		else:
			move_limit_default_checkbox.button_pressed = true
			move_limit_input.value = 0

		if limits_data.has("cmd_limit"):
			cmd_limit_default_checkbox.button_pressed = false
			cmd_limit_input.value = limits_data.get("cmd_limit", 0)
		else:
			cmd_limit_default_checkbox.button_pressed = true
			cmd_limit_input.value = 0

		if limits_data.has("time_limit_seconds"):
			time_limit_default_checkbox.button_pressed = false
			time_limit_input.value = limits_data.get("time_limit_seconds", 0)
		else:
			time_limit_default_checkbox.button_pressed = true
			time_limit_input.value = 0
		_sync_auto_carry_requirements()
		_close_carry_requirements_dialog()
		grid.set_document(document)
		grid.reset_pan()
		_layout_grid()
		_saved_signature = _current_signature()
	else:
		status_label.text = "Could not load level: invalid JSON."
	dialog.queue_free()


func _make_level_filename(level_name: String) -> String:
	var safe_name := level_name.strip_edges().replace(" ", "_")
	var invalid_characters := RegEx.new()
	invalid_characters.compile("[^A-Za-z0-9_-]")
	safe_name = invalid_characters.sub(safe_name, "_", true)
	return safe_name if not safe_name.is_empty() else "untitled_level"

func _on_apple_button_pressed() -> void:
	grid.set_object_type("apple")
	_select_tool(EditorGridView.Tool.OBJECT, apple_button, "Apple")


func _on_banana_button_pressed() -> void:
	grid.set_object_type("banana")
	_select_tool(EditorGridView.Tool.OBJECT, banana_button, "Banana")


func _on_carrot_button_pressed() -> void:
	grid.set_object_type("carrot")
	_select_tool(EditorGridView.Tool.OBJECT, carrot_button, "Carrot")


func _on_star_button_pressed() -> void:
	grid.set_object_type("star")
	_select_tool(EditorGridView.Tool.OBJECT, star_button, "Star")


func _on_token_button_pressed() -> void:
	grid.set_object_type("token")
	_select_tool(EditorGridView.Tool.OBJECT, token_button, "Token")


func _on_erase_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.ERASE, erase_button, "Erase")


func _on_new_button_pressed() -> void:
	var cols := int(columns_input.value)
	var rows := int(rows_input.value)

	document.create_blank(cols, rows)
	_close_carry_requirements_dialog()
	grid.set_document(document)
	grid.reset_pan()
	_layout_grid()
	level_name_input.clear()
	_update_save_button_availability()
	description_input.clear()
	move_limit_default_checkbox.button_pressed = false
	cmd_limit_default_checkbox.button_pressed = false
	time_limit_default_checkbox.button_pressed = false
	move_limit_input.value = 0
	cmd_limit_input.value = 0
	time_limit_input.value = 0
	save_button.text = "Save Level"
	_saved_signature = _current_signature()

func _on_resize_button_pressed() -> void:
	var cols := int(columns_input.value)
	var rows := int(rows_input.value)

	document.resize(cols, rows)
	_sync_auto_carry_requirements()
	_refresh_open_carry_requirements()
	grid.set_document(document)
	grid.reset_pan()
	_layout_grid()
	save_button.text = "Save Level"


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu/scenes/main_menu.tscn")

func _on_object_count_changed(value: float) -> void:
	grid.set_object_count(int(value))
	status_label.text = "Object count per click: %d" % int(value)

func _on_goal_objects_button_pressed() -> void:
	_open_goal_objects_dialog()

## Total number of each object type placed on the map.
func _placed_object_totals() -> Dictionary:
	var totals := {}
	for tile_objects in document.data.get("objects", {}).values():
		if not (tile_objects is Dictionary):
			continue
		for object_name in tile_objects:
			var name := str(object_name)
			totals[name] = int(totals.get(name, 0)) + int(tile_objects[object_name])
	return totals


## The carry requirement as {object_name: minimum count}.
func _normalized_carry_requirement() -> Dictionary:
	var goal: Dictionary = document.data.get("goal", {})
	return preload("res://map/scripts/carry_requirements.gd").normalize(goal.get("require_carry", {}))


func _open_carry_requirements_dialog() -> void:
	if _carry_requirements_dialog != null and is_instance_valid(_carry_requirements_dialog) and not _carry_requirements_dialog.is_queued_for_deletion():
		_carry_requirements_dialog.move_to_foreground()
		return
	_sync_auto_carry_requirements()
	var dialog := ConfirmationDialog.new()
	dialog.title = "Carry Requirements"
	dialog.ok_button_text = "Apply"
	dialog.exclusive = false

	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)

	var instruction := Label.new()
	instruction.text = "Minimum number of each object the robot must be carrying when it reaches the goal:"
	vbox.add_child(instruction)

	var requirement := _normalized_carry_requirement()
	var carry_rules = preload("res://map/scripts/carry_requirements.gd")
	var goal: Dictionary = document.data.get("goal", {})
	var auto_requirement := carry_rules.normalize_auto(goal.get("require_carry_auto", {}))
	var types := {}
	for object_name in _placed_object_totals():
		if carry_rules.is_valid_object_name(str(object_name)):
			types[str(object_name)] = true
	var robots: Array = document.data.get("robots", [])
	var robot: Dictionary = robots[0] if not robots.is_empty() and robots[0] is Dictionary else {}
	for object_name in robot.get("objects", {}):
		var name := str(object_name)
		if carry_rules.is_valid_object_name(name):
			types[name] = true
	for object_name in requirement:
		types[object_name] = true
	for object_name in auto_requirement:
		types[object_name] = true

	var rows := VBoxContainer.new()
	vbox.add_child(rows)
	var carry_rows := {}
	for object_name in types.keys():
		var object_name_str := str(object_name)
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = object_name_str.capitalize()
		label.custom_minimum_size = Vector2(140, 0)
		row.add_child(label)

		var auto_check := CheckBox.new()
		auto_check.text = "Map max"
		auto_check.tooltip_text = "Use the number of %s objects on the map and keep it updated" % object_name_str
		row.add_child(auto_check)

		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 9999
		spin.step = 1
		spin.value = int(requirement.get(object_name_str, 0))
		row.add_child(spin)
		rows.add_child(row)
		carry_rows[object_name_str] = {"auto": auto_check, "spin": spin}
		auto_check.toggled.connect(_on_carry_auto_toggled.bind({"name": object_name_str, "spin": spin}))
		if auto_requirement.has(object_name_str):
			auto_check.button_pressed = true

	if types.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Place objects on the map first."
		rows.add_child(empty_label)

	dialog.confirmed.connect(_apply_carry_requirements.bind(carry_rows))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	_carry_requirements_dialog = dialog
	_carry_requirement_rows = carry_rows
	dialog.tree_exited.connect(_on_carry_requirements_dialog_closed.bind(dialog))
	add_child(dialog)
	dialog.popup_centered()


func _on_grid_objects_changed() -> void:
	_sync_auto_carry_requirements()
	_refresh_open_carry_requirements()


func _sync_auto_carry_requirements() -> void:
	var goal_value = document.data.get("goal", {})
	if not (goal_value is Dictionary):
		return
	var goal: Dictionary = goal_value
	var carry_rules = preload("res://map/scripts/carry_requirements.gd")
	var auto := carry_rules.normalize_auto(goal.get("require_carry_auto", {}))
	if auto.is_empty():
		return
	var totals := _placed_object_totals()
	var required_value = goal.get("require_carry", {})
	var required: Dictionary = required_value if required_value is Dictionary else {}
	for object_name in auto:
		var total := int(totals.get(object_name, 0))
		if total > 0:
			required[object_name] = total
		else:
			required.erase(object_name)
	goal["require_carry"] = required
	document.data["goal"] = goal


func _refresh_open_carry_requirements() -> void:
	if _carry_requirement_rows.is_empty():
		return
	_refresh_carry_auto_totals(_carry_requirement_rows)


func _close_carry_requirements_dialog() -> void:
	if _carry_requirements_dialog != null and is_instance_valid(_carry_requirements_dialog):
		_carry_requirements_dialog.queue_free()
	_carry_requirements_dialog = null
	_carry_requirement_rows.clear()


func _on_carry_auto_toggled(pressed: bool, controls: Dictionary) -> void:
	var spin := controls["spin"] as SpinBox
	spin.editable = not pressed
	spin.mouse_filter = Control.MOUSE_FILTER_IGNORE if pressed else Control.MOUSE_FILTER_STOP
	if pressed:
		_set_map_max_spin(str(controls["name"]), spin, _placed_object_totals())
	else:
		spin.tooltip_text = ""


func _refresh_carry_auto_totals(carry_rows: Dictionary) -> void:
	var totals := _placed_object_totals()
	for object_name in carry_rows:
		var controls: Dictionary = carry_rows[object_name]
		var auto_check := controls["auto"] as CheckBox
		if auto_check != null and auto_check.button_pressed:
			_set_map_max_spin(str(object_name), controls["spin"] as SpinBox, totals)


func _set_map_max_spin(object_name: String, spin: SpinBox, totals: Dictionary) -> void:
	var total := int(totals.get(object_name, 0))
	spin.max_value = maxf(9999.0, float(total))
	spin.value = total
	spin.tooltip_text = "Map total: %d" % total


func _apply_carry_requirements(carry_rows: Dictionary) -> void:
	_refresh_carry_auto_totals(carry_rows)
	var required := {}
	var auto_required := {}
	for object_name in carry_rows:
		var controls: Dictionary = carry_rows[object_name]
		var count := int((controls["spin"] as SpinBox).value)
		if count > 0:
			required[str(object_name)] = count
		if (controls["auto"] as CheckBox).button_pressed:
			auto_required[str(object_name)] = true
	if required.is_empty():
		document.data["goal"].erase("require_carry")
	else:
		document.data["goal"]["require_carry"] = required
	if auto_required.is_empty():
		document.data["goal"].erase("require_carry_auto")
	else:
		document.data["goal"]["require_carry_auto"] = auto_required
	status_label.text = "Carry requirements updated"


func _on_carry_requirements_dialog_closed(dialog: ConfirmationDialog) -> void:
	if _carry_requirements_dialog == dialog:
		_carry_requirements_dialog = null
		_carry_requirement_rows.clear()

const GOAL_OBJECT_TYPES := ["apple", "banana", "carrot", "star", "token"]

func _open_goal_objects_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Set Goal Objects"
	dialog.unresizable = true

	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)

	var instruction := Label.new()
	instruction.text = "Add requirements for objects that must be placed at specific tiles when the goal is reached:"
	vbox.add_child(instruction)

	var rows := VBoxContainer.new()
	vbox.add_child(rows)

	var buttons := HBoxContainer.new()
	vbox.add_child(buttons)
	var add_button := Button.new()
	add_button.text = "Add Requirement"
	buttons.add_child(add_button)

	var goal_rows := []

	var add_row := func(x: int, y: int, object_type: String, count: int) -> void:
		var row := HBoxContainer.new()
		var x_label := Label.new()
		x_label.text = "X:"
		row.add_child(x_label)
		var x_input := SpinBox.new()
		x_input.min_value = 1
		x_input.max_value = 9999
		x_input.value = x
		x_input.tooltip_text = "X coordinate"
		row.add_child(x_input)
		var y_label := Label.new()
		y_label.text = "Y:"
		row.add_child(y_label)
		var y_input := SpinBox.new()
		y_input.min_value = 1
		y_input.max_value = 9999
		y_input.value = y
		y_input.tooltip_text = "Y coordinate"
		row.add_child(y_input)
		var type_label := Label.new()
		type_label.text = "Object:"
		row.add_child(type_label)
		var type_option := OptionButton.new()
		for object_name in GOAL_OBJECT_TYPES:
			type_option.add_item(object_name.capitalize())
		type_option.selected = max(0, GOAL_OBJECT_TYPES.find(object_type))
		row.add_child(type_option)
		var count_label := Label.new()
		count_label.text = "Count:"
		row.add_child(count_label)
		var count_input := SpinBox.new()
		count_input.min_value = 1
		count_input.max_value = 9999
		count_input.value = max(1, count)
		count_input.tooltip_text = "Required count"
		row.add_child(count_input)
		var delete_button := Button.new()
		delete_button.text = "Delete"
		delete_button.tooltip_text = "Remove this requirement"
		row.add_child(delete_button)
		rows.add_child(row)
		var row_controls := {"x": x_input, "y": y_input, "type": type_option, "count": count_input}
		goal_rows.append(row_controls)
		delete_button.pressed.connect(func() -> void:
			goal_rows.erase(row_controls)
			row.queue_free()
		)

	add_button.pressed.connect(func() -> void:
		add_row.call(1, 1, GOAL_OBJECT_TYPES[0], 1)
	)

	# Pre-fill with existing goal objects
	if document.data.has("goal") and document.data["goal"].has("objects"):
		var goal_objs: Dictionary = document.data["goal"]["objects"]
		for key in goal_objs:
			var parts := str(key).split(",")
			if parts.size() != 2:
				continue
			var required: Dictionary = goal_objs[key]
			for obj_name in required:
				add_row.call(int(parts[0]), int(parts[1]), str(obj_name), int(required[obj_name]))
	else:
		add_row.call(1, 1, GOAL_OBJECT_TYPES[0], 1)

	dialog.confirmed.connect(_apply_goal_objects.bind(goal_rows))
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _apply_goal_objects(goal_rows: Array) -> void:
	var goal_objects := {}
	for row in goal_rows:
		var x := int(row["x"].value)
		var y := int(row["y"].value)
		var object_type: String = GOAL_OBJECT_TYPES[row["type"].selected]
		var count := int(row["count"].value)
		if count <= 0:
			continue
		var key := "%d,%d" % [x, y]
		if not goal_objects.has(key):
			goal_objects[key] = {}
		goal_objects[key][object_type] = count

	document.data["goal"]["objects"] = goal_objects
	grid.queue_redraw()
	status_label.text = "Goal objects configured"

func _on_move_limit_default_toggled(checked: bool) -> void:
	move_limit_input.visible = not checked

func _on_cmd_limit_default_toggled(checked: bool) -> void:
	cmd_limit_input.visible = not checked

func _on_time_limit_default_toggled(checked: bool) -> void:
	time_limit_input.visible = not checked

# Escape leaves the editor and returns to the main menu (same as the Back button).
# If a text field is being edited, the first Escape just drops focus so typing isn't interrupted
# by an accidental exit; the next Escape leaves.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	# don't leave while a dialog (e.g. the Load file dialog) is still open
	for child in get_children():
		if child is Window and child.visible:
			return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		focused.release_focus()
		get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	_request_exit()
