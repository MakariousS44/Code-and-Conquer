extends SceneTree

var failures := 0
var visual := false

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)


func goal_test_level(positions: Variant, legacy_position: Variant = null) -> Dictionary:
	var goal := {"possible_final_positions": positions}
	if legacy_position != null:
		goal["position"] = legacy_position
	return {
		"cols": 5,
		"rows": 5,
		"robots": [{"x": 1, "y": 1}],
		"walls": {},
		"goal": goal
	}


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

	var goal_doc := LevelDocument.new()
	var merged_result := goal_doc.load_level(goal_test_level([[2, 2]], {"x": 3, "y": 3}))
	check(merged_result.get("ok", false), "Valid legacy goal position must merge")
	check(goal_doc.data["goal"]["possible_final_positions"] == [[2, 2], [3, 3]], "Distinct legacy goal must be appended")
	goal_doc = LevelDocument.new()
	check(goal_doc.load_level(goal_test_level([[2, 2]], {"x": 2, "y": 2})).get("ok", false), "Duplicate legacy goal must load")
	check(goal_doc.data["goal"]["possible_final_positions"] == [[2, 2]], "Duplicate legacy goal must not be appended")
	goal_doc = LevelDocument.new()
	check(goal_doc.load_level(goal_test_level([[2.0, 2.0]], {"x": 3.0, "y": 3.0})).get("ok", false), "Integral float goal coordinates must load")
	check(goal_doc.data["goal"]["possible_final_positions"] == [[2, 2], [3, 3]], "Goal coordinates must normalize to integers")
	for entry in [[{}, 2], ["a", 2], ["2", 2], [null, 2], [1.5, 2]]:
		goal_doc = LevelDocument.new()
		var result := goal_doc.load_level(goal_test_level([entry], {"x": 3, "y": 3}))
		check(not result.get("ok", false) and result.get("error") == "Goal position is invalid.", "Malformed goal coordinate must be rejected: %s" % str(entry))
	goal_doc = LevelDocument.new()
	var out_of_bounds := goal_doc.load_level(goal_test_level([[6, 2]], {"x": 3, "y": 3}))
	check(not out_of_bounds.get("ok", false) and out_of_bounds.get("error") == "Goal position is outside the grid.", "Out-of-bounds goal must keep grid error")
	goal_doc = LevelDocument.new()
	var no_legacy := goal_doc.load_level(goal_test_level([[{}, 2]]))
	check(no_legacy.get("error") == "Goal position is invalid.", "Malformed goal must be rejected without legacy merge")
	for legacy in [{"x": {}, "y": 3}, {"x": "3", "y": 3}]:
		goal_doc = LevelDocument.new()
		var legacy_result := goal_doc.load_level(goal_test_level([[2, 2]], legacy))
		check(legacy_result.get("error") == "Goal position is invalid.", "Malformed legacy goal must be rejected: %s" % str(legacy))
	goal_doc = LevelDocument.new()
	var legacy_out := goal_doc.load_level(goal_test_level([[2, 2]], {"x": 6, "y": 3}))
	check(legacy_out.get("error") == "Goal position is outside the grid.", "Out-of-bounds legacy goal must keep grid error")
	goal_doc = LevelDocument.new()
	var legacy_only := goal_doc.load_level(goal_test_level([], {"x": {}, "y": 3}))
	check(legacy_only.get("error") == "Goal position is invalid.", "Malformed legacy-only goal must be rejected")

	# Carry requirements dialog lists placed and starting-inventory types,
	# allows counts above 99, and frees itself when closed.
	doc.data["objects"] = {"1,2": {"token": 150}}
	doc.data["robots"][0]["objects"] = {"gem": 2}
	level_editor._open_carry_requirements_dialog()
	var carry_dialog: Window = null
	for child in level_editor.get_children():
		if child is ConfirmationDialog and child.title == "Carry Requirements":
			carry_dialog = child
	check(carry_dialog != null, "Carry requirements dialog must open")
	if carry_dialog != null:
		check(not carry_dialog.exclusive, "Carry requirements must stay editable while the map changes")
		var found_token := false
		var found_gem := false
		var max_ok := true
		for node in carry_dialog.find_children("*", "Label", true, false):
			found_token = found_token or node.text == "Token"
			found_gem = found_gem or node.text == "Gem"
		for node in carry_dialog.find_children("*", "SpinBox", true, false):
			max_ok = max_ok and node.max_value >= 150
		check(found_token and found_gem, "Dialog must list placed and starting-inventory object types")
		check(max_ok, "Carry count spinboxes must allow totals above 99")
		check(carry_dialog.find_children("*", "CheckBox", true, false).size() == 2, "Each carry requirement needs a map-max checkbox")

		var token_auto: CheckBox = null
		var token_spin: SpinBox = null
		for node in carry_dialog.find_children("*", "HBoxContainer", true, false):
			if node.get_child_count() < 3:
				continue
			var row_label := node.get_child(0) as Label
			if row_label != null and row_label.text == "Token":
				token_auto = node.get_child(1) as CheckBox
				token_spin = node.get_child(2) as SpinBox
		check(token_auto != null and token_spin != null, "Token row must contain a checkbox and spinbox")
		if token_auto != null and token_spin != null:
			check(not token_auto.button_pressed and token_spin.editable, "Map-max mode must start off and editable")
			token_auto.button_pressed = true
			check(token_spin.value == 150 and not token_spin.editable, "Checking map max must fill and disable the count")

			level_editor.grid.set_tool(EditorGridView.Tool.OBJECT)
			level_editor.grid.set_object_type("token")
			level_editor.grid.set_object_count(5)
			level_editor.grid.apply_tool(3, 3)
			check(token_spin.value == 155, "Map max must update when objects are added")
			level_editor.grid.set_tool(EditorGridView.Tool.ERASE)
			level_editor.grid.apply_tool(1, 2)
			check(token_spin.value == 5, "Map max must update when objects are removed")

			level_editor._apply_carry_requirements(level_editor._carry_requirement_rows)
			check(doc.data["goal"]["require_carry"] == {"token": 5}, "Apply must save refreshed map-max counts")
			check(doc.data["goal"]["require_carry_auto"] == {"token": true}, "Apply must remember map-max selections")
			token_auto.button_pressed = false
			check(token_spin.editable, "Unchecking map max must re-enable manual counts")
			token_spin.value = 7
			level_editor._apply_carry_requirements(level_editor._carry_requirement_rows)
			check(doc.data["goal"]["require_carry"] == {"token": 7}, "Manual counts must still apply")
			check(not doc.data["goal"].has("require_carry_auto"), "Manual counts must clear map-max selections")

			token_auto.button_pressed = true
			level_editor._apply_carry_requirements(level_editor._carry_requirement_rows)
			check(doc.data["goal"]["require_carry"] == {"token": 5}, "Re-enabling map max must restore the map total")
			check(doc.data["goal"]["require_carry_auto"] == {"token": true}, "Map max must be saved again")
		carry_dialog.canceled.emit()
		check(carry_dialog.is_queued_for_deletion(), "Closing the carry dialog must free it")
		await process_frame

		level_editor.grid.set_tool(EditorGridView.Tool.OBJECT)
		level_editor.grid.set_object_type("token")
		level_editor.grid.set_object_count(3)
		level_editor.grid.apply_tool(4, 4)
		check(doc.data["goal"]["require_carry"] == {"token": 8}, "Closed dialog map-max counts must track map changes")
		check(doc.data["goal"]["require_carry_auto"] == {"token": true}, "Map-max selection must persist after closing")

		var saved_data: Dictionary = JSON.parse_string(JSON.stringify(doc.data))
		var reloaded := LevelDocument.new()
		check(reloaded.load_level(saved_data).ok, "Levels with map-max selections must load")
		check(int(reloaded.data["goal"]["require_carry"].get("token", 0)) == 8, "Map-max counts must survive JSON round trip")
		check(reloaded.data["goal"].get("require_carry_auto", {}) == {"token": true}, "Map-max selections must survive JSON round trip")

		level_editor._open_carry_requirements_dialog()
		var reopened_dialog: Window = null
		for child in level_editor.get_children():
			if child is ConfirmationDialog and child.title == "Carry Requirements":
				reopened_dialog = child
		check(reopened_dialog != null, "Carry requirements dialog must reopen")
		if reopened_dialog != null:
			var reopened_auto: CheckBox = null
			var reopened_spin: SpinBox = null
			for node in reopened_dialog.find_children("*", "HBoxContainer", true, false):
				if node.get_child_count() < 3:
					continue
				var row_label := node.get_child(0) as Label
				if row_label != null and row_label.text == "Token":
					reopened_auto = node.get_child(1) as CheckBox
					reopened_spin = node.get_child(2) as SpinBox
			check(reopened_auto != null and reopened_auto.button_pressed and reopened_spin != null and reopened_spin.value == 8 and not reopened_spin.editable, "Reopened dialog must restore map-max state")
			reopened_dialog.canceled.emit()
			check(reopened_dialog.is_queued_for_deletion(), "Reopened carry dialog must free itself")
		await process_frame

	level_editor._open_goal_objects_dialog()
	var goal_dialog: Window = null
	for child in level_editor.get_children():
		if child is AcceptDialog and child.title == "Set Goal Objects":
			goal_dialog = child
	check(goal_dialog != null, "Goal objects dialog must open")
	if goal_dialog != null:
		goal_dialog.canceled.emit()
		check(goal_dialog.is_queued_for_deletion(), "Closing the goal objects dialog must free it")

	await capture("level-editor-updated.png")
	level_editor.queue_free()
	await process_frame

	var carry_world = load("res://map/scenes/map_view.tscn").instantiate()
	root.add_child(carry_world)
	carry_world.build_level({
		"cols": 3, "rows": 3,
		"robots": [{"x": 1, "y": 1, "_orientation": 0, "objects": {}}],
		"walls": {},
		"objects": {"1,2": {"apple": 2, "token": 1}},
		"goal": {"possible_final_positions": [[3, 3]], "require_carry": {"apple": 2, "token": 1}}
	})
	check(carry_world._get_carry_requirement() == {"apple": 2, "token": 1}, "Carry requirements must read per-object minimums")
	var carry_outcome := {"won": false, "incomplete": 0}
	carry_world.level_complete.connect(func(): carry_outcome.won = true)
	carry_world.level_incomplete.connect(func(_msg): carry_outcome.incomplete += 1)
	carry_world.player.carried_object = {"apple": 2}
	carry_world.check_win_condition(3, 3)
	check(not carry_outcome.won and carry_outcome.incomplete == 1, "Missing a required object must block the win")
	carry_world.player.carried_object = {"apple": 3, "token": 1}
	carry_world.check_win_condition(3, 3)
	check(carry_outcome.won, "Carrying more than the minimum must still win")
	carry_world.level_data["goal"]["require_carry"] = {"apple": "lots", "token": 1, "[b]x": 2, "coin": 1.5}
	check(carry_world._get_carry_requirement() == {"token": 1}, "Malformed carry entries must be ignored")
	carry_world.level_data["goal"]["require_carry"] = "all_tokens"
	check(carry_world._get_carry_requirement().is_empty(), "Non-dictionary carry requirements must be ignored")
	var carry_rules = load("res://map/scripts/carry_requirements.gd")
	check(carry_rules.validate({"goal": {"require_carry": {"apple": 2, "token": 1}}}).is_empty(), "Valid carry requirements must pass validation")
	check(not carry_rules.validate({"goal": {"require_carry": "all_tokens"}}).is_empty(), "String carry requirements must be rejected")
	check(not carry_rules.validate({"goal": {"require_carry": {"apple": "lots"}}}).is_empty(), "Non-integer counts must be rejected")
	check(not carry_rules.validate({"goal": {"require_carry": {"apple": 1.5}}}).is_empty(), "Fractional counts must be rejected")
	check(not carry_rules.validate({"goal": {"require_carry": {"[b]x": 1}}}).is_empty(), "Markup object names must be rejected")
	check(carry_rules.validate({"goal": {"require_carry_auto": {"apple": true}}}).is_empty(), "Valid carry auto requirements must pass validation")
	check(not carry_rules.validate({"goal": {"require_carry_auto": "all"}}).is_empty(), "String carry auto requirements must be rejected")
	check(not carry_rules.validate({"goal": {"require_carry_auto": {"[b]x": true}}}).is_empty(), "Markup auto object names must be rejected")
	check(not carry_rules.validate({"goal": {"require_carry_auto": {"apple": 1}}}).is_empty(), "Non-boolean auto values must be rejected")
	check(carry_rules.normalize_auto({"apple": true, "[b]x": true, "token": 1}) == {"apple": true}, "Auto normalization must keep only valid true flags")
	var bad_carry_level: Dictionary = doc.data.duplicate(true)
	bad_carry_level["goal"]["require_carry"] = {"apple": "lots"}
	check(not restored.load_level(bad_carry_level).ok, "Level editor must reject malformed carry requirements")
	carry_world.queue_free()
	await process_frame

	root.get_node("SelectedLevel").path = "res://data/custom_levels/VoidCrossing.json"
	var station = load("res://workstation/scenes/workstation.tscn").instantiate()
	station.set_script(load("res://tests/campaign_workstation_fixture.gd"))
	root.add_child(station)
	await process_frame
	station.editor.text = "if (x < 3) move();"
	station._setup_syntax_highlighting()
	check(station.editor.syntax_highlighter.get_script() == load("res://workstation/scripts/cpp_highlighter.gd"), "C++ must use the literal-aware highlighter")
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
	# In headless runs the audio driver never finishes a playback, so each
	# play() orphans the previous one. Stop the lose sound between losses.
	station.get_node("LoseSound").stop()
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
		check(station.lose_overlay.visible and station.player_node.modulate.a == 1.0 and station.player_node.grid_x == 1, "Map edges must behave like walls at every rotation")
		station.get_node("LoseSound").stop()
		station._on_lose_retry()
		await process_frame
	# Stop any playing audio before freeing so playbacks don't leak at exit.
	for player in station.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	station.queue_free()
	await process_frame
	print("WORLD FEATURE TESTS: %d failures" % failures)
	# Stop any playing audio and free anything still in the tree.
	for player in root.find_children("*", "AudioStreamPlayer", true, false):
		player.stop()
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
