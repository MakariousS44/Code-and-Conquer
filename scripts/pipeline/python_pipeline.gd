extends RefCounted

var _validator = preload("res://scripts/pipeline/python_validator.gd").new()
var _compiler  = preload("res://scripts/pipeline/python_compiler.gd").new()

# Python API injected into the student's environment.
const ROBOT_API := """
def move():
    print("[CMD] MOVE")

def turn_left():
    print("[CMD] TURN_LEFT")

def turn_right():
    print("[CMD] TURN_RIGHT")

def pick_object():
    print("[CMD] PICK_OBJECT")

def put_object():
    print("[CMD] PUT_OBJECT")
"""

func _init() -> void:
	_compiler.api_source = ROBOT_API

func validate(source: String) -> Dictionary:
	return _validator.validate(source)

func run(source: String) -> Dictionary:
	var result = _compiler.run(source)
	return {
		"ok":     result.success,
		"output": result.stdout if result.success else result.stderr
	}
