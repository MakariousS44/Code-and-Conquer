extends Control

@onready var text_editor = $HBoxContainer/TextEdit
@onready var map_visuals = $HBoxContainer/MapVisuals

# You would preload your actual scenes here
var test_scene = preload("res://scene/example.tscn")
var tile_size = 64

func _ready():
	# Connect the typing signal to our parser function
	text_editor.text_changed.connect(_on_editor_text_changed)
	
	# Put some default JSON in the editor to start
	text_editor.text = '{"robot_start": {"x": 0, "y": 0}}'
	_on_editor_text_changed() # Draw the initial map

func _on_editor_text_changed():
	var current_text = text_editor.text
	
	# Godot 4 JSON parsing
	var json = JSON.new()
	var error = json.parse(current_text)
	
	if error == OK:
		# The user typed valid JSON! Let's draw it.
		var map_data = json.data
		draw_map(map_data)
	else:
		# The JSON is invalid (e.g., they are in the middle of typing a word).
		# We just do nothing and wait for them to finish the syntax!
		pass

func draw_map(data: Dictionary):
	# 1. Clear the old map completely
	for child in map_visuals.get_children():
		child.queue_free()
		
	# 2. Draw Walls
	if data.has("walls"):
		for wall_pos in data["walls"]:
			var new_wall = test_scene.instantiate()
			new_wall.position = Vector2(wall_pos["x"] * tile_size, wall_pos["y"] * tile_size)
			map_visuals.add_child(new_wall)
			
	# 3. Draw the Robot
	if data.has("robot_start"):
		var start_data = data["robot_start"]
		var new_robot = test_scene.instantiate()
		new_robot.position = Vector2(start_data["x"] * tile_size, start_data["y"] * tile_size)
		
		# Optional: Set rotation based on direction
		if start_data.has("direction"):
			if start_data["direction"] == "south": new_robot.rotation_degrees = 90
			elif start_data["direction"] == "west": new_robot.rotation_degrees = 180
			elif start_data["direction"] == "north": new_robot.rotation_degrees = 270
			
		map_visuals.add_child(new_robot)
