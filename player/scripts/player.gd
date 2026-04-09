extends Node2D

signal lose_triggered(reason: String)

# === player config ===
# movement timing + visual tuning
@export var use_animated_sprite: bool = true
@export var player_sprite_frames: SpriteFrames
@export var idle_animation_name: String = "idle"
@export var move_duration: float = 0.3
@export var use_sprite_visual: bool = true
@export var player_texture: Texture2D = preload("res://assets/textures/kenney_isometric-miniature-prototype/Characters/Human/Human_0_Idle0.png")
@export var sprite_scale: Vector2 = Vector2(0.45, 0.45)
@export var sprite_offset: Vector2 = Vector2(2, 4)
@export var rotate_sprite_with_facing: bool = false
@export var snap_sprite_to_pixels: bool = true
@export var auto_trim_player_region: bool = true
@export var trim_alpha_padding_px: int = 2
@export var show_player_shadow: bool = false

# optional orientation mapping for incoming JSON _orientation values
# default assumes 0=east, 1=north, 2=west, 3=south
@export var orientation_0_facing: String = "east"
@export var orientation_1_facing: String = "north"
@export var orientation_2_facing: String = "west"
@export var orientation_3_facing: String = "south"

# fallback debug marker colors (used when sprite mode is disabled)
@export var player_color: Color = Color("7a4df3")
@export var player_shadow_color: Color = Color(0, 0, 0, 0.18)

# === player state ===
# logical grid position + facing direction
var grid_x: int = 1
var grid_y: int = 1
var facing: String = "north"
var _trim_region_cache: Dictionary = {}
var _has_lost: bool = false


func _ready() -> void:
	# Ensure a visible body even before level data has been injected.
	if get_child_count() == 0:
		_rebuild_visuals()


# === level setup ===
# called when a level is loaded
# this file owns player state + player appearance, so setup happens here now
func initialize_from_level(robot_data: Dictionary, world_pos: Vector2) -> void:
	_has_lost = false
	grid_x = robot_data.get("x", 1)
	grid_y = robot_data.get("y", 1)
	facing = robot_data.get("direction", "north")
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

	if use_animated_sprite and player_sprite_frames != null:
		var anim := AnimatedSprite2D.new()
		anim.name = "Body"
		anim.sprite_frames = player_sprite_frames
		anim.animation = idle_animation_name
		anim.centered = true
		anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		anim.scale = sprite_scale
		anim.position = sprite_offset
		anim.z_index = 100
		add_child(anim)
		anim.play()

		_update_facing_visual()
		return

	if show_player_shadow:
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

	_update_facing_visual()


func _apply_trimmed_region(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return

	var texture_path := sprite.texture.resource_path
	if _trim_region_cache.has(texture_path):
		var cached: Rect2 = _trim_region_cache[texture_path]
		if cached.size.x > 0.0 and cached.size.y > 0.0:
			sprite.region_enabled = true
			sprite.region_rect = cached
		return

	var image: Image = sprite.texture.get_image()
	if image == null:
		return

	var min_x: int = image.get_width()
	var min_y: int = image.get_height()
	var max_x: int = -1
	var max_y: int = -1

	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				if x < min_x:
					min_x = x
				if y < min_y:
					min_y = y
				if x > max_x:
					max_x = x
				if y > max_y:
					max_y = y

	if max_x < 0 or max_y < 0:
		return

	var pad: int = int(max(trim_alpha_padding_px, 0))
	min_x = max(0, min_x - pad)
	min_y = max(0, min_y - pad)
	max_x = min(image.get_width() - 1, max_x + pad)
	max_y = min(image.get_height() - 1, max_y + pad)

	var rect: Rect2 = Rect2(
		Vector2(min_x, min_y),
		Vector2(max_x - min_x + 1, max_y - min_y + 1)
	)
	_trim_region_cache[texture_path] = rect

	sprite.region_enabled = true
	sprite.region_rect = rect


func _extract_initial_facing(robot_data: Dictionary) -> String:
	if robot_data.has("direction"):
		var d: String = str(robot_data["direction"]).to_lower()
		if d == "north" or d == "east" or d == "south" or d == "west":
			return d

	if robot_data.has("_orientation"):
		var o := int(robot_data.get("_orientation", 0)) % 4
		match o:
			0:
				return orientation_0_facing
			1:
				return orientation_1_facing
			2:
				return orientation_2_facing
			3:
				return orientation_3_facing

	return "north"


func _update_facing_visual() -> void:
	if not has_node("Body"):
		if has_node("Marker"):
			var marker: Node2D = get_node("Marker") as Node2D
			if marker != null:
				marker.rotation_degrees = _facing_angle_deg()
		return

	var body := get_node("Body") as Node2D
	if body == null:
		return

	if rotate_sprite_with_facing:
		body.rotation_degrees = _facing_angle_deg()


func _facing_angle_deg() -> float:
	match facing:
		"north":
			return -45.0
		"east":
			return 45.0
		"south":
			return 135.0
		"west":
			return -135.0
		_:
			return 0.0


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
			next_y += 1  
		"south":
			next_y -= 1  

	# lose if the player attempts to leave the playable floor
	if world.has_method("is_in_bounds"):
		if not world.is_in_bounds(next_x, next_y):
			_trigger_lose("You lose: attempted to move outside the floor.")
			return
			
	# lose on attempted move through a wall edge
	if world.has_method("is_move_blocked"):
		if world.is_move_blocked(grid_x, grid_y, facing):
			_trigger_lose("You lose: attempted to move through a wall.")
			return

	grid_x = next_x
	grid_y = next_y

	if world.has_method("grid_to_world_position"):
		var target_pos: Vector2 = world.grid_to_world_position(grid_x, grid_y)
		var tween = create_tween()
		tween.tween_property(self, "position", target_pos, move_duration)

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
		"north":
			facing = "west"
		"west":
			facing = "south"
		"south":
			facing = "east"

	_update_facing_visual()


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

	_update_facing_visual()


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
