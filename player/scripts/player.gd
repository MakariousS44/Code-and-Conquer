extends Node2D

signal lose_triggered(reason: String)

# === player state ===
# Array ordered to exactly match your rotation_step integers
# 0 = East, 1 = South, 2 = West, 3 = North
const DIRS = ["east", "south", "west", "north"]
# logical grid position + facing direction
var grid_x: int = 1
var grid_y: int = 1
var facing: String = "north"
var carried_object: String = "" 
var _has_lost: bool = false
var current_tween: Tween

func _ready() -> void:
	pass
	

func update_animation(is_running: bool = false) -> void:
	var world = _get_world()
	var camera_offset = 0
	
	# Fetch the current rotation step from the world
	if world != null and world.has_method("get_rotation_step"):
		camera_offset = world.get_rotation_step()
		
	# 1. Find the player's logical direction index (0 to 3)
	var current_idx = DIRS.find(facing)
	
	# 2. Apply the camera offset. Modulo (%) 4 safely wraps it around.
	var visual_idx = (current_idx + camera_offset) % 4
	var visual_facing = DIRS[visual_idx]
	
	# 3. Construct and play the animation
	var prefix = "Run_" if is_running else "Idle_"
	var suffix = ""
	
	match visual_facing:
		"north": suffix = "N"
		"east":  suffix = "E"
		"south": suffix = "S"
		"west":  suffix = "W"
		
	$AnimatedSprite2D.play(prefix + suffix)
	
## Initialize player at proper location and face direction
func initialize_from_level(robot_data: Dictionary, world_pos: Vector2, is_rotating: bool) -> void:
	_has_lost = false
	carried_object = ""
	
	# Prevent the tween from fighting the sudden camera snap
	if current_tween and current_tween.is_running():
		current_tween.kill()
		
	# Snap to the rotated coordinates instantly
	position = world_pos
	
	if not is_rotating:
		# BRAND NEW LEVEL: Reset logical variables
		_has_lost = false
		carried_object = ""
		grid_x = robot_data.get("x", 1)
		grid_y = robot_data.get("y", 1)
		
		var start_face: int = robot_data.get("_orientation", 1)
		facing = DIRS[start_face] 
	
	# Whether brand new or just rotating, update the visual sprite
	update_animation(false)

## Check if we are inside a parent and gives node acces
func _get_world() -> Node:
	var world_root = get_parent()
	if world_root == null:
		return null
	return world_root.get_parent()

# ========= Movement =========
## Advances the player one step to where its facing
func move_forward() -> void:
	var world = _get_world()
	var next_x = grid_x
	var next_y = grid_y
	
	# Determine its next grid position logically
	match facing:
		"east": next_x += 1
		"west": next_x -= 1
		"north": next_y += 1
		"south": next_y -= 1

	# Lose Condition ----------------------------------------
	# LOSE: if the player attempts to leave the playable floor
	if world.has_method("is_in_bounds"):
		if not world.is_in_bounds(next_x, next_y):
			_trigger_lose("You lose: attempted to move outside the floor.")
			return

	# LOSE: on attempted move through a wall edge
	if world.has_method("is_move_blocked"):
		if world.is_move_blocked(grid_x, grid_y, facing):
			_trigger_lose("You lose: attempted to move through a wall.")
			return
	# -------------------------------------------------------

	grid_x = next_x
	grid_y = next_y

	# Play running animation
	update_animation(true)

	# Obtain next logical coordinate position and move
	if world.has_method("player_grid_position"):
		var target_pos: Vector2 = world.player_grid_position(grid_x, grid_y)
		
		# Assign it to the class variable so initialize_from_level can stop it if needed
		current_tween = create_tween()
		current_tween.tween_property(self, "position", target_pos, 0.5)
		await current_tween.finished
	
	# Stop running animation
	update_animation(false)

	if world.has_method("check_win_condition"):
		world.check_win_condition(grid_x, grid_y)


func _trigger_lose(reason: String) -> void:
	if _has_lost:
		return
	_has_lost = true
	emit_signal("lose_triggered", reason)


# === turning ===
# just changes facing for now
# later could also rotate sprite/marker visually if desired
func turn_left() -> void:
	var current_idx = DIRS.find(facing)
	# -1 goes counter-clockwise. Add 4 before modulo to prevent negative indexes.
	var new_idx = (current_idx - 1 + 4) % 4 
	facing = DIRS[new_idx]
	
	update_animation() # Updates the Idle animation automatically


# === object interaction stubs ===
# world behavior for objects is still placeholder-ish,
# so for now the robot just asks the world if it knows how to handle it
func pick_object() -> void:
	var world = _get_world()
	if world == null:
		return

	if carried_object != "":
		return

	if world.has_method("remove_object_at"):
		var obj = world.remove_object_at(grid_x, grid_y)
		if obj != "":
			carried_object = obj


func put_object() -> void:
	var world = _get_world()
	if world == null:
		return

	if carried_object == "":
		return

	if world.has_method("place_object_at"):
		world.place_object_at(grid_x, grid_y, carried_object)
		carried_object = ""
