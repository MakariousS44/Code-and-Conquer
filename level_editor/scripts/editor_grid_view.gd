class_name EditorGridView
extends Node2D

const CELL_SIZE := 48.0
const VOID_ICON = preload("res://assets/objects/void.png")
const MIN_ZOOM := 0.25
const MAX_ZOOM := 3.0
const ZOOM_STEP := 1.12
const PAN_STEP := 96.0
const SIDEBAR_WIDTH := 280.0

enum Tool {
	ROBOT,
	GOAL,
	WALL,
	EAST_WALL,
	OBJECT,
	ERASE,
	VOID
}



signal view_changed
signal objects_changed

var active_tool := Tool.ROBOT
var suppress_tool_application := false

var document: LevelDocument
var show_coordinates := false
var object_type := "token"
var object_count := 1
var zoom_level := 1.0
var zoom_initialized := false
var pan_offset := Vector2.ZERO
var _panning := false
var _left_button_down := false
var _left_button_panned := false
var _click_start_tile := Vector2i(-1, -1)
const ROBOT_ICON = preload("res://assets/objects/robot.png")
const GOAL_ICON = preload("res://assets/objects/goal.png")
const APPLE_ICON = preload("res://assets/objects/apple.png")
const BANANA_ICON = preload("res://assets/objects/banana.png")
const CARROT_ICON = preload("res://assets/objects/carrot.png")
const STAR_ICON = preload("res://assets/objects/star.png")
const TOKEN_ICON = preload("res://assets/objects/token.png")

const OBJECT_ICONS := {
	"apple": APPLE_ICON,
	"banana": BANANA_ICON,
	"carrot": CARROT_ICON,
	"star": STAR_ICON,
	"token": TOKEN_ICON
}


func _draw_icon(texture: Texture2D, center: Vector2, icon_size := 32.0) -> void:
	var rect := Rect2(
		center - Vector2.ONE * icon_size * 0.5,
		Vector2.ONE * icon_size
	)
	draw_texture_rect(texture, rect, false)


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		show_coordinates = bool(config.get_value("learning", "show_grid_coordinates", false))


func set_document(value: LevelDocument) -> void:
	document = value
	queue_redraw()

func _cell_center(gx: int, gy: int, rows: int) -> Vector2:
	return Vector2(
		(gx - 0.5) * CELL_SIZE,
		(rows - gy + 0.5) * CELL_SIZE
	)

func _draw() -> void:
	if document == null:
		return

	var cols := int(document.data["cols"])
	var rows := int(document.data["rows"])

	# Draw all grid squares first.
	for x in range(cols):
		for y in range(rows):
			var rect := Rect2(
				Vector2(x * CELL_SIZE, (rows - 1 - y) * CELL_SIZE),
				Vector2(CELL_SIZE, CELL_SIZE)
			)

			var tile_color := Color("#29313d")
			if (x + y) % 2 != 0:
				tile_color = Color("#222a35")

			draw_rect(rect, tile_color)
			if preload("res://map/scripts/void_tiles.gd").contains(document.data, x + 1, y + 1):
				draw_rect(rect, Color("0b1020"))
				draw_texture_rect(VOID_ICON, rect.grow(-8.0), false)
			draw_rect(rect, Color("#668099"), false, 1.0)
			if show_coordinates:
				draw_string(ThemeDB.fallback_font, rect.position + Vector2(4, 15), "%d,%d" % [x + 1, rows - y], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#b9d8e8"))

	# Draw walls on top of the grid.
	for wall_key in document.data["walls"]:
		var parts := str(wall_key).split(",")
		var wall_x := int(parts[0])
		var wall_y := int(parts[1])

		for direction in document.data["walls"][wall_key]:
			if direction == "north":
				draw_line(Vector2((wall_x - 1) * CELL_SIZE, (rows - wall_y) * CELL_SIZE), Vector2(wall_x * CELL_SIZE, (rows - wall_y) * CELL_SIZE), Color("#e8f0ff"), 5.0)
			elif direction == "east":
				draw_line(Vector2(wall_x * CELL_SIZE, (rows - wall_y) * CELL_SIZE), Vector2(wall_x * CELL_SIZE, (rows - wall_y + 1) * CELL_SIZE), Color("#e8f0ff"), 5.0)
	
	# Draw objects.
	for object_key in document.data["objects"]:
		var parts := str(object_key).split(",")
		var object_x := int(parts[0])
		var object_y := int(parts[1])
		var tile_objects: Dictionary = document.data["objects"][object_key]

		for object_name in tile_objects:
			var icon: Texture2D = OBJECT_ICONS.get(object_name)
			if icon == null:
				continue
			var object_center := _cell_center(object_x, object_y, rows)
			_draw_icon(icon, object_center)
			var object_count := int(tile_objects[object_name])
			if object_count > 1:
				draw_string(ThemeDB.fallback_font, object_center + Vector2(9, 14), str(object_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

	# Draw goal object markers.
	if document.data.has("goal") and document.data["goal"].has("objects"):
		var goal_objs: Dictionary = document.data["goal"]["objects"]
		for key in goal_objs:
			var parts := str(key).split(",")
			if parts.size() != 2:
				continue
			var gx := int(parts[0])
			var gy := int(parts[1])
			var required: Dictionary = goal_objs[key]
			var placed: Dictionary = document.data["objects"].get(key, {})
			
			for obj_name in required:
				var needed := int(required[obj_name])
				var have := int(placed.get(obj_name, 0))
				for i in range(needed):
					var marker_center := _cell_center(gx, gy, rows)
					var satisfied := i < have
					var marker_color := Color(0.35, 0.9, 0.45, 0.55) if satisfied else Color(1.0, 1.0, 1.0, 0.75)
					draw_circle(marker_center + Vector2(8, 8), CELL_SIZE * 0.12, marker_color)
					draw_circle(marker_center + Vector2(8, 8), CELL_SIZE * 0.12, Color("#668099"), false, 1.0)
	
	# Draw robot.
	var robot: Dictionary = document.data["robots"][0]
	var robot_center := _cell_center(
		int(robot["x"]),
		int(robot["y"]),
		rows
	)
	_draw_icon(ROBOT_ICON, robot_center, 36.0)

	# Draw goal.
	var finish: Array = document.data["goal"]["possible_final_positions"][0]
	var goal_center := _cell_center(
		int(finish[0]),
		int(finish[1]),
		rows
	)
	_draw_icon(GOAL_ICON, goal_center, 36.0)

func set_tool(tool: Tool) -> void:
	active_tool = tool

func set_object_type(type: String) -> void:
	object_type = type.to_lower()
	queue_redraw()

func set_object_count(count: int) -> void:
	object_count = clampi(count, 1, 100)


func set_zoom(value: float) -> void:
	zoom_initialized = true
	zoom_level = clampf(value, MIN_ZOOM, MAX_ZOOM)
	scale = Vector2.ONE * zoom_level
	view_changed.emit()


func zoom_in() -> void:
	set_zoom(zoom_level * ZOOM_STEP)


func zoom_out() -> void:
	set_zoom(zoom_level / ZOOM_STEP)


func reset_pan() -> void:
	pan_offset = Vector2.ZERO
	_panning = false


func pan_by(delta: Vector2) -> void:
	if delta == Vector2.ZERO:
		return
	if _left_button_down:
		_left_button_panned = true
	pan_offset += delta
	view_changed.emit()


func pan_up() -> void:
	pan_by(Vector2(0, PAN_STEP))


func pan_down() -> void:
	pan_by(Vector2(0, -PAN_STEP))


func pan_left() -> void:
	pan_by(Vector2(PAN_STEP, 0))


func pan_right() -> void:
	pan_by(Vector2(-PAN_STEP, 0))


func begin_map_click() -> void:
	_left_button_down = true
	_left_button_panned = false
	_click_start_tile = _tile_at_local_mouse()


func end_map_click() -> void:
	if not _left_button_down:
		return
	_left_button_down = false
	var was_panned := _left_button_panned
	_left_button_panned = false
	_click_start_tile = Vector2i(-1, -1)
	if not was_panned and not suppress_tool_application:
		_apply_tool_at_mouse_position()


func _cancel_map_click() -> void:
	_left_button_down = false
	_left_button_panned = false
	_click_start_tile = Vector2i(-1, -1)


func apply_layout(available_size: Vector2, unscaled_grid_size: Vector2) -> void:
	scale = Vector2.ONE * zoom_level
	var scaled := unscaled_grid_size * zoom_level
	pan_offset.x = _clamp_pan_axis(pan_offset.x, available_size.x, scaled.x)
	pan_offset.y = _clamp_pan_axis(pan_offset.y, available_size.y, scaled.y)
	position = (available_size - scaled) * 0.5 + pan_offset


func _clamp_pan_axis(pan: float, available: float, scaled: float) -> float:
	if scaled <= available + 0.5:
		# Keep small maps movable while the editor is in pan mode instead of
		# forcing them back to the exact center every time the view updates.
		return clampf(pan, -available * 0.35, available * 0.35)
	var centered := (available - scaled) * 0.5
	var min_pan := (available - scaled) - centered
	var max_pan := -centered
	return clampf(pan, min_pan, max_pan)


func _hovered_control() -> Control:
	return get_viewport().gui_get_hovered_control()


func _is_under_named_control(control: Control, node_name: String) -> bool:
	var node: Node = control
	while node != null:
		if node.name == node_name:
			return true
		node = node.get_parent()
	return false


func _is_over_dialog(control: Control) -> bool:
	var node: Node = control
	while node != null:
		if node is AcceptDialog or node is FileDialog or node is Popup:
			return true
		node = node.get_parent()
	return false


func _should_handle_zoom() -> bool:
	var mouse := get_viewport().get_mouse_position()
	if mouse.x < SIDEBAR_WIDTH:
		return false
	var hovered := _hovered_control()
	if hovered != null and _is_over_dialog(hovered):
		return false
	return true


func _should_handle_map_click() -> bool:
	var mouse := get_viewport().get_mouse_position()
	if mouse.x < SIDEBAR_WIDTH:
		return false
	var hovered := _hovered_control()
	if hovered == null:
		return true
	if _is_over_dialog(hovered):
		return false
	if _is_under_named_control(hovered, "ViewControls"):
		return false
	if hovered is BaseButton:
		return false
	return true


func _should_handle_canvas_drag() -> bool:
	if not _should_handle_zoom():
		return false
	return _should_handle_map_click()


func _input(event: InputEvent) -> void:
	if document == null:
		return

	if event is InputEventMouseMotion:
		if _panning:
			if not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
				_panning = false
				return
			pan_by((event as InputEventMouseMotion).relative)
			get_viewport().set_input_as_handled()
			return
		if _left_button_down and not _left_button_panned and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if _tile_at_local_mouse() != _click_start_tile:
				_left_button_panned = true

	if not (event is InputEventMouseButton):
		return

	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed and _should_handle_canvas_drag():
			_panning = true
			get_viewport().set_input_as_handled()
		else:
			_panning = false
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		if _should_handle_zoom():
			zoom_in()
			get_viewport().set_input_as_handled()
		return

	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		if _should_handle_zoom():
			zoom_out()
			get_viewport().set_input_as_handled()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		if _should_handle_map_click():
			begin_map_click()
		else:
			_cancel_map_click()
		return

	end_map_click()


func _tile_at_local_mouse() -> Vector2i:
	if document == null:
		return Vector2i(-1, -1)
	var mouse_position := get_local_mouse_position()
	var cols := int(document.data["cols"])
	var rows := int(document.data["rows"])

	if mouse_position.x < 0 or mouse_position.y < 0:
		return Vector2i(-1, -1)

	var gx := int(mouse_position.x / CELL_SIZE) + 1
	var gy := rows - int(mouse_position.y / CELL_SIZE)

	if gx < 1 or gx > cols or gy < 1 or gy > rows:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)


func _apply_tool_at_mouse_position() -> void:
	if not _should_handle_map_click():
		return

	var tile := _tile_at_local_mouse()
	if tile.x < 0:
		return

	apply_tool(tile.x, tile.y)


func apply_tool(gx: int, gy: int) -> void:
	var key := "%d,%d" % [gx, gy]
	var did_objects_change := false
	if not document.data.has("void_tiles"):
		document.data["void_tiles"] = {}
	if active_tool in [Tool.ROBOT, Tool.GOAL]:
		document.data["void_tiles"].erase(key)
	elif active_tool == Tool.OBJECT and document.data["void_tiles"].has(key):
		return
	if active_tool == Tool.VOID:
		var robot: Dictionary = document.data["robots"][0]
		if int(robot.x) == gx and int(robot.y) == gy:
			return
		if document.data["objects"].has(key):
			return
		for pos in document.data["goal"].get("possible_final_positions", []):
			if int(pos[0]) == gx and int(pos[1]) == gy:
				return
		if document.data["goal"].get("objects", {}).has(key):
			return  # Do not void tiles that have goal object requirements.
		document.data["void_tiles"][key] = true
		if document.data["objects"].has(key):
			document.data["objects"].erase(key)
			did_objects_change = true
	elif active_tool == Tool.ROBOT:
		var robots: Array = document.data["robots"]
		var robot: Dictionary = robots[0]
		robot["x"] = gx
		robot["y"] = gy
		robots[0] = robot
		document.data["robots"] = robots

	elif active_tool == Tool.GOAL:
		var goal: Dictionary = document.data["goal"]
		goal["possible_final_positions"] = [[gx, gy]]
		# Do not leave an old legacy goal tile active after moving the goal.
		goal.erase("position")
		document.data["goal"] = goal

	elif active_tool == Tool.WALL or active_tool == Tool.EAST_WALL:
		var wall_key := "%d,%d" % [gx, gy]
		var walls: Dictionary = document.data["walls"]
		var directions: Array = walls.get(wall_key, [])

		var direction := "east" if active_tool == Tool.EAST_WALL else "north"
		if directions.has(direction):
			directions.erase(direction)
			if directions.is_empty():
				walls.erase(wall_key)
			else:
				walls[wall_key] = directions
		else:
			directions.append(direction)
			walls[wall_key] = directions

		document.data["walls"] = walls

	elif active_tool == Tool.OBJECT:
		var object_key := "%d,%d" % [gx, gy]
		var objects: Dictionary = document.data["objects"]
		var tile_objects: Dictionary = objects.get(object_key, {})
		# A tile can stack one object type, but it cannot mix object types.
		# Use Erase before placing a different object on the tile.
		if not tile_objects.is_empty() and not tile_objects.has(object_type):
			return
		tile_objects[object_type] = int(tile_objects.get(object_type, 0)) + object_count
		objects[object_key] = tile_objects
		document.data["objects"] = objects
		did_objects_change = true

	elif active_tool == Tool.ERASE:
		document.data["void_tiles"].erase(key)
		var cell_key := "%d,%d" % [gx, gy]

		var objects: Dictionary = document.data["objects"]
		if objects.has(cell_key):
			did_objects_change = true
		objects.erase(cell_key)
		document.data["objects"] = objects

		# Also remove from goal objects if this tile is a goal tile
		if document.data.has("goal") and document.data["goal"].has("objects"):
			var goal_objs: Dictionary = document.data["goal"]["objects"]
			if goal_objs.has(cell_key):
				goal_objs.erase(cell_key)
				document.data["goal"]["objects"] = goal_objs

		var walls: Dictionary = document.data["walls"]
		walls.erase(cell_key)
		document.data["walls"] = walls

	queue_redraw()
	if did_objects_change:
		objects_changed.emit()
