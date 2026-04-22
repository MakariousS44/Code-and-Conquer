extends OptionButton

var file_paths: Array[String] = []

const CUSTOM_LEVELS_DIR := "user://custom_levels/"


func _ready() -> void:
	print("=== DROPDOWN READY ===")
	print("Dropdown real folder path: ", ProjectSettings.globalize_path(CUSTOM_LEVELS_DIR))

	var real_custom_dir := ProjectSettings.globalize_path(CUSTOM_LEVELS_DIR)
	DirAccess.make_dir_recursive_absolute(real_custom_dir)

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

	var real_custom_dir := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(real_custom_dir)

	clear()
	file_paths.clear()

	add_item(" -- Select a world -- ")
	file_paths.append("")

	var dir := DirAccess.open(path)
	if dir == null:
		print("Could not open folder: ", path)
		SelectedLevel.path = ""
		select(0)
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

	select(0)
	SelectedLevel.path = ""


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
