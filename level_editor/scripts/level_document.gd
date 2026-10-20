class_name LevelDocument
extends RefCounted

var data: Dictionary = {}


func create_blank(cols: int = 10, rows: int = 10) -> void:
	data = {
		"cols": cols,
		"rows": rows,
		"robots": [
			{
				"x": 1,
				"y": 1,
				"_orientation": 0,
				"objects": {}
			}
		],
		"walls": {},
		"objects": {},
		"goal": {
			"possible_final_positions": [[cols, rows]],
			"objects": {}
		}
	}
