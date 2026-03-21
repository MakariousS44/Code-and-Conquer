extends RefCounted

# Converts a Reeborg JSON world into your internal world format.
func convert(data: Dictionary) -> Dictionary:
	var result := {
		"width": data.get("cols", 10),
		"height": data.get("rows", 10),
		"player": {},
		"walls": []
	}

	# --- Player ---
	if data.has("robots") and data["robots"].size() > 0:
		var robot = data["robots"][0]

		result["player"] = {
			"x": robot.get("x", 1),
			"y": robot.get("y", 1),
			"facing": _map_orientation(robot.get("_orientation", 0))
		}

	# --- Walls ---
	if data.has("walls"):
		for key in data["walls"].keys():
			var parts = key.split(",")

			if parts.size() != 2:
				continue

			var x = int(parts[0])
			var y = int(parts[1])

			for dir in data["walls"][key]:
				result["walls"].append({
					"x": x,
					"y": y,
					"dir": dir
				})

	return result


func _map_orientation(o: int) -> String:
	match o:
		0: return "north"
		1: return "west"
		2: return "south"
		3: return "east"
		_: return "north"
