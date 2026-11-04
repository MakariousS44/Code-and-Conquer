class_name EditorGridView
extends Node2D

const CELL_SIZE := 48.0
const MIN_ZOOM := 0.25
const MAX_ZOOM := 3.0
const ZOOM_STEP := 1.12
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



signal zoom_changed

var active_tool := Tool.ROBOT

var document: LevelDocument
var show_coordinates := false
var object_type := "token"
var object_count := 1
var zoom_level := 1.0
var zoom_initialized := false


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
				draw_line(rect.position + Vector2(12, 12), rect.end - Vector2(12, 12), Color("68718e"), 2.0)
				draw_line(rect.position + Vector2(12, 36), rect.position + Vector2(36, 12), Color("68718e"), 2.0)
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

		# Apples
		if tile_objects.has("apple"):
			var apple_center := _cell_center(object_x, object_y, rows)
			draw_circle(apple_center, CELL_SIZE * 0.16, Color("#e74c3c"))  # Red for apples
			var apple_count := int(tile_objects["apple"])
			if apple_count > 1:
				draw_string(ThemeDB.fallback_font, apple_center + Vector2(9, 14), str(apple_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

		# Tokens
		if tile_objects.has("token"):
			var token_center := _cell_center(object_x, object_y, rows)
			draw_circle(token_center, CELL_SIZE * 0.16, Color("#ffff00"))  # Yellow for tokens
			var token_count := int(tile_objects["token"])
			if token_count > 1:
				draw_string(ThemeDB.fallback_font, token_center + Vector2(9, 14), str(token_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

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
	draw_circle(robot_center, CELL_SIZE * 0.25, Color("#9b59ff"))

	# Draw goal.
	var finish: Array = document.data["goal"]["possible_final_positions"][0]
	var goal_center := _cell_center(
		int(finish[0]),
		int(finish[1]),
		rows
	)
	draw_circle(goal_center, CELL_SIZE * 0.25, Color("#f5a623"))
	
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
	zoom_changed.emit()


func zoom_in() -> void:
	set_zoom(zoom_level * ZOOM_STEP)


func zoom_out() -> void:
	set_zoom(zoom_level / ZOOM_STEP)


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
	if _is_under_named_control(hovered, "ZoomControls"):
		return false
	if hovered is BaseButton:
		return false
	return true


func _input(event: InputEvent) -> void:
	if document == null:
		return

	if not (event is InputEventMouseButton):
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

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	if not _should_handle_map_click():
		return

	var mouse_position := get_local_mouse_position()
	var cols := int(document.data["cols"])
	var rows := int(document.data["rows"])

	if mouse_position.x < 0 or mouse_position.y < 0:
		return

	var gx := int(mouse_position.x / CELL_SIZE) + 1
	var gy := rows - int(mouse_position.y / CELL_SIZE)

	if gx < 1 or gx > cols or gy < 1 or gy > rows:
		return

	apply_tool(gx, gy)


func apply_tool(gx: int, gy: int) -> void:
	var key := "%d,%d" % [gx, gy]
	if not document.data.has("void_tiles"):
		document.data["void_tiles"] = {}
	if active_tool in [Tool.ROBOT, Tool.GOAL, Tool.OBJECT]:
		document.data["void_tiles"].erase(key)
	if active_tool == Tool.VOID:
		var robot: Dictionary = document.data["robots"][0]
		if int(robot.x) == gx and int(robot.y) == gy:
			return
		for pos in document.data["goal"].get("possible_final_positions", []):
			if int(pos[0]) == gx and int(pos[1]) == gy:
				return
		if document.data["goal"].get("objects", {}).has(key):
			return  # Do not void tiles that have goal object requirements.
		document.data["void_tiles"][key] = true
		document.data["objects"].erase(key)
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
		
		tile_objects[object_type] = int(tile_objects.get(object_type, 0)) + object_count
		objects[object_key] = tile_objects
		document.data["objects"] = objects

	elif active_tool == Tool.ERASE:
		document.data["void_tiles"].erase(key)
		var cell_key := "%d,%d" % [gx, gy]

		var objects: Dictionary = document.data["objects"]
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
