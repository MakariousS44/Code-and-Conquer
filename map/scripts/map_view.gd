extends Node2D

signal level_complete

@onready var camera: Camera2D = $Camera2D
@onready var world_root: Node2D = $WorldRoot
@onready var player: Node2D = $WorldRoot/Player
@onready var objects_node: Node2D = $WorldRoot/Objects
@onready var FloorTiles: TileMapLayer = $WorldRoot/FloorMapLayer
@onready var WallTiles: TileMapLayer = $WorldRoot/WallMapLayer

# ============ Global Values ============

var level_data: Dictionary = {}
var object_data: Dictionary = {}
var world_x_size: int = 10
var world_y_size: int = 10
var player_x_pos: int = 0
var player_y_pos: int = 0
var rotation_state = 0
var offset_x = 256
var offset_y = 64
var player_moved = false

# CAUTION: Do not change this is to scale to the floor size
const chunk_size = 2
# =======================================


# === scene lifecycle ===
# runs when this scene is instantiated into the tree
# this scene owns the camera, so it configures it here
func _ready() -> void:
	# EventManager.rotate_camera_left.connect(rotate_world_left)
	# EventManager.rotate_camera_right.connect(rotate_world_right)
	pass


# ======= MAIN POINT: Build Rendition =======
## Builds a world given that JSON data (format: Reborg)
##
## INPUTS: A dictionary that describe the world (obj:description)
## OUTPUTS: A render of the world given by dictionary
func build_level(data: Dictionary) -> void:
	level_data = data
	object_data = data.get("objects", {})

	# IF NEEDED: enforce ordering
	FloorTiles.z_index = 0
	WallTiles.z_index = 1
	player.z_index = 1
	objects_node.z_index = 1

	# Generate the Floor Grid
	if data.has("cols") and data.has("rows"):
		var cols = int(data["cols"])
		var rows = int(data["rows"])

		world_x_size = cols
		world_y_size = rows
		print("Floor: ", cols, "x", rows)

		# Create the floor
		_build_floor(cols, rows)
		# Create the wall
		_build_walls(data, cols, rows)
		# Create the player
		_place_player(data, cols, rows)
		# Place goals
		_build_goal_cells(data, cols, rows)
		# Set the camera
		_center_camera(cols, rows)
		_build_objects()
	else:
		push_warning("JSON loaded, but 'cols' or 'rows' keys were missing!")


## Just signal rotation state to the right and calls for redraw
func rotate_world_right():
	rotation_state -= 1
	if rotation_state == -1:
		rotation_state = 3
	_rotate_world()


## Just signal rotation state to the left and calls for redraw
func rotate_world_left():
	rotation_state += 1
	if rotation_state == 4:
		rotation_state = 0
	_rotate_world()


## Rebuild the world given a new rotation state
func _rotate_world():
	var data = level_data

	# Generate the Floor Grid
	if data.has("cols") and data.has("rows"):
		# Given the rotation step are cols and rows swap
		var cols = int(data["cols"])
		var rows = int(data["rows"])

		print(rotation_state)

		world_x_size = cols
		world_y_size = rows
		print("Floor: ", cols, "x", rows)

		# Create the floor
		_build_floor(cols, rows)
		# Create the wall
		# _build_walls(data, cols, rows)
		# Create the player
		_place_player(data, cols, rows)
		# Place goals
		# _build_goal_cells(data, cols, rows)
		# Set the camera
		# _center_camera(cols, rows)
	else:
		push_warning("JSON loaded, but 'cols' or 'rows' keys were missing!")


# ====== World Rendering Functions ======
## This builds the floor given the grid size
func _build_floor(cols: int, rows: int) -> void:
	# Clear current floor
	FloorTiles.clear()
	# Loop through every x (column) and y (row) to fill the grid
	var max_grid = max(cols, rows)

	for x in range(cols):
		var draw_x = x
		for y in range(rows):
			var draw_y = y
			# Swap the coordinates based on the current angle!
			if rotation_state == 1: # 90 Degrees
				draw_x = y
				draw_y = x
			elif rotation_state == 2: # 180 Degrees
				draw_x = (max_grid - 1) - x
				draw_y = (max_grid - 1) - y
			elif rotation_state == 3: # 270 Degrees
				draw_x = (max_grid - 1) - y
				draw_y = (max_grid - 1) - x

			var grid_pos = Vector2i(draw_x, draw_y)
			# Draw your floor tile
			FloorTiles.set_cell(grid_pos, 8, Vector2i(0, 1))


## This builds the walls given its coordinate and face
func _build_walls(data: Dictionary, cols: int, rows: int) -> void:
	# Define how big each logical cell is in physical tiles
	cols = cols * chunk_size
	@warning_ignore("narrowing_conversion")
	rows = (rows + 0.5) * chunk_size
	print("Scaled size: ", cols, ",", rows)

	# Generate the walls
	if data.has("walls"):
		var walls = Dictionary(data["walls"])
		for keys in walls:
			# Obtain wall position
			var wall_coords = keys.split(",")
			var x_coords = int(wall_coords[0])
			var y_coords = int(wall_coords[1])
			var grid_pos = Vector2((x_coords) * chunk_size - 1, rows - (y_coords) * chunk_size)

			# Obtain wall direction
			var wall_directions = walls[keys]
			if wall_directions.size() == 1:
				# ONLY EAST WALL
				if wall_directions[0] == "east":
					WallTiles.set_cell(grid_pos, 44, Vector2i(6, 1))

					grid_pos = Vector2(grid_pos[0], grid_pos[1] + 1)
					WallTiles.set_cell(grid_pos, 44, Vector2i(6, 1))
				# ONLY NORTH WALL
				else:
					WallTiles.set_cell(grid_pos, 44, Vector2i(4, 1))

					grid_pos = Vector2(grid_pos[0] - 1, grid_pos[1])
					WallTiles.set_cell(grid_pos, 44, Vector2i(4, 1))
			# ONLY CORNER WALL
			else:
				var temp_pos = grid_pos
				grid_pos = Vector2(temp_pos[0] - 1, temp_pos[1])
				WallTiles.set_cell(grid_pos, 44, Vector2i(4, 1))

				grid_pos = Vector2(temp_pos[0], temp_pos[1])
				WallTiles.set_cell(grid_pos, 44, Vector2i(6, 0))

				grid_pos = Vector2(temp_pos[0], temp_pos[1] + 1)
				WallTiles.set_cell(grid_pos, 44, Vector2i(6, 1))

			# Add a corner
			var all_floor_cells: Array[Vector2i] = WallTiles.get_used_cells_by_id(44, Vector2i(4, 1))

			for cell in all_floor_cells:
				var other_wall = WallTiles.get_cell_atlas_coords(Vector2i(cell[0] - 1, cell[1] - 1))
				if other_wall == Vector2i(6, 1):
					WallTiles.set_cell(Vector2i(cell[0] - 1, cell[1]), 44, Vector2i(2, 2))
	else:
		push_warning("JSON loaded, but 'walls' keys were missing!")


func _build_goal_cells(data: Dictionary, cols: int, rows: int) -> void:
	if not data.has("goal"):
		return
	var goal = data["goal"]
	if goal.has("possible_final_positions"):
		for pos in goal["possible_final_positions"]:
			if typeof(pos) == TYPE_ARRAY and pos.size() >= 2:
				var grid_pos = Vector2i((pos[0]) - 1, rows - (pos[1]))
				print(grid_pos)
				FloorTiles.set_cell(grid_pos, 8, Vector2i(0, 0))
	if goal.has("position"):
		var pos = goal["position"]
		if typeof(pos) == TYPE_DICTIONARY:
			var grid_pos = Vector2i((int(pos.get("x", -1)) - 1), rows - (int(pos.get("y", -1))))
			print(grid_pos)
			FloorTiles.set_cell(grid_pos, 8, Vector2i(0, 0))


func _is_goal_tile(gx: int, gy: int) -> void:
	pass


## Define and places the player at starting position
func _place_player(data: Dictionary, cols: int, rows: int) -> void:
	if data.has("robots"):
		var robots = level_data["robots"]
		if robots.is_empty():
			push_warning("JSON loaded, but 'robots' is empty!")
		else:
			# Determine the starting position given by the JSON
			var robot_info = robots[0]
			var innit_x: int = robot_info.get("x", 1)
			var innit_y: int = robot_info.get("y", 1)

			if player_moved:
				innit_x = player_x_pos
				innit_y = player_y_pos

			# Move to desired position
			cols = cols * chunk_size
			rows = rows * chunk_size
			var max_grid = max(cols, rows)

			innit_x = (innit_x * chunk_size) - 2
			innit_y = (innit_y * chunk_size) - 2

			var pos_x = innit_x
			var pos_y = rows - innit_y - 2

			if rotation_state == 1:
				pos_x = innit_y
				pos_y = innit_x
			elif rotation_state == 2:
				pos_x = max_grid - innit_x - 2
				pos_y = innit_y
			elif rotation_state == 3:
				pos_x = max_grid - innit_y - 2
				pos_y = max_grid - innit_x - 2

			# Ask the TileMapLayer where that specific grid tile is in actual pixels
			var grid_pos = FloorTiles.map_to_local(Vector2i(pos_x, pos_y))

			@warning_ignore("narrowing_conversion")
			var pixel_pos = Vector2i(grid_pos[0] + offset_x, grid_pos[1] + offset_y)

			print("Start Position: ", innit_x, ",", innit_y, " Grid Position: ", grid_pos, " Pixel Position: ", pixel_pos)
			player.initialize_from_level(robot_info, pixel_pos, player_moved)


## Centers the camera to the middle and zoom relative to the grid size.
func _center_camera(cols: int, rows: int) -> void:
	var top_corner = FloorTiles.map_to_local(Vector2i(0, 0))
	var bottom_corner = FloorTiles.map_to_local(Vector2i(cols - 1, rows - 1))
	var right_corner = FloorTiles.map_to_local(Vector2i(cols - 1, 0))
	var left_corner = FloorTiles.map_to_local(Vector2i(0, rows - 1))

	var min_x = left_corner.x
	var max_x = right_corner.x
	var min_y = top_corner.y
	var max_y = bottom_corner.y

	var half_tile = Vector2(FloorTiles.tile_set.tile_size) / 2.0
	min_x -= half_tile.x
	max_x += half_tile.x
	min_y -= half_tile.y
	max_y += half_tile.y

	var center_x = (min_x + max_x) / 2.0
	var center_y = (min_y + max_y) / 2.0

	camera.global_position = FloorTiles.to_global(Vector2(center_x, center_y))

	var max_grid_size = max(cols, rows)

	@warning_ignore("integer_division")
	var step = (int(max_grid_size) - 1) / 5

	var final_zoom = 1
	print("Grid Size Level: ", step)
	if step < 5:
		final_zoom = 0.15 - (step * 0.03)
	else:
		final_zoom = 0.1 - (step * 0.01)

	final_zoom = max(final_zoom, 0.01)
	camera.zoom = Vector2(final_zoom, final_zoom)


# ======= public helpers =======

## Returns the proper position in relation to the floor grids.
func grid_position(x_pos: int, y_pos: int) -> Vector2:
	var cols = world_x_size * chunk_size
	var rows = world_y_size * chunk_size
	var max_grid = max(cols, rows)

	x_pos = (x_pos * chunk_size) - 2
	y_pos = (y_pos * chunk_size) - 2

	var pos_x = x_pos
	var pos_y = rows - y_pos - 2

	if rotation_state == 1:
		pos_x = y_pos
		pos_y = x_pos
	elif rotation_state == 2:
		pos_x = max_grid - x_pos - 2
		pos_y = y_pos
	elif rotation_state == 3:
		pos_x = max_grid - y_pos - 2
		pos_y = max_grid - x_pos - 2

	var grid_pos = FloorTiles.map_to_local(Vector2i(pos_x, pos_y))

	@warning_ignore("narrowing_conversion")
	var pixel_pos = Vector2i(grid_pos[0] + offset_x, grid_pos[1] + offset_y)
	print("New Position: ", x_pos, ",", y_pos, " Grid Position: ", grid_pos, " Pixel Position: ", pixel_pos)
	return pixel_pos


## simple bounds check so the player doesn't walk off the map
func is_in_bounds(gx: int, gy: int) -> bool:
	return gx >= 1 and gx <= world_x_size and gy >= 1 and gy <= world_y_size


## Check if movement in dir from (gx,gy) is blocked by a wall.
func is_move_blocked(gx: int, gy: int, dir: String) -> bool:
	if not level_data.has("walls"):
		return false

	var key := "%d,%d" % [gx, gy]
	if level_data["walls"].has(key):
		for d in level_data["walls"][key]:
			if str(d).to_lower() == dir:
				return true

	match dir:
		"west":
			var adj := "%d,%d" % [gx - 1, gy]
			if level_data["walls"].has(adj):
				for d in level_data["walls"][adj]:
					if str(d).to_lower() == "east":
						return true
		"south":
			var adj := "%d,%d" % [gx, gy - 1]
			if level_data["walls"].has(adj):
				for d in level_data["walls"][adj]:
					if str(d).to_lower() == "north":
						return true

	return false


func _cell_key(gx: int, gy: int) -> String:
	return "%d,%d" % [gx, gy]


# Returns true if the given grid position satisfies the goal condition.
# Used by the IPC query system without emitting the win signal.
func is_at_goal(gx: int, gy: int) -> bool:
	if not level_data.has("goal"):
		return false
	var goal = level_data["goal"]
	if goal.has("possible_final_positions"):
		for pos in goal["possible_final_positions"]:
			if typeof(pos) == TYPE_ARRAY and pos.size() >= 2:
				if int(pos[0]) == gx and int(pos[1]) == gy:
					return true
	if goal.has("position"):
		var pos = goal["position"]
		if typeof(pos) == TYPE_DICTIONARY:
			if int(pos.get("x", -1)) == gx and int(pos.get("y", -1)) == gy:
				return true
	return false


# === win condition ===
func check_win_condition(gx: int, gy: int) -> void:
	if not level_data.has("goal"):
		return

	var goal = level_data["goal"]

	if goal.has("possible_final_positions"):
		for pos in goal["possible_final_positions"]:
			if typeof(pos) == TYPE_ARRAY and pos.size() >= 2:
				if int(pos[0]) == gx and int(pos[1]) == gy:
					level_complete.emit()
					return

	if goal.has("position"):
		var pos = goal["position"]
		if typeof(pos) == TYPE_DICTIONARY:
			var goal_x := int(pos.get("x", -1))
			var goal_y := int(pos.get("y", -1))

			if gx == goal_x and gy == goal_y:
				if not goal.has("objects"):
					level_complete.emit()
					return

				var tile_objects: Dictionary = get_objects_at(goal_x, goal_y)
				var required_objects: Dictionary = goal["objects"]

				for object_name in required_objects.keys():
					var needed := int(required_objects[object_name])
					var present := int(tile_objects.get(object_name, 0))
					if present < needed:
						return

				level_complete.emit()


# === objects ===
func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _build_objects() -> void:
	_clear_children(objects_node)

	for key in object_data.keys():
		var parts = key.split(",")
		if parts.size() != 2:
			continue

		var gx := int(parts[0])
		var gy := int(parts[1])

		var tile_objects: Dictionary = object_data[key]
		var type_index := 0

		for object_name in tile_objects.keys():
			var count := int(tile_objects[object_name])
			if count > 0:
				_spawn_object(object_name, gx, gy, count, type_index)
				type_index += 1


func _spawn_object(object_name: String, gx: int, gy: int, count: int, type_index: int = 0) -> void:
	var container := Node2D.new()

	var marker := Polygon2D.new()
	marker.polygon = PackedVector2Array([
		Vector2(0, -32),
		Vector2(32, 0),
		Vector2(0, 32),
		Vector2(-32, 0)
	])
	marker.color = _get_object_color(object_name)
	container.add_child(marker)

	if count > 1:
		var label := Label.new()
		label.text = str(count)
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		label.position = Vector2(12, -28)
		container.add_child(label)

	var pixel_pos = grid_position(gx, gy)
	container.position = pixel_pos + Vector2(type_index * 18, -type_index * 10)
	container.z_index = 2

	objects_node.add_child(container)


func _get_object_color(object_name: String) -> Color:
	match object_name:
		"apple":
			return Color(1.0, 0.2, 0.2)
		"banana":
			return Color(1.0, 0.9, 0.2)
		"carrot":
			return Color(1.0, 0.5, 0.1)
		"star":
			return Color(1.0, 1.0, 0.3)
		"token":
			return Color(0.3, 0.8, 1.0)
		_:
			return Color(1.0, 1.0, 1.0)


func get_objects_at(gx: int, gy: int) -> Dictionary:
	return object_data.get(_cell_key(gx, gy), {})


func remove_object_at(gx: int, gy: int) -> String:
	var key := _cell_key(gx, gy)

	if not object_data.has(key):
		return ""

	var tile_objects: Dictionary = object_data[key]

	for object_name in tile_objects.keys():
		if object_name == "rock" or object_name == "spike":
			continue

		tile_objects[object_name] -= 1

		if tile_objects[object_name] <= 0:
			tile_objects.erase(object_name)

		if tile_objects.is_empty():
			object_data.erase(key)

		_build_objects()
		return object_name

	return ""


func place_object_at(gx: int, gy: int, object_name: String) -> bool:
	if object_name == "":
		return false

	var key := _cell_key(gx, gy)

	if not object_data.has(key):
		object_data[key] = {}

	if not object_data[key].has(object_name):
		object_data[key][object_name] = 0

	object_data[key][object_name] += 1
	_build_objects()
	check_win_condition(gx, gy)
	return true


func handle_player_enter_tile(gx: int, gy: int, player_ref) -> void:
	var tile_objects: Dictionary = get_objects_at(gx, gy)

	for object_name in tile_objects.keys():
		match object_name:
			"spike":
				if player_ref.has_method("_trigger_lose"):
					player_ref._trigger_lose("You lose: stepped on spikes.")
			"banana":
				pass
			_:
				pass


func handle_pick_attempt(gx: int, gy: int, player_ref) -> bool:
	var tile_objects: Dictionary = get_objects_at(gx, gy)

	if tile_objects.is_empty():
		return false

	for object_name in tile_objects.keys():
		if object_name == "rock":
			return false

	return true


func handle_place_attempt(gx: int, gy: int, object_name: String, player_ref) -> bool:
	match object_name:
		"banana":
			return true
		"apple":
			return true
		_:
			return true


func tile_has_any_object(gx: int, gy: int) -> bool:
	var tile_objects: Dictionary = get_objects_at(gx, gy)

	for object_name in tile_objects.keys():
		if object_name == "rock" or object_name == "spike":
			continue
		if int(tile_objects[object_name]) > 0:
			return true

	return false
