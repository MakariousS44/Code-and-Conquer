# Script that populates a dropdown menu based on files in a folder
# Gemini spat this out at me without even asking me so thats sick

extends OptionButton

# Level path sent to workstation.gd
var file_paths = []

@export_dir var target_folder: String = "res://data/campaign_levels"

func _on_item_selected(index: int) -> void:
	LevelToLoad.level = file_paths[index]

func _ready():
	populate_from_folder(target_folder)

func populate_from_folder(path: String):
	var dir = DirAccess.open(path)
	
	if dir:
		# Get all files in the directory
		var files = dir.get_files()
		var current_dir = dir.get_current_dir()
		for file_name in files:
			if file_name.ends_with(".json"):
				## Option 1: Files contain file extension
				add_item(file_name)
				## Option 2: Remove file extension
				# var clean_name = file_name.get_basename() 
				# add_item(clean_name)
		for file_name in files:
			# Join directory path and filename
			var full_path = current_dir.path_join(file_name)
			file_paths.append(full_path)
		LevelToLoad.level = file_paths[0] # Load first level in list by default
	else:
		print("An error occurred when trying to access the path.")
