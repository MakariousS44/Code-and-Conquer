class_name ObjectManager
extends RefCounted

var objects: Array = []

func get_objects_at(gx: int, gy: int) -> Array:
	var result: Array = []
	for obj in objects:
		if obj["grid_x"] == gx and obj["grid_y"] == gy:
			result.append(obj)
	return result


func get_pickable_at(gx: int, gy: int):
	for obj in objects:
		if obj["grid_x"] == gx and obj["grid_y"] == gy and obj.get("is_pickable", false):
			return obj
	return null


func has_pickable_at(gx: int, gy: int) -> bool:
	return get_pickable_at(gx, gy) != null


func remove_pickable_at(gx: int, gy: int):
	for obj in objects:
		if obj["grid_x"] == gx and obj["grid_y"] == gy and obj.get("is_pickable", false):
			objects.erase(obj)
			return obj
	return null


func remove_object(obj) -> void:
	objects.erase(obj)


func add_object(obj) -> void:
	objects.append(obj)
