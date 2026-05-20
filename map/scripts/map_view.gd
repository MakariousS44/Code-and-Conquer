extends Node2D

signal level_complete
signal level_incomplete(reason: String)

@onready var camera: Camera2D = $Camera2D
@onready var world_root: Node2D = $WorldRoot
@onready var player: Node2D = $WorldRoot/Player
@onready var objects_node: Node2D = $WorldRoot/Objects
@onready var FloorTiles: TileMapLayer = $WorldRoot/FloorMapLayer
@onready var WallTiles: TileMapLayer = $WorldRoot/WallMapLayer

# ============ Global Values ============
const LABEL_FONT_PATH := "res://assets/fonts/ttf/FiraCode-Bold.ttf"
var _compass_font: Font = null

var level_data: Dictionary = {}
var object_data: Dictionary = {}
var world_x_size : int = 10
var world_y_size : int = 10
var rotation_state = 0
var offset_x = 256
var offset_y = 64
var is_rotating = false
const CAMERA_ZOOM_STEP := 0.05
const CAMERA_ZOOM_OUT_FLOOR := 0.05
# Higher zoom value = zoomed in (less visible). Lower value = zoomed out (more visible).
var camera_zoom_min := CAMERA_ZOOM_OUT_FLOOR
var camera_zoom_max := 4.0
var camera_start_zoom := 1.0
const CAMERA_PAN_SPEED := 1700.0
const CAMERA_DRAG_SPEED := 1.8
var camera_bounds_min := Vector2.ZERO
var camera_bounds_max := Vector2.ZERO
var camera_pan_min := Vector2.ZERO
var camera_pan_max := Vector2.ZERO
var camera_bounds_ready := false
var camera_dragging := false
var _pending_camera_restore: Dictionary = {}
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_camera_zoom(-CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_camera_zoom(CAMERA_ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			camera_dragging = true
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		camera_dragging = false
	elif event is InputEventMouseMotion and camera_dragging:
		camera.global_position -= event.relative * CAMERA_DRAG_SPEED
		_clamp_camera_to_bounds()


func _process(delta: float) -> void:
	queue_redraw()
	if not camera_bounds_ready:
		return

	var move_direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_ALT):
		if Input.is_key_pressed(KEY_A):
			move_direction.x -= 1.0
		if Input.is_key_pressed(KEY_D):
			move_direction.x += 1.0
		if Input.is_key_pressed(KEY_W):
			move_direction.y -= 1.0
		if Input.is_key_pressed(KEY_S):
			move_direction.y += 1.0

	if move_direction != Vector2.ZERO:
		camera.global_position += move_direction.normalized() * CAMERA_PAN_SPEED * delta
		_clamp_camera_to_bounds()


func _draw() -> void:
	if _compass_font == null:
		_compass_font = load(LABEL_FONT_PATH)
	var font := _compass_font
	var fs   := 18
	var col  := Color(0.28, 0.78, 0.92, 0.85)
	var inv  := get_canvas_transform().affine_inverse()
	var vp   := get_viewport_rect()
	var pad  := 20.0

	# Directions rotate with the world: N stays "above" whatever is grid-north on screen
	var dirs: Array[String] = ["N", "E", "S", "W"]
	var top_lbl:    String = dirs[rotation_state % 4]
	var right_lbl:  String = dirs[(rotation_state + 1) % 4]
	var bottom_lbl: String = dirs[(rotation_state + 2) % 4]
	var left_lbl:   String = dirs[(rotation_state + 3) % 4]

	var top    := inv * Vector2(vp.size.x * 0.5, pad)
	var right  := inv * Vector2(vp.size.x - pad, vp.size.y * 0.5)
	var bottom := inv * Vector2(vp.size.x * 0.5, vp.size.y - pad * 0.5)
	var left   := inv * Vector2(pad, vp.size.y * 0.5)

	draw_string(font, top,    top_lbl,    HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)
	draw_string(font, right,  right_lbl,  HORIZONTAL_ALIGNMENT_LEFT,   -1, fs, col)
	draw_string(font, bottom, bottom_lbl, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, col)
	draw_string(font, left,   left_lbl,   HORIZONTAL_ALIGNMENT_RIGHT,  -1, fs, col)


func get_camera_state() -> Dictionary:
	return {
		"zoom": camera.zoom,
		"position": camera.global_position,
		"zoom_min": camera_zoom_min,
		"zoom_max": camera_zoom_max,
		"start_zoom": camera_start_zoom,
	}


func set_pending_camera_restore(state: Dictionary) -> void:
	_pending_camera_restore = state


func apply_camera_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if state.has("zoom_min"):
		camera_zoom_min = state["zoom_min"]
	if state.has("zoom_max"):
		camera_zoom_max = state["zoom_max"]
	if state.has("start_zoom"):
		camera_start_zoom = state["start_zoom"]
	if state.has("zoom"):
		camera.zoom = state["zoom"]
	if state.has("position"):
		camera.global_position = state["position"]
	_update_camera_pan_bounds()
	_clamp_camera_to_bounds()
	
	
func _adjust_camera_zoom(delta: float) -> void:
	var next_zoom = clampf(camera.zoom.x + delta, camera_zoom_min, camera_zoom_max)
	camera.zoom = Vector2(next_zoom, next_zoom)
	_update_camera_pan_bounds()


func _clamp_camera_to_bounds() -> void:
	if not camera_bounds_ready:
		return

	camera.global_position.x = clampf(camera.global_position.x, camera_pan_min.x, camera_pan_max.x)
	camera.global_position.y = clampf(camera.global_position.y, camera_pan_min.y, camera_pan_max.y)


func _update_camera_pan_bounds() -> void:
	if not camera_bounds_ready:
		return

	var viewport_size: Vector2 = get_viewport_rect().size
	# Standard Camera2D: visible world size = viewport / zoom (higher zoom = zoomed in).
	var half_viewport_world: Vector2 = (viewport_size / camera.zoom) / 2.0
	var zoom_growth := maxf(0.0, camera_start_zoom / maxf(camera.zoom.x, 0.001) - 1.0)
	var extra_pan_x := (camera_bounds_max.x - camera_bounds_min.x) * 0.5 * zoom_growth
	var extra_pan_y := (camera_bounds_max.y - camera_bounds_min.y) * 0.5 * zoom_growth

	var left_bound := camera_bounds_min.x + half_viewport_world.x - extra_pan_x
	var right_bound := camera_bounds_max.x - half_viewport_world.x + extra_pan_x
	var top_bound := camera_bounds_min.y + half_viewport_world.y - extra_pan_y
	var bottom_bound := camera_bounds_max.y - half_viewport_world.y + extra_pan_y

	if left_bound > right_bound:
		var center_x := (camera_bounds_min.x + camera_bounds_max.x) / 2.0
		left_bound = center_x
		right_bound = center_x

	if top_bound > bottom_bound:
		var center_y := (camera_bounds_min.y + camera_bounds_max.y) / 2.0
		top_bound = center_y
		bottom_bound = center_y

	camera_pan_min = Vector2(left_bound, top_bound)
	camera_pan_max = Vector2(right_bound, bottom_bound)
	_clamp_camera_to_bounds()


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

## Rotate a 0-based floor cell for the current camera angle.
## Uses cols and rows separately so non-square grids (e.g. 6x10) stay aligned.
func _rotate_floor_cell(x: int, y: int, cols: int, rows: int) -> Vector2i:
	match rotation_state:
		1:
			return Vector2i(y, x)
		2:
			return Vector2i(cols - 1 - x, rows - 1 - y)
		3:
			return Vector2i(rows - 1 - y, cols - 1 - x)
		_:
			return Vector2i(x, y)


## Rotate a 1-based Reeborg goal cell into floor tile coordinates.
func _rotate_goal_cell(gx: int, gy: int, cols: int, rows: int) -> Vector2i:
	match rotation_state:
		1:
			return Vector2i(gy - 1, gx - 1)
		2:
			return Vector2i(cols - gx, gy - 1)
		3:
			return Vector2i(rows - gy, cols - gx)
		_:
			return Vector2i(gx - 1, rows - gy)


## This builds the floor given the grid size
func _build_floor(cols: int,rows: int) -> void:
	# Clear current floor
	FloorTiles.clear()
	# Loop through every x (column) and y (row) to fill the grid
	for x in range(cols):
		for y in range(rows):
			var grid_pos := _rotate_floor_cell(x, y, cols, rows)
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
	if not data.has("goal"):
		return
	var goal = data["goal"]
	if goal.has("possible_final_positions"):
		for pos in goal["possible_final_positions"]:
			if typeof(pos) == TYPE_ARRAY and pos.size() >= 2:
				var grid_pos := _rotate_goal_cell(int(pos[0]), int(pos[1]), cols, rows)
				FloorTiles.set_cell(grid_pos, 8, Vector2i(0, 0))
	if goal.has("position"):
		var pos = goal["position"]
		if typeof(pos) == TYPE_DICTIONARY:
				var grid_pos := _rotate_goal_cell(
					int(pos.get("x", -1)),
					int(pos.get("y", -1)),
					cols,
					rows
				)
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
			
			innit_x = (innit_x * chunk_size) - 2
			innit_y = (innit_y * chunk_size) - 2
			
			var pos_x = innit_x
			var pos_y = rows - innit_y - 2
			
			if rotation_state == 1:
				pos_x = innit_y
				pos_y = innit_x
			elif rotation_state == 2:
				pos_x = cols - innit_x - 2
				pos_y = innit_y
			elif rotation_state == 3:
				pos_x = rows - innit_y - 2
				pos_y = cols - innit_x - 2

			var grid_pos = FloorTiles.map_to_local(Vector2i(pos_x, pos_y))
			@warning_ignore("narrowing_conversion")
			var pixel_pos = Vector2i(grid_pos[0] + offset_x, grid_pos[1] + offset_y)
			
			player.initialize_from_level(robot_info, pixel_pos, is_rotating)

## Queues a deferred camera fit so the SubViewport has its final size first.
func _center_camera(_cols: int, _rows: int) -> void:
	call_deferred("_fit_camera_to_level")


## Centers and zooms the camera so the full floor grid is visible on level start.
func _fit_camera_to_level() -> void:
	var bounds := _compute_level_pixel_bounds()
	if bounds.is_empty():
		return

	var min_local: Vector2 = bounds["min"]
	var max_local: Vector2 = bounds["max"]
	var center_local: Vector2 = (min_local + max_local) / 2.0

	camera_bounds_min = FloorTiles.to_global(min_local)
	camera_bounds_max = FloorTiles.to_global(max_local)
	camera_bounds_ready = true

	if not _pending_camera_restore.is_empty():
		var restore_state := _pending_camera_restore
		_pending_camera_restore = {}
		apply_camera_state(restore_state)
		return

	camera.global_position = FloorTiles.to_global(center_local)

	var viewport_size: Vector2 = get_viewport_rect().size
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		return

	var map_width: float = maxf(max_local.x - min_local.x, 1.0)
	var map_height: float = maxf(max_local.y - min_local.y, 1.0)
	var fit_zoom_x: float = viewport_size.x / map_width
	var fit_zoom_y: float = viewport_size.y / map_height
	var fit_zoom: float = minf(fit_zoom_x, fit_zoom_y)

	# Pull back slightly so walls/tiles are not clipped on load (lower zoom = more visible).
	fit_zoom = maxf(fit_zoom * 0.85, CAMERA_ZOOM_OUT_FLOOR)
	camera.zoom = Vector2(fit_zoom, fit_zoom)
	camera_start_zoom = fit_zoom
	# zoom_min = lowest value = furthest zoom out; zoom_max = highest value = furthest zoom in.
	camera_zoom_min = maxf(fit_zoom * 0.25, CAMERA_ZOOM_OUT_FLOOR)
	camera_zoom_max = maxf(fit_zoom * 3.0, fit_zoom + 0.5)
	_update_camera_pan_bounds()


## Pixel bounds of floor + wall tiles in FloorTiles local space.
func _compute_level_pixel_bounds() -> Dictionary:
	var min_local := Vector2(INF, INF)
	var max_local := Vector2(-INF, -INF)
	var found := false

	var half_floor := Vector2(FloorTiles.tile_set.tile_size) * FloorTiles.scale / 2.0
	for cell in FloorTiles.get_used_cells():
		found = true
		var center := FloorTiles.map_to_local(cell)
		min_local.x = minf(min_local.x, center.x - half_floor.x)
		min_local.y = minf(min_local.y, center.y - half_floor.y)
		max_local.x = maxf(max_local.x, center.x + half_floor.x)
		max_local.y = maxf(max_local.y, center.y + half_floor.y)

	if WallTiles.tile_set != null:
		var half_wall := Vector2(WallTiles.tile_set.tile_size) / 2.0
		for cell in WallTiles.get_used_cells():
			found = true
			var center := FloorTiles.to_local(WallTiles.to_global(WallTiles.map_to_local(cell)))
			min_local.x = minf(min_local.x, center.x - half_wall.x)
			min_local.y = minf(min_local.y, center.y - half_wall.y)
			max_local.x = maxf(max_local.x, center.x + half_wall.x)
			max_local.y = maxf(max_local.y, center.y + half_wall.y)

	if not found:
		return {}

	return { "min": min_local, "max": max_local }

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
	
	x_pos = (x_pos * chunk_size) - 2
	y_pos = (y_pos * chunk_size) - 2
	
	var pos_x = x_pos
	var pos_y = rows - y_pos - 2
	
	if rotation_state == 1:
		pos_x = y_pos
		pos_y = x_pos
	elif rotation_state == 2:
		pos_x = cols - x_pos - 2
		pos_y = y_pos
	elif rotation_state == 3:
		pos_x = rows - y_pos - 2
		pos_y = cols - x_pos - 2

	var grid_pos = FloorTiles.map_to_local(Vector2i(pos_x, pos_y))
	@warning_ignore("narrowing_conversion")
	var pixel_pos = Vector2i(grid_pos[0] + offset_x, grid_pos[1] + offset_y)
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
		level_incomplete.emit("Reached the goal without completing all the objectives.")
		return

	level_complete.emit()


# === objects ===
# render objects as small colored diamonds for now
func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()

func object_grid_position(x_pos: int, y_pos: int) -> Vector2:
	var cols = world_x_size * chunk_size
	var rows = world_y_size * chunk_size
	
	x_pos = (x_pos * chunk_size) - 2
	y_pos = (y_pos * chunk_size) - 2
	
	var pos_x = x_pos
	var pos_y = rows - y_pos - 2
	
	if rotation_state == 1:
		pos_x = y_pos - 2
		pos_y = x_pos - 2
	elif rotation_state == 2:
		pos_x = cols - x_pos - 2
		pos_y = y_pos - 4
	elif rotation_state == 3:
		pos_x = rows - y_pos
		pos_y = cols - x_pos - 4

	var grid_pos = FloorTiles.map_to_local(Vector2i(pos_x, pos_y))
	@warning_ignore("narrowing_conversion")
	var pixel_pos = Vector2i(grid_pos[0] + offset_x, grid_pos[1] + offset_y)
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
	var grid_pos = object_grid_position(gx, gy + 1)
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


func restore_object_data(data: Dictionary) -> void:
	object_data = data.duplicate(true)
	_build_objects()
