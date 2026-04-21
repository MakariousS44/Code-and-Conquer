extends Control

const CUSTOM_LEVELS_DIR := "user://custom_levels/"

@onready var level_popup: Window = $LevelSelectPopup
@onready var options_popup: Window = get_node_or_null("OptionsPopup")
@onready var level_file_dialog: FileDialog = $FileDialog

# main menu buttons
@onready var start_button: Button = $StartButton
@onready var options_button: Button = $OptionsButton
@onready var quit_button: Button = $QuitButton

# popup controls
@onready var play_button: Button = $LevelSelectPopup/CenterContainer/MarginContainer/VBoxContainer/PlayButton
@onready var upload_button: Button = $LevelSelectPopup/CenterContainer/MarginContainer/VBoxContainer/UploadLevelButton
@onready var level_dropdown: OptionButton = $LevelSelectPopup/CenterContainer/MarginContainer/VBoxContainer/MenuButton


func _ready() -> void:
	if level_popup == null:
		push_error("LevelSelectPopup node not found.")
		return

	if level_file_dialog == null:
		push_error("FileDialog node not found.")
		return

	level_popup.hide()

	if options_popup != null:
		options_popup.hide()

	level_file_dialog.hide()
	level_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	level_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	level_file_dialog.clear_filters()
	level_file_dialog.add_filter("*.json ; JSON Level Files")

	if not level_file_dialog.file_selected.is_connected(_on_level_file_selected):
		level_file_dialog.file_selected.connect(_on_level_file_selected)

	# connect buttons in code so scene signal hookups can't betray you
	if start_button != null and not start_button.pressed.is_connected(_on_button_start_pressed):
		start_button.pressed.connect(_on_button_start_pressed)

	if options_button != null and not options_button.pressed.is_connected(_on_options_button_pressed):
		options_button.pressed.connect(_on_options_button_pressed)

	if quit_button != null and not quit_button.pressed.is_connected(_on_quit_button_pressed):
		quit_button.pressed.connect(_on_quit_button_pressed)

	if play_button != null and not play_button.pressed.is_connected(_on_play_button_pressed):
		play_button.pressed.connect(_on_play_button_pressed)

	if upload_button != null and not upload_button.pressed.is_connected(_on_upload_level_button_pressed):
		upload_button.pressed.connect(_on_upload_level_button_pressed)

	# populate dropdown once on startup
	if level_dropdown != null and level_dropdown.has_method("populate_from_folder"):
		level_dropdown.populate_from_folder(CUSTOM_LEVELS_DIR)


func _on_button_start_pressed() -> void:
	print("START BUTTON PRESSED")
	$TabMoveSound.play()

	if level_dropdown != null and level_dropdown.has_method("populate_from_folder"):
		level_dropdown.populate_from_folder(CUSTOM_LEVELS_DIR)

	level_popup.popup_centered()


func _on_options_button_pressed() -> void:
	print("OPTIONS BUTTON PRESSED")
	$TabMoveSound.play()
	if options_popup != null:
		options_popup.popup_centered()


func _on_quit_button_pressed() -> void:
	print("QUIT BUTTON PRESSED")
	$QuitSound.play()
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


func _on_upload_level_button_pressed() -> void:
	print("UPLOAD BUTTON PRESSED")
	$TabMoveSound.play()
	level_file_dialog.popup_centered_ratio(0.75)


func _on_level_file_selected(path: String) -> void:
	print("=== FILE SELECTED ===")
	print("Original selected path: ", path)

	var real_custom_dir := ProjectSettings.globalize_path(CUSTOM_LEVELS_DIR)
	print("Virtual custom dir: ", CUSTOM_LEVELS_DIR)
	print("Real custom dir: ", real_custom_dir)

	var mkdir_result := DirAccess.make_dir_recursive_absolute(real_custom_dir)
	print("mkdir result: ", mkdir_result)

	var file_name := path.get_file()
	var dest_path := CUSTOM_LEVELS_DIR.path_join(file_name)
	var real_dest_path := ProjectSettings.globalize_path(dest_path)

	print("Destination virtual path: ", dest_path)
	print("Destination real path: ", real_dest_path)

	var source_file := FileAccess.open(path, FileAccess.READ)
	if source_file == null:
		push_error("Could not open selected file: " + path)
		return

	var contents := source_file.get_as_text()
	source_file.close()

	print("Read source file successfully. Length: ", contents.length())

	var dest_file := FileAccess.open(dest_path, FileAccess.WRITE)
	if dest_file == null:
		push_error("Could not save imported level to: " + dest_path)
		return

	dest_file.store_string(contents)
	dest_file.close()

	print("File copied successfully.")
	print("File exists at destination: ", FileAccess.file_exists(dest_path))

	if level_dropdown != null and level_dropdown.has_method("populate_from_folder"):
		level_dropdown.populate_from_folder(CUSTOM_LEVELS_DIR)

	if level_dropdown != null and level_dropdown.has_method("select_path"):
		level_dropdown.select_path(dest_path)
	else:
		SelectedLevel.path = dest_path

	print("SelectedLevel.path set to: ", SelectedLevel.path)


func _on_play_button_pressed() -> void:
	print("PLAY BUTTON PRESSED")
	print("PLAY pressed. SelectedLevel.path = ", SelectedLevel.path)

	$StartSound.play()
	level_popup.hide()

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property($Mask, "modulate:a", 0.0, 1.0)

	tween.set_parallel(false)
	tween.tween_property($Mask, "modulate:a", 255.0, 1.2)

	await get_tree().create_timer(2.2).timeout
	get_tree().change_scene_to_file("res://workstation/scenes/workstation.tscn")


func _on_level_select_popup_close_requested() -> void:
	level_popup.hide()


func _on_options_popup_close_requested() -> void:
	if options_popup != null:
		options_popup.hide()
