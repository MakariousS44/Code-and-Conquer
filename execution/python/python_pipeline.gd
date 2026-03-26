extends RefCounted

const Paths = preload("res://execution/shared/paths.gd")

var _compiler  = preload(Paths.PYTHON_COMPILER).new()
var _validator = preload(Paths.PYTHON_VALIDATOR).new()
var _commands  = preload(Paths.ROBOT_COMMANDS).new()

func _init() -> void:
	_compiler.api_source = _commands.get_python_api()

func validate(source: String) -> Dictionary:
	return _validator.validate(source)

func run(source: String) -> Dictionary:
	var result = _compiler.run(source)
	return {
		"ok":     result.success,
		"output": result.stdout if result.success else result.stderr
	}
