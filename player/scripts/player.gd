extends Node2D

signal lose_triggered(reason: String)

# === player state ===
# logical grid position + facing direction
var grid_x: int = 1
var grid_y: int = 1
var facing: String = "north"
var carried_object: String = "" 
var _has_lost: bool = false

func _ready() -> void:
	pass
	

## Initialize player at proper location and face direction
func initialize_from_level(robot_data: Dictionary, world_pos: Vector2, has_moved: bool) -> void:
	_has_lost = false
	carried_object = ""
	
	if not has_moved:
		grid_x = robot_data.get("x", 1)
		grid_y = robot_data.get("y", 1)
	
	# Starting numerical player facing
	var start_face: int = robot_data.get("_orientation", 1)
	match start_face:
		0:
			facing = "east"
			$AnimatedSprite2D.play("Idle_E")
		1:
			facing = "north"
			$AnimatedSprite2D.play("Idle_N")
		2:
			facing = "west"
			$AnimatedSprite2D.play("Idle_W")
		3:
			facing = "east"
			$AnimatedSprite2D.play("Idle_E")

	position = world_pos

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
	
	# Dermine its next grid position depending on where its facing
	match facing:
		"east":
			next_x += 1
			$AnimatedSprite2D.play("Run_E")
		"west":
			next_x -= 1
			$AnimatedSprite2D.play("Run_W")
		"north":
			next_y += 1  
			$AnimatedSprite2D.play("Run_N")
		"south":
			next_y -= 1  
			$AnimatedSprite2D.play("Run_S")

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

	# Obtains its next logical coordinate position and moves
	if world.has_method("grid_position"):
		var target_pos: Vector2 = world.grid_position(grid_x, grid_y)
		var tween = create_tween()
		
		tween.tween_property(self, "position", target_pos, 0.5)
		await tween.finished
	
	# Stop running animation
	match facing:
		"east":
			$AnimatedSprite2D.play("Idle_E")
		"west":
			$AnimatedSprite2D.play("Idle_W")
		"north":
			$AnimatedSprite2D.play("Idle_N")
		"south":
			$AnimatedSprite2D.play("Idle_S")

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
	match facing:
		"east":
			facing = "north"
			$AnimatedSprite2D.play("Idle_N")
		"north":
			facing = "west"
			$AnimatedSprite2D.play("Idle_W")
		"west":
			facing = "south"
			$AnimatedSprite2D.play("Idle_S")
		"south":
			facing = "east"
			$AnimatedSprite2D.play("Idle_E")

# IMPORTANT: No turn right functions


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
