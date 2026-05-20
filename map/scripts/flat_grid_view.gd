# flat_grid_view.gd
# To whom it may concern: This script draws a flat top-down 2D version of the level.
# Think of it like a map view — grid squares, walls as lines, robot as a colored arrow.
# It reads live state from the map_view instance (level data, object data, player position)
# so it always reflects what's actually happening in the game without needing its own copy.
# Toggle it on/off from the workstation top bar with the "2D View" button.

# Used by: workstation.gd (spawned dynamically into game_subviewport alongside the iso scene)
# Relies on: map_view.gd instance (for level_data, object_data, world_x_size, world_y_size)

extends Node2D

const CELL_SIZE       := 60.0
const WALL_WIDTH      := 4.5

const FLOOR_COLOR     := Color(0.22, 0.24, 0.29)
const FLOOR_ALT_COLOR := Color(0.20, 0.22, 0.27)
const GOAL_COLOR      := Color(0.18, 0.58, 0.35, 0.85)
const WALL_COLOR      := Color(0.85, 0.70, 0.30)
const GRID_LINE_COLOR := Color(0.32, 0.34, 0.40)
const PLAYER_COLOR    := Color(0.30, 0.65, 1.00)

const OBJECT_COLORS := {
	"apple":  Color(1.00, 0.25, 0.25),
	"banana": Color(1.00, 0.90, 0.20),
	"carrot": Color(1.00, 0.55, 0.10),
	"star":   Color(0.92, 1.00, 0.70),
	"token":  Color(0.30, 0.80, 1.00),
}

var _map_ref: Node    = null
var _player_ref: Node = null
var _cols: int        = 0
var _rows: int        = 0
var _camera: Camera2D = null


func _ready() -> void:
	_camera = Camera2D.new()
	_camera.enabled = false
	add_child(_camera)


func setup(map_instance: Node, player: Node) -> void:
	_map_ref    = map_instance
	_player_ref = player
	_cols       = map_instance.world_x_size
	_rows       = map_instance.world_y_size
	_fit_camera()
	queue_redraw()


func activate() -> void:
	_camera.enabled = true
	_camera.make_current()


func deactivate() -> void:
	_camera.enabled = false


func _fit_camera() -> void:
	if _camera == null or _cols == 0 or _rows == 0:
		return
	var grid_w := _cols * CELL_SIZE
	var grid_h := _rows * CELL_SIZE
	_camera.position = Vector2(grid_w / 2.0, grid_h / 2.0)
	var vp_size := get_viewport().get_visible_rect().size
	var zoom: float = minf(vp_size.x / (grid_w + CELL_SIZE * 2.5), vp_size.y / (grid_h + CELL_SIZE * 2.5)) * 0.92
	_camera.zoom = Vector2(zoom, zoom)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if _map_ref == null or _cols == 0 or _rows == 0:
		return
	_draw_floor()
	_draw_goal()
	_draw_grid_lines()
	_draw_walls()
	_draw_border()
	_draw_objects()
	_draw_player()


# cell (gx, gy) in JSON coords → pixel rect
# JSON: gx=1..cols left→right, gy=1..rows bottom→top
# Screen: y increases downward, so we flip gy
func _cell_rect(gx: int, gy: int) -> Rect2:
	return Rect2(
		Vector2((gx - 1) * CELL_SIZE, (_rows - gy) * CELL_SIZE),
		Vector2(CELL_SIZE, CELL_SIZE)
	)


func _draw_floor() -> void:
	for gx in range(1, _cols + 1):
		for gy in range(1, _rows + 1):
			var color := FLOOR_COLOR if (gx + gy) % 2 == 0 else FLOOR_ALT_COLOR
			draw_rect(_cell_rect(gx, gy), color)


func _draw_goal() -> void:
	if not _map_ref.level_data.has("goal"):
		return
	var goal = _map_ref.level_data["goal"]
	var positions: Array = []
	if goal.has("possible_final_positions"):
		for pos in goal["possible_final_positions"]:
			if typeof(pos) == TYPE_ARRAY and pos.size() >= 2:
				positions.append(Vector2i(int(pos[0]), int(pos[1])))
	if goal.has("position") and typeof(goal["position"]) == TYPE_DICTIONARY:
		var pos = goal["position"]
		positions.append(Vector2i(int(pos.get("x", -1)), int(pos.get("y", -1))))
	for p in positions:
		draw_rect(_cell_rect(p.x, p.y), GOAL_COLOR)


func _draw_grid_lines() -> void:
	for gx in range(1, _cols + 1):
		for gy in range(1, _rows + 1):
			draw_rect(_cell_rect(gx, gy), GRID_LINE_COLOR, false, 1.0)


func _draw_border() -> void:
	draw_rect(Rect2(0, 0, _cols * CELL_SIZE, _rows * CELL_SIZE), WALL_COLOR, false, WALL_WIDTH)


func _draw_walls() -> void:
	if not _map_ref.level_data.has("walls"):
		return
	for key in _map_ref.level_data["walls"]:
		var parts = key.split(",")
		if parts.size() != 2:
			continue
		var gx := int(parts[0])
		var gy := int(parts[1])
		for d in _map_ref.level_data["walls"][key]:
			_draw_wall_segment(gx, gy, str(d).to_lower())


func _draw_wall_segment(gx: int, gy: int, dir: String) -> void:
	var r := _cell_rect(gx, gy)
	match dir:
		"north":
			draw_line(r.position, r.position + Vector2(CELL_SIZE, 0), WALL_COLOR, WALL_WIDTH, true)
		"east":
			var top_right := r.position + Vector2(CELL_SIZE, 0)
			draw_line(top_right, top_right + Vector2(0, CELL_SIZE), WALL_COLOR, WALL_WIDTH, true)
		"south":
			draw_line(r.position + Vector2(0, CELL_SIZE), r.end, WALL_COLOR, WALL_WIDTH, true)
		"west":
			draw_line(r.position, r.position + Vector2(0, CELL_SIZE), WALL_COLOR, WALL_WIDTH, true)


func _draw_player() -> void:
	if _player_ref == null:
		return
	var gx: int     = _player_ref.grid_x
	var gy: int     = _player_ref.grid_y
	var facing: String = _player_ref.facing
	var r := _cell_rect(gx, gy)

	# filled square for the robot body
	var pad := CELL_SIZE * 0.15
	draw_rect(Rect2(r.position + Vector2(pad, pad), Vector2(CELL_SIZE - pad * 2.0, CELL_SIZE - pad * 2.0)), PLAYER_COLOR)

	# directional arrow on top
	var center  := r.get_center()
	var tip_d   := CELL_SIZE * 0.28
	var base_d  := CELL_SIZE * 0.08
	var half_b  := CELL_SIZE * 0.14
	var tip: Vector2
	var base_c: Vector2
	match facing:
		"north":
			tip    = center + Vector2(0, -tip_d)
			base_c = center + Vector2(0,  base_d)
		"south":
			tip    = center + Vector2(0,  tip_d)
			base_c = center + Vector2(0, -base_d)
		"east":
			tip    = center + Vector2( tip_d, 0)
			base_c = center + Vector2(-base_d, 0)
		"west":
			tip    = center + Vector2(-tip_d, 0)
			base_c = center + Vector2( base_d, 0)
		_:
			return
	var perp := (tip - base_c).rotated(PI / 2.0).normalized() * half_b
	draw_polygon(
		[tip, base_c + perp, base_c - perp],
		[Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.95)]
	)


func _draw_objects() -> void:
	if _map_ref == null:
		return
	for key in _map_ref.object_data:
		var parts = key.split(",")
		if parts.size() != 2:
			continue
		var gx := int(parts[0])
		var gy := int(parts[1])
		var tile_objs: Dictionary = _map_ref.object_data[key]
		if tile_objs.is_empty():
			continue

		var r := _cell_rect(gx, gy)
		var color := Color(1, 1, 1)
		var total := 0
		for obj_name in tile_objs:
			color  = OBJECT_COLORS.get(str(obj_name), Color(1, 1, 1))
			total += int(tile_objs[obj_name])

		# small colored square inside the cell
		var op := CELL_SIZE * 0.28
		draw_rect(Rect2(r.position + Vector2(op, op), Vector2(CELL_SIZE - op * 2.0, CELL_SIZE - op * 2.0)), color)

		# count label
		if total > 1:
			var font := ThemeDB.fallback_font
			var font_size := int(CELL_SIZE * 0.26)
			var label_pos := r.get_center() + Vector2(-font_size * 0.3, font_size * 0.38)
			draw_string(font, label_pos, str(total), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.9))
