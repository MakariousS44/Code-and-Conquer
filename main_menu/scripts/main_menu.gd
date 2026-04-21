extends Control

var OptionsOpen := false
var LevelsOpen := false

var selected_level_path: String = ""

const CUSTOM_LEVELS_DIR := "user://custom_levels/"

@onready var level_file_dialog: FileDialog = $UploadMarginContainer/VBoxContainer/FileDialog

func _ready() -> void:
	level_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	level_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	level_file_dialog.clear_filters()
	level_file_dialog.add_filter("*.json ; JSON Level Files")
	level_file_dialog.file_selected.connect(_on_level_file_selected)

func _on_button_start_pressed() -> void:
	$TabMoveSound.play()
	var tween = create_tween()
	
	if LevelsOpen == false:
		var duration = 1.0
		var distance = Vector2(-300, 0)
		var target_pos = position + distance

		tween.tween_property($"LevelsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		LevelsOpen = true
	else:
		var duration = 1.0
		var distance = Vector2(-600, 0)
		var target_pos = position + distance

		tween.tween_property($"LevelsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		LevelsOpen = false

func _on_options_button_pressed() -> void:
	$TabMoveSound.play()
	var tween = create_tween()
	
	if OptionsOpen == false:
		var duration = 1.0
		var distance = Vector2(1000, 0)
		var target_pos = position + distance

		tween.tween_property($"OptionsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		OptionsOpen = true
	else:
		var duration = 1.0
		var distance = Vector2(1300, 0)
		var target_pos = position + distance

		tween.tween_property($"OptionsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		OptionsOpen = false

func _on_quit_button_pressed() -> void:
	$QuitSound.play()
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

func _on_upload_level_button_pressed() -> void:
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

	selected_level_path = dest_path
	SelectedLevel.path = dest_path

	print("SelectedLevel.path set to: ", SelectedLevel.path)

	if has_node("LevelsTab/PanelContainer/MarginContainer/VBoxContainer/MenuButton"):
		var dropdown = $LevelsTab/PanelContainer/MarginContainer/VBoxContainer/MenuButton
		if dropdown.has_method("populate_from_folder"):
			dropdown.populate_from_folder(CUSTOM_LEVELS_DIR)
			print("Dropdown refreshed.")

func _on_play_button_pressed() -> void:
	$StartSound.play()
	var tween = create_tween()
	tween.set_parallel(true)
	
	var duration = 1.0
	var distance = Vector2(-600, 0)
	var target_pos = $"LevelsTab".position + distance
	tween.tween_property($"LevelsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
	
	duration = 1.0
	distance = Vector2(400, 0)
	target_pos = $"OptionsTab".position + distance
	tween.tween_property($"OptionsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
	
	tween.tween_property($Mask, "modulate:a", 0.0, 1.0)
	
	tween.set_parallel(false)
	tween.tween_property($Mask, "modulate:a", 255.0, 1.2)

	await get_tree().create_timer(2.2).timeout

	if selected_level_path != "":
		SelectedLevel.path = selected_level_path

	get_tree().change_scene_to_file("res://workstation/scenes/workstation.tscn")
