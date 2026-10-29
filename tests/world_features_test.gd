extends SceneTree

var failures := 0
var visual := false

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	visual = "--visual" in OS.get_cmdline_user_args()
	call_deferred("run_tests")

func capture(filename: String) -> void:
	if visual:
		await process_frame
		await RenderingServer.frame_post_draw
		var folder := OS.get_environment("CODE_CONQUER_SCREENSHOTS")
		if folder.is_empty():
			folder = OS.get_temp_dir()
		root.get_texture().get_image().save_png(folder.path_join(filename))

func run_tests() -> void:
	var menu = load("res://main_menu/scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	var colors := []
	for button in menu.get_node("MenuBG/ButtonsContainer").get_children():
		if button is Button:
			var color: Color = button.get_theme_color("font_color")
			check(color not in colors, "Menu actions need distinct colors")
			colors.append(color)
	await capture("menu-updated.png")
	menu.queue_free()
	await process_frame

	var level_editor = load("res://level_editor/scenes/level_editor.tscn").instantiate()
	root.add_child(level_editor)
	var doc = level_editor.document
	check(level_editor.void_button.visible, "Void tool must be available in the editor")
	level_editor.grid.set_tool(EditorGridView.Tool.VOID)
	level_editor.grid.apply_tool(2, 2)
	check(doc.data.void_tiles.has("2,2"), "Void tool must remove floor")
	level_editor.grid.apply_tool(1, 1)
	check(not doc.data.void_tiles.has("1,1"), "Cannot remove robot's starting floor")
	var restored := LevelDocument.new()
	check(restored.load_level(JSON.parse_string(JSON.stringify(doc.data))).ok, "Void tiles must survive JSON round trip")
	check(restored.data.void_tiles.has("2,2"), "Void tile must survive loading")
	level_editor.grid.set_tool(EditorGridView.Tool.ERASE)
	level_editor.grid.apply_tool(2, 2)
	check(not doc.data.void_tiles.has("2,2"), "Erase must restore floor")
	var before: Dictionary = restored.data.duplicate(true)
	var invalid: Dictionary = before.duplicate(true)
	invalid.void_tiles["1,1"] = true
	check(not restored.load_level(invalid).ok, "Reject void under robot")
	check(restored.data == before, "Failed load must preserve editor document")
	restored.resize(1, 1)
	check(restored.data.void_tiles.is_empty(), "Resize must discard out-of-bounds voids")
	await capture("level-editor-updated.png")
	level_editor.queue_free()
	await process_frame

	root.get_node("SelectedLevel").path = "res://data/custom_levels/VoidCrossing.json"
	var station = load("res://workstation/scenes/workstation.tscn").instantiate()
	station.set_script(load("res://tests/campaign_workstation_fixture.gd"))
	root.add_child(station)
	await process_frame
	station.editor.text = "if (x < 3) move();"
	station._setup_syntax_highlighting()
	check(not station.editor.syntax_highlighter.has_color_region("<"), "C++ comparisons must not start string regions")
	station._setup_python_highlighting()
	check(not station.editor.syntax_highlighter.has_color_region("*"), "Python multiplication must not start a region")
	check(station.editor.syntax_highlighter.has_color_region("'''"), "Python triple-quoted strings need coloring")
	var world = station.game_instance
	for i in range(4):
		await process_frame
		var void_cell: Vector2i = world._rotate_goal_cell(3, 2, 6, 4)
		check(world.FloorTiles.get_cell_source_id(void_cell) == -1, "Void must remain empty at every rotation")
		var bounds: Dictionary = world._compute_level_pixel_bounds()
		var world_size: Vector2 = world.FloorTiles.to_global(bounds.max) - world.FloorTiles.to_global(bounds.min)
		var vp_size: Vector2 = world.get_viewport_rect().size
		check(world_size.x * world.camera.zoom.x <= vp_size.x + 1 and world_size.y * world.camera.zoom.y <= vp_size.y + 1, "Camera must fit rotated world")
		world.rotate_world_right()
	await process_frame
	await capture("world-updated.png")
	station._on_grid_2d_button_pressed()
	await capture("world-flat-updated.png")
	station.player_node.grid_x = 2
	station.player_node.grid_y = 2
	station.player_node.facing = "east"
	check(station._answer_query("FRONT_IS_CLEAR") == "true", "Sensors must not detect voids")
	check(station._answer_query("WALL_IN_FRONT") == "false", "Void is not a wall")
	station.player_node.facing = "south"
	check(station._answer_query("LEFT_IS_CLEAR") == "true", "Left sensor must not detect voids")
	station.player_node.facing = "north"
	check(station._answer_query("RIGHT_IS_CLEAR") == "true", "Right sensor must not detect voids")
	station.player_node.facing = "east"
	world.level_data.walls["2,2"] = ["east"]
	check(station._answer_query("FRONT_IS_CLEAR") == "false", "Walls still block sensors")
	world.level_data.walls.clear()
	await station.player_node.move_forward(0.001)
	check(station.lose_overlay.visible, "Moving into void must lose")
	station._on_lose_retry()
	await process_frame
	check(station.player_node.modulate.a == 1.0, "Retry must restore character visibility")
	for rotation in range(4):
		world = station.game_instance
		for turn in range(rotation):
			world.rotate_world_right()
		station.player_node.grid_x = 1
		station.player_node.grid_y = 2
		station.player_node.facing = "west"
		check(station._answer_query("FRONT_IS_CLEAR") == "false", "Keep the original boundary sensor behavior for campaign solutions")
		await station.player_node.move_forward(0.001)
		check(station.lose_overlay.visible and station.player_node.modulate.a == 0.0, "Outside edges must trigger a visible fall at every rotation")
		station._on_lose_retry()
		await process_frame
	station.queue_free()
	await process_frame
	print("WORLD FEATURE TESTS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
