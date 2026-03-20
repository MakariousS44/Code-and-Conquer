extends RefCounted

# Queue of commands waiting to be executed.
# Each command is a small dictionary describing an action.
var command_queue: Array = []

# Tracks whether a command sequence is currently running.
# Prevents multiple execution loops from starting at once.
var is_executing: bool = false

# Reference to the SceneTree so we can use timers.
# This is passed in from a Node since RefCounted does not have get_tree().
var scene_tree: SceneTree


func execute(commands: Array, player_node: Node, tree: SceneTree) -> void:
	# Entry point for executing a new set of commands.

	# If there is no player to act on, stop early.
	if player_node == null:
		return

	# Store the SceneTree reference for timing.
	scene_tree = tree

	# Copy commands into the internal queue.
	command_queue = commands.duplicate()

	# Start execution if nothing is currently running.
	if not is_executing:
		_execute_next(player_node)


func _execute_next(player_node: Node) -> void:
	# Processes one command at a time, then schedules the next.

	# If no commands remain, mark execution as finished.
	if command_queue.is_empty():
		is_executing = false
		return

	is_executing = true

	# Get the next command from the front of the queue.
	var command = command_queue.pop_front()

	# Dispatch based on command type.
	match command.get("type", ""):
		"move":
			if player_node.has_method("move_forward"):
				player_node.move_forward()

	# Wait briefly before executing the next command.
	# This creates visible step by step behavior instead of instant movement nice
	await scene_tree.create_timer(0.3).timeout

	# Continue processing remaining commands
	_execute_next(player_node)
