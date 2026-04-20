extends RefCounted

const Paths = preload("res://execution/shared/paths.gd")

var _compiler  = preload(Paths.PYTHON_COMPILER).new()
var _validator = preload(Paths.PYTHON_VALIDATOR).new()


func validate(source: String) -> Dictionary:
	return _validator.validate(source)

## Launches student code connecting to the given IPC port. Returns OS PID or -1
func start(source: String, port: int) -> int:
	return _compiler.start(source, port)
