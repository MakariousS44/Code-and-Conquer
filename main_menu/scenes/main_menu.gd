extends Control

# Keeps track of whether or not a given menu is open
@onready var OptionsOpen = false
@onready var LevelsOpen = false

# Select Level button behavior
func _on_button_start_pressed() -> void:
	$TabMoveSound.play()
	var tween = create_tween()
	# Tweens are used for all varieties of movement
	
	if LevelsOpen == false:	
		# These variables are used in conjunction with tween.tween_property to allow
		# for movement of elements.
		var duration = 1.0 # Time in seconds
		var distance = Vector2(-300, 0)  # Defines relative position to be moved. Coordinates
										# are pixels relative to top left of screen
		var target_pos = position + distance # Calculates absolute position to move to

		tween.tween_property($"MenuBG/LevelsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		LevelsOpen = true
	else:
		var duration = 1.0
		var distance = Vector2(-600, 0)
		var target_pos = position + distance

		tween.tween_property($"MenuBG/LevelsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		LevelsOpen = false
	
# Options button behavior
func _on_options_button_pressed() -> void:
	$TabMoveSound.play()
	var tween = create_tween()
	
	if OptionsOpen == false:	
		var duration = 1.0 
		var distance = Vector2(900, 0) 
		var target_pos = position + distance

		tween.tween_property($"MenuBG/OptionsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		OptionsOpen = true
	else:
		var duration = 1.0 
		var distance = Vector2(1200, 0)
		var target_pos = position + distance

		tween.tween_property($"MenuBG/OptionsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
		OptionsOpen = false
		


func _on_quit_button_pressed() -> void:
	$QuitSound.play()
	await get_tree().create_timer(2.0).timeout
	get_tree().quit()

# Play button behavior
func _on_play_button_pressed() -> void:
	$StartSound.play()
	var tween = create_tween()
	tween.set_parallel(true)
	# Tweens typically play one at a time, tween paralle is turned on
	# so that both the options and level menus may move off the screen
	# simultaneously
	
	var duration = 1.0
	var distance = Vector2(-600, 0)
	var target_pos = $"MenuBG/LevelsTab".position + distance
	tween.tween_property($"MenuBG/LevelsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
	
	duration = 1.0 
	distance = Vector2(400, 0)
	target_pos = $"MenuBG/OptionsTab".position + distance
	tween.tween_property($"MenuBG/OptionsTab", "position", target_pos, duration).set_trans(Tween.TRANS_SINE)
	
	tween.tween_property($Mask, "modulate:a", 0.0, 1.0) 
	# Tweens the alpha channel of the mask texture to 0 (full transparent) for
	# one second. Achieves a one second pause as the mask is already transparent.
	# Absolutely no idea why the below await function does not work here but this does
	
	tween.set_parallel(false)
	tween.tween_property($Mask, "modulate:a", 255.0, 1.2)
	# Tweens the alpha channel to the max value over 1.2 seconds

	await get_tree().create_timer(2.2).timeout
	get_tree().change_scene_to_file("res://workstation/scenes/workstation.tscn")
