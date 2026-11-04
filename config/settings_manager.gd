extends Node

const SETTINGS_PATH := "user://settings.cfg"

var _config := ConfigFile.new()


func _ready() -> void:
	reload_settings()


func reload_settings() -> void:
	_config = ConfigFile.new()
	_config.load(SETTINGS_PATH)
	_apply_global_settings()


func get_setting(section: String, key: String, fallback):
	return _config.get_value(section, key, fallback)


func _apply_global_settings() -> void:
	var ui_scale_index := clampi(int(get_setting("display", "ui_scale", 1)), 0, 2)
	var ui_scales := [0.85, 1.0, 1.15]
	get_window().content_scale_factor = ui_scales[ui_scale_index]
