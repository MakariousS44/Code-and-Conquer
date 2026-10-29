class_name LevelDocument
extends RefCounted

var data: Dictionary = {}

const MAX_GRID_SIZE := 50


func create_blank(cols: int = 10, rows: int = 10) -> void:
	data = {
		"cols": cols,
		"rows": rows,
		"robots": [
			{
				"x": 1,
				"y": 1,
				"_orientation": 0,
				"objects": {}
			}
		],
		"walls": {},
		"void_tiles": {},
		"objects": {},
		"goal": {
			"possible_final_positions": [[cols, rows]],
			"objects": {}
		}
	}


func load_level(raw_data: Dictionary) -> Dictionary:
	var candidate: Dictionary = raw_data.duplicate(true)
	var cols := int(candidate.get("cols", 0))
	var rows := int(candidate.get("rows", 0))
	if cols < 1 or rows < 1 or cols > MAX_GRID_SIZE or rows > MAX_GRID_SIZE:
		return {"ok": false, "error": "Level size must be between 1 and %d tiles." % MAX_GRID_SIZE}
	if not (candidate.get("robots", []) is Array) or candidate["robots"].is_empty() or not (candidate["robots"][0] is Dictionary):
		return {"ok": false, "error": "Level needs one robot."}
	if not (candidate.get("walls", {}) is Dictionary):
		return {"ok": false, "error": "Level walls are invalid."}
	if not (candidate.get("goal", {}) is Dictionary):
		return {"ok": false, "error": "Level needs a goal."}
	for wall in candidate["walls"].values():
		if not (wall is Array):
			return {"ok": false, "error": "Level walls are invalid."}

	# Older campaign files store their finish tile in goal.position. Convert it once
	# so the editor and newly saved files use the current format.
	var goal: Dictionary = candidate["goal"]
	if not (goal.get("possible_final_positions", []) is Array) or goal["possible_final_positions"].is_empty():
		var legacy_position = goal.get("position", {})
		if not (legacy_position is Dictionary):
			return {"ok": false, "error": "Goal position is invalid."}
		goal["possible_final_positions"] = [[int(legacy_position.get("x", 0)), int(legacy_position.get("y", 0))]]
	for position in goal["possible_final_positions"]:
		if not (position is Array) or position.size() < 2 or int(position[0]) < 1 or int(position[0]) > cols or int(position[1]) < 1 or int(position[1]) > rows:
			return {"ok": false, "error": "Goal position is outside the grid."}
	var robot: Dictionary = candidate["robots"][0]
	if int(robot.get("x", 0)) < 1 or int(robot.get("x", 0)) > cols or int(robot.get("y", 0)) < 1 or int(robot.get("y", 0)) > rows:
		return {"ok": false, "error": "Robot position is outside the grid."}
	goal["objects"] = goal.get("objects", {}) if goal.get("objects", {}) is Dictionary else {}
	candidate["goal"] = goal
	candidate["objects"] = candidate.get("objects", {}) if candidate.get("objects", {}) is Dictionary else {}
	candidate["description"] = candidate.get("description", []) if candidate.get("description", []) is Array else [str(candidate.get("description", ""))]
	var void_error := preload("res://map/scripts/void_tiles.gd").validate(candidate)
	if not void_error.is_empty():
		return {"ok": false, "error": void_error}
	data = candidate
	data["void_tiles"] = data.get("void_tiles", {})
	return {"ok": true}


func resize(cols: int, rows: int) -> void:
	data["cols"] = clampi(cols, 1, MAX_GRID_SIZE)
	data["rows"] = clampi(rows, 1, MAX_GRID_SIZE)
	var robot: Dictionary = data["robots"][0]
	robot["x"] = clampi(int(robot.get("x", 1)), 1, data["cols"])
	robot["y"] = clampi(int(robot.get("y", 1)), 1, data["rows"])
	var robots: Array = data["robots"]
	robots[0] = robot
	data["robots"] = robots
	var goal: Dictionary = data["goal"]
	var positions: Array = []
	for position in goal.get("possible_final_positions", []):
		if position is Array and position.size() >= 2:
			positions.append([clampi(int(position[0]), 1, data["cols"]), clampi(int(position[1]), 1, data["rows"])])
	goal["possible_final_positions"] = positions if not positions.is_empty() else [[data["cols"], data["rows"]]]
	goal.erase("position")
	data["goal"] = goal
	data["walls"] = _items_inside_grid(data["walls"])
	data["objects"] = _items_inside_grid(data["objects"])
	data["void_tiles"] = _items_inside_grid(data.get("void_tiles", {}))
	data["void_tiles"].erase("%d,%d" % [robot.x, robot.y])
	for position in goal["possible_final_positions"]:
		data["void_tiles"].erase("%d,%d" % [position[0], position[1]])


func _items_inside_grid(items: Dictionary) -> Dictionary:
	var kept := {}
	for key in items:
		var parts := str(key).split(",")
		if parts.size() == 2:
			var x := int(parts[0])
			var y := int(parts[1])
			if x >= 1 and x <= int(data["cols"]) and y >= 1 and y <= int(data["rows"]):
				kept[key] = items[key]
	return kept
