extends Node

# Define global signal for different scenes to communicate
@warning_ignore("unused_signal")
signal rotate_camera_right
@warning_ignore("unused_signal")
signal rotate_camera_left

# Emitted by player.gd whenever character facing direction changes
# facing_index: 0=east, 1=south, 2=west, 3=north
@warning_ignore("unused_signal")
signal player_facing_changed(facing_index: int)
