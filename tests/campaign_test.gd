extends SceneTree

const Campaign = preload("res://config/campaign_levels.gd")
const Loader = preload("res://map/scripts/map_loader.gd")
const CppValidator = preload("res://execution/cpp/cpp_validator.gd")
const PythonValidator = preload("res://execution/python/python_validator.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	var save_path := OS.get_temp_dir().path_join("campaign-test-%d.cfg" % OS.get_process_id())
	check(Campaign.completed_ids(save_path).is_empty(), "Fresh progress must be empty")
	check(Campaign.is_unlocked(0, []), "First level must be unlocked")
	check(not Campaign.is_unlocked(1, []), "Second level must start locked")
	check(Campaign.mark_complete(Campaign.LEVELS[2].path, save_path) == ERR_UNAUTHORIZED, "Cannot skip locked levels")
	for i in range(Campaign.LEVELS.size()):
		check(Campaign.mark_complete(Campaign.LEVELS[i].path, save_path) == OK, "Progress must save")
		check(Campaign.mark_complete(Campaign.LEVELS[i].path, save_path) == OK, "Replay must save")
		var ids := Campaign.completed_ids(save_path)
		check(ids.size() == i + 1, "Replay must not duplicate progress")
		if i + 1 < Campaign.LEVELS.size():
			check(Campaign.is_unlocked(i + 1, ids), "Winning must unlock next level")
	check(Campaign.index_for_path("user://custom_levels/custom.json") == -1, "Custom worlds must not grant campaign progress")
	DirAccess.remove_absolute(save_path)

	# M = move, L = turn left. Each route should reach its level's goal.
	var solutions := ["MMMM", "MMMMLMMMM", "MMMMLMMLMMMMLLLMMLLLMMMM"]
	for i in range(Campaign.LEVELS.size()):
		var result: Dictionary = Loader.new().load(Campaign.LEVELS[i].path)
		check(result.ok, "Campaign JSON must load")
		var data: Dictionary = result.definition
		check(CppValidator.new().validate("\n".join(data.editor.cpp)).ok, "C++ starter must pass validation")
		check(PythonValidator.new().validate("\n".join(data.editor.python)).ok, "Python starter must pass validation")
		var world = load("res://map/scenes/map_view.tscn").instantiate()
		root.add_child(world)
		world.build_level(data)
		var outcome := {"won": false, "lost": false}
		world.level_complete.connect(func(): outcome.won = true)
		world.player.lose_triggered.connect(func(_reason): outcome.lost = true)
		for action in solutions[i]:
			if action == "M":
				await world.player.move_forward(0.001)
			else:
				world.player.turn_left()
		check(outcome.won and not outcome.lost, "Level %d must be solvable without collisions" % (i + 1))
		world.queue_free()
		await process_frame

	var menu = load("res://main_menu/scenes/main_menu.tscn").instantiate()
	root.add_child(menu)
	menu._on_button_start_pressed()
	check(menu.campaign_menu.visible, "Play must open campaign selection")
	check(menu.campaign_menu._list.get_child_count() == 3, "Campaign must show three levels")
	menu.campaign_menu.hide()
	menu._open_custom_worlds()
	check(menu.level_popup.visible, "Custom worlds must remain accessible")
	menu.queue_free()
	await process_frame
	var workstation = load("res://workstation/scenes/workstation.tscn").instantiate()
	check(workstation != null, "Workstation must instantiate with campaign code")
	workstation.set_script(load("res://tests/campaign_workstation_fixture.gd"))
	workstation.campaign_progress_path = save_path
	root.get_node("SelectedLevel").path = Campaign.LEVELS[0].path
	root.add_child(workstation)
	await process_frame
	check(workstation.campaign_panel.visible, "Campaign instructions must be visible")
	workstation.campaign_hint_button.pressed.emit()
	check(workstation.campaign_hint.visible, "Hint button must reveal hint")
	workstation._on_language_changed(1)
	await process_frame
	check(workstation.editor.text.begins_with("from robot"), "Python selection must load Python scaffold")
	for i in range(Campaign.LEVELS.size()):
		for action in solutions[i]:
			if action == "M":
				await workstation.player_node.move_forward(0.001)
			else:
				workstation.player_node.turn_left()
		check(workstation.win_overlay.visible, "Campaign victory must show overlay")
		check(Campaign.LEVELS[i].id in Campaign.completed_ids(save_path), "Workstation victory must save completion")
		if i + 1 < Campaign.LEVELS.size():
			check(workstation.campaign_next_button.visible, "Next Level must appear after victory")
			workstation.campaign_next_button.pressed.emit()
			await process_frame
			check(root.get_node("SelectedLevel").path == Campaign.LEVELS[i + 1].path, "Next Level must select next map")
			check(workstation.editor.text.begins_with("from robot"), "Next Level must preserve Python selection")
		else:
			check(not workstation.campaign_next_button.visible, "Final level must hide Next Level")
			check(workstation.get_node("WinOverlay/WinCard/WinContent/WinTitle").text == "Campaign Complete!", "Final victory must celebrate campaign completion")
	workstation._on_win_retry()
	await process_frame
	check(not workstation.win_overlay.visible and workstation.editor.editable, "Replay must restore controls")
	workstation.queue_free()
	await process_frame
	DirAccess.remove_absolute(save_path)
	print("CAMPAIGN TESTS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
