extends RefCounted

# Carry requirement object names are interpolated into player-facing messages,
# so they are restricted to simple identifiers. This also keeps BBCode
# metacharacters out of RichTextLabel output.
static var _name_pattern: RegEx = null


static func is_valid_object_name(name: String) -> bool:
	if _name_pattern == null:
		_name_pattern = RegEx.new()
		_name_pattern.compile("^[A-Za-z0-9_-]+$")
	return _name_pattern.search(name) != null


static func _is_valid_count(value: Variant) -> bool:
	var value_type := typeof(value)
	if value_type != TYPE_INT and value_type != TYPE_FLOAT:
		return false
	var number := float(value)
	return number == floor(number) and number >= 0.0


# Strict check used when loading a level. Returns an error message, or "".
static func validate(data: Dictionary) -> String:
	var goal = data.get("goal", {})
	if not (goal is Dictionary):
		return ""
	var carry = goal.get("require_carry", {})
	if not (carry is Dictionary):
		return "Goal carry requirement must be an object of object names and counts."
	for object_name in carry:
		if not is_valid_object_name(str(object_name)):
			return "Invalid carry requirement object name: %s" % object_name
		if not _is_valid_count(carry[object_name]):
			return "Carry requirement counts must be non-negative integers: %s" % object_name
	var auto = goal.get("require_carry_auto", {})
	if not (auto is Dictionary):
		return "Goal carry auto requirements must be an object of object names and booleans."
	for object_name in auto:
		if not is_valid_object_name(str(object_name)):
			return "Invalid carry auto requirement object name: %s" % object_name
		if typeof(auto[object_name]) != TYPE_BOOL:
			return "Carry auto requirements must be booleans: %s" % object_name
	return ""


# Tolerant version for runtime use: keeps only valid {name: count} entries so a
# malformed level can never crash the win check or inject markup into messages.
static func normalize(requirement: Variant) -> Dictionary:
	var required := {}
	if not (requirement is Dictionary):
		return required
	for object_name in requirement:
		var name := str(object_name)
		if not is_valid_object_name(name) or not _is_valid_count(requirement[object_name]):
			continue
		var count := int(requirement[object_name])
		if count > 0:
			required[name] = count
	return required


static func normalize_auto(requirement: Variant) -> Dictionary:
	var auto := {}
	if not (requirement is Dictionary):
		return auto
	for object_name in requirement:
		var name := str(object_name)
		if is_valid_object_name(name) and typeof(requirement[object_name]) == TYPE_BOOL and requirement[object_name]:
			auto[name] = true
	return auto
