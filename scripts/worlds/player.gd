extends Node2D

@export var move_duration: float = 0.15

var grid_x: int = 1
var grid_y: int = 1
var facing: String = "east"

func set_grid_position(gx: int, gy: int, world_pos: Vector2) -> void:
	grid_x = gx
	grid_y = gy
	position = world_pos

func move_forward() -> void:
	var parent_world = get_parent().get_parent()
	if parent_world == null:
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

	# Stay inside world bounds for now
	if parent_world.has_method("is_in_bounds"):
		if not parent_world.is_in_bounds(next_x, next_y):
			return

	grid_x = next_x
	grid_y = next_y

	if parent_world.has_method("grid_to_world_position"):
		var target_pos: Vector2 = parent_world.grid_to_world_position(grid_x, grid_y)

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
