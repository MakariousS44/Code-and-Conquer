extends Node2D

signal level_complete


# === visual config ===
@export var tile_width: int = 64
@export var tile_height: int = 32

@export var use_tilesheet_floor: bool = true
@export var use_tilesheet_walls: bool = true

@export var floor_texture: Texture2D = preload("res://assets/tilesheets/ground.png")
@export var floor_tile_pixel_size: Vector2i = Vector2i(256, 128)
@export var floor_primary_atlas: Vector2i = Vector2i(0, 7)
@export var floor_alt_atlas: Vector2i = Vector2i(1, 7)
@export var floor_use_checker_alt: bool = true
@export var floor_use_marked_tiles: bool = true
@export var floor_marked_atlas: Vector2i = Vector2i(3, 7)
@export var floor_goal_atlas: Vector2i = Vector2i(2, 7)
@export var floor_goal_color: Color = Color(0.95, 0.80, 0.20, 1)
@export var floor_bottom_offset: float = 0.0

@export var wall_texture: Texture2D = preload("res://assets/tilesheets/walls.png")
@export var wall_tile_pixel_size: Vector2i = Vector2i(256, 512)
@export var wall_north_atlas: Vector2i = Vector2i(5, 1)
@export var wall_east_atlas: Vector2i = Vector2i(7, 1)
@export var wall_south_atlas: Vector2i = Vector2i(5, 1)
@export var wall_west_atlas: Vector2i = Vector2i(7, 1)
@export var wall_bottom_offset: float = 0.0

@export var use_block_wall_png: bool = true
@export var wall_block_texture: Texture2D = preload("res://assets/textures/kenney_isometric-miniature-prototype/Isometric/block_N.png")
@export var wall_block_scale: Vector2 = Vector2(0.25, 0.25)
@export var wall_block_offset: Vector2 = Vector2(0, -26)

@export var floor_color: Color = Color("6d8f58")
@export var floor_color_alt: Color = Color("769862")
@export var grid_color: Color = Color("d0d5c8")
@export var show_grid_overlay: bool = true
@export var wall_color: Color = Color("f5ead7")
@export var board_shadow_color: Color = Color(0, 0, 0, 0.14)


# === scene references ===
@onready var world_root: Node2D = $WorldRoot
@onready var floor_node: Node2D = $WorldRoot/Floor
@onready var grid_node: Node2D = $WorldRoot/Grid
@onready var walls_node: Node2D = $WorldRoot/Walls
@onready var objects_node: Node2D = $WorldRoot/Objects
@onready var player: Node2D = $WorldRoot/Player
@onready var camera: Camera2D = $Camera2D


# === loaded level state ===
var level_data: LevelData = null
var rows: int = 0
var cols: int = 0
var wall_cells: Dictionary = {}
var goal_cells: Dictionary = {}


func _ready() -> void:
	camera.enabled = true
	camera.make_current()


func build_level(data: LevelData) -> void:
	if data == null:
		push_error("build_level called with null LevelData")
		return

	level_data = data
	rows = data.rows
	cols = data.cols

	_clear_children(floor_node)
	_clear_children(grid_node)
	_clear_children(walls_node)
	_clear_children(objects_node)
	wall_cells.clear()
	goal_cells.clear()
	_build_goal_cells()

	floor_node.z_index = 0
	grid_node.z_index = 1
	walls_node.z_index = 2
	objects_node.z_index = 3
	player.z_index = 10

	_build_board_shadow()
	_build_floor()
	if show_grid_overlay:
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
	if use_tilesheet_floor and floor_texture != null:
		_build_floor_tiles()
		return

	_build_floor_legacy()


func _build_goal_cells() -> void:
	if level_data == null or level_data.goal == null:
		return

	var goal: GoalData = level_data.goal

	for pos in goal.possible_final_positions:
		goal_cells["%d,%d" % [pos.x, pos.y]] = true

	if goal.position.x >= 1 and goal.position.y >= 1:
		goal_cells["%d,%d" % [goal.position.x, goal.position.y]] = true


func _is_goal_tile(gx: int, gy: int) -> bool:
	return goal_cells.has("%d,%d" % [gx, gy])


func _build_floor_tiles() -> void:
	var scale_x := float(tile_width) / float(floor_tile_pixel_size.x)
	var scale_y := float(tile_height) / float(floor_tile_pixel_size.y)

	for gx in range(1, cols + 1):
		for gy in range(1, rows + 1):
			var atlas := floor_primary_atlas

			if _is_goal_tile(gx, gy):
				_build_goal_tile_visual(gx, gy)
				continue
			elif floor_use_marked_tiles and _is_marked_tile(gx, gy):
				atlas = floor_marked_atlas
			elif floor_use_checker_alt and (gx + gy) % 2 != 0:
				atlas = floor_alt_atlas

			var sprite := Sprite2D.new()
			sprite.texture = floor_texture
			sprite.region_enabled = true
			sprite.region_rect = Rect2(
				Vector2(atlas.x * floor_tile_pixel_size.x, atlas.y * floor_tile_pixel_size.y),
				Vector2(floor_tile_pixel_size.x, floor_tile_pixel_size.y)
			)
			sprite.centered = true
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.scale = Vector2(scale_x, scale_y)
			sprite.position = _cell_center(gx, gy) + Vector2(0, floor_bottom_offset)

			floor_node.add_child(sprite)


func _build_goal_tile_visual(gx: int, gy: int) -> void:
	var scale_x := float(tile_width) / float(floor_tile_pixel_size.x)
	var scale_y := float(tile_height) / float(floor_tile_pixel_size.y)

	var sprite := Sprite2D.new()
	sprite.texture = floor_texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		Vector2(floor_primary_atlas.x * floor_tile_pixel_size.x, floor_primary_atlas.y * floor_tile_pixel_size.y),
		Vector2(floor_tile_pixel_size.x, floor_tile_pixel_size.y)
	)
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(scale_x, scale_y)
	sprite.position = _cell_center(gx, gy) + Vector2(0, floor_bottom_offset)
	floor_node.add_child(sprite)

	var overlay := Polygon2D.new()
	overlay.polygon = PackedVector2Array([
		Vector2(0, -tile_height / 2.0),
		Vector2(tile_width / 2.0, 0),
		Vector2(0, tile_height / 2.0),
		Vector2(-tile_width / 2.0, 0)
	])
	overlay.color = floor_goal_color
	overlay.position = _cell_center(gx, gy) + Vector2(0, floor_bottom_offset)
	overlay.z_index = 1
	floor_node.add_child(overlay)


func _is_marked_tile(gx: int, gy: int) -> bool:
	if level_data == null:
		return false

	for tile in level_data.marked_tiles:
		if tile is MarkedTileData and tile.x == gx and tile.y == gy:
			return true

	return false


func _build_floor_legacy() -> void:
	for gx in range(1, cols + 1):
		for gy in range(1, rows + 1):
			var tile := Polygon2D.new()

			tile.polygon = PackedVector2Array([
				Vector2(0, -tile_height / 2.0),
				Vector2(tile_width / 2.0, 0),
				Vector2(0, tile_height / 2.0),
				Vector2(-tile_width / 2.0, 0)
			])

			tile.color = floor_color if (gx + gy) % 2 == 0 else floor_color_alt
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
	if level_data == null or level_data.player_spawn == null:
		return

	var spawn: PlayerSpawnData = level_data.player_spawn
	var gx: int = spawn.x
	var gy: int = spawn.y
	var world_pos := _cell_center(gx, gy)

	if player.has_method("initialize_from_level"):
		player.initialize_from_level(
			{
				"x": spawn.x,
				"y": spawn.y,
				"direction": spawn.facing
			},
			world_pos
		)


func _build_walls() -> void:
	if level_data == null:
		return

	if use_block_wall_png and wall_block_texture != null:
		_build_walls_block_cells()
		return

	for wall_data in level_data.wall_cells:
		if not (wall_data is WallCellData):
			continue

		var gx: int = wall_data.x
		var gy: int = wall_data.y
		wall_cells[_cell_key(gx, gy)] = true

		for dir in wall_data.directions:
			_add_wall_segment(gx, gy, str(dir).to_lower())


func _build_walls_block_cells() -> void:
	if level_data == null:
		return

	for wall_data in level_data.wall_cells:
		if not (wall_data is WallCellData):
			continue

		var gx : int = wall_data.x
		var gy : int = wall_data.y
		var k := _cell_key(gx, gy)

		if wall_cells.has(k):
			continue

		wall_cells[k] = true

		var sprite := Sprite2D.new()
		sprite.texture = wall_block_texture
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = wall_block_scale
		sprite.position = _cell_center(gx, gy) + wall_block_offset

		walls_node.add_child(sprite)


func _add_wall_segment(gx: int, gy: int, dir: String) -> void:
	if use_tilesheet_walls and wall_texture != null:
		_add_wall_segment_tiles(gx, gy, dir)
		return

	_add_wall_segment_legacy(gx, gy, dir)


func _add_wall_segment_tiles(gx: int, gy: int, dir: String) -> void:
	var c := _cell_center(gx, gy)

	var top := c + Vector2(0, -tile_height / 2.0)
	var right := c + Vector2(tile_width / 2.0, 0)
	var bottom := c + Vector2(0, tile_height / 2.0)
	var left := c + Vector2(-tile_width / 2.0, 0)

	var start := Vector2.ZERO
	var end := Vector2.ZERO
	var atlas := wall_north_atlas

	match dir:
		"north":
			start = top
			end = right
			atlas = wall_north_atlas
		"east":
			start = right
			end = bottom
			atlas = wall_east_atlas
		"south":
			start = bottom
			end = left
			atlas = wall_south_atlas
		"west":
			start = left
			end = top
			atlas = wall_west_atlas
		_:
			return

	var anchor := (start + end) * 0.5

	var scale_x := float(tile_width) / float(wall_tile_pixel_size.x)
	var scale_y := scale_x
	var scaled_wall_height := float(wall_tile_pixel_size.y) * scale_y

	var sprite := Sprite2D.new()
	sprite.texture = wall_texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(
		Vector2(atlas.x * wall_tile_pixel_size.x, atlas.y * wall_tile_pixel_size.y),
		Vector2(wall_tile_pixel_size.x, wall_tile_pixel_size.y)
	)
	sprite.centered = true
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(scale_x, scale_y)
	sprite.position = anchor + Vector2(0, -scaled_wall_height * 0.5 + wall_bottom_offset)

	walls_node.add_child(sprite)


func _add_wall_segment_legacy(gx: int, gy: int, dir: String) -> void:
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
	var fit_zoom = min(zoom_x, zoom_y) * 0.85

	camera.zoom = Vector2(fit_zoom, fit_zoom)


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


func is_in_bounds(gx: int, gy: int) -> bool:
	return gx >= 1 and gx <= cols and gy >= 1 and gy <= rows


func is_move_blocked(gx: int, gy: int, dir: String) -> bool:
	if not is_in_bounds(gx, gy):
		return true

	var nx := gx
	var ny := gy
	match dir:
		"east":
			nx += 1
		"west":
			nx -= 1
		"north":
			ny -= 1
		"south":
			ny += 1
		_:
			return true

	if not is_in_bounds(nx, ny):
		return true

	if _is_wall_cell(nx, ny):
		return true

	if _cell_has_wall_edge(gx, gy, dir):
		return true

	var opposite := ""
	match dir:
		"east":
			opposite = "west"
		"west":
			opposite = "east"
		"north":
			opposite = "south"
		"south":
			opposite = "north"

	return _cell_has_wall_edge(nx, ny, opposite)


func _is_wall_cell(gx: int, gy: int) -> bool:
	var k := _cell_key(gx, gy)
	if wall_cells.has(k):
		return true

	if level_data == null:
		return false

	for wall_data in level_data.wall_cells:
		if wall_data is WallCellData and wall_data.x == gx and wall_data.y == gy:
			return true

	return false


func _cell_key(gx: int, gy: int) -> String:
	return "%d,%d" % [gx, gy]


func _cell_has_wall_edge(gx: int, gy: int, dir: String) -> bool:
	if level_data == null:
		return false

	for wall_data in level_data.wall_cells:
		if not (wall_data is WallCellData):
			continue
		if wall_data.x != gx or wall_data.y != gy:
			continue

		for d in wall_data.directions:
			if str(d).to_lower() == dir:
				return true

	return false


func check_win_condition(gx: int, gy: int) -> void:
	if level_data == null or level_data.goal == null:
		return

	var goal: GoalData = level_data.goal

	for pos in goal.possible_final_positions:
		if pos.x == gx and pos.y == gy:
			level_complete.emit()
			return

	if goal.position.x == gx and goal.position.y == gy:
		level_complete.emit()
