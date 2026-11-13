extends "res://workstation/scripts/workstation.gd"

# Skip the normal startup so tests don't kill a running student program.
func _ready() -> void:
	_setup_campaign_ui()
	_setup_language_selector()
	_load_level_scene()
