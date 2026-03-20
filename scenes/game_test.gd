extends Node2D

@export var tile_width: int = 64
@export var tile_height: int = 32

@export var floor_color: Color = Color("6d8f58")
@export var floor_color_alt: Color = Color("769862")
@export var grid_color: Color = Color("d0d5c8")
@export var wall_color: Color = Color("f5ead7")
@export var player_color: Color = Color("7a4df3")
@export var player_shadow_color: Color = Color(0, 0, 0, 0.18)
@export var board_shadow_color: Color = Color(0, 0, 0, 0.14)

@onready var world_root: Node2D = $WorldRoot
@onready var floor_node: Node2D = $WorldRoot/Floor
@onready var grid_node: Node2D = $WorldRoot/Grid
@onready var walls_node: Node2D = $WorldRoot/Walls
@onready var objects_node: Node2D = $WorldRoot/Objects
@onready var player: Node2D = $WorldRoot/Player
@onready var camera: Camera2D = $Camera2D

var world_data: Dictionary = {}
var rows: int = 0
var cols: int = 0


func _ready() -> void:
	camera.enabled = true
	camera.make_current()


func load_world_data(data: Dictionary) -> void:
	world_data = data
	rows = data.get("rows", 10)
	cols = data.get("cols", 10)

	_clear_children(floor_node)
	_clear_children(grid_node)
	_clear_children(walls_node)
	_clear_children(objects_node)

	floor_node.z_index = 0
	grid_node.z_index = 1
	walls_node.z_index = 2
	objects_node.z_index = 3
	player.z_index = 10

	_build_board_shadow()
	_build_floor()
	_build_grid()
	_place_player()
	_build_walls()
	_center_camera()


func _build_board_shadow() -> void:
	var shadow := Polygon2D.new()

	var top := _cell_center(1, rows)
	var right := _cell_center(1, 1)
	var bottom := _cell_center(cols, 1)
	var left := _cell_center(cols, rows)

	shadow.polygon = PackedVector2Array([
		top + Vector2(0, 18),
		right + Vector2(0, 18),
		bottom + Vector2(0, 18),
		left + Vector2(0, 18)
	])
	shadow.color = board_shadow_color
	shadow.z_index = -1

	floor_node.add_child(shadow)


func _build_floor() -> void:
	for gx in range(1, cols + 1):
		for gy in range(1, rows + 1):
			var tile := Polygon2D.new()
			tile.polygon = PackedVector2Array([
				Vector2(0, -tile_height / 2.0),
				Vector2(tile_width / 2.0, 0),
				Vector2(0, tile_height / 2.0),
				Vector2(-tile_width / 2.0, 0)
			])

			if (gx + gy) % 2 == 0:
				tile.color = floor_color
			else:
				tile.color = floor_color_alt

			tile.position = _cell_center(gx, gy)
			floor_node.add_child(tile)


func _build_grid() -> void:
	for gx in range(1, cols + 1):
		for gy in range(1, rows + 1):
			var diamond := Line2D.new()
			diamond.width = 1.0
			diamond.default_color = grid_color

			var c := _cell_center(gx, gy)
			var top := c + Vector2(0, -tile_height / 2.0)
			var right := c + Vector2(tile_width / 2.0, 0)
			var bottom := c + Vector2(0, tile_height / 2.0)
			var left := c + Vector2(-tile_width / 2.0, 0)

			diamond.add_point(top)
			diamond.add_point(right)
			diamond.add_point(bottom)
			diamond.add_point(left)
			diamond.add_point(top)

			grid_node.add_child(diamond)


func _place_player() -> void:
	if not world_data.has("robots"):
		return

	var robots = world_data["robots"]
	if robots.is_empty():
		return

	var robot = robots[0]
	var gx: int = robot.get("x", 1)
	var gy: int = robot.get("y", 1)

	var world_pos = _cell_center(gx, gy)

	if player.has_method("set_grid_position"):
		player.set_grid_position(gx, gy, world_pos)
	else:
		player.position = world_pos

	for child in player.get_children():
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
	player.add_child(shadow)

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
	player.add_child(marker)


func _build_walls() -> void:
	if not world_data.has("walls"):
		return

	for key in world_data["walls"].keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2:
			continue

		var gx := int(parts[0])
		var gy := int(parts[1])
		var directions = world_data["walls"][key]

		for dir in directions:
			_add_wall_segment(gx, gy, dir)


func _add_wall_segment(gx: int, gy: int, dir: String) -> void:
	var c := _cell_center(gx, gy)

	var top := c + Vector2(0, -tile_height / 2.0)
	var right := c + Vector2(tile_width / 2.0, 0)
	var bottom := c + Vector2(0, tile_height / 2.0)
	var left := c + Vector2(-tile_width / 2.0, 0)

	var wall := Line2D.new()
	wall.width = 5.0
	wall.default_color = wall_color

	match dir:
		"north":
			wall.add_point(top)
			wall.add_point(right)
		"east":
			wall.add_point(right)
			wall.add_point(bottom)
		"south":
			wall.add_point(bottom)
			wall.add_point(left)
		"west":
			wall.add_point(left)
			wall.add_point(top)
		_:
			return

	walls_node.add_child(wall)


func _center_camera() -> void:
	camera.enabled = true
	camera.make_current()

	var top := _cell_center(1, rows)
	var bottom := _cell_center(cols, 1)
	var left := _cell_center(cols, rows)
	var right := _cell_center(1, 1)

	var min_x = min(top.x, bottom.x, left.x, right.x)
	var max_x = max(top.x, bottom.x, left.x, right.x)
	var min_y = min(top.y, bottom.y, left.y, right.y)
	var max_y = max(top.y, bottom.y, left.y, right.y)

	var world_width = max_x - min_x
	var world_height = max_y - min_y

	camera.position = Vector2(
		min_x + world_width / 2.0,
		min_y + world_height / 2.0
	)

	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		camera.zoom = Vector2.ONE
		return

	var zoom_x = viewport_size.x / world_width
	var zoom_y = viewport_size.y / world_height
	var fit_zoom = min(zoom_x, zoom_y)

	fit_zoom *= 0.75
	fit_zoom = min(fit_zoom, 1.0)

	camera.zoom = Vector2(1, 1)

	# Slight composition bias so the board feels a little less stiff.
	camera.position.x += world_width * 0.05
	camera.position.y -= world_height * 0.03


func _cell_center(gx: int, gy: int) -> Vector2:
	var grid_x := float(cols - gx)
	var grid_y := float(rows - gy)

	var iso_x := (grid_x - grid_y) * (tile_width / 2.0)
	var iso_y := (grid_x + grid_y) * (tile_height / 2.0)

	var offset_x := cols * tile_width * 0.5
	var offset_y := tile_height * 1.5

	return Vector2(iso_x + offset_x, iso_y + offset_y)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func grid_to_world_position(gx: int, gy: int) -> Vector2:
	return _cell_center(gx, gy)
