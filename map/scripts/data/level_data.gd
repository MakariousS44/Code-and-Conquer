extends Resource
class_name LevelData

@export var rows: int = 10
@export var cols: int = 10
@export var player_spawn: PlayerSpawnData = PlayerSpawnData.new()
@export var wall_cells: Array = []
@export var marked_tiles: Array = []
@export var goal: GoalData = GoalData.new()
