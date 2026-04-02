extends RefCounted
class_name MapLoader

# === level importer / loader ===
# reads external JSON, converts it into native LevelData,
# and can also save the result as a .tres resource for faster runtime loading.


func load_json_as_level_data(path: String) -> Dictionary:
	var json_result := _load_json_dictionary(path)
	if not json_result.ok:
		return json_result

	var convert_result := _dictionary_to_level_data(json_result.definition)
	if not convert_result.ok:
		return convert_result

	return {
		"ok": true,
		"level_data": convert_result.level_data
	}


func import_json_to_tres(json_path: String, tres_path: String) -> Dictionary:
	var load_result := load_json_as_level_data(json_path)
	if not load_result.ok:
		return load_result

	var level_data: LevelData = load_result.level_data
	var save_result := ResourceSaver.save(level_data, tres_path)

	if save_result != OK:
		return {
			"ok": false,
			"error": "Failed to save level resource: %s" % tres_path
		}

	return {
		"ok": true,
		"level_data": level_data,
		"tres_path": tres_path
	}


func load_level_resource(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		return {
			"ok": false,
			"error": "Level resource not found: %s" % path
		}

	var resource := load(path)
	if resource == null:
		return {
			"ok": false,
			"error": "Could not load level resource: %s" % path
		}

	if not (resource is LevelData):
		return {
			"ok": false,
			"error": "Resource is not a LevelData: %s" % path
		}

	return {
		"ok": true,
		"level_data": resource
	}


func _load_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"error": "Level file not found: %s" % path
		}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"error": "Could not open level file: %s" % path
		}

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(text)

	if parse_result != OK:
		return {
			"ok": false,
			"error": "Invalid JSON in level file: %s" % path
		}

	var data = json.data

	if typeof(data) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": "Level JSON must be an object."
		}

	return {
		"ok": true,
		"definition": data
	}


func _dictionary_to_level_data(data: Dictionary) -> Dictionary:
	var level := LevelData.new()

	level.rows = int(data.get("rows", 10))
	level.cols = int(data.get("cols", 10))

	if data.has("player"):
		level.player_spawn = _parse_player(data.get("player", {}))
	elif data.has("robots"):
		var raw_robots = data.get("robots", [])
		if typeof(raw_robots) == TYPE_ARRAY and not raw_robots.is_empty():
			level.player_spawn = _parse_player(raw_robots[0])

	level.wall_cells = _parse_walls(data.get("walls", {}))
	level.marked_tiles = _parse_tiles(data.get("tiles", {}))
	level.goal = _parse_goal(data.get("goal", {}))

	return {
		"ok": true,
		"level_data": level
	}


func _parse_player(raw_player: Variant) -> PlayerSpawnData:
	var player := PlayerSpawnData.new()

	if typeof(raw_player) != TYPE_DICTIONARY:
		return player

	player.x = int(raw_player.get("x", 1))
	player.y = int(raw_player.get("y", 1))

	if raw_player.has("facing"):
		player.facing = str(raw_player.get("facing", "north")).to_lower()
	elif raw_player.has("direction"):
		player.facing = str(raw_player.get("direction", "north")).to_lower()
	elif raw_player.has("_orientation"):
		var orientation := int(raw_player.get("_orientation", 0)) % 4
		match orientation:
			0:
				player.facing = "east"
			1:
				player.facing = "north"
			2:
				player.facing = "west"
			3:
				player.facing = "south"

	return player


func _parse_walls(raw_walls: Variant) -> Array[WallCellData]:
	var walls: Array[WallCellData] = []

	if typeof(raw_walls) != TYPE_DICTIONARY:
		return walls

	for key in raw_walls.keys():
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue

		var wall := WallCellData.new()
		wall.x = int(parts[0])
		wall.y = int(parts[1])

		var raw_directions = raw_walls[key]
		if typeof(raw_directions) == TYPE_ARRAY:
			for dir in raw_directions:
				wall.directions.append(str(dir).to_lower())

		walls.append(wall)

	return walls


func _parse_tiles(raw_tiles: Variant) -> Array[MarkedTileData]:
	var tiles: Array[MarkedTileData] = []

	if typeof(raw_tiles) != TYPE_DICTIONARY:
		return tiles

	for key in raw_tiles.keys():
		var parts := str(key).split(",")
		if parts.size() != 2:
			continue

		var tile := MarkedTileData.new()
		tile.x = int(parts[0])
		tile.y = int(parts[1])
		tiles.append(tile)

	return tiles


func _parse_goal(raw_goal: Variant) -> GoalData:
	var goal := GoalData.new()

	if typeof(raw_goal) != TYPE_DICTIONARY:
		return goal

	if raw_goal.has("position"):
		var pos = raw_goal["position"]
		if typeof(pos) == TYPE_DICTIONARY:
			goal.position = Vector2i(
				int(pos.get("x", -1)),
				int(pos.get("y", -1))
			)

	if raw_goal.has("possible_final_positions"):
		var positions = raw_goal["possible_final_positions"]
		if typeof(positions) == TYPE_ARRAY:
			for pos in positions:
				if typeof(pos) == TYPE_ARRAY and pos.size() >= 2:
					goal.possible_final_positions.append(
						Vector2i(int(pos[0]), int(pos[1]))
					)

	return goal
