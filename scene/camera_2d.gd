extends Camera2D

var is_panning: bool = false

# We use _unhandled_input so we don't accidentally pan the camera
# when the player is trying to click and highlight text in the CodeEdit!
func _unhandled_input(event: InputEvent) -> void:
	
	# 1. Check if the player clicks or releases the Right Mouse Button
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# is_pressed() returns true when clicking down, and false when letting go
			is_panning = event.is_pressed()
			
	# 2. Check if the mouse is physically moving on the screen
	elif event is InputEventMouseMotion:
		# 3. If they are holding the button AND moving the mouse...
		if is_panning:
			# We subtract the relative movement to drag the world WITH the mouse.
			# We divide by zoom so the dragging feels 1:1 even if you zoom in/out later.
			position -= event.relative / zoom
