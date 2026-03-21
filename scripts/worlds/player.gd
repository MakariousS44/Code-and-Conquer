extends Node2D

@export var move_duration: float = 0.3

var grid_x: int = 1
var grid_y: int = 1
var facing: String = "north"

func set_grid_position(gx: int, gy: int, world_pos: Vector2) -> void:
	grid_x = gx
	grid_y = gy
	position = world_pos

func _get_world() -> Node:
	var world_root = get_parent()
	if world_root == null:
		return null
	return world_root.get_parent()

func move_forward() -> void:
	var world = _get_world()
	if world == null:
		return

	var next_x = grid_x
	var next_y = grid_y

	match facing:
		"east":
			next_x += 1
		"west":
			next_x -= 1
		"north":
			next_y += 1
		"south":
			next_y -= 1

	if world.has_method("is_in_bounds"):
		if not world.is_in_bounds(next_x, next_y):
			return

	grid_x = next_x
	grid_y = next_y

	if world.has_method("grid_to_world_position"):
		var target_pos: Vector2 = world.grid_to_world_position(grid_x, grid_y)
		var tween = create_tween()
		tween.tween_property(self, "position", target_pos, move_duration)

func turn_left() -> void:
	match facing:
		"east":
			facing = "north"
		"north":
			facing = "west"
		"west":
			facing = "south"
		"south":
			facing = "east"

func turn_right() -> void:
	match facing:
		"east":
			facing = "south"
		"south":
			facing = "west"
		"west":
			facing = "north"
		"north":
			facing = "east"

func pick_object() -> void:
	var world = _get_world()
	if world == null:
		return
	if world.has_method("remove_object_at"):
		world.remove_object_at(grid_x, grid_y)

func put_object() -> void:
	var world = _get_world()
	if world == null:
		return
	if world.has_method("place_object_at"):
		world.place_object_at(grid_x, grid_y)
