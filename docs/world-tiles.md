# World tiles and presentation

Use **Level Editor → Void Tile** to remove floor tiles. **Erase** restores them.
The robot start and finish must stay on solid floor. Placing a robot, goal, or
object on a gap restores its floor. Resizing removes gaps outside the new grid.

Levels store holes in an optional JSON object, using the same one-based coordinates
as walls and objects:

```json
"void_tiles": {
  "3,2": true,
  "4,2": true
}
```

Omitting `void_tiles` gives the original solid rectangular floor. Moving onto a
void tile triggers a fall and ends the run. The clear-path and wall sensors check
walls and grid boundaries only: a void tile inside the grid is reported as clear.
Players must plan around the visible gaps. Reports use `~` for missing floor.

Try **Custom Worlds → Void Crossing** for a bridge example, or load its JSON from
`data/custom_levels/VoidCrossing.json` in the level editor.

The world refits when its viewport changes size, when it rotates, and when the
next campaign level loads. Both views support holes. The editor fits larger grids
to the available space and its tools scroll on smaller screens.

Run checks with Godot:

```text
godot --headless --path . --script res://tests/world_features_test.gd
godot --headless --path . --script res://tests/campaign_test.gd
```

The feature test also accepts `-- --visual` when running with a renderer. It writes
screenshots to the temporary folder, or to `CODE_CONQUER_SCREENSHOTS` if set.
