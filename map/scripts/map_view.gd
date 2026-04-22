extends Node2D

signal level_complete

@onready var camera: Camera2D = $Camera2D
@onready var world_root: Node2D = $WorldRoot
@onready var player: Node2D = $WorldRoot/Player
@onready var objects_node: Node2D = $WorldRoot/Objects
@onready var FloorTiles: TileMapLayer = $WorldRoot/FloorMapLayer
@onready var WallTiles: TileMapLayer = $WorldRoot/WallMapLayer

# ============ Global Values ============
const LABEL_FONT_PATH := "res://assets/fonts/ttf/FiraCode-Bold.ttf"

var level_data: Dictionary = {}
var object_data: Dictionary = {}
var world_x_size : int = 10
var world_y_size : int = 10
var rotation_state = 0
var offset_x = 256
var offset_y = 64
var is_rotating = false
# =======================================


# CAUTION: Do not change this is to scale to the floor size
const chunk_size = 2
# =======================================

# === scene lifecycle ===
# runs when this scene is instantiated into the tree
# this scene owns the camera, so it configures it here
func _ready() -> void:
	EventManager.rotate_camera_left.connect(rotate_world_left)
	EventManager.rotate_camera_right.connect(rotate_world_right)


# ======= MAIN POINT: Build Rendition =======
## Builds a world given that JSON data (format: Reborg)
##
## INPUTS: A dictonary that describe the world (obj:description)
## OUTPUS: A render of the world given by dictionary
func build_level(data: Dictionary) -> void:
	is_rotating = false
	level_data = data
	object_data = data.get("objects", {})
	rotation_state = 0
	# IF NEEDED: enforce ordering
	FloorTiles.z_index = 0
	WallTiles.z_index  = 1
	player.z_index     = 1
	objects_node.z_index = 1
	
	# Generate the Floor Grid
	if data.has("cols") and data.has("rows"):
		var cols = int(data["cols"])
		var rows = int(data["rows"])
		
		world_x_size = cols
		world_y_size = rows
		print("Floor: ", cols,"x",rows)
		
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

## Just signal rotation state to the left and calls for redraw
func rotate_world_left():
	rotation_state -=1
	if rotation_state == -1:
		rotation_state = 3
	_rotate_world()

## Just signal rotation state to the right and calls for redraw
func rotate_world_right():
	rotation_state +=1
	if rotation_state == 4:
		rotation_state = 0
	_rotate_world()

## Rebuild the wolrd given a new rotation state
func _rotate_world():
	is_rotating = true
	var data = level_data
	
	# Generate the Floor Grid
	if data.has("cols") and data.has("rows"):
		# Given the rotation step are cols and rows swap
		var cols = int(data["cols"])
		var rows = int(data["rows"])
		
		print(rotation_state)

		world_x_size = cols
		world_y_size = rows
		print("Floor: ", cols,"x",rows)
		
		# Create the floor
		_build_floor(cols, rows)
		# Create the wall
		_build_walls(data, cols, rows)
		# Create the player
		_place_player(data, cols, rows)
		# Place goals
		_build_goal_cells(data, cols, rows)
		
		_build_objects()
	else:
		push_warning("JSON loaded, but 'cols' or 'rows' keys were missing!")

# ====== World Rendering Functions ======
## This builds the floor given the grid size
func _build_floor(cols: int,rows: int) -> void:
	# Clear current floor
	FloorTiles.clear()
	# Loop through every x (column) and y (row) to fill the grid
	var max_grid = max(cols,rows)
	
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
			
			var grid_pos = Vector2i(draw_x,draw_y)
			# Draw your floor tile (Assuming source_id 0 and atlas coords 0,0)
			FloorTiles.set_cell(grid_pos, 8, Vector2i(0, 1))

## This builds the walls given its coordinate and face
func _build_walls(data: Dictionary, cols: int, rows: int) -> void:
	# Clear current walls
	WallTiles.clear()
	
	# Define how big each logical cell is in physical tiles
	cols = (cols) * chunk_size
	@warning_ignore("narrowing_conversion")
	rows = (rows+0.5) * chunk_size
	print("Scaled size: ", cols, ",", rows)

	# Generate the walls
	# The dictonary is formated as:
	#		 ["x-coords","y-coords"] : ["direction"]
	if data.has("walls"):
		var walls = Dictionary(data["walls"])
		for keys in walls:
			# Obtain wall position
			var wall_coords = keys.split(",")
			var x_coords = int(wall_coords[0])
			var y_coords = int(wall_coords[1])
			
			x_coords = (x_coords * chunk_size) - 1
			y_coords = rows - (y_coords * chunk_size) 
			
			var pos_x = x_coords
			var pos_y = y_coords
			
			if rotation_state == 1:
				pos_x = rows - y_coords - 1
				pos_y = x_coords + 1
			elif rotation_state == 2:
				pos_x = cols - x_coords - 1
				pos_y = rows - y_coords
			elif rotation_state == 3:
				pos_x = y_coords - 1
				pos_y = cols - x_coords
			
			var grid_pos = Vector2(pos_x, pos_y)
			var grid_pos2 = Vector2(pos_x, pos_y)
			
			# Obtain wall direction
			# CRITICAL: Reborg world only utilizes "east" and "north"
			# - This is optimize for Reborg world editor
			# - An array of size of 1, is either a wall facing "east" and "north"
			# - An array of size of 2, is a corner betwenn  "east" and "north" 
			var wall_directions = walls[keys]
			if wall_directions.size() == 1:
				# ONLY EAST WALL
				if wall_directions[0] == "east":
					if rotation_state == 1:
						grid_pos = Vector2(grid_pos[0], grid_pos[1])
						WallTiles.set_cell(grid_pos, 44, Vector2i(7,1))
						
						grid_pos2 = Vector2(grid_pos2[0]-1, grid_pos2[1])
						WallTiles.set_cell(grid_pos2, 44, Vector2i(7,1))
					elif rotation_state == 2:
						grid_pos = Vector2(grid_pos[0], grid_pos[1]-1)
						WallTiles.set_cell(grid_pos, 44, Vector2i(5,1))
						
						grid_pos2 = Vector2(grid_pos2[0], grid_pos2[1])
						WallTiles.set_cell(grid_pos2, 44, Vector2i(5,1))
					elif rotation_state == 3:
						grid_pos = Vector2(grid_pos[0], grid_pos[1])
						WallTiles.set_cell(grid_pos, 44, Vector2i(4,1))
						
						grid_pos2 = Vector2(grid_pos2[0]+1, grid_pos2[1])
						WallTiles.set_cell(grid_pos2, 44, Vector2i(4,1))
					else:
						grid_pos = Vector2(grid_pos[0], grid_pos[1])
						WallTiles.set_cell(grid_pos, 44, Vector2i(6,1))
						
						grid_pos2 = Vector2(grid_pos2[0], grid_pos2[1]+1)
						WallTiles.set_cell(grid_pos2, 44, Vector2i(6,1))
				# ONLY NORTH WALL
				else:
					if rotation_state == 1:
						grid_pos = Vector2(grid_pos[0], grid_pos[1])
						WallTiles.set_cell(grid_pos, 44, Vector2i(6,1))
						
						grid_pos2 = Vector2(grid_pos2[0], grid_pos2[1]-1)
						WallTiles.set_cell(grid_pos2, 44, Vector2i(6,1))
					elif rotation_state == 2:
						grid_pos = Vector2(grid_pos[0], grid_pos[1])
						WallTiles.set_cell(grid_pos, 44, Vector2i(7,1))
						
						grid_pos2 = Vector2(grid_pos2[0]+1, grid_pos2[1])
						WallTiles.set_cell(grid_pos2, 44, Vector2i(7,1))
					elif rotation_state == 3:
						grid_pos = Vector2(grid_pos[0], grid_pos[1]+1)
						WallTiles.set_cell(grid_pos, 44, Vector2i(5,1))
						
						grid_pos2 = Vector2(grid_pos2[0], grid_pos2[1])
						WallTiles.set_cell(grid_pos2, 44, Vector2i(5,1))
					else:
						grid_pos = Vector2(grid_pos[0], grid_pos[1])
						WallTiles.set_cell(grid_pos, 44, Vector2i(4,1))
						
						grid_pos2 = Vector2(grid_pos2[0]-1, grid_pos2[1])
						WallTiles.set_cell(grid_pos2, 44, Vector2i(4,1))
			# ONLY CORNER WALL
			else:
				var temp_pos = grid_pos
				if rotation_state == 1:
					grid_pos = Vector2(temp_pos[0]-1, temp_pos[1])
					WallTiles.set_cell(grid_pos, 44, Vector2i(7,1))
					
					grid_pos = Vector2(temp_pos[0], temp_pos[1])
					WallTiles.set_cell(grid_pos, 44, Vector2i(7,0))
					
					grid_pos = Vector2(temp_pos[0], temp_pos[1]-1)
					WallTiles.set_cell(grid_pos, 44, Vector2i(6,1))
				elif rotation_state == 2:
					grid_pos = Vector2(temp_pos[0]+1, temp_pos[1])
					WallTiles.set_cell(grid_pos, 44, Vector2i(7,1))
					
					grid_pos = Vector2(temp_pos[0], temp_pos[1])
					WallTiles.set_cell(grid_pos, 44, Vector2i(5,0))
					
					grid_pos = Vector2(temp_pos[0], temp_pos[1]-1)
					WallTiles.set_cell(grid_pos, 44, Vector2i(5,1))
				elif rotation_state == 3:
					grid_pos = Vector2(temp_pos[0]+1, temp_pos[1])
					WallTiles.set_cell(grid_pos, 44, Vector2i(4,1))
					
					grid_pos = Vector2(temp_pos[0], temp_pos[1])
					WallTiles.set_cell(grid_pos, 44, Vector2i(4,0))
					
					grid_pos = Vector2(temp_pos[0], temp_pos[1]+1)
					WallTiles.set_cell(grid_pos, 44, Vector2i(5,1))
				else:
					grid_pos = Vector2(temp_pos[0]-1, temp_pos[1])
					WallTiles.set_cell(grid_pos, 44, Vector2i(4,1))
					
					grid_pos = Vector2(temp_pos[0], temp_pos[1])
					WallTiles.set_cell(grid_pos, 44, Vector2i(6,0))
					
					grid_pos = Vector2(temp_pos[0], temp_pos[1]+1)
					WallTiles.set_cell(grid_pos, 44, Vector2i(6,1))
				
			#Add a corner
			if rotation_state == 1:
				#find all cell that id
				var all_floor_cells: Array[Vector2i] = WallTiles.get_used_cells_by_id(44, Vector2i(7,1))
		
				# You can now loop through this array directly
				for cell in all_floor_cells:
					var other_wall = WallTiles.get_cell_atlas_coords(Vector2i(cell[0]-1,cell[1]+1))
					if other_wall == Vector2i(6,1):
						var corner_pos = Vector2i(cell[0]-1,cell[1])
						# T-intersection: skip corner if a straight wall already occupies this cell
						if WallTiles.get_cell_source_id(corner_pos) == -1:
							WallTiles.set_cell(corner_pos, 44, Vector2i(3,2))
			elif rotation_state == 2:
				#find all cell that id
				var all_floor_cells: Array[Vector2i] = WallTiles.get_used_cells_by_id(44, Vector2i(7,1))
		
				# You can now loop through this array directly
				for cell in all_floor_cells:
					var other_wall = WallTiles.get_cell_atlas_coords(Vector2i(cell[0]+1,cell[1]+1))
					if other_wall == Vector2i(5,1):
						var corner_pos = Vector2i(cell[0]+1,cell[1])
						# T-intersection: skip corner if a straight wall already occupies this cell
						if WallTiles.get_cell_source_id(corner_pos) == -1:
							WallTiles.set_cell(corner_pos, 44, Vector2i(1,2))
			elif rotation_state == 3:
				#find all cell that id
				var all_floor_cells: Array[Vector2i] = WallTiles.get_used_cells_by_id(44, Vector2i(4,1))
		
				# You can now loop through this array directly
				for cell in all_floor_cells:
					var other_wall = WallTiles.get_cell_atlas_coords(Vector2i(cell[0]+1,cell[1]-1))
					if other_wall == Vector2i(5,1):
						var corner_pos = Vector2i(cell[0]+1,cell[1])
						# T-intersection: skip corner if a straight wall already occupies this cell
						if WallTiles.get_cell_source_id(corner_pos) == -1:
							WallTiles.set_cell(corner_pos, 44, Vector2i(0,2))
			else:
				#find all cell that id
				var all_floor_cells: Array[Vector2i] = WallTiles.get_used_cells_by_id(44, Vector2i(4,1))
		
				# You can now loop through this array directly
				for cell in all_floor_cells:
					var other_wall = WallTiles.get_cell_atlas_coords(Vector2i(cell[0]-1,cell[1]-1))
					if other_wall == Vector2i(6,1):
						var corner_pos = Vector2i(cell[0]-1,cell[1])
						# T-intersection: skip corner if a straight wall already occupies this cell
						if WallTiles.get_cell_source_id(corner_pos) == -1:
							WallTiles.set_cell(corner_pos, 44, Vector2i(2,2))

	else:
		push_warning("JSON loaded, but 'walls' keys were missing!")

func _build_goal_cells(data: Dictionary, cols: int, rows: int) -> void:
	var max_grid = max(cols,rows)
	
	if not data.has("goal"):
		return
	var goal = data["goal"]
	if goal.has("possible_final_positions"):
		for pos in goal["possible_final_positions"]:
			if typeof(pos) == TYPE_ARRAY and pos.size() >= 2:
				var draw_x = pos[0] - 1
				var draw_y = rows - pos[1]
				
				# Swap the coordinates based on the current angle!
				if rotation_state == 1: # 90 Degrees
					draw_x = pos[1] - 1
					draw_y = pos[0] - 1
				elif rotation_state == 2: # 180 Degrees
					draw_x = (max_grid) - pos[0]
					draw_y = pos[1] - 1
				elif rotation_state == 3: # 270 Degrees
					draw_x = (max_grid) - pos[1]
					draw_y = (max_grid) - pos[0]
				var grid_pos = Vector2i(draw_x, draw_y)
				print(grid_pos)
				
				# Draw your floor tile (Assuming source_id 0 and atlas coords 0,0)
				FloorTiles.set_cell(grid_pos, 8, Vector2i(0, 0))
	if goal.has("position"):
		var pos = goal["position"]
		if typeof(pos) == TYPE_DICTIONARY:
				var draw_x = (int(pos.get("x", -1))) - 1
				var draw_y = rows - (int(pos.get("y", -1)))
				
				# Swap the coordinates based on the current angle!
				if rotation_state == 1: # 90 Degrees
					draw_x =  (int(pos.get("y", -1))) - 1
					draw_y = (int(pos.get("x", -1))) - 1
				elif rotation_state == 2: # 180 Degrees
					draw_x = (max_grid) - (int(pos.get("x", -1)))
					draw_y =  (int(pos.get("y", -1))) - 1
				elif rotation_state == 3: # 270 Degrees
					draw_x = (max_grid) -  (int(pos.get("y", -1)))
					draw_y = (max_grid) - (int(pos.get("x", -1)))
				var grid_pos = Vector2i(draw_x, draw_y)
				print(grid_pos)
				
				# Draw your floor tile (Assuming source_id 0 and atlas coords 0,0)
				FloorTiles.set_cell(grid_pos, 8, Vector2i(0, 0))

## Define and places the player at starting position
func _place_player(data: Dictionary, cols: int, rows: int) -> void:
	if data.has("robots"):
		var robots = level_data["robots"]
		if not robots.is_empty():
			var robot_info = robots[0]
			var innit_x: int
			var innit_y: int
			
			# ALWAYS trust the Player's memory if we are just rotating the camera
			if is_rotating and player != null:
				innit_x = player.grid_x
				innit_y = player.grid_y
			else:
				innit_x = robot_info.get("x", 1)
				innit_y = robot_info.get("y", 1)
			# Move to desired position
			# CAUTION: mantain chunk_size since floor are scale 2x
			cols = cols * chunk_size
			rows = rows * chunk_size
			var max_grid = max(cols,rows)
			
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

			var grid_pos = FloorTiles.map_to_local(Vector2i(pos_x,pos_y))
			@warning_ignore("narrowing_conversion")
			var pixel_pos = Vector2i(grid_pos[0]+offset_x,grid_pos[1]+offset_y)
			
			# Pass `is_rotating` to the player so it knows whether to reset its facing
			player.initialize_from_level(robot_info, pixel_pos, is_rotating)
			#player.global_position = pixel_pos

## Centers the camera to the middle and zoom relative to the grid size.
func _center_camera(cols: int, rows: int) -> void:
	# 1. Find the 4 extreme corners of the isometric diamond grid
	# (Subtracting 1 because a 6x6 grid goes from index 0 to 5)
	var top_corner = FloorTiles.map_to_local(Vector2i(0, 0))
	var bottom_corner = FloorTiles.map_to_local(Vector2i(cols - 1, rows - 1))
	var right_corner = FloorTiles.map_to_local(Vector2i(cols - 1, 0))
	var left_corner = FloorTiles.map_to_local(Vector2i(0, rows - 1))

	# 2. Get the base pixel boundaries
	var min_x = left_corner.x
	var max_x = right_corner.x
	var min_y = top_corner.y
	var max_y = bottom_corner.y

	# 3. Add padding for the tile edges! 
	# map_to_local() returns the CENTER of the tile. If we don't add half 
	# of the tile's size, the camera will cut off the outer halves of the edge tiles.
	var half_tile = Vector2(FloorTiles.tile_set.tile_size) / 2.0
	min_x -= half_tile.x
	max_x += half_tile.x
	min_y -= half_tile.y
	max_y += half_tile.y

	# 4. Center the camera
	var center_x = (min_x + max_x) / 2.0
	var center_y = (min_y + max_y) / 2.0
	
	# Convert local coordinates back to global just in case the Node2D is moved
	camera.global_position = FloorTiles.to_global(Vector2(center_x, center_y))

	# Hardcode the zoom depending on the grid size
	# - Determine the zoom size byt an incresing grid interval of 5
	# - The starting zoom is 0.5
	# - The max zoom is 0.1
	var max_grid_size = max(cols, rows)
	
	# Determine on what interval of 5 we are on
	@warning_ignore("integer_division")
	var step = (int(max_grid_size) - 1) / 5
	
	# Determine a proper zoom between grid sizes
	var final_zoom = 1
	print("Grid Size Level: ", step)
	if step < 5:
		final_zoom = 0.15 - (step * 0.03)
	else:
		final_zoom = 0.1 - (step * 0.01)
	
	# CRITICAL: Put a floor. Camera zoom cannot be 0
	final_zoom = max(final_zoom, 0.01) 
	
	# Apply the zoom
	# # CRITICAL: Since this camera zoom is fixed recomend no bigger than 35X35 grid size
	camera.zoom = Vector2(final_zoom, final_zoom)

# === grid overlay ===
# visual helper for readability and debugging (not gameplay logic)
#func _build_grid() -> void:
	#for gx in range(1, cols + 1):
		#for gy in range(1, rows + 1):
			#var diamond := Line2D.new()
			#diamond.width = 1.0
			#diamond.default_color = grid_color
#
			#var c := _cell_center(gx, gy)
			#var top := c + Vector2(0, -tile_height / 2.0)
			#var right := c + Vector2(tile_width / 2.0, 0)
			#var bottom := c + Vector2(0, tile_height / 2.0)
			#var left := c + Vector2(-tile_width / 2.0, 0)
#
			#diamond.add_point(top)
			#diamond.add_point(right)
			#diamond.add_point(bottom)
			#diamond.add_point(left)
			#diamond.add_point(top)
#
			#grid_node.add_child(diamond)

# ======= public helpers =======

## Returns the proper position in realation to the floor grids.
## Input:  New grid position
## Output: Pixel position in relation to the grid position
func player_grid_position(x_pos: int, y_pos: int) -> Vector2:	
	var cols = world_x_size * chunk_size
	var rows = world_y_size * chunk_size
	var max_grid = max(cols,rows)
	
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

	# 5. Ask the TileMapLayer where that specific grid tile is in actual pixels
	var grid_pos = FloorTiles.map_to_local(Vector2i(pos_x,pos_y))
	
	# If offset is needed
	@warning_ignore("narrowing_conversion")
	var pixel_pos = Vector2i(grid_pos[0]+offset_x,grid_pos[1]+offset_y)
	print("New Position: ", x_pos, ",", y_pos, " Grid Postion: ", grid_pos, " Pixel Position: ", pixel_pos)
	return pixel_pos

## simple bounds check so the player doesn't walk off the map like a clown
func is_in_bounds(gx: int, gy: int) -> bool:
	return gx >= 1 and gx <= world_x_size and gy >= 1 and gy <= world_y_size

## Check if movement in dir from (gx,gy) is blocked by a wall.
## Walls are stored as "east" and "north" only (Reborg format).
## Moving west/south requires checking the adjacent cell's east/north wall.
func is_move_blocked(gx: int, gy: int, dir: String) -> bool:
	# Check if wall even exist
	if not level_data.has("walls"):
		return false
	
	# Direct check: does this cell have a wall on this face?
	# Covers "east" and "north" moves.
	var key := "%d,%d" % [gx, gy]
	if level_data["walls"].has(key):
		for d in level_data["walls"][key]:
			if str(d).to_lower() == dir:
				return true
	
	# Indirect check: moving west/south means checking the neighbour's east/north wall.
	# A "west" wall on (gx,gy) is stored as an "east" wall on (gx-1,gy).
	# A "south" wall on (gx,gy) is stored as a "north" wall on (gx,gy-1).
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

func get_rotation_step() -> int:
	return rotation_state
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
# Returns true when every required object is present at its goal cell
# Returns true if there are no object goals
func are_goal_objects_satisfied() -> bool:
	if not level_data.has("goal") or not level_data["goal"].has("objects"):
		return true
	var goal_objs: Dictionary = level_data["goal"]["objects"]
	for key in goal_objs:
		var required: Dictionary = goal_objs[key]
		var placed: Dictionary = object_data.get(key, {})
		for obj_name in required:
			if int(placed.get(obj_name, 0)) < int(required[obj_name]):
				return false
	return true

# Emits level_complete signal if player reached goal position
# and are_goal_objects_satisfied is true
func check_win_condition(gx: int, gy: int) -> void:
	if not level_data.has("goal"):
		return

	var goal = level_data["goal"]
	var at_position := false
	
	if goal.has("possible_final_positions"):
		for pos in goal["possible_final_positions"]:
			if typeof(pos) == TYPE_ARRAY and pos.size() >= 2:
				if int(pos[0]) == gx and int(pos[1]) == gy:
					at_position = true
					break

	if not at_position and goal.has("position"):
		var pos = goal["position"]
		if typeof(pos) == TYPE_DICTIONARY:
			if int(pos.get("x", -1)) == gx and int(pos.get("y", -1)) == gy:
				at_position = true
	
	# If no position requirement is defined, treat position as satisfied
	if not goal.has("possible_final_positions") and not goal.has("position"):
		at_position = true

	if not at_position:
		return

	# --- object goal check ---
	if not are_goal_objects_satisfied():
		return

	level_complete.emit()


# === objects ===
# render objects as small colored diamonds for now
func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func object_grid_position(x_pos: int, y_pos: int) -> Vector2:
	# Remember if the player has moved
	var cols = world_x_size * chunk_size
	var rows = world_y_size * chunk_size
	var max_grid = max(cols,rows)
	
	x_pos = (x_pos * chunk_size) - 2
	y_pos = (y_pos * chunk_size) - 2
	
	var pos_x = x_pos
	var pos_y = rows - y_pos - 2
	
	if rotation_state == 1:
		pos_x = y_pos - 2
		pos_y = x_pos - 2
	elif rotation_state == 2:
		pos_x = max_grid - x_pos - 2
		pos_y = y_pos - 4
	elif rotation_state == 3:
		pos_x = max_grid - y_pos
		pos_y = max_grid - x_pos - 2

	# 5. Ask the TileMapLayer where that specific grid tile is in actual pixels
	var grid_pos = FloorTiles.map_to_local(Vector2i(pos_x,pos_y))

	# If offset is needed
	@warning_ignore("narrowing_conversion")
	var pixel_pos = Vector2i(grid_pos[0]+offset_x,grid_pos[1]+offset_y)
	print("New Position: ", x_pos, ",", y_pos, " Grid Postion: ", grid_pos, " Pixel Position: ", pixel_pos)
	return pixel_pos

func _build_objects() -> void:
	_clear_children(objects_node)
	
	# Render goal-object outlines first so actual objects draw on top
	_build_goal_object_markers()
	
	for key in object_data.keys():
		var parts = key.split(",")
		if parts.size() != 2:
			continue

		var gx := int(parts[0])
		var gy := int(parts[1])

		var tile_objects: Dictionary = object_data[key]

		for object_name in tile_objects.keys():
			var count := int(tile_objects[object_name])

			for i in range(count):
				print(object_name, ", ", gx, ", ", gy, ", ", i)
				_spawn_object(object_name, gx, gy)

		var is_goal_tile : bool = level_data.has("goal") \
			and level_data["goal"].has("objects") \
			and level_data["goal"]["objects"].has(key)
		if not is_goal_tile:
			_add_object_count_label(gx, gy, tile_objects)

func _spawn_object(object_name: String, gx: int, gy: int) -> void:
	var sprite := Sprite2D.new()
	var tex = load("res://assets/objects/" + object_name + ".png")
	if tex:
		sprite.texture = tex
	sprite.scale = Vector2(5.0, 5.0)
	var grid_pos = object_grid_position(gx, gy+1)
	sprite.position = Vector2i(int(grid_pos[0] + offset_x), int(grid_pos[1] + offset_y))
	sprite.z_index = 1
	objects_node.add_child(sprite)


## Renders outlined diamond markers for every object required by the level goal.
## Unsatisfied slots show in the object's colour; satisfied slots turn green.
## Called before actual objects so markers sit visually behind them.
func _build_goal_object_markers() -> void:
	if not level_data.has("goal") or not level_data["goal"].has("objects"):
		return
	var goal_objs: Dictionary = level_data["goal"]["objects"]
	for key in goal_objs:
		var parts = key.split(",")
		if parts.size() != 2:
			continue
		var gx := int(parts[0])
		var gy := int(parts[1])
		var required: Dictionary = goal_objs[key]
		for obj_name in required:
			var needed := int(required[obj_name])
			var have  := 0
			if object_data.has(key) and object_data[key].has(obj_name):
				have = int(object_data[key][obj_name])
			for i in range(needed):
				_spawn_goal_marker(obj_name, gx, gy, i < have)
			
			_add_goal_count_label(gx, gy, have, needed)


## Spawns a single outlined diamond at a goal cell.
## satisfied = the matching object has already been placed here.
func _spawn_goal_marker(object_name: String, gx: int, gy: int, satisfied: bool) -> void:
	var sprite := Sprite2D.new()
	var tex = load("res://assets/objects/" + object_name + "_goal.png")
	if tex:
		sprite.texture = tex
	sprite.scale = Vector2(4.8, 4.8)

	if satisfied:
		sprite.modulate = Color(0.35, 0.9, 0.45, 0.55)
	else:
		sprite.modulate = Color(1.0, 1.0, 1.0, 0.75)

	var grid_pos = object_grid_position(gx, gy + 1)
	sprite.position = Vector2i(int(grid_pos[0] + offset_x), int(grid_pos[1] + offset_y))
	sprite.z_index = 0
	objects_node.add_child(sprite)


## Adds a count label to a regular object tile.
## Shows total count if all objects are the same type, "?" if mixed.
func _add_object_count_label(gx: int, gy: int, tile_objects: Dictionary) -> void:
	var center: Vector2 = object_grid_position(gx, gy + 1)
	center = Vector2(center.x + offset_x, center.y + offset_y)

	var is_mixed := tile_objects.size() > 1
	var total := 0
	for obj_name in tile_objects:
		total += int(tile_objects[obj_name])

	var text := "?" if is_mixed else str(total)
	var label := _make_count_label(text, center + Vector2(18, 28), Color(0.0, 0.0, 0.0, 1.0))
	objects_node.add_child(label)


## Adds have/needed labels to a goal marker tile.
## "have" sits at the bottom-left corner, "needed" at the bottom-right.
func _add_goal_count_label(gx: int, gy: int, have: int, needed: int) -> void:
	print("\n[goal label] (%d,%d) have=%d needed=%d   object_data=%s\n" % [gx, gy, have, needed, object_data])
	var center: Vector2 = object_grid_position(gx, gy + 1)
	center = Vector2(center.x + offset_x, center.y + offset_y)

	var have_label := _make_count_label(str(have), center + Vector2(-72, 28), Color(0.0, 0.0, 0.0, 1.0))
	var needed_label := _make_count_label(str(needed), center + Vector2(18, 28), Color(0.046, 0.649, 0.924, 1.0))
	objects_node.add_child(have_label)
	objects_node.add_child(needed_label)


## Creates a styled Label at world_pos with the given text and colour.
func _make_count_label(text: String, world_pos: Vector2, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = world_pos

	var font = load(LABEL_FONT_PATH)
	if font:
		label.add_theme_font_override("font", font)

	label.add_theme_font_size_override("font_size", 100)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.378, 0.378, 0.378, 1.0))
	label.add_theme_constant_override("outline_size", 5)
	label.z_index = 10
	return label
	

func _get_object_color(object_name: String) -> Color:
	match object_name:
		"apple":
			return Color(1.0, 0.2, 0.2)
		"banana":
			return Color(1.0, 0.9, 0.2)
		"carrot":
			return Color(1.0, 0.5, 0.1)
		"star":
			return Color(0.922, 1.0, 0.698, 1.0)
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
		tile_objects[object_name] -= 1

		if tile_objects[object_name] <= 0:
			tile_objects.erase(object_name)

		if tile_objects.is_empty():
			object_data.erase(key)

		_build_objects()
		return object_name

	return ""

func place_object_at(gx: int, gy: int, object_name: String) -> void:
	if object_name == "":
		return

	var key := _cell_key(gx, gy)

	if not object_data.has(key):
		object_data[key] = {}

	if not object_data[key].has(object_name):
		object_data[key][object_name] = 0

	object_data[key][object_name] += 1
	_build_objects()


func tile_has_any_object(gx: int, gy: int) -> bool:
	var tile_objects: Dictionary = get_objects_at(gx, gy)
	return not tile_objects.is_empty()
