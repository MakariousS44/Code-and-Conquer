extends Camera2D

# Camera Settings
var pan_speed = 500.0 # How fast the camera glides across the map
var zoom_step = Vector2(0.1, 0.1)
var min_zoom = Vector2(0.4, 0.4)
var max_zoom = Vector2(4.0, 4.0)

# _process runs every single frame to smoothly slide the camera
func _process(delta):
	# 1. Get the Arrow Key inputs (returns a vector like (1, 0) for Right)
	var pan_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# 2. Move the camera! 
	# We multiply by delta so it moves at the same speed on all computers.
	# We divide by zoom.x so the panning doesn't feel painfully slow when zoomed in.
	position += (pan_dir * pan_speed * delta) / zoom.x

# _unhandled_input waits for specific, one-off events like scrolling the mouse wheel
func _unhandled_input(event):
	if event is InputEventMouseButton and event.is_pressed():
	# Scrolling Up = Zoom In
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom += zoom_step
			
		# Scrolling Down = Zoom Out
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom -= zoom_step
		
	# Lock the zoom so it doesn't break our minimum or maximum limits
	zoom = zoom.clamp(min_zoom, max_zoom)
