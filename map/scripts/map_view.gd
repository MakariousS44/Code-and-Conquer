extends Node2D

# === visual config ===
# tweakables so we're not hardcoding mystery numbers all over the place
@export var tile_width: int = 64
@export var tile_height: int = 32

@export var use_tilesheet_floor: bool = true
@export var use_tilesheet_walls: bool = true

@export var floor_texture: Texture2D = preload("res://assets/tilesheets/ground.png")
@export var floor_tile_pixel_size: Vector2i = Vector2i(256, 128)
@export var floor_primary_atlas: Vector2i = Vector2i(0, 7)
@export var floor_alt_atlas: Vector2i = Vector2i(1, 7)
@export var floor_use_checker_alt: bool = true
@export var floor_use_json_tiles: bool = true
@export var floor_json_marked_atlas: Vector2i = Vector2i(3, 7)
@export var floor_bottom_offset: float = 0.0

@export var wall_texture: Texture2D = preload("res://assets/tilesheets/walls.png")
@export var wall_tile_pixel_size: Vector2i = Vector2i(256, 512)
@export var wall_north_atlas: Vector2i = Vector2i(5, 1)
@export var wall_east_atlas: Vector2i = Vector2i(7, 1)
@export var wall_south_atlas: Vector2i = Vector2i(5, 1)
@export var wall_west_atlas: Vector2i = Vector2i(7, 1)
@export var wall_bottom_offset: float = 0.0

# Optional wall mode: render one solid block sprite per wall cell.
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
# all the visual level layers live under WorldRoot
@onready var world_root: Node2D = $WorldRoot
@onready var floor_node: Node2D = $WorldRoot/Floor
@onready var grid_node: Node2D = $WorldRoot/Grid
@onready var walls_node: Node2D = $WorldRoot/Walls
@onready var objects_node: Node2D = $WorldRoot/Objects
@onready var player: Node2D = $WorldRoot/Player
@onready var camera: Camera2D = $Camera2D


# === loaded level state ===
# this is already-usable level data, not raw JSON
var level_data: Dictionary = {}
var rows: int = 0
var cols: int = 0
var wall_cells: Dictionary = {}


# === scene lifecycle ===
# runs when this scene is instantiated into the tree
# this scene owns the camera, so it configures it here
func _ready() -> void:
	camera.enabled = true
	camera.make_current()


# === main entry point ===
# outside code gives this scene a level definition dictionary
# this file then builds the full playable board from it
func build_level(data: Dictionary) -> void:
	level_data = data
	rows = data.get("rows", 10)
	cols = data.get("cols", 10)

	# wipe old visuals so we don't stack levels on top of each other
	_clear_children(floor_node)
	_clear_children(grid_node)
	_clear_children(walls_node)
	_clear_children(objects_node)
	wall_cells.clear()

	# enforce consistent draw order
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


# === board shadow ===
# purely visual polish so the board doesn't feel like it’s floating in void
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


# === floor tiles ===
# builds the base surface of the level using isometric diamonds
func _build_floor() -> void:
	if use_tilesheet_floor and floor_texture != null:
		_build_floor_tiles()
		return

	_build_floor_legacy()


func _build_floor_tiles() -> void:
	var scale_x := float(tile_width) / float(floor_tile_pixel_size.x)
	var scale_y := float(tile_height) / float(floor_tile_pixel_size.y)

	for gx in range(1, cols + 1):
		for gy in range(1, rows + 1):
			var atlas := floor_primary_atlas

			if floor_use_json_tiles and _is_json_marked_tile(gx, gy):
				atlas = floor_json_marked_atlas
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


func _is_json_marked_tile(gx: int, gy: int) -> bool:
	if not level_data.has("tiles"):
		return false

	if typeof(level_data["tiles"]) != TYPE_DICTIONARY:
		return false

	var key := "%d,%d" % [gx, gy]
	return level_data["tiles"].has(key)


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

			# alternating colors so the board doesn't look dead
			tile.color = floor_color if (gx + gy) % 2 == 0 else floor_color_alt
			tile.position = _cell_center(gx, gy)

			floor_node.add_child(tile)


# === grid overlay ===
# visual helper for readability and debugging (not gameplay logic)
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


# === player placement ===
# decides WHERE the player goes
# the player script decides how it behaves and looks
func _place_player() -> void:
	if not level_data.has("robots"):
		return

	var robots = level_data["robots"]
	if robots.is_empty():
		return

	var robot = robots[0]
	var gx: int = robot.get("x", 1)
	var gy: int = robot.get("y", 1)
	var world_pos := _cell_center(gx, gy)

	# pass this level_scene into the player so it can query bounds and positions cleanly
	if player.has_method("initialize_from_level"):
		player.initialize_from_level(robot, world_pos)


# === walls ===
# reads wall data and draws directional wall segments
func _build_walls() -> void:
	if not level_data.has("walls"):
		return

	if use_block_wall_png and wall_block_texture != null:
		_build_walls_block_cells()
		return

	for key in level_data["walls"].keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2:
			continue

		var gx := int(parts[0])
		var gy := int(parts[1])
		wall_cells[_cell_key(gx, gy)] = true
		var directions = level_data["walls"][key]

		for dir in directions:
			_add_wall_segment(gx, gy, dir)


func _build_walls_block_cells() -> void:
	for key in level_data["walls"].keys():
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 2:
			continue

		var gx := int(parts[0])
		var gy := int(parts[1])
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


# === camera framing ===
# centers and zooms the camera so the entire board fits on screen
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


# === coordinate system ===
# converts grid coordinates into isometric world positions
func _cell_center(gx: int, gy: int) -> Vector2:
	var grid_x := float(cols - gx)
	var grid_y := float(rows - gy)

	var iso_x := (grid_x - grid_y) * (tile_width / 2.0)
	var iso_y := (grid_x + grid_y) * (tile_height / 2.0)

	var offset_x := cols * tile_width * 0.5
	var offset_y := tile_height * 1.5

	return Vector2(iso_x + offset_x, iso_y + offset_y)


# === helpers ===
# removes all children from a node (used for rebuilding levels)
func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


# === public helpers ===
# these are used by runtime systems like the player

# converts grid coordinates into world space position
func grid_to_world_position(gx: int, gy: int) -> Vector2:
	return _cell_center(gx, gy)

# simple bounds check so the player doesn't walk off the map like a clown
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
			ny += 1
		"south":
			ny -= 1
		_:
			return true

	if not is_in_bounds(nx, ny):
		return true

	# Block-wall mode: entering a wall cell is always blocked.
	if _is_wall_cell(nx, ny):
		return true

	# Edge-wall mode fallback: blocked by wall edge on current cell.
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

	if not level_data.has("walls"):
		return false
	if typeof(level_data["walls"]) != TYPE_DICTIONARY:
		return false

	return level_data["walls"].has(k)


func _cell_key(gx: int, gy: int) -> String:
	return "%d,%d" % [gx, gy]


func _cell_has_wall_edge(gx: int, gy: int, dir: String) -> bool:
	if not level_data.has("walls"):
		return false

	if typeof(level_data["walls"]) != TYPE_DICTIONARY:
		return false

	var key := "%d,%d" % [gx, gy]
	if not level_data["walls"].has(key):
		return false

	var directions = level_data["walls"][key]
	if typeof(directions) != TYPE_ARRAY:
		return false

	for d in directions:
		if str(d).to_lower() == dir:
			return true

	return false
