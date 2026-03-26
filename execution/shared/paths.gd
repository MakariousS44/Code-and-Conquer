extends RefCounted

# === execution paths ===
const EXECUTION_CPP     := "res://execution/cpp/"
const EXECUTION_PYTHON  := "res://execution/python/"
const EXECUTION_SHARED  := "res://execution/shared/"

# === map paths ===
const MAP_SCRIPTS       := "res://map/scripts/"
const MAP_SCENES        := "res://map/scenes/"

# === specific file paths ===
const CPP_VALIDATOR     := EXECUTION_CPP    + "cpp_validator.gd"
const CPP_GENERATOR     := EXECUTION_CPP    + "cpp_generator.gd"
const CPP_DRIVER        := EXECUTION_CPP    + "cpp_driver.gd"
const PYTHON_COMPILER   := EXECUTION_PYTHON + "python_compiler.gd"
const PYTHON_PIPELINE   := EXECUTION_PYTHON + "python_pipeline.gd"
const PYTHON_VALIDATOR  := EXECUTION_PYTHON + "python_validator.gd"
const COMMAND_TRANSLATOR := EXECUTION_SHARED + "command_translator.gd"
const COMMAND_EXECUTOR  := EXECUTION_SHARED + "command_executor.gd"
const ROBOT_COMMANDS    := EXECUTION_SHARED + "robot_commands.gd"
const MAP_LOADER        := MAP_SCRIPTS      + "map_loader.gd"
const MAP_VIEW_SCENE    := MAP_SCENES       + "map_view.tscn"
