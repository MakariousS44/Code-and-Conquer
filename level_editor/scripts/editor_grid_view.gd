class_name EditorGridView
extends Node2D

const CELL_SIZE := 48.0

enum Tool {
	ROBOT,
	GOAL,
	WALL,
	EAST_WALL,
	APPLE,
	ERASE
}



var active_tool := Tool.ROBOT

var document: LevelDocument
var show_coordinates := false


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
	
	# Draw apples.
	for object_key in document.data["objects"]:
		var parts := str(object_key).split(",")
		var object_x := int(parts[0])
		var object_y := int(parts[1])
		var tile_objects: Dictionary = document.data["objects"][object_key]

		if tile_objects.has("apple"):
			var apple_center := _cell_center(object_x, object_y, rows)
			draw_circle(apple_center, CELL_SIZE * 0.16, Color("#e74c3c"))
			var apple_count := int(tile_objects["apple"])
			if apple_count > 1:
				draw_string(ThemeDB.fallback_font, apple_center + Vector2(9, 14), str(apple_count), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
	
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

func _input(event: InputEvent) -> void:
	if document == null:
		return

	if not (event is InputEventMouseButton):
		return

	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
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

	if active_tool == Tool.ROBOT:
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

	elif active_tool == Tool.APPLE:
		var object_key := "%d,%d" % [gx, gy]
		var objects: Dictionary = document.data["objects"]
		var tile_objects: Dictionary = objects.get(object_key, {})

		tile_objects["apple"] = int(tile_objects.get("apple", 0)) + 1
		objects[object_key] = tile_objects
		document.data["objects"] = objects

	elif active_tool == Tool.ERASE:
		var cell_key := "%d,%d" % [gx, gy]

		var objects: Dictionary = document.data["objects"]
		objects.erase(cell_key)
		document.data["objects"] = objects

		var walls: Dictionary = document.data["walls"]
		walls.erase(cell_key)
		document.data["walls"] = walls

	queue_redraw()
