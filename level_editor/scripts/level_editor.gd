extends Control

const SIDEBAR_WIDTH := 280.0
const PROJECT_CUSTOM_LEVELS_DIR := "res://data/custom_levels/"
const PLAYER_CUSTOM_LEVELS_DIR := "user://custom_levels/"

var document := LevelDocument.new()

@onready var grid: EditorGridView = $EditorGrid as EditorGridView
@onready var robot_button: Button = $SidebarScroll/VBoxContainer/RobotButton
@onready var goal_button: Button = $SidebarScroll/VBoxContainer/GoalButton
@onready var wall_button: Button = $SidebarScroll/VBoxContainer/WallButton
@onready var east_wall_button: Button = $SidebarScroll/VBoxContainer/EastWallButton
@onready var load_button: Button = $SidebarScroll/VBoxContainer/LoadButton
@onready var description_input: TextEdit = $SidebarScroll/VBoxContainer/DescriptionInput
@onready var save_button: Button = $SidebarScroll/VBoxContainer/SaveButton
@onready var level_name_input: LineEdit = $SidebarScroll/VBoxContainer/LevelNameInput
@onready var apple_button: Button = $SidebarScroll/VBoxContainer/AppleButton
@onready var erase_button: Button = $SidebarScroll/VBoxContainer/EraseButton
@onready var void_button: Button = $SidebarScroll/VBoxContainer/VoidButton
@onready var new_button: Button = $SidebarScroll/VBoxContainer/NewButton
@onready var columns_input: SpinBox = $SidebarScroll/VBoxContainer/ColumnsInput
@onready var rows_input: SpinBox = $SidebarScroll/VBoxContainer/RowsInput
@onready var resize_button: Button = $SidebarScroll/VBoxContainer/ResizeButton
@onready var back_button: Button = $SidebarScroll/VBoxContainer/BackButton
@onready var status_label: Label = $SidebarScroll/VBoxContainer/StatusLabel

func _ready() -> void:
	_arrange_sidebar()
	document.create_blank(10, 10)

	grid.set_document(document)
	resized.connect(_center_grid)
	call_deferred("_center_grid")
	save_button.disabled = true

	robot_button.pressed.connect(_on_robot_button_pressed)
	goal_button.pressed.connect(_on_goal_button_pressed)
	wall_button.pressed.connect(_on_wall_button_pressed)
	east_wall_button.pressed.connect(_on_east_wall_button_pressed)
	load_button.pressed.connect(_on_load_button_pressed)
	save_button.pressed.connect(_on_save_button_pressed)
	apple_button.pressed.connect(_on_apple_button_pressed)
	erase_button.pressed.connect(_on_erase_button_pressed)
	void_button.pressed.connect(func(): _select_tool(EditorGridView.Tool.VOID, void_button, "Void (Erase restores floor; start and goal stay solid)"))
	new_button.pressed.connect(_on_new_button_pressed)
	resize_button.pressed.connect(_on_resize_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	level_name_input.text_changed.connect(_on_level_name_changed)
	for tool_button in [robot_button, goal_button, wall_button, east_wall_button, apple_button, erase_button, void_button]:
		tool_button.toggle_mode = true
	robot_button.button_pressed = true


func _arrange_sidebar() -> void:
	var sidebar := $SidebarScroll/VBoxContainer
	var order := [
		"TitleLabel", "LevelNameLabel", "LevelNameInput", "DescriptionLabel", "DescriptionInput",
		"GridSetupLabel", "ColumnsLabel", "ColumnsInput", "RowsLabel", "RowsInput", "ResizeButton",
		"PlacementLabel", "RobotButton", "GoalButton",
		"WallsLabel", "WallButton", "EastWallButton",
		"ObjectsLabel", "AppleButton", "VoidButton", "EraseButton",
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


func _center_grid() -> void:
	if document.data.is_empty():
		return
	var grid_size := Vector2(
		int(document.data["cols"]) * EditorGridView.CELL_SIZE,
		int(document.data["rows"]) * EditorGridView.CELL_SIZE
	)
	var available_size := size - Vector2(SIDEBAR_WIDTH, 0.0)
	var fit := maxf(0.05, minf((available_size.x - 48.0) / grid_size.x, (available_size.y - 48.0) / grid_size.y))
	grid.scale = Vector2.ONE * minf(fit, 1.5)
	grid.position = Vector2(SIDEBAR_WIDTH, 0.0) + (available_size - grid_size * grid.scale) * 0.5
	
func _on_robot_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.ROBOT, robot_button, "Robot")


func _on_goal_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.GOAL, goal_button, "Goal")

func _on_wall_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.WALL, wall_button, "North Wall")


func _on_east_wall_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.EAST_WALL, east_wall_button, "East Wall")


func _select_tool(tool: int, selected_button: Button, tool_name: String) -> void:
	grid.set_tool(tool)
	for tool_button in [robot_button, goal_button, wall_button, east_wall_button, apple_button, erase_button, void_button]:
		tool_button.button_pressed = tool_button == selected_button
	status_label.text = "Active tool: %s" % tool_name

func _on_save_button_pressed() -> void:
	var level_name := level_name_input.text.strip_edges()
	if level_name.is_empty():
		return
	document.data["name"] = level_name
	document.data["description"] = [description_input.text]

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
		grid.set_document(document)
		_center_grid()
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
	_select_tool(EditorGridView.Tool.APPLE, apple_button, "Apple")


func _on_erase_button_pressed() -> void:
	_select_tool(EditorGridView.Tool.ERASE, erase_button, "Erase")


func _on_new_button_pressed() -> void:
	var cols := int(columns_input.value)
	var rows := int(rows_input.value)

	document.create_blank(cols, rows)
	grid.set_document(document)
	_center_grid()
	level_name_input.clear()
	description_input.clear()
	save_button.text = "Save Level"
	
func _on_resize_button_pressed() -> void:
	var cols := int(columns_input.value)
	var rows := int(rows_input.value)

	document.resize(cols, rows)
	grid.set_document(document)
	_center_grid()
	save_button.text = "Save Level"


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu/scenes/main_menu.tscn")
