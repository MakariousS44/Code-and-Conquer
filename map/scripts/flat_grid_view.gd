# flat_grid_view.gd
# To whom it may concern: This script draws a flat top-down 2D version of the level.
# Think of it like a map view — grid squares, walls as lines, robot as a colored arrow.
# It reads live state from the map_view instance (level data, object data, player position)
# so it always reflects what's actually happening in the game without needing its own copy.
# Toggle it on/off from the workstation top bar with the "2D View" button.

# Used by: workstation.gd (spawned dynamically into game_subviewport alongside the iso scene)
# Relies on: map_view.gd instance (for level_data, object_data, world_x_size, world_y_size)

extends Node2D

const CELL_SIZE       := 64.0
const WALL_WIDTH      := 7.0

const BG_COLOR        := Color(0.10, 0.11, 0.14, 1)
const FLOOR_COLOR     := Color(0.17, 0.19, 0.23)
const FLOOR_ALT_COLOR := Color(0.15, 0.17, 0.21)
const GOAL_COLOR      := Color(0.964, 0.548, 0.0, 1.0)
const GOAL_MARKER     := Color(1.0, 1.0, 1.0, 1.0)
const WALL_COLOR      := Color(0x8bffffff)
const GRID_LINE_COLOR := Color(0.544, 1.387, 1.479, 1.0)
const PLAYER_COLOR    := Color(0.636, 0.0, 0.822, 1.0)
const PLAYER_RIM      := Color(0.636, 0.0, 0.822, 1.0)
const TRAIL_COLOR     := Color(0.78, 0.25, 0.95, 0.72)
const TRAIL_WIDTH     := 3.0
const TRAIL_OFFSET    := CELL_SIZE * 0.18

const OBJECT_COLORS := {
	"apple":  Color(0.95, 0.28, 0.28),
	"banana": Color(1.00, 0.88, 0.18),
	"carrot": Color(1.00, 0.52, 0.08),
	"star":   Color(0.95, 1.00, 0.55),
	"token":  Color(0.28, 0.82, 1.00),
}

const DEPOSIT_EMPTY_COLOR := Color(0.88, 0.65, 0.15, 0.85)
const DEPOSIT_FULL_COLOR  := Color(0.28, 0.90, 0.45, 1.0)

var _map_ref: Node    = null
var _player_ref: Node = null
var _cols: int        = 0
var _rows: int        = 0
var _camera: Camera2D = null

var _trail: Array[Vector2] = []
var _trail_gx: int    = -1
var _trail_gy: int    = -1
var _trail_facing: String = ""


func _ready() -> void:
	_camera = Camera2D.new()
	_camera.enabled = false
	add_child(_camera)


func setup(map_instance: Node, player: Node) -> void:
	_map_ref    = map_instance
	_player_ref = player
	_cols       = map_instance.world_x_size
	_rows       = map_instance.world_y_size
	_trail.clear()
	_trail_gx = -1
	_trail_gy = -1
	_trail_facing = ""
	if player != null:
		_record_trail(player.grid_x, player.grid_y, player.facing)
	_fit_camera()
	queue_redraw()


func _right_foot_offset(facing: String) -> Vector2:
	match facing:
		"north": return Vector2( TRAIL_OFFSET,  0)
		"east":  return Vector2( 0,  TRAIL_OFFSET)
		"south": return Vector2(-TRAIL_OFFSET,  0)
		"west":  return Vector2( 0, -TRAIL_OFFSET)
	return Vector2.ZERO


func _record_trail(gx: int, gy: int, facing: String) -> void:
	var center := _cell_rect(gx, gy).get_center()
	var from_off := _right_foot_offset(_trail_facing)
	var to_off   := _right_foot_offset(facing)

	# Turned in place — add a single corner point for a sharp right-angle elbow
	if gx == _trail_gx and gy == _trail_gy and _trail_facing != "" and _trail_facing != facing:
		_trail.append(center + from_off + to_off)

	_trail.append(center + to_off)
	_trail_gx     = gx
	_trail_gy     = gy
	_trail_facing = facing


## Rebuild the trail from a list of {gx, gy, facing} entries (oldest first).
## Used by step-back so the trail shows only the path up to the current state,
## with later segments trimmed off.
func rebuild_trail(positions: Array) -> void:
	_trail.clear()
	_trail_gx = -1
	_trail_gy = -1
	_trail_facing = ""
	for p in positions:
		_record_trail(int(p.gx), int(p.gy), String(p.facing))
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
	var zoom: float = minf(vp_size.x / (grid_w + CELL_SIZE * 3.0), vp_size.y / (grid_h + CELL_SIZE * 3.0)) * 0.95
	_camera.zoom = Vector2(zoom, zoom)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _camera == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_camera.zoom = _camera.zoom * 1.12
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_camera.zoom = Vector2(maxf(_camera.zoom.x * 0.89, 0.05), maxf(_camera.zoom.y * 0.89, 0.05))


func _process(_delta: float) -> void:
	if _player_ref != null:
		var gx: int        = _player_ref.grid_x
		var gy: int        = _player_ref.grid_y
		var facing: String = _player_ref.facing
		if gx != _trail_gx or gy != _trail_gy or facing != _trail_facing:
			_record_trail(gx, gy, facing)
	if visible:
		queue_redraw()


func _draw() -> void:
	if _map_ref == null or _cols == 0 or _rows == 0:
		return
	_draw_background()
	_draw_floor()
	_draw_goal()
	_draw_grid_lines()
	_draw_walls()
	_draw_border()
	_draw_deposits()
	_draw_objects()
	_draw_trail()
	_draw_player()
	_draw_compass()


# cell (gx, gy) in JSON coords → pixel rect
# JSON: gx=1..cols left→right, gy=1..rows bottom→top
# Screen: y increases downward, so we flip gy
func _cell_rect(gx: int, gy: int) -> Rect2:
	return Rect2(
		Vector2((gx - 1) * CELL_SIZE, (_rows - gy) * CELL_SIZE),
		Vector2(CELL_SIZE, CELL_SIZE)
	)


func _draw_background() -> void:
	# flood the entire canvas so nothing bleeds through around the grid
	draw_rect(Rect2(-10000, -10000, 20000, 20000), BG_COLOR)


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
		var r := _cell_rect(p.x, p.y)
		draw_rect(r, GOAL_COLOR)
		# small diamond marker in the center
		var c := r.get_center()
		var d := CELL_SIZE * 0.22
		draw_polygon(
			[c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)],
			[GOAL_MARKER, GOAL_MARKER, GOAL_MARKER, GOAL_MARKER]
		)


func _draw_grid_lines() -> void:
	for gx in range(1, _cols + 1):
		for gy in range(1, _rows + 1):
			draw_rect(_cell_rect(gx, gy), GRID_LINE_COLOR, false, -0.5)


func _draw_border() -> void:
	var w := _cols * CELL_SIZE
	var h := _rows * CELL_SIZE
	var hw := WALL_WIDTH / 2.0
	draw_rect(Rect2(-hw,      -hw,      w + WALL_WIDTH, WALL_WIDTH), WALL_COLOR)  # top
	draw_rect(Rect2(-hw,      h - hw,   w + WALL_WIDTH, WALL_WIDTH), WALL_COLOR)  # bottom
	draw_rect(Rect2(-hw,      -hw,      WALL_WIDTH, h + WALL_WIDTH), WALL_COLOR)  # left
	draw_rect(Rect2(w - hw,   -hw,      WALL_WIDTH, h + WALL_WIDTH), WALL_COLOR)  # right


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
	var r  := _cell_rect(gx, gy)
	var hw := WALL_WIDTH / 2.0
	# extend each rect by hw on both ends so adjacent walls share an overlapping corner square
	match dir:
		"north":
			draw_rect(Rect2(r.position.x - hw, r.position.y - hw, CELL_SIZE + WALL_WIDTH, WALL_WIDTH), WALL_COLOR)
		"east":
			draw_rect(Rect2(r.position.x + CELL_SIZE - hw, r.position.y - hw, WALL_WIDTH, CELL_SIZE + WALL_WIDTH), WALL_COLOR)
		"south":
			draw_rect(Rect2(r.position.x - hw, r.position.y + CELL_SIZE - hw, CELL_SIZE + WALL_WIDTH, WALL_WIDTH), WALL_COLOR)
		"west":
			draw_rect(Rect2(r.position.x - hw, r.position.y - hw, WALL_WIDTH, CELL_SIZE + WALL_WIDTH), WALL_COLOR)


func _draw_trail() -> void:
	if _trail.size() < 2:
		return
	# Start dot
	draw_circle(_trail[0], TRAIL_WIDTH * 1.2, TRAIL_COLOR)
	for i in range(1, _trail.size()):
		draw_line(_trail[i - 1], _trail[i], TRAIL_COLOR, TRAIL_WIDTH, true)


func _draw_player() -> void:
	if _player_ref == null:
		return
	var gx: int        = _player_ref.grid_x
	var gy: int        = _player_ref.grid_y
	var facing: String = _player_ref.facing
	var r      := _cell_rect(gx, gy)
	var center := r.get_center()
	var radius := CELL_SIZE * 0.36

	# outer rim glow
	draw_circle(center, radius + 3.0, PLAYER_RIM)
	# filled circle body
	draw_circle(center, radius, PLAYER_COLOR)

	# directional arrow
	var tip_d  := radius * 0.78
	var base_d := radius * 0.22
	var half_b := radius * 0.42
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
		[Color(1, 1, 1, 1.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 1.0)]
	)


func _draw_compass() -> void:
	var font  := ThemeDB.fallback_font
	var fs    := int(CELL_SIZE * 0.30)
	var col   := Color(0.28, 0.78, 0.92, 0.85)
	var gw    := _cols * CELL_SIZE
	var gh    := _rows * CELL_SIZE
	var pad   := CELL_SIZE * 0.35
	# N above grid center
	draw_string(font, Vector2(gw * 0.5 - fs * 0.3, -pad * 0.3), "N",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# S below grid center
	draw_string(font, Vector2(gw * 0.5 - fs * 0.3, gh + pad + fs * 0.5), "S",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# E right of grid center
	draw_string(font, Vector2(gw + pad * 0.4, gh * 0.5 + fs * 0.4), "E",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# W left of grid center
	draw_string(font, Vector2(-pad - fs * 0.6, gh * 0.5 + fs * 0.4), "W",
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _draw_deposits() -> void:
	if _map_ref == null:
		return
	if not _map_ref.level_data.has("goal"):
		return
	var goal = _map_ref.level_data["goal"]
	if not goal.has("objects"):
		return
	var goal_objs: Dictionary = goal["objects"]
	for key in goal_objs:
		var parts = key.split(",")
		if parts.size() != 2:
			continue
		var gx := int(parts[0])
		var gy := int(parts[1])
		var obj_dict = goal_objs[key]
		if not (obj_dict is Dictionary) or obj_dict.is_empty():
			continue
		var obj_name: String = ""
		var expected: int = 0
		for k in obj_dict:
			obj_name = str(k)
			expected = int(obj_dict[k])
			break
		var actual := 0
		if _map_ref.object_data.has(key):
			var tile_objs = _map_ref.object_data[key]
			if tile_objs is Dictionary and tile_objs.has(obj_name):
				actual = int(tile_objs[obj_name])
		var filled  := actual >= expected
		var obj_col := OBJECT_COLORS.get(obj_name, Color(1, 1, 1)) as Color
		var r       := _cell_rect(gx, gy)
		var c       := r.get_center()
		var hw      := CELL_SIZE * 0.30
		var box_col := DEPOSIT_FULL_COLOR if filled else DEPOSIT_EMPTY_COLOR
		# square outline
		draw_rect(Rect2(c.x - hw, c.y - hw, hw * 2.0, hw * 2.0), box_col, false, 2.5)
		# small circle: bright object color when empty, dulled when filled
		var circle_col := Color(obj_col, 0.28) if filled else Color(obj_col, 0.85)
		draw_circle(c, CELL_SIZE * 0.22, circle_col)
		# count inside the circle when objects have been deposited
		if actual > 0:
			var font      := ThemeDB.fallback_font
			var font_size := int(CELL_SIZE * 0.24)
			draw_string(font, c + Vector2(-font_size * 0.3, font_size * 0.38),
				str(actual), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.95))


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

		# deposit tiles render their own object count inside the box
		var _goal_objs: Dictionary = {}
		if _map_ref.level_data.has("goal") and _map_ref.level_data["goal"].has("objects"):
			_goal_objs = _map_ref.level_data["goal"]["objects"]
		if _goal_objs.has(key):
			continue

		var r := _cell_rect(gx, gy)
		var color := Color(1, 1, 1)
		var total := 0
		for obj_name in tile_objs:
			color  = OBJECT_COLORS.get(str(obj_name), Color(1, 1, 1))
			total += int(tile_objs[obj_name])

		draw_circle(r.get_center(), CELL_SIZE * 0.26, color)

		var font      := ThemeDB.fallback_font
		var font_size := int(CELL_SIZE * 0.24)
		var label_pos := r.get_center() + Vector2(-font_size * 0.3, font_size * 0.38)
		draw_string(font, label_pos, str(total), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.9))
