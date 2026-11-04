extends Window

signal level_selected(path: String)
signal custom_worlds_requested

const Campaign = preload("res://config/campaign_levels.gd")
var _list: VBoxContainer
var _progress: Label

func _ready() -> void:
	title = "Code & Conquer - Campaign"
	size = Vector2i(640, 520)
	min_size = Vector2i(520, 480)
	close_requested.connect(hide)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("172333")
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "YOUR FIRST CAMPAIGN"
	heading.add_theme_font_size_override("font_size", 26)
	column.add_child(heading)
	_progress = Label.new()
	column.add_child(_progress)
	var level_scroll := ScrollContainer.new()
	level_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	level_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(level_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_scroll.add_child(_list)
	var worlds := Button.new()
	worlds.text = "Custom Worlds & Test Templates"
	worlds.custom_minimum_size.y = 44
	worlds.pressed.connect(func():
		hide()
		custom_worlds_requested.emit())
	column.add_child(worlds)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(hide)
	column.add_child(back)

func show_campaign() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var completed := Campaign.completed_ids()
	var count := 0
	for i in range(Campaign.LEVELS.size()):
		var level: Dictionary = Campaign.LEVELS[i]
		var unlocked := Campaign.is_unlocked(i, completed)
		var state := "Ready" if unlocked else "Locked"
		if level.id in completed:
			state = "Completed"
			count += 1
		var button := Button.new()
		button.text = "%d. %s  -  %s\n%s" % [i + 1, level.title, state, level.concept]
		button.custom_minimum_size.y = 76
		button.add_theme_font_size_override("font_size", 20)
		button.disabled = not unlocked
		button.tooltip_text = "Complete the previous level to unlock." if not unlocked else "Play this level"
		button.pressed.connect(_select_level.bind(i))
		_list.add_child(button)
	_progress.text = "%d / %d levels completed. Your progress saves automatically." % [count, Campaign.LEVELS.size()]
	popup_centered()

func _select_level(index: int) -> void:
	if not Campaign.is_unlocked(index, Campaign.completed_ids()):
		return
	hide()
	level_selected.emit(Campaign.LEVELS[index].path)
