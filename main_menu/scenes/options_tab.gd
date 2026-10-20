extends Control

const SETTINGS_PATH := "user://settings.cfg"

@onready var volume_slider: HSlider = $Panel/VBoxContainer/VolumeSlider
@onready var music_slider: HSlider = $Panel/VBoxContainer/MusicSlider
@onready var sfx_slider: HSlider = $Panel/VBoxContainer/SfxSlider
@onready var fullscreen_check: CheckButton = $Panel/VBoxContainer/FullscreenCheck
@onready var ui_scale_option: OptionButton = $Panel/VBoxContainer/UiScaleOption
@onready var code_font_size_option: OptionButton = $Panel/VBoxContainer/CodeFontSizeOption
@onready var editor_theme_option: OptionButton = $Panel/VBoxContainer/EditorThemeOption
@onready var animation_speed_option: OptionButton = $Panel/VBoxContainer/AnimationSpeedOption
@onready var grid_coordinates_check: CheckButton = $Panel/VBoxContainer/GridCoordinatesCheck
@onready var command_trail_check: CheckButton = $Panel/VBoxContainer/CommandTrailCheck
@onready var beginner_hints_check: CheckButton = $Panel/VBoxContainer/BeginnerHintsCheck
@onready var default_language_option: OptionButton = $Panel/VBoxContainer/DefaultLanguageOption
@onready var reset_button: Button = $Panel/VBoxContainer/ResetButton
@onready var back_button: Button = $Panel/VBoxContainer/BackButton

func _ready() -> void:
	_populate_choice_lists()
	_load_settings()

	if not volume_slider.value_changed.is_connected(_on_volume_changed):
		volume_slider.value_changed.connect(_on_volume_changed)
	if not fullscreen_check.toggled.is_connected(_on_fullscreen_toggled):
		fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	if not music_slider.value_changed.is_connected(_on_preference_changed):
		music_slider.value_changed.connect(_on_preference_changed)
	if not sfx_slider.value_changed.is_connected(_on_preference_changed):
		sfx_slider.value_changed.connect(_on_preference_changed)
	for option in [ui_scale_option, code_font_size_option, editor_theme_option, animation_speed_option, default_language_option]:
		if not option.item_selected.is_connected(_on_option_selected):
			option.item_selected.connect(_on_option_selected)
	for check in [grid_coordinates_check, command_trail_check, beginner_hints_check]:
		if not check.toggled.is_connected(_on_toggle_changed):
			check.toggled.connect(_on_toggle_changed)
	if not reset_button.pressed.is_connected(_on_reset_button_pressed):
		reset_button.pressed.connect(_on_reset_button_pressed)
	if not back_button.pressed.is_connected(hide):
		back_button.pressed.connect(hide)

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))
	_save_settings()
func _on_fullscreen_toggled(enabled: bool) -> void:
	if enabled:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	_save_settings()
func _load_settings() -> void:
	var config := ConfigFile.new()

	if config.load(SETTINGS_PATH) == OK:
		volume_slider.value = float(config.get_value("audio", "master_volume", 1.0))
		music_slider.value = float(config.get_value("audio", "music_volume", 1.0))
		sfx_slider.value = float(config.get_value("audio", "sfx_volume", 1.0))
		fullscreen_check.button_pressed = bool(config.get_value("display", "fullscreen", false))
		ui_scale_option.select(int(config.get_value("display", "ui_scale", 1)))
		code_font_size_option.select(int(config.get_value("editor", "font_size", 1)))
		editor_theme_option.select(int(config.get_value("editor", "theme", 0)))
		animation_speed_option.select(int(config.get_value("gameplay", "animation_speed", 0)))
		grid_coordinates_check.button_pressed = bool(config.get_value("learning", "show_grid_coordinates", false))
		command_trail_check.button_pressed = bool(config.get_value("learning", "show_command_trail", true))
		beginner_hints_check.button_pressed = bool(config.get_value("learning", "beginner_hints", true))
		default_language_option.select(int(config.get_value("editor", "default_language", 0)))
	else:
		volume_slider.value = 1.0
		music_slider.value = 1.0
		sfx_slider.value = 1.0
		fullscreen_check.button_pressed = false

	_apply_settings()


func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(volume_slider.value))

	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", volume_slider.value)
	config.set_value("audio", "music_volume", music_slider.value)
	config.set_value("audio", "sfx_volume", sfx_slider.value)
	config.set_value("display", "fullscreen", fullscreen_check.button_pressed)
	config.set_value("display", "ui_scale", ui_scale_option.selected)
	config.set_value("editor", "font_size", code_font_size_option.selected)
	config.set_value("editor", "theme", editor_theme_option.selected)
	config.set_value("gameplay", "animation_speed", animation_speed_option.selected)
	config.set_value("learning", "show_grid_coordinates", grid_coordinates_check.button_pressed)
	config.set_value("learning", "show_command_trail", command_trail_check.button_pressed)
	config.set_value("learning", "beginner_hints", beginner_hints_check.button_pressed)
	config.set_value("editor", "default_language", default_language_option.selected)
	config.save(SETTINGS_PATH)
	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		settings_manager.reload_settings()


func _populate_choice_lists() -> void:
	_add_choices(ui_scale_option, ["Small", "Medium", "Large"])
	_add_choices(code_font_size_option, ["Small", "Medium", "Large"])
	_add_choices(editor_theme_option, ["Dark", "Light"])
	_add_choices(animation_speed_option, ["Normal", "Fast"])
	_add_choices(default_language_option, ["Python", "C++"])


func _add_choices(option: OptionButton, choices: Array[String]) -> void:
	option.clear()
	for choice in choices:
		option.add_item(choice)


func _on_preference_changed(_value: float) -> void:
	_save_settings()


func _on_option_selected(_index: int) -> void:
	_save_settings()


func _on_toggle_changed(_enabled: bool) -> void:
	_save_settings()


func _on_reset_button_pressed() -> void:
	volume_slider.value = 1.0
	music_slider.value = 1.0
	sfx_slider.value = 1.0
	fullscreen_check.button_pressed = false
	ui_scale_option.select(1)
	code_font_size_option.select(1)
	editor_theme_option.select(0)
	animation_speed_option.select(0)
	grid_coordinates_check.button_pressed = false
	command_trail_check.button_pressed = true
	beginner_hints_check.button_pressed = true
	default_language_option.select(0)
	_apply_settings()
	_save_settings()
