extends RefCounted

const FORBIDDEN_WORDS := {
	"import": "import statements are not allowed.",
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

	for i in range(lines.size()):
		var line: String = lines[i]

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

	return {
		"ok": errors.is_empty(),
		"errors": errors
	}
