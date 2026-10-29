extends RefCounted

# === level definition ===
# reads a JSON file from disk and returns a parsed level definition
# used by level_scene.gd to build the playable level
# this does NOT construct the scene, it only preps the data for building

func load(path: String) -> Dictionary:
	# make sure the file exists duh
	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"error": "Level file not found: %s" % path
		}

	var file := FileAccess.open(path, FileAccess.READ)

	# file exists but still failed to open somehow uh oh
	if file == null:
		return {
			"ok": false,
			"error": "could not open level file: %s" % path
		}

	var text := file.get_as_text()

	# parse JSON content
	var json := JSON.new()
	var parse_result := json.parse(text)

	if parse_result != OK:
		return {
			"ok": false,
			"error": "Invalid JSON in level file: %s" % path
		}

	var data = json.data

	# toplevel structure should be one object
	if typeof(data) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": "Level JSON must be an object."
		}

	var void_error := preload("res://map/scripts/void_tiles.gd").validate(data)
	if not void_error.is_empty():
		return {"ok": false, "error": void_error}
	return {
		"ok": true,
		"definition": data
	}
