# main_menu.gd
# To whom it may concern: This script runs the main menu, duh! It wires up buttons, manages the
# level select popup, handles custom level importing, and starts the transition into the actual
# workstation/ actual game situation. I have tried to include comments outlining functionalities
# below.

# Used by: main_menu.tscn (main_menu scene file)
# Relies on: level_loader.gd (which populates the level dropdown), selected_level.gd (which holds
# selected level path)

extends Control

const CUSTOM_LEVELS_DIR := "user://custom_levels/"

# we used get_node_or_null() directly here instead of going through get_tree().current_scene
# on Linux, current_scene can be null when these vars get initialized direct paths are fine 
# since this script lives on the root node! but if you make changes to the setup you'll need to 
# beware!

@onready var level_popup: Window = get_node_or_null("MenuBG/LevelSelectPopup")
@onready var options_popup: Control = get_node_or_null("MenuBG/OptionsTab")
@onready var level_file_dialog: FileDialog = get_node_or_null("MenuBG/FileDialog")

# main menu buttons
@onready var main_menu_start_button: Button = get_node_or_null("MenuBG/ButtonsContainer/StartButton")
@onready var upload_button: Button = get_node_or_null("MenuBG/ButtonsContainer/Upload")
@onready var options_button: Button = get_node_or_null("MenuBG/ButtonsContainer/OptionsButton")
@onready var quit_button: Button = get_node_or_null("MenuBG/ButtonsContainer/QuitButton")

# popup controls
@onready var popup_play_button: Button = get_node_or_null("MenuBG/LevelSelectPopup/VBoxContainer/PlayButton")
@onready var level_dropdown: OptionButton = get_node_or_null("MenuBG/LevelSelectPopup/VBoxContainer/MenuButton")


func _ready() -> void:
	# bail early if critical nodes are missing, nothing below will work without them
	if level_popup == null:
		push_error("LevelSelectPopup node not found.")
		return

	if level_file_dialog == null:
		push_error("FileDialog node not found.")
		return

	# make sure the custom levels folder exists before we try to use it...if not, it makes one!
	var real_custom_dir := ProjectSettings.globalize_path(CUSTOM_LEVELS_DIR)
	DirAccess.make_dir_recursive_absolute(real_custom_dir)

	# hide popups on startup so they don't flash on screen
	level_popup.hide()
	if options_popup != null:
		options_popup.hide()

	# set up the file dialog for importing .json level files
	level_file_dialog.hide()
	level_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	level_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	level_file_dialog.clear_filters()
	level_file_dialog.add_filter("*.json ; JSON Level Files")

	# wire up all signals in code: the scene file also has connections, so we
	# gots to check 'is_connected' first to make sure nothing gets hooked up twice
	if not level_file_dialog.file_selected.is_connected(_on_level_file_selected):
		level_file_dialog.file_selected.connect(_on_level_file_selected)

	if main_menu_start_button != null and not main_menu_start_button.pressed.is_connected(_on_button_start_pressed):
		main_menu_start_button.pressed.connect(_on_button_start_pressed)

	if upload_button != null and not upload_button.pressed.is_connected(_on_upload_level_button_pressed):
		upload_button.pressed.connect(_on_upload_level_button_pressed)

	if options_button != null and not options_button.pressed.is_connected(_on_options_button_pressed):
		options_button.pressed.connect(_on_options_button_pressed)

	if quit_button != null and not quit_button.pressed.is_connected(_on_quit_button_pressed):
		quit_button.pressed.connect(_on_quit_button_pressed)

	if popup_play_button != null and not popup_play_button.pressed.is_connected(_on_play_button_pressed):
		popup_play_button.pressed.connect(_on_play_button_pressed)

	# level_loader.gd populates the dropdown in its own _ready(), no need to do it again here
	if level_dropdown != null:
		level_dropdown.item_selected.connect(func(_i: int): _update_play_button())

	_update_play_button()


# keeps the play button greyed out until the user has actually picked a level
func _update_play_button() -> void:
	if popup_play_button != null:
		popup_play_button.disabled = SelectedLevel.path.is_empty()


func _on_button_start_pressed() -> void:
	$TabMoveSound.play()

	# refreshes the dropdown in case new levels were added since the menu loaded the first time
	# users can drag and drop to the file outside of the game so this is important
	if level_dropdown != null and level_dropdown.has_method("populate_from_folder"):
		level_dropdown.populate_from_folder(CUSTOM_LEVELS_DIR)

	if level_popup != null:
		level_popup.popup_centered()


func _on_options_button_pressed() -> void:
	$TabMoveSound.play()

	if options_popup != null:
		options_popup.show()


var _quitting := false
func _on_quit_button_pressed() -> void:
	# prevents the quit sequence from running 2 times if the button gets clicked again during the delay
	if _quitting:
		return
	_quitting = true
	$QuitSound.play()
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()


func _on_upload_level_button_pressed() -> void:
	$TabMoveSound.play()

	if level_file_dialog != null:
		level_file_dialog.popup_centered_ratio(0.75)


# this will copy the selected file into the custom levels folder and refreshes the dropdown
func _on_level_file_selected(path: String) -> void:
	var real_custom_dir := ProjectSettings.globalize_path(CUSTOM_LEVELS_DIR)
	DirAccess.make_dir_recursive_absolute(real_custom_dir)

	var file_name := path.get_file()
	var dest_path := CUSTOM_LEVELS_DIR.path_join(file_name)

	var source_file := FileAccess.open(path, FileAccess.READ)
	if source_file == null:
		push_error("Could not open selected file: " + path)
		return

	var contents := source_file.get_as_text()
	source_file.close()

	var dest_file := FileAccess.open(dest_path, FileAccess.WRITE)
	if dest_file == null:
		push_error("Could not save imported level to: " + dest_path)
		return

	dest_file.store_string(contents)
	dest_file.close()

	if level_dropdown != null and level_dropdown.has_method("populate_from_folder"):
		level_dropdown.populate_from_folder(CUSTOM_LEVELS_DIR)

	if level_dropdown != null and level_dropdown.has_method("select_path"):
		level_dropdown.select_path(dest_path)
	else:
		SelectedLevel.path = dest_path


# plays a little fade animation then loads the workstation scene
func _on_play_button_pressed() -> void:
	if SelectedLevel.path.is_empty():
		return

	$StartSound.play()

	if level_popup != null:
		level_popup.hide()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property($Mask, "modulate:a", 0.0, 1.0)

	tween.set_parallel(false)
	tween.tween_property($Mask, "modulate:a", 255.0, 1.2)

	await get_tree().create_timer(2.2).timeout
	get_tree().change_scene_to_file("res://workstation/scenes/workstation.tscn")


func _on_level_select_popup_close_requested() -> void:
	if level_popup != null:
		level_popup.hide()
