extends RefCounted

# Converts raw runtime output from the compiled C++ program
# into structured data that the game can understand and act on.
func translate_runtime_output(raw_output: String) -> Dictionary:
	var commands: Array = []
	var normal_output_lines: Array = []
	var warnings: Array = []

	# Process output line by line.
	for line in raw_output.split("\n"):
		var cleaned := line.strip_edges()

		# Skip empty lines to keep things clean clean clean
		if cleaned == "":
			continue

		# Lines starting with [CMD] represent game actions
		if cleaned.begins_with("[CMD] "):
			var cmd := cleaned.trim_prefix("[CMD] ")

			# Map command strings to structured command objects
			match cmd:
				"MOVE":
					commands.append({"type": "move"})
				"TURN_LEFT":
					commands.append({"type": "turn_left"})
				"TURN_RIGHT":
					commands.append({"type": "turn_right"})
				"FRONT_IS_CLEAR":
					commands.append({"type": "front_is_clear"})
				"PICK_OBJECT":
					commands.append({"type": "pick_object"})
				"PUT_OBJECT":
					commands.append({"type": "put_object"})

				# If a command is not recognized yet, record a warning.
				_:
					warnings.append("Unknown command: %s" % cmd)

		# All other lines are treated as normal console output
		else:
			normal_output_lines.append(cleaned)

	# Return everything in a structured format.
	# This keeps translation separate from execution.
	return {
		"commands": commands,
		"normal_output_lines": normal_output_lines,
		"warnings": warnings
	}
