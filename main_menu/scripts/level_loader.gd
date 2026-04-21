extends OptionButton

# full paths that correspond to the visible dropdown items
var file_paths: Array[String] = []

@export_dir var target_folder: String = "res://data/campaign_levels"

func _ready() -> void:
	if not item_selected.is_connected(_on_item_selected):
		item_selected.connect(_on_item_selected)
	populate_from_folder(target_folder)

func _on_item_selected(index: int) -> void:
	if index >= 0 and index < file_paths.size():
		SelectedLevel.path = file_paths[index]

func populate_from_folder(path: String) -> void:
	clear()
	file_paths.clear()

	var dir := DirAccess.open(path)

	if dir == null:
		print("An error occurred when trying to access the path: ", path)
		return

	var files := dir.get_files()
	files.sort()

	var current_dir := dir.get_current_dir()

	for file_name in files:
		if file_name.ends_with(".json"):
			var clean_name := file_name.get_basename()
			var full_path := current_dir.path_join(file_name)

			add_item(clean_name)
			file_paths.append(full_path)

	if file_paths.size() > 0:
		select(0)
		SelectedLevel.path = file_paths[0]
	else:
		print("No JSON files found in: ", path)
		SelectedLevel.path = ""
