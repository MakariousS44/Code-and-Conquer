extends OptionButton

var file_paths: Array[String] = []

const CUSTOM_LEVELS_DIR := "user://custom_levels/"

func _ready() -> void:
	print("=== DROPDOWN READY ===")
	print("Dropdown real folder path: ", ProjectSettings.globalize_path(CUSTOM_LEVELS_DIR))

	if not item_selected.is_connected(_on_item_selected):
		item_selected.connect(_on_item_selected)

	populate_from_folder(CUSTOM_LEVELS_DIR)

func _on_item_selected(index: int) -> void:
	print("Dropdown selected index: ", index)

	if index >= 0 and index < file_paths.size():
		SelectedLevel.path = file_paths[index]
		print("SelectedLevel.path updated from dropdown: ", SelectedLevel.path)

func populate_from_folder(path: String) -> void:
	print("=== POPULATING DROPDOWN ===")
	print("Virtual path: ", path)
	print("Real path: ", ProjectSettings.globalize_path(path))

	clear()
	file_paths.clear()

	var dir := DirAccess.open(path)
	if dir == null:
		print("Could not open folder: ", path)
		SelectedLevel.path = ""
		return

	var files := dir.get_files()
	files.sort()

	print("Files found: ", files)

	for file_name in files:
		if file_name.ends_with(".json"):
			var clean_name := file_name.get_basename()
			var full_path := path.path_join(file_name)

			print("Adding dropdown item: ", clean_name, " -> ", full_path)

			add_item(clean_name)
			file_paths.append(full_path)

	print("Dropdown item count: ", item_count)

	if file_paths.size() > 0:
		select(0)
		SelectedLevel.path = file_paths[0]
		print("Default selected path: ", SelectedLevel.path)
	else:
		print("No JSON files found in: ", path)
		SelectedLevel.path = ""
