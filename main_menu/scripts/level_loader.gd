extends OptionButton

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
	print("Dropdown selected index: ", index)

	if index >= 0 and index < file_paths.size():
		SelectedLevel.path = file_paths[index]
		print("SelectedLevel.path updated from dropdown: ", SelectedLevel.path)

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
		if file_name.ends_with(".json"):
			var clean_name := file_name.get_basename()
			var full_path := path.path_join(file_name)
			var display_name := _read_level_name(full_path, clean_name)

			print("Adding level: ", display_name, " -> ", full_path)

			add_item(display_name)
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
		if file_paths[i] == path:
			select(i)
			SelectedLevel.path = path
			print("Dropdown re-selected path: ", path)
			return

	print("Path not found in dropdown: ", path)
