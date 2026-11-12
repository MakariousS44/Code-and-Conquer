extends OptionButton
const Paths = preload("res://execution/shared/paths.gd")
var level_definition = load(Paths.MAP_LOADER).new()

var file_paths: Array[String] = []

# built in campaign levels
const CAMPAIGN_LEVELS_DIR := "res://data/campaign_levels/"
const PROJECT_CUSTOM_LEVELS_DIR := "res://data/custom_levels/"
const CUSTOM_LEVELS_DIR := "user://custom_levels/"


func _ready() -> void:
	print("=== DROPDOWN READY ===")
	print("Dropdown real folder path: ", ProjectSettings.globalize_path(CUSTOM_LEVELS_DIR))

	var real_custom_dir := ProjectSettings.globalize_path(CUSTOM_LEVELS_DIR)
	DirAccess.make_dir_recursive_absolute(real_custom_dir)

	if not item_selected.is_connected(_on_item_selected):
		item_selected.connect(_on_item_selected)
		
	populate_levels()
	#populate_from_folder(CUSTOM_LEVELS_DIR)



func _on_item_selected(index: int) -> void:
	if index <= 0 or index >= file_paths.size():
		SelectedLevel.path = ""
		return

	if is_item_disabled(index):
		SelectedLevel.path = ""
		select(0)
		return

	var path: String = file_paths[index]
	var result: Dictionary = level_definition.load(path)

	if not result.get("ok", false):
		SelectedLevel.path = ""
		select(0)
		push_warning("Cannot select invalid level: " + path)
		return

	SelectedLevel.path = path
	print("Selected level: ", path)

#rebuilds level dropdown
func populate_levels() -> void:
	print("=== POPULATING LEVELS ===")
	
	clear()
	file_paths.clear()

	add_item(" -- Select a world -- ")
	file_paths.append("")

	# add the levels that come with the game
	_add_levels_from_folder(CAMPAIGN_LEVELS_DIR)

	# load custom levels if needed
	_add_levels_from_folder(PROJECT_CUSTOM_LEVELS_DIR)
	_add_levels_from_folder(CUSTOM_LEVELS_DIR)
	
	print("Dropdown item count: ", item_count)

	select(0)
	SelectedLevel.path = ""

# add all JSON levels from the given folder
func _add_levels_from_folder(path: String) -> void:
	var dir := DirAccess.open(path)

	if dir == null:
		print("Could not open folder: ", path)
		return

	var files := dir.get_files()
	files.sort()

	for file_name in files:
		if not file_name.to_lower().ends_with(".json"):
			continue

		var clean_name := file_name.get_basename()
		var full_path := path.path_join(file_name)
		var display_name := _read_level_name(full_path, clean_name)

		var result: Dictionary = level_definition.load(full_path)
		var is_valid: bool = result.get("ok", false)

		var item_index: int = item_count

		if is_valid:
			add_item(display_name)
		else:
			add_item(display_name + " (Invalid)")
			set_item_disabled(item_index, true)
			set_item_tooltip(
				item_index,
				"This level file is invalid and cannot be played."
			)
			print("Disabled invalid level: ", full_path)
		
		if not is_valid:
			set_item_disabled(item_index, true)
			set_item_text(item_index, display_name + " (Invalid)")

		file_paths.append(full_path)


func _read_level_name(path: String, fallback: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return fallback
	return str(json.data.get("name", fallback))


func select_path(path: String) -> void:
	print("=== SELECTING PATH IN DROPDOWN ===")
	print("Requested path: ", path)

	for i in range(file_paths.size()):
		if file_paths[i] != path:
			continue

		if is_item_disabled(i):
			SelectedLevel.path = ""
			select(0)
			push_warning("Cannot select invalid level: " + path)
			return

		var result: Dictionary = level_definition.load(path)

		if not result.get("ok", false):
			SelectedLevel.path = ""
			select(0)
			push_warning("Level validation failed: " + path)
			return

		select(i)
		SelectedLevel.path = path
		print("Dropdown selected path: ", path)
		return

	print("Path not found in dropdown: ", path)
	SelectedLevel.path = ""
	select(0)
