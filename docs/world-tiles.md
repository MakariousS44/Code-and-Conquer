## World tiles and presentation

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
void tile or off an open outside edge triggers a fall and ends the run. Clear-path
sensors retain the original wall and grid-boundary checks, but ignore void tiles
inside the grid. This preserves existing campaign sensor solutions.
Players must plan around the visible gaps. Reports use `~` for missing floor.

Campaign layouts and objectives are unchanged. Add holes to custom levels with
the Void Tile tool; stepping past an unprotected map edge also plays the fall.

Try **Custom Worlds → Void Crossing** for a bridge example, or load its JSON from
`data/custom_levels/VoidCrossing.json` in the level editor.

## Goal Configuration

The level editor supports advanced goal configuration to recreate campaign-level objectives:

### Object Requirements

Use **Goal Configuration → Set Goal Objects** to specify which tiles require specific objects to be placed. This opens a dialog where you can enter requirements in the format:

`x,y object_type count`

For example:

`6,4 token 5`

`1,5 apple 2`


This requires 5 tokens at tile (6,4) and 2 apples at tile (1,5). The level is only complete when all required objects are placed at their goal tiles.

### Carry Requirements

Use **Goal Configuration → Carry Requirement** to specify an object type that the robot must be carrying when reaching the goal. Options include:
- None (no carry requirement)
- Token
- Apple

The level is only complete if the robot is carrying the required object when it reaches the goal position.

### Visual Feedback

Goal object requirements are displayed as outlined markers on the grid. Unsatisfied requirements show in white, while satisfied requirements turn green when the required objects are placed.

## Campaign Level Compatibility

These features enable full recreation of campaign levels:
- Level 06: Uses carry requirement to ensure token is picked up
- Level 07: Requires 1 token to be delivered to goal tile
- Level 11: Requires 10 tokens to be delivered to goal tile
- Level 14: Requires 1 token at each of 8 different goal tiles

## Other

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
