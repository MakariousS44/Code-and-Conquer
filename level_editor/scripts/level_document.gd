class_name LevelDocument
extends RefCounted

var data: Dictionary = {}

const MAX_GRID_SIZE := 30
const VALID_OBJECT_NAMES := ["apple", "banana", "carrot", "star", "token"]
const VALID_WALL_DIRECTIONS := ["north", "east"]
const CARRY_RULES := preload("res://map/scripts/carry_requirements.gd")


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


## Collects every problem in the current level data before saving.
## Returns {"errors": PackedStringArray, "warnings": PackedStringArray}.
## Errors mean the file would be rejected or broken when loaded; warnings mean
## the level is legal but probably cannot be completed as designed.
func validate_level() -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()

	var cols := int(data.get("cols", 0))
	var rows := int(data.get("rows", 0))
	var size_ok := cols >= 1 and rows >= 1 and cols <= MAX_GRID_SIZE and rows <= MAX_GRID_SIZE
	if not size_ok:
		errors.append("Grid size must be between 1 and %d tiles." % MAX_GRID_SIZE)

	var void_raw = data.get("void_tiles", {})
	var void_tiles: Dictionary = void_raw if void_raw is Dictionary else {}
	if not (void_raw is Dictionary):
		errors.append("Void tiles data is invalid.")

	# --- robot start and starting inventory ---
	var robot := {}
	var inventory := {}
	var robot_position_ok := false
	var robots = data.get("robots", [])
	if not (robots is Array) or robots.is_empty() or not (robots[0] is Dictionary):
		errors.append("Level needs one robot.")
	else:
		robot = robots[0]
		if _is_number(robot.get("x")) and _is_number(robot.get("y")):
			var rx := int(robot["x"])
			var ry := int(robot["y"])
			if size_ok and not _inside(rx, ry, cols, rows):
				errors.append("Robot start (%d, %d) is outside the grid." % [rx, ry])
			elif _is_void(void_tiles, rx, ry):
				errors.append("The robot must start on solid floor.")
			else:
				robot_position_ok = true
		else:
			errors.append("Robot start position is invalid.")
		var robot_objects = robot.get("objects", {})
		if not (robot_objects is Dictionary):
			errors.append("Robot inventory must be an object of object names and counts.")
		else:
			for object_name in robot_objects:
				var name := str(object_name)
				if not VALID_OBJECT_NAMES.has(name):
					errors.append("Unknown inventory object '%s'." % name)
				elif not _is_positive_int(robot_objects[object_name]):
					errors.append("Inventory count for '%s' must be a positive integer." % name)
				else:
					inventory[name] = int(robot_objects[object_name])
		if robot.has("_orientation"):
			var orientation = robot["_orientation"]
			if not _is_number(orientation) or int(orientation) != float(orientation) or int(orientation) < 0 or int(orientation) > 3:
				errors.append("Robot starting direction must be an integer from 0 (east) to 3 (north).")

	# --- goal ---
	var goal_raw = data.get("goal", {})
	var goal: Dictionary = goal_raw if goal_raw is Dictionary else {}
	if not (goal_raw is Dictionary):
		errors.append("Level is missing a goal.")
	var goal_tiles: Array[Vector2i] = []
	var positions = goal.get("possible_final_positions", [])
	if not (positions is Array) or positions.is_empty():
		errors.append("Level needs at least one goal position.")
	else:
		for pos in positions:
			if pos is Array and pos.size() >= 2 and _is_number(pos[0]) and _is_number(pos[1]):
				var gx := int(pos[0])
				var gy := int(pos[1])
				if size_ok and not _inside(gx, gy, cols, rows):
					errors.append("Goal position (%d, %d) is outside the grid." % [gx, gy])
				else:
					if _is_void(void_tiles, gx, gy):
						errors.append("Goal position (%d, %d) must be on solid floor." % [gx, gy])
					goal_tiles.append(Vector2i(gx, gy))
			else:
				errors.append("Goal position is invalid: %s" % str(pos))

	# --- walls ---
	var walls_raw = data.get("walls", {})
	var walls: Dictionary = walls_raw if walls_raw is Dictionary else {}
	if not (walls_raw is Dictionary):
		errors.append("Level walls are invalid.")
	else:
		for key in walls:
			var parts := str(key).split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				errors.append("Wall entry has invalid coordinates: %s" % key)
				continue
			var wx := int(parts[0])
			var wy := int(parts[1])
			if size_ok and not _inside(wx, wy, cols, rows):
				errors.append("Wall entry is outside the grid: %s" % key)
			var faces = walls[key]
			if not (faces is Array):
				errors.append("Wall entry is invalid: %s" % key)
				continue
			var seen := {}
			for face in faces:
				var direction := str(face)
				if not VALID_WALL_DIRECTIONS.has(direction):
					errors.append("Unknown wall direction '%s' at %s (only north and east are supported)." % [direction, key])
				elif seen.has(direction):
					errors.append("Duplicate wall direction '%s' at %s." % [direction, key])
				seen[direction] = true

	# --- placed objects and goal objects ---
	var objects_raw = data.get("objects", {})
	var objects: Dictionary = objects_raw if objects_raw is Dictionary else {}
	if not (objects_raw is Dictionary):
		errors.append("Level objects are invalid.")
	var placed_totals := {}
	_validate_object_layer(errors, objects, "Map", cols, rows, size_ok, void_tiles, placed_totals)

	var goal_objects_raw = goal.get("objects", {})
	var goal_objects: Dictionary = goal_objects_raw if goal_objects_raw is Dictionary else {}
	if goal.has("objects") and not (goal_objects_raw is Dictionary):
		errors.append("Goal objects are invalid.")
	_validate_object_layer(errors, goal_objects, "Goal", cols, rows, size_ok, void_tiles, {})

	# --- carry requirements ---
	var required_carry := {}
	var carry = goal.get("require_carry", {})
	if not (carry is Dictionary):
		errors.append("Goal carry requirement must be an object of object names and counts.")
	else:
		for object_name in carry:
			var name := str(object_name)
			if not CARRY_RULES.is_valid_object_name(name):
				errors.append("Invalid carry requirement object name: %s" % name)
			elif not _is_nonneg_int(carry[object_name]):
				errors.append("Carry requirement counts must be non-negative integers: %s" % name)
			elif int(carry[object_name]) > 0:
				required_carry[name] = int(carry[object_name])
	var carry_auto = goal.get("require_carry_auto", {})
	if not (carry_auto is Dictionary):
		errors.append("Goal carry auto requirements must be an object of object names and booleans.")
	else:
		for object_name in carry_auto:
			var name := str(object_name)
			if not CARRY_RULES.is_valid_object_name(name):
				errors.append("Invalid carry auto requirement object name: %s" % name)
			elif typeof(carry_auto[object_name]) != TYPE_BOOL:
				errors.append("Carry auto requirements must be booleans: %s" % name)

	# --- void tile entries themselves ---
	for key in void_tiles:
		var parts := str(key).split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			errors.append("Void tile has invalid coordinates: %s" % key)
			continue
		var vx := int(parts[0])
		var vy := int(parts[1])
		if str(key) != "%d,%d" % [vx, vy]:
			errors.append("Void tile coordinates must use 'x,y' format: %s" % key)
		if size_ok and not _inside(vx, vy, cols, rows):
			errors.append("Void tile is outside the grid: %s" % key)
		if not (void_tiles[key] is bool) or void_tiles[key] != true:
			errors.append("Void tile values must be true: %s" % key)

	var description = data.get("description", [])
	if not (description is Array):
		errors.append("Level description is invalid.")
	if data.has("hint") and not (data["hint"] is String):
		errors.append("Level hint must be text.")
	if data.has("editor"):
		var editor_value = data["editor"]
		if editor_value is Dictionary:
			for language in editor_value:
				var starter = editor_value[language]
				if not (starter is String) and not (starter is Array):
					errors.append("Starter code for '%s' must be text or a list of lines." % language)
		elif not (editor_value is String) and not (editor_value is Array):
			errors.append("Starter code must be an object with 'cpp' and 'python' entries.")

	# Objects already sitting on a goal tile count toward its requirement, so
	# only the remainder has to be carried there by the robot.
	var goal_deliveries := {}
	for key in goal_objects:
		if not (goal_objects[key] is Dictionary):
			continue
		var placed_here = objects.get(key, {})
		if not (placed_here is Dictionary):
			placed_here = {}
		for object_name in goal_objects[key]:
			if not _is_positive_int(goal_objects[key][object_name]):
				continue
			var name := str(object_name)
			var still_needed := int(goal_objects[key][object_name]) - int(placed_here.get(name, 0))
			if still_needed > 0:
				goal_deliveries[name] = int(goal_deliveries.get(name, 0)) + still_needed

	# Carry-at-finish and goal-tile deliveries draw from the same pool: an
	# object placed on a goal tile is no longer carried, so the demands add up.
	var demand_names := {}
	for name in required_carry:
		demand_names[name] = true
	for name in goal_deliveries:
		demand_names[name] = true
	for name in demand_names:
		var demand := int(required_carry.get(name, 0)) + int(goal_deliveries.get(name, 0))
		var available := int(placed_totals.get(name, 0)) + int(inventory.get(name, 0))
		if demand > available:
			warnings.append("Level needs %d %s but only %d are available (map + starting inventory)." % [demand, name, available])

	# --- reachability warnings ---
	if size_ok and robot_position_ok:
		var start := Vector2i(int(robot["x"]), int(robot["y"]))
		var reachable := _reachable_tiles(start, walls, void_tiles)

		for goal_tile in goal_tiles:
			if goal_tile == start:
				warnings.append("The robot starts on a goal tile; the level may end immediately.")
				break
		var any_goal_reachable := false
		for goal_tile in goal_tiles:
			if reachable.has(goal_tile):
				any_goal_reachable = true
				break
		if not goal_tiles.is_empty() and not any_goal_reachable:
			warnings.append("No goal tile is reachable from the robot start.")

		for key in goal_objects:
			var parts := str(key).split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
				continue
			var gx := int(parts[0])
			var gy := int(parts[1])
			if not _inside(gx, gy, cols, rows):
				continue
			if not reachable.has(Vector2i(gx, gy)):
				warnings.append("Goal object tile %s is unreachable." % key)

		# Objects the robot must pick up: combined carry + delivery demand not
		# already covered by the starting inventory.
		var needed_names := {}
		for name in demand_names:
			var demand := int(required_carry.get(name, 0)) + int(goal_deliveries.get(name, 0))
			if demand > int(inventory.get(name, 0)):
				needed_names[name] = true
		if not needed_names.is_empty():
			for key in objects:
				var parts := str(key).split(",")
				if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
					continue
				var gx := int(parts[0])
				var gy := int(parts[1])
				if not _inside(gx, gy, cols, rows) or reachable.has(Vector2i(gx, gy)):
					continue
				var tile_objects = objects[key]
				if not (tile_objects is Dictionary):
					continue
				for object_name in tile_objects:
					if needed_names.has(str(object_name)):
						warnings.append("Objects at %s can never be picked up (tile is unreachable)." % key)
						break

	return {"errors": errors, "warnings": warnings}


func _validate_object_layer(errors: PackedStringArray, layer: Dictionary, label: String, cols: int, rows: int, size_ok: bool, void_tiles: Dictionary, totals: Dictionary) -> void:
	for key in layer:
		var parts := str(key).split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			errors.append("%s object entry has invalid coordinates: %s" % [label, key])
			continue
		var gx := int(parts[0])
		var gy := int(parts[1])
		if size_ok and not _inside(gx, gy, cols, rows):
			errors.append("%s object entry is outside the grid: %s" % [label, key])
		elif _is_void(void_tiles, gx, gy):
			errors.append("%s objects must be on solid floor: %s" % [label, key])
		var tile_objects = layer[key]
		if not (tile_objects is Dictionary):
			errors.append("%s object entry is invalid: %s" % [label, key])
			continue
		for object_name in tile_objects:
			var name := str(object_name)
			if not VALID_OBJECT_NAMES.has(name):
				errors.append("Unknown object '%s' at %s." % [name, key])
				continue
			if not _is_positive_int(tile_objects[object_name]):
				errors.append("Object count for '%s' at %s must be a positive integer." % [name, key])
			else:
				totals[name] = int(totals.get(name, 0)) + int(tile_objects[object_name])


func _reachable_tiles(start: Vector2i, walls: Dictionary, void_tiles: Dictionary) -> Dictionary:
	var cols := int(data.get("cols", 0))
	var rows := int(data.get("rows", 0))
	var reachable := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + step
			if next.x < 1 or next.x > cols or next.y < 1 or next.y > rows or reachable.has(next):
				continue
			if _is_void(void_tiles, next.x, next.y) or _wall_between(walls, cell, next):
				continue
			reachable[next] = true
			queue.append(next)
	return reachable


func _wall_between(walls: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	var delta := b - a
	var key := ""
	var direction := ""
	if delta == Vector2i(1, 0):
		key = _coord_key(a.x, a.y)
		direction = "east"
	elif delta == Vector2i(-1, 0):
		key = _coord_key(b.x, b.y)
		direction = "east"
	elif delta == Vector2i(0, 1):
		key = _coord_key(a.x, a.y)
		direction = "north"
	elif delta == Vector2i(0, -1):
		key = _coord_key(b.x, b.y)
		direction = "north"
	else:
		return true
	var faces = walls.get(key, [])
	return faces is Array and faces.has(direction)


func _is_number(value: Variant) -> bool:
	var value_type := typeof(value)
	return value_type == TYPE_INT or value_type == TYPE_FLOAT


func _is_positive_int(value: Variant) -> bool:
	if not _is_number(value):
		return false
	var number := float(value)
	return number == floor(number) and number > 0.0


func _is_nonneg_int(value: Variant) -> bool:
	if not _is_number(value):
		return false
	var number := float(value)
	return number == floor(number) and number >= 0.0


func _inside(x: int, y: int, cols: int, rows: int) -> bool:
	return x >= 1 and x <= cols and y >= 1 and y <= rows


func _coord_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func _is_void(void_tiles: Dictionary, x: int, y: int) -> bool:
	return void_tiles.get(_coord_key(x, y), false) == true


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
