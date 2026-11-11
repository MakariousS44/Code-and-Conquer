extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run_tests() -> void:
	root.get_node("SelectedLevel").path = "res://data/custom_levels/VoidCrossing.json"
	var station = load("res://workstation/scenes/workstation.tscn").instantiate()
	station.set_script(load("res://tests/campaign_workstation_fixture.gd"))
	root.add_child(station)
	await process_frame
	check(not station.check_button.disabled, "Check Code starts enabled")
	var endings := [
		station._on_level_complete, station._on_execution_done,
		station._on_player_lose.bind("Wall collision"),
		station._trigger_incomplete_lose.bind("Goal not reached"),
		station._trigger_move_limit_lose, station._trigger_cmd_limit_lose,
		station._trigger_time_limit_lose,
	]
	for ending in endings:
		ending.call()
		check(station.check_button.disabled, "Check Code must be disabled after " + str(ending))
		station.has_checked_code = false
		station._on_check_button_pressed()
		check(not station.has_checked_code and station.run_button.disabled, "Check Code cannot unlock a finished run")
		station._set_controls_disabled(false)
		check(station.check_button.disabled, "Closing an overlay cannot unlock Check Code")
		station._on_lose_retry()
		station.win_overlay.hide()
		station.done_overlay.hide()
		await process_frame
		check(not station.check_button.disabled, "Retry restores Check Code")
	station._ipc_active = true
	station._run_had_error = true
	station._stop_execution()
	station._re_enable_buttons()
	check(station.check_button.disabled, "Runtime errors keep Check Code disabled until Reset")
	station._on_reset_button_pressed()
	await process_frame
	check(not station.check_button.disabled, "Reset restores Check Code after runtime errors")
	station.queue_free()
	await process_frame
	print("CHECK CODE LIFECYCLE TESTS: %d failures" % failures)
	quit(0 if failures == 0 else 1)
