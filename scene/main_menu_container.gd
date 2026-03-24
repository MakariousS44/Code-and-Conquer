extends VBoxContainer

# The distance the whole container moves left
@export var move_distance: float = 800.0 
@export var animation_duration: float = 0.3 

# 1. This creates a list in the Inspector where you can drag and drop any nodes you want to move
@export var nodes_to_move: Array[Control]

# 2. A Dictionary to remember the starting position of EVERY node in that list
var original_positions: Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Loop through the list of nodes and save each of their starting positions
	for node in nodes_to_move:
		original_positions[node] = node.position


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_editor_button_pressed():
	var tween = create_tween()
	# 3. THIS IS MAGIC: It tells the tween to run all animations at the exact same time
	tween.set_parallel(true)
	for node in nodes_to_move:
		var target_x = original_positions[node].x - move_distance
		tween.tween_property(node, "position:x", target_x, animation_duration)\
				.set_trans(Tween.TRANS_SINE)\
				.set_ease(Tween.EASE_OUT)
