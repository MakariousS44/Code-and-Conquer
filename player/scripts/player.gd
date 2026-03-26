extends Node2D

# === player config ===
# movement timing + current placeholder colors for the debug robot visuals
@export var move_duration: float = 0.3
@export var player_color: Color = Color("7a4df3")
@export var player_shadow_color: Color = Color(0, 0, 0, 0.18)

# === player state ===
# logical grid position + facing direction
var grid_x: int = 1
var grid_y: int = 1
var facing: String = "north"


# === level setup ===
# called when a level is loaded
# this file owns player state + player appearance, so setup happens here now
func initialize_from_level(robot_data: Dictionary, world_pos: Vector2) -> void:
	grid_x = robot_data.get("x", 1)
	grid_y = robot_data.get("y", 1)
	facing = robot_data.get("direction", "south")
	position = world_pos
	_rebuild_visuals()


# fallback/simple positioning helper
# useful if something only wants to move the player without full setup
func set_grid_position(gx: int, gy: int, world_pos: Vector2) -> void:
	grid_x = gx
	grid_y = gy
	position = world_pos


# === player visuals ===
# rebuilds the debug marker + shadow from scratch
# later this could become sprites/animations/textures instead
func _rebuild_visuals() -> void:
	for child in get_children():
		child.queue_free()

	var shadow := Polygon2D.new()
	shadow.name = "Shadow"
	shadow.polygon = PackedVector2Array([
		Vector2(0, -6),
		Vector2(12, 0),
		Vector2(0, 6),
		Vector2(-12, 0)
	])
	shadow.color = player_shadow_color
	shadow.position = Vector2(0, 12)
	shadow.z_index = 99
	add_child(shadow)

	var marker := Polygon2D.new()
	marker.name = "Marker"
	marker.polygon = PackedVector2Array([
		Vector2(0, -20),
		Vector2(16, -4),
		Vector2(10, 16),
		Vector2(-10, 16),
		Vector2(-16, -4)
	])
	marker.color = player_color
	marker.z_index = 100
	add_child(marker)


# === world lookup ===
# finds the outer world/view node so the player can ask things like:
# "am i in bounds?" or "where is this tile in world space?"
func _get_world() -> Node:
	var world_root = get_parent()
	if world_root == null:
		return null
	return world_root.get_parent()


# === movement ===
# updates logical grid coords first, then tweens to the matching world position
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
			next_y -= 1
		"south":
			next_y += 1

	# don't move off the board like an idiot
	if world.has_method("is_in_bounds"):
		if not world.is_in_bounds(next_x, next_y):
			return

	grid_x = next_x
	grid_y = next_y

	if world.has_method("grid_to_world_position"):
		var target_pos: Vector2 = world.grid_to_world_position(grid_x, grid_y)
		var tween = create_tween()
		tween.tween_property(self, "position", target_pos, move_duration)


# === turning ===
# just changes facing for now
# later could also rotate sprite/marker visually if desired
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


# === object interaction stubs ===
# world behavior for objects is still placeholder-ish,
# so for now the robot just asks the world if it knows how to handle it
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
