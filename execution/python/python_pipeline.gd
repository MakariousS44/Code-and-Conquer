extends RefCounted

const Paths = preload("res://execution/shared/paths.gd")

var _compiler  = preload(Paths.PYTHON_COMPILER).new()
var _validator = preload(Paths.PYTHON_VALIDATOR).new()


func validate(source: String) -> Dictionary:
	return _validator.validate(source)

func is_available() -> bool:
	return _compiler.is_available()

func prepare_sandbox_files(
	source: String,
	sandbox_path: String,
	ipc_endpoint: String
) -> Dictionary:
	return _compiler.prepare_sandbox_files(
		source,
		sandbox_path,
		ipc_endpoint
	)
