class_name CampaignLevels
extends RefCounted

const SAVE_PATH := "user://campaign_progress.cfg"
const LEVELS := [
	{"id": "first_steps", "title": "First Steps", "concept": "Move forward", "path": "res://data/campaign_levels/campaign/01_first_steps.json"},
	{"id": "around_the_corner", "title": "Around the Corner", "concept": "Move and turn left", "path": "res://data/campaign_levels/campaign/02_around_the_corner.json"},
	{"id": "winding_path", "title": "The Winding Path", "concept": "Plan a sequence of commands", "path": "res://data/campaign_levels/campaign/03_winding_path.json"},
	{"id": "long_hallway", "title": "Long Hallway", "concept": "A long hallway", "path": "res://data/campaign_levels/campaign/04_long_hallway.json"},
	{"id": "staircase", "title": "Staircase Pattern", "concept": "A repeatable pattern", "path": "res://data/campaign_levels/campaign/05_staircase.json"},
	{"id": "first_pickup", "title": "First Pickup", "concept": "An object must be picked up", "path": "res://data/campaign_levels/campaign/06_first_pickup.json"},
]

static func index_for_path(path: String) -> int:
	for i in range(LEVELS.size()):
		if LEVELS[i].path == path:
			return i
	return -1

static func completed_ids(save_path: String = SAVE_PATH) -> Array:
	var config := ConfigFile.new()
	if config.load(save_path) != OK:
		return []
	var saved = config.get_value("campaign", "completed", [])
	return saved if saved is Array else []

static func is_unlocked(index: int, completed: Array) -> bool:
	if index < 0 or index >= LEVELS.size():
		return false
	return index == 0 or LEVELS[index].id in completed or LEVELS[index - 1].id in completed

static func mark_complete(path: String, save_path: String = SAVE_PATH) -> Error:
	var index := index_for_path(path)
	if index < 0:
		return ERR_INVALID_PARAMETER
	var completed := completed_ids(save_path)
	if not is_unlocked(index, completed):
		return ERR_UNAUTHORIZED
	if LEVELS[index].id not in completed:
		completed.append(LEVELS[index].id)
	var config := ConfigFile.new()
	config.set_value("campaign", "completed", completed)
	return config.save(save_path)
