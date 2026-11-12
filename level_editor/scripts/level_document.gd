class_name LevelDocument
extends RefCounted

var data: Dictionary = {}

const MAX_GRID_SIZE := 30


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
			"objects": {},
			"require_carry": {}
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
	if not candidate.has("walls"):
		candidate["walls"] = {}
	elif not (candidate["walls"] is Dictionary):
		return {"ok": false, "error": "Level walls are invalid."}
	for wall in candidate["walls"].values():
		if not (wall is Array):
			return {"ok": false, "error": "Level walls are invalid."}

	# Older campaign files store their finish tile in goal.position. Convert it once
	# so the editor and newly saved files use the current format.
	var goal: Dictionary = candidate["goal"]
	var positions = goal.get("possible_final_positions", [])
	var use_legacy_position: bool = not (positions is Array) or positions.is_empty()
	var normalized_positions: Array = []
	if use_legacy_position:
		var legacy_coordinates := _legacy_goal_coordinates(goal)
		if legacy_coordinates.is_empty():
			return {"ok": false, "error": "Goal position is invalid."}
		if not _coordinates_in_bounds(legacy_coordinates, cols, rows):
			return {"ok": false, "error": "Goal position is outside the grid."}
		normalized_positions = [[int(legacy_coordinates[0]), int(legacy_coordinates[1])]]
	else:
		for position in positions:
			var coordinates := _goal_coordinates(position)
			if coordinates.is_empty():
				return {"ok": false, "error": "Goal position is invalid."}
			if not _coordinates_in_bounds(coordinates, cols, rows):
				return {"ok": false, "error": "Goal position is outside the grid."}
			normalized_positions.append([int(coordinates[0]), int(coordinates[1])])
	if not use_legacy_position and goal.get("position") is Dictionary:
		# The runtime treats goal.position as an extra finish tile, so a
		# distinct legacy tile is merged in rather than dropped.
		var legacy_coordinates := _legacy_goal_coordinates(goal)
		if legacy_coordinates.is_empty():
			return {"ok": false, "error": "Goal position is invalid."}
		if not _coordinates_in_bounds(legacy_coordinates, cols, rows):
			return {"ok": false, "error": "Goal position is outside the grid."}
		var legacy_tile := [int(legacy_coordinates[0]), int(legacy_coordinates[1])]
		var already_listed := false
		for position in normalized_positions:
			if position[0] == legacy_tile[0] and position[1] == legacy_tile[1]:
				already_listed = true
				break
		if not already_listed:
			normalized_positions.append(legacy_tile)
	goal["possible_final_positions"] = normalized_positions
	goal.erase("position")
	var robot: Dictionary = candidate["robots"][0]
	if int(robot.get("x", 0)) < 1 or int(robot.get("x", 0)) > cols or int(robot.get("y", 0)) < 1 or int(robot.get("y", 0)) > rows:
		return {"ok": false, "error": "Robot position is outside the grid."}
	goal["objects"] = goal.get("objects", {}) if goal.get("objects", {}) is Dictionary else {}
	var carry_error := preload("res://map/scripts/carry_requirements.gd").validate(candidate)
	if not carry_error.is_empty():
		return {"ok": false, "error": carry_error}
	candidate["goal"] = goal
	if not candidate.has("objects"):
		candidate["objects"] = {}
	elif not (candidate["objects"] is Dictionary):
		return {"ok": false, "error": "Level objects are invalid."}
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


func _legacy_goal_coordinates(goal: Dictionary) -> Array:
	var legacy_position = goal.get("position", {})
	if not (legacy_position is Dictionary):
		return []
	return _coordinate_pair(legacy_position.get("x", 0), legacy_position.get("y", 0))


func _goal_coordinates(position: Variant) -> Array:
	if not (position is Array) or position.size() < 2:
		return []
	return _coordinate_pair(position[0], position[1])


func _coordinate_pair(x: Variant, y: Variant) -> Array:
	if not _is_grid_coordinate(x) or not _is_grid_coordinate(y):
		return []
	return [float(x), float(y)]


func _is_grid_coordinate(value: Variant) -> bool:
	var value_type := typeof(value)
	if value_type != TYPE_INT and value_type != TYPE_FLOAT:
		return false
	var coordinate := float(value)
	return coordinate == floor(coordinate)


func _coordinates_in_bounds(coordinates: Array, cols: int, rows: int) -> bool:
	return coordinates[0] >= 1.0 and coordinates[0] <= float(cols) and coordinates[1] >= 1.0 and coordinates[1] <= float(rows)


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
