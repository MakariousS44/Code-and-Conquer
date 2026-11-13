extends RefCounted

# === level definition ===
# reads a JSON file from disk and returns a parsed level definition
# used by level_scene.gd to build the playable level
# this does NOT construct the scene, it only preps the data for building

# neighbouring cells: east, west, north, south (y grows northward in this game)
const MAZE_STEPS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# random mazes are generated once per loader, so pressing Reset keeps the same maze.
# Leaving the level and opening it again makes a fresh one.
var _maze_cache := {}


func load(path: String) -> Dictionary:
	# make sure the file exists duh
	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"error": "Level file not found: %s" % path
		}

	var file := FileAccess.open(path, FileAccess.READ)

	# file exists but still failed to open somehow uh oh
	if file == null:
		return {
			"ok": false,
			"error": "could not open level file: %s" % path
		}

	var text := file.get_as_text()

	# parse JSON content
	var json := JSON.new()
	var parse_result := json.parse(text)

	if parse_result != OK:
		return {
			"ok": false,
			"error": "Invalid JSON in level file: %s" % path
		}

	var data = json.data

	# toplevel structure should be one object
	if typeof(data) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": "Level JSON must be an object."
		}

	# levels with a "random_maze" entry get their walls, start and goal built on load
	if data.has("random_maze"):
		if not _maze_cache.has(path):
			_maze_cache[path] = _generate_random_maze(data)
		data = _maze_cache[path].duplicate(true)

	var void_error := preload("res://map/scripts/void_tiles.gd").validate(data)
	if not void_error.is_empty():
		return {"ok": false, "error": void_error}
	var carry_error := preload("res://map/scripts/carry_requirements.gd").validate(data)
	if not carry_error.is_empty():
		return {"ok": false, "error": carry_error}
	return {
		"ok": true,
		"definition": data
	}


# === random maze ===
# Builds a "perfect" maze (every tile reachable, exactly one route between any two tiles) with a
# randomized depth-first search, then picks a random start tile and a goal far away from it.
# Because there are no loops, the classic right-hand wall-following solution always works.
# Optional settings in the level's "random_maze" object:
#   "min_goal_distance": 0.0 - 1.0, how far the goal must be compared to the farthest tile
#                        (default 0.75; higher = longer route)
func _generate_random_maze(source: Dictionary) -> Dictionary:
	var data: Dictionary = source.duplicate(true)
	var settings: Dictionary = data["random_maze"] if data["random_maze"] is Dictionary else {}
	var cols := clampi(int(data.get("cols", 7)), 2, 30)
	var rows := clampi(int(data.get("rows", 7)), 2, 30)
	var distance_ratio := clampf(float(settings.get("min_goal_distance", 0.75)), 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# carve passages (open[edge] = true means there is NO wall between those two tiles)
	var open := {}
	var visited := {}
	var first := Vector2i(rng.randi_range(1, cols), rng.randi_range(1, rows))
	var stack: Array[Vector2i] = [first]
	visited[first] = true
	while not stack.is_empty():
		var cell: Vector2i = stack.back()
		var options: Array[Vector2i] = []
		for step in MAZE_STEPS:
			var next := cell + step
			if next.x >= 1 and next.x <= cols and next.y >= 1 and next.y <= rows and not visited.has(next):
				options.append(next)
		if options.is_empty():
			stack.pop_back()
			continue
		var chosen: Vector2i = options[rng.randi_range(0, options.size() - 1)]
		visited[chosen] = true
		open[_maze_edge_key(cell, chosen)] = true
		stack.append(chosen)

	# random start tile, then measure the route length to every other tile
	var start := Vector2i(rng.randi_range(1, cols), rng.randi_range(1, rows))
	var distance := {start: 0}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var farthest := 0
	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1
		for step in MAZE_STEPS:
			var next := current + step
			if distance.has(next) or not open.has(_maze_edge_key(current, next)):
				continue
			distance[next] = int(distance[current]) + 1
			farthest = maxi(farthest, int(distance[next]))
			queue.append(next)

	# the goal is a random tile among the far-away ones, so the route is never trivial
	var minimum := maxi(1, int(ceil(farthest * distance_ratio)))
	var goal_choices: Array[Vector2i] = []
	for cell in distance:
		if int(distance[cell]) >= minimum:
			goal_choices.append(cell)
	var goal_cell: Vector2i = goal_choices[rng.randi_range(0, goal_choices.size() - 1)]

	# every closed edge between neighbouring tiles becomes a wall (east / north faces only)
	var walls := {}
	for x in range(1, cols + 1):
		for y in range(1, rows + 1):
			var faces: Array = []
			if x < cols and not open.has(_maze_edge_key(Vector2i(x, y), Vector2i(x + 1, y))):
				faces.append("east")
			if y < rows and not open.has(_maze_edge_key(Vector2i(x, y), Vector2i(x, y + 1))):
				faces.append("north")
			if not faces.is_empty():
				walls["%d,%d" % [x, y]] = faces

	var robots: Array = data.get("robots", [])
	var robot: Dictionary = robots[0] if not robots.is_empty() and robots[0] is Dictionary else {"_orientation": 0, "objects": {}}
	robot["x"] = start.x
	robot["y"] = start.y
	data["robots"] = [robot]
	data["cols"] = cols
	data["rows"] = rows
	data["walls"] = walls
	data["void_tiles"] = {}
	data["goal"] = {
		"possible_final_positions": [[goal_cell.x, goal_cell.y]],
		"position": {"x": goal_cell.x, "y": goal_cell.y, "image": "green_home_tile"},
		"objects": {}
	}
	return data


# same key no matter which of the two tiles you ask from
func _maze_edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x > b.x or (a.x == b.x and a.y > b.y):
		var swap := a
		a = b
		b = swap
	return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
