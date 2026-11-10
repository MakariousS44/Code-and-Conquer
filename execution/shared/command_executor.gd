extends RefCounted

signal execution_finished

# Queue of commands waiting to be executed.
# Each command is a small dictionary describing an action.
var command_queue: Array = []

# Tracks whether a command sequence is currently running.
# Prevents multiple execution loops from starting at once.
var is_executing: bool = false

var cancelled: bool = false


func stop() -> void:
	# Hard-stop any pending execution sequence.
	command_queue.clear()
	is_executing = false


func execute(commands: Array, player_node: Node) -> void:
	# Entry point for executing a new set of commands.
	if player_node == null:
		return
	cancelled = false

	# Copy commands into the internal queue.
	command_queue = commands.duplicate()

	# Start execution if nothing is currently running.
	if not is_executing:
		_execute_next(player_node)
		
func cancel() -> void:
	cancelled = true
	command_queue.clear()
	is_executing = false

func _execute_next(player_node: Node) -> void:
	# Processes one command at a time, then schedules the next.
	if command_queue.is_empty() or not is_instance_valid(player_node):
		is_executing = false
		if not cancelled:
			execution_finished.emit()
		return

	is_executing = true

	# Get the next command from the front of the queue.
	var command = command_queue.pop_front()

	# Dispatch based on command type.
	var awaited_move := false
	match command.get("type", ""):
		"move":
			if player_node.has_method("move_forward"):
				if player_node.has_signal("move_finished"):
					# Wait for the full move (walk + any void fall) so queued
					# commands can't run before movement or loss handling ends.
					var move_done := [false]
					player_node.move_finished.connect(func(): move_done[0] = true, CONNECT_ONE_SHOT)
					player_node.move_forward()
					var waited := 0.0
					while is_instance_valid(player_node) and not move_done[0] and waited < 2.0:
						await player_node.get_tree().create_timer(0.05).timeout
						waited += 0.05
					if not move_done[0]:
						# Movement never finished; don't run later commands.
						is_executing = false
						if not cancelled:
							execution_finished.emit()
						return
					awaited_move = true
				else:
					player_node.move_forward()
		"turn_left":
			if player_node.has_method("turn_left"):
				player_node.turn_left()
		"turn_right":
			if player_node.has_method("turn_right"):
				player_node.turn_right()
		"front_is_clear":
			pass
		"pick_object":
			if player_node.has_method("pick_object"):
				player_node.pick_object()
		"put_object":
			if player_node.has_method("put_object"):
				player_node.put_object()

	# Use the player's own tree (inside SubViewport) for the timer.
	# Moves already waited on move_finished above.
	if not awaited_move:
		await player_node.get_tree().create_timer(0.5).timeout
	
	# check again, the player may have reset
	if not is_instance_valid(player_node) or not is_executing or cancelled:
		is_executing = false
		return

	if not is_executing:
		return

	# Continue processing remaining commands.
	_execute_next(player_node)
	
