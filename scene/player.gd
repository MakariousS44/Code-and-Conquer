extends CharacterBody2D

var speed = 300.0

func _physics_process(_delta):
	# 1. Get input and calculate movement
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = input_dir * speed

	# 2. Actually move the player
	move_and_slide()
	
# 3. Check for collisions that happened during move_and_slide
	for i in get_slide_collision_count():
		# Get the data of the crash
		var collision = get_slide_collision(i)
		# Get the actual object we hit
		var object_we_hit = collision.get_collider()

		# Check if the object has the "walls" name tag
		if object_we_hit.is_in_group("walls"):
			# queue_free() deletes the player node entirely!
			queue_free()
