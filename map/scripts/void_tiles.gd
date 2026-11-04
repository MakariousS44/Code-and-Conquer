extends RefCounted

static func contains(data: Dictionary, x: int, y: int) -> bool:
	return data.get("void_tiles", {}).get("%d,%d" % [x, y], false) == true

static func validate(data: Dictionary) -> String:
	var tiles = data.get("void_tiles", {})
	if not tiles is Dictionary:
		return "void_tiles must be an object of coordinate keys and true values."
	for key in tiles:
		var parts := str(key).split(",")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return "Invalid void tile coordinate: %s" % key
		var x := int(parts[0])
		var y := int(parts[1])
		if str(key) != "%d,%d" % [x, y] or x < 1 or y < 1 or x > int(data.get("cols", 0)) or y > int(data.get("rows", 0)):
			return "Void tile is outside the grid: %s" % key
		if not tiles[key] is bool or tiles[key] != true:
			return "Void tile values must be true. Erase the entry to restore floor."
	for robot in data.get("robots", []):
		if contains(data, int(robot.get("x", 1)), int(robot.get("y", 1))):
			return "The robot must start on solid floor."
	var goal: Dictionary = data.get("goal", {})
	var positions: Array = goal.get("possible_final_positions", []).duplicate()
	if goal.has("position"):
		positions.append([goal.position.get("x", 0), goal.position.get("y", 0)])
	for pos in positions:
		if pos is Array and pos.size() >= 2 and contains(data, int(pos[0]), int(pos[1])):
			return "Goals must be on solid floor."
	for objects in [data.get("objects", {}), goal.get("objects", {})]:
		for key in objects:
			if tiles.has(key):
				return "Objects must be on solid floor."
	return ""
