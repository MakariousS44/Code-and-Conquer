extends RefCounted

# Only this exact import is allowed
const REQUIRED_IMPORT := "from robot import *"

const FORBIDDEN_WORDS := {
	"__import__": "Direct imports are not allowed.",
	"open": "File access is not allowed.",
	"exec": "exec() is not allowed.",
	"eval": "eval() is not allowed.",
	"compile": "compile() is not allowed.",
	"subprocess": "Subprocess access is not allowed.",
	"os.system": "System calls are not allowed.",
	"socket": "Networking is not allowed.",
	"__builtins__": "Accessing __builtins__ is not allowed.",
}

func validate(source: String) -> Dictionary:
	var errors: Array = []
	var lines := source.split("\n")
	var has_required_import := false

	for i in range(lines.size()):
		var line: String = lines[i]
		var trimmed := line.strip_edges()

		# Import statements: only the required one is allowed.
		if trimmed.begins_with("import ") or trimmed.begins_with("from "):
			if trimmed == REQUIRED_IMPORT:
				has_required_import = true
			else:
				errors.append({
					"line": i + 1,
					"column": 1,
					"message": "Import '%s' is not allowed. Only '%s' is permitted." % [trimmed, REQUIRED_IMPORT]
				})
			continue

		for word in FORBIDDEN_WORDS.keys():
			var idx := line.find(word)
			if idx != -1:
				errors.append({
					"line": i + 1,
					"column": idx + 1,
					"message": FORBIDDEN_WORDS[word]
				})

	if source.strip_edges().is_empty():
		errors.append({ "line": 1, "column": 1, "message": "Program is empty." })
	elif not has_required_import:
		errors.append({
			"line": 1,
			"column": 1,
			"message": "Missing required import: %s" % REQUIRED_IMPORT
		})

	return {
		"ok": errors.is_empty(),
		"errors": errors
	}
