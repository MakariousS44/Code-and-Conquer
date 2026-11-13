extends Node2D

var floor_layer: TileMapLayer

func _draw() -> void:
	if floor_layer == null:
		return
	draw_rect(Rect2(-100000, -100000, 200000, 200000), Color("0b1220"))
	var half := Vector2(floor_layer.tile_set.tile_size) * 0.5
	for cell in floor_layer.get_used_cells():
		var center := floor_layer.map_to_local(cell)
		var points := PackedVector2Array()
		for offset in [Vector2(-half.x, 0), Vector2(0, half.y), Vector2(half.x, 0)]:
			points.append(to_local(floor_layer.to_global(center + offset)))
		var depth := Vector2(0, 22)
		draw_colored_polygon(PackedVector2Array([points[0], points[1], points[1] + depth, points[0] + depth]), Color("172b3a"))
		draw_colored_polygon(PackedVector2Array([points[1], points[2], points[2] + depth, points[1] + depth]), Color("244553"))
		draw_polyline(PackedVector2Array([points[0] + depth, points[1] + depth, points[2] + depth]), Color("355c6b"), 2.0, true)
