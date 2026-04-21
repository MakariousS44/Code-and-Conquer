extends Control

var OptionsOpen := false
var LevelsOpen := false

var selected_level_path: String = ""

@onready var level_file_dialog: FileDialog = $UploadMarginContainer/FileDialog

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

		tween.tween_property($"MenuBG/LevelsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		LevelsOpen = true
	else:
		var duration = 1.0
		var distance = Vector2(-600, 0)
		var target_pos = position + distance

		tween.tween_property($"MenuBG/LevelsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		LevelsOpen = false

func _on_options_button_pressed() -> void:
	$TabMoveSound.play()
	var tween = create_tween()

	if OptionsOpen == false:
		var duration = 1.0
		var distance = Vector2(1000, 0)
		var target_pos = position + distance

		tween.tween_property($"MenuBG/OptionsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		OptionsOpen = true
	else:
		var duration = 1.0
		var distance = Vector2(1300, 0)
		var target_pos = position + distance

		tween.tween_property($"MenuBG/OptionsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		OptionsOpen = false

func _on_quit_button_pressed() -> void:
	$QuitSound.play()
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

func _on_upload_level_button_pressed() -> void:
	$TabMoveSound.play()
	level_file_dialog.popup_centered_ratio(0.75)

func _on_level_file_selected(path: String) -> void:
	selected_level_path = path
	print("Selected level file: ", selected_level_path)

func _on_play_button_pressed() -> void:
	$StartSound.play()
	var tween = create_tween()
	tween.set_parallel(true)

	var duration = 1.0
	var distance = Vector2(-600, 0)
	var target_pos = $"MenuBG/LevelsTab".position + distance
	tween.tween_property($"MenuBG/LevelsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)

	duration = 1.0
	distance = Vector2(400, 0)
	target_pos = $"MenuBG/OptionsTab".position + distance
	tween.tween_property($"MenuBG/OptionsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)

	tween.tween_property($Mask, "modulate:a", 0.0, 1.0)

	tween.set_parallel(false)
	tween.tween_property($Mask, "modulate:a", 255.0, 1.2)

	await get_tree().create_timer(2.2).timeout

	if selected_level_path != "":
		SelectedLevel.path = selected_level_path

	get_tree().change_scene_to_file("res://workstation/scenes/workstation.tscn")
