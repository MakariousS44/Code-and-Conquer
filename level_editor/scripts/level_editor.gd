extends Control

const SIDEBAR_WIDTH := 280.0
const TOOLBAR_WIDTH := 300.0
const PROJECT_CUSTOM_LEVELS_DIR := "res://data/custom_levels/"
const PLAYER_CUSTOM_LEVELS_DIR := "user://custom_levels/"

var document := LevelDocument.new()
var pan_mode := false
var is_panning := false

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
@onready var token_button: Button = $RightToolbar/ObjectsGrid/TokenButton
@onready var erase_button: Button = $RightToolbar/ObjectsGrid/EraseButton
@onready var void_button: Button = $RightToolbar/ObjectsGrid/VoidButton
@onready var new_button: Button = $SidebarScroll/VBoxContainer/NewButton
@onready var columns_input: SpinBox = $SidebarScroll/VBoxContainer/ColumnsInput
@onready var rows_input: SpinBox = $SidebarScroll/VBoxContainer/RowsInput
@onready var resize_button: Button = $SidebarScroll/VBoxContainer/ResizeButton
@onready var back_button: Button = $SidebarScroll/VBoxContainer/BackButton
@onready var status_label: Label = $ActiveToolLabel
@onready var object_count_input: SpinBox = $SidebarScroll/VBoxContainer/ObjectCountInput
@onready var goal_objects_button: Button = $SidebarScroll/VBoxContainer/GoalObjectsButton
@onready var goal_carry_selector: OptionButton = $SidebarScroll/VBoxContainer/GoalCarrySelector
@onready var move_limit_input: SpinBox = $SidebarScroll/VBoxContainer/MoveLimitInput
@onready var cmd_limit_input: SpinBox = $SidebarScroll/VBoxContainer/CmdLimitInput
@onready var time_limit_input: SpinBox = $SidebarScroll/VBoxContainer/TimeLimitInput
@onready var move_limit_default_checkbox: CheckBox = $SidebarScroll/VBoxContainer/MoveLimitDefaultCheckbox
@onready var cmd_limit_default_checkbox: CheckBox = $SidebarScroll/VBoxContainer/CmdLimitDefaultCheckbox
@onready var time_limit_default_checkbox: CheckBox = $SidebarScroll/VBoxContainer/TimeLimitDefaultCheckbox
func _ready() -> void:
	_arrange_sidebar()
	document.create_blank(10, 10)
	_set_goal_carry_selector()

	grid.set_document(document)
	grid.view_changed.connect(_layout_grid)
	resized.connect(_layout_grid)
	call_deferred("_layout_grid")
	save_button.disabled = true

	robot_button.pressed.connect(_on_robot_button_pressed)
	goal_button.pressed.connect(_on_goal_button_pressed)
	wall_button.pressed.connect(_on_wall_button_pressed)
	east_wall_button.pressed.connect(_on_east_wall_button_pressed)
	load_button.pressed.connect(_on_load_button_pressed)
	save_button.pressed.connect(_on_save_button_pressed)
	apple_button.pressed.connect(_on_apple_button_pressed)
	token_button.pressed.connect(_on_token_button_pressed)
	erase_button.pressed.connect(_on_erase_button_pressed)
	void_button.pressed.connect(func(): _select_tool(EditorGridView.Tool.VOID, void_button, "Void (Erase restores floor; start and goal stay solid)"))
	new_button.pressed.connect(_on_new_button_pressed)
	resize_button.pressed.connect(_on_resize_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	level_name_input.text_changed.connect(_on_level_name_changed)
	for tool_button in [robot_button, goal_button, wall_button, east_wall_button, apple_button, token_button, erase_button, void_button]:
		tool_button.toggle_mode = true
	robot_button.button_pressed = true
	object_count_input.value_changed.connect(_on_object_count_changed)
	goal_objects_button.pressed.connect(_on_goal_objects_button_pressed)
	goal_carry_selector.item_selected.connect(_on_goal_carry_changed)
	move_limit_default_checkbox.toggled.connect(_on_move_limit_default_toggled)
	cmd_limit_default_checkbox.toggled.connect(_on_cmd_limit_default_toggled)
	time_limit_default_checkbox.toggled.connect(_on_time_limit_default_toggled)


func _arrange_sidebar() -> void:
	var sidebar := $SidebarScroll/VBoxContainer
	var order := [
		"TitleLabel", "LevelNameLabel", "LevelNameInput", "DescriptionLabel", "DescriptionInput",
		"GridSetupLabel", "ColumnsLabel", "ColumnsInput", "RowsLabel", "RowsInput", "ResizeButton",
		"ObjectCountLabel", "ObjectCountInput",
		"GoalConfigLabel", "GoalObjectsButton", "GoalCarryLabel", "GoalCarrySelector",
		"LimitsLabel", "MoveLimitDefaultCheckbox", "MoveLimitLabel", "MoveLimitInput", "CmdLimitDefaultCheckbox", "CmdLimitLabel", "CmdLimitInput", "TimeLimitDefaultCheckbox", "TimeLimitLabel", "TimeLimitInput",
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
	for tool_button in [robot_button, goal_button, wall_button, east_wall_button, apple_button, token_button, erase_button, void_button]:
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
			for tool_button in [robot_button, goal_button, wall_button, east_wall_button, apple_button, token_button, erase_button, void_button]:
				tool_button.button_pressed = false
			status_label.text = "Pan mode: drag with left-click. Select a tool to place tiles again."
			get_viewport().set_input_as_handled()
			return

		if pan_mode and event.button_index == MOUSE_BUTTON_LEFT and event.position.x > SIDEBAR_WIDTH and event.position.x < size.x - TOOLBAR_WIDTH:
			is_panning = event.pressed
			get_viewport().set_input_as_handled()
			return

	if pan_mode and is_panning and event is InputEventMouseMotion:
		grid.pan_by(event.relative)
		get_viewport().set_input_as_handled()

func _on_save_button_pressed() -> void:
	var level_name := level_name_input.text.strip_edges()
	if level_name.is_empty():
		return
	document.data["name"] = level_name
	document.data["description"] = [description_input.text]
	# Save limits
	var limits_data := {}
	if not move_limit_default_checkbox.button_pressed and move_limit_input.value > 0:
		limits_data["move_limit"] = int(move_limit_input.value)
	if not cmd_limit_default_checkbox.button_pressed and cmd_limit_input.value > 0:
		limits_data["cmd_limit"] = int(cmd_limit_input.value)
	if not time_limit_default_checkbox.button_pressed and time_limit_input.value > 0:
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


func _on_level_name_changed(new_name: String) -> void:
	save_button.disabled = new_name.strip_edges().is_empty()
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
		description_input.text = "\n".join(PackedStringArray(document.data.get("description", [])))
		columns_input.value = int(document.data.get("cols", 10))
		rows_input.value = int(document.data.get("rows", 10))
		_set_goal_carry_selector()
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
		grid.set_document(document)
		grid.reset_pan()
		_layout_grid()
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


func _on_token_button_pressed() -> void:
	grid.set_object_type("token")
	_select_tool(EditorGridView.Tool.OBJECT, token_button, "Token")


func _on_erase_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.ERASE, erase_button, "Erase")


func _on_new_button_pressed() -> void:
	var cols := int(columns_input.value)
	var rows := int(rows_input.value)

	document.create_blank(cols, rows)
	_set_goal_carry_selector()
	grid.set_document(document)
	grid.reset_pan()
	_layout_grid()
	level_name_input.clear()
	description_input.clear()
	move_limit_default_checkbox.button_pressed = false
	cmd_limit_default_checkbox.button_pressed = false
	time_limit_default_checkbox.button_pressed = false
	move_limit_input.value = 0
	cmd_limit_input.value = 0
	time_limit_input.value = 0
	save_button.text = "Save Level"
	
func _on_resize_button_pressed() -> void:
	var cols := int(columns_input.value)
	var rows := int(rows_input.value)

	document.resize(cols, rows)
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

func _on_goal_carry_changed(index: int) -> void:
	var carry_modes := ["none", "token", "apple", "all_apples", "all_tokens", "all_apples_and_tokens"]
	var selected_carry := goal_carry_selector.get_item_text(index)
	var carry_mode: String = carry_modes[index]
	# Keep the requirement as a mode so it can describe one item or every placed item.
	document.data["goal"].erase("require_carry_object")
	if carry_mode == "none":
		document.data["goal"].erase("require_carry")
	else:
		document.data["goal"]["require_carry"] = carry_mode
	status_label.text = "Goal carry requirement: %s" % selected_carry


func _set_goal_carry_selector() -> void:
	var carry_modes := ["none", "token", "apple", "all_apples", "all_tokens", "all_apples_and_tokens"]
	var goal: Dictionary = document.data.get("goal", {})
	var mode := str(goal.get("require_carry", ""))
	if mode.is_empty() and goal.has("require_carry_object"):
		mode = str(goal["require_carry_object"])
	var selected_index := carry_modes.find(mode)
	goal_carry_selector.select(selected_index if selected_index >= 0 else 0)

func _open_goal_objects_dialog() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Set Goal Objects"
	dialog.unresizable = true
	
	var vbox := VBoxContainer.new()
	dialog.add_child(vbox)
	
	var instruction := Label.new()
	instruction.text = "Add goal object requirements (e.g., '6,4 token 5' for 5 tokens at tile 6,4):"
	vbox.add_child(instruction)
	
	var input := TextEdit.new()
	input.custom_minimum_size = Vector2(400, 150)
	input.placeholder_text = "Format: x,y object_type count\nExample:\n6,4 token 5\n1,5 apple 2"
	
	# Pre-fill with existing goal objects
	if document.data.has("goal") and document.data["goal"].has("objects"):
		var goal_objs: Dictionary = document.data["goal"]["objects"]
		var lines := []
		for key in goal_objs:
			var required: Dictionary = goal_objs[key]
			for obj_name in required:
				var count := int(required[obj_name])
				lines.append("%s %s %d" % [key, obj_name, count])
		input.text = "\n".join(lines)
	
	vbox.add_child(input)
	
	dialog.confirmed.connect(_apply_goal_objects.bind(input))
	add_child(dialog)
	dialog.popup_centered()

func _apply_goal_objects(input: TextEdit) -> void:
	var lines := input.text.split("\n")
	var goal_objects := {}
	
	for line in lines:
		line = line.strip_edges()
		if line.is_empty():
			continue
		var parts := line.split(" ")
		if parts.size() >= 3:
			var coords := parts[0].split(",")
			if coords.size() == 2:
				var x := int(coords[0])
				var y := int(coords[1])
				var obj_type := parts[1].to_lower()
				var count := int(parts[2])
				var key := "%d,%d" % [x, y]
				if not goal_objects.has(key):
					goal_objects[key] = {}
				goal_objects[key][obj_type] = count
	
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
	_on_back_button_pressed()
