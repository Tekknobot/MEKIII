# STORY MODE: SIGNAL 7 — Isometric campaign integration

The STORY button opens `scenes/story_mode.tscn`, an **inherited instance of `scenes/Game.tscn`**. The original campaign remains untouched when `story_mode_enabled` is false.

## What now uses the campaign systems
- Original TileMaps: Terrain, RoadsDL, RoadsDR, RoadsX (32×16 isometric tile size and atlas textures).
- Existing Structures node, isometric positioning, layered units and overlay nodes.
- MapController for move pathing, attack/ability execution, real zombies, and real playable rescued allies.
- TurnManager, player/enemy turns, turn controls, HUD and stackable ability buttons.
- The usual camera with an added exploration follow while in Story.

## World assembly
The map logic/grid is created once so pathfinding still functions. StoryDirector caches the four original TileMaps and clears just the *drawn* cells. It reveals each tile by animating an image drawn from that TileMap's existing atlas at that TileMap's map_to_local position, then places the real TileMap cell at the end of the drop. Buildings fade into view. Road positions are mapped through global space to avoid square-grid assumptions. Explored terrain persists.

## Objective and encounters
Start with one real soldier. Move with the normal campaign movement controls, attack, use specials and press End Turn. Explore to reveal terrain. Find five stranded units; stepping next to a marker recruits a fully playable allied Unit using its existing scene/abilities. Entering a previously unseen 6×6 region can create 2–3 zombies at walkable positions in the nearby explored area. They fade in after the terrain animation; a zombie still fading in does not act yet. Standard unlimited edge-spawn waves and campaign beacon deadline are disabled in Story.

## Scope / testing notes
- This is a Story Mode foundation, not a fully authored campaign with cutscenes or save checkpoints.
- Single-player only. Uses the existing TurnManager combat, **not free movement or free aiming**.
- The old `scripts/story_mode.gd` prototype (square sprites and real-time controls) is intentionally retired.
- This build has been checked for archive integrity and file references, but has **not** been run in the Godot editor. Test the opening reveal, character selection, turns, rescues and new encounters before distributing.

## Story road counts (Godot Inspector)
Open `scenes/story_mode.tscn`, select the root `Game`, and expand **Story Mode Roads**.
- `Story Vertical Roads`: number of full-length roads running along road-grid columns.
- `Story Horizontal Roads`: number of full-length roads running along road-grid rows.
- Defaults in Story Mode: **2 vertical, 2 horizontal**.
- Set either field to **0** to disable that direction; set both to 0 to make no roads.
- Counts are exact provided the requested number does not exceed available road lanes (for the current 30x30 terrain, each axis has 29 possible road lanes). They are spaced out rather than stacked at the same coordinate.
- The global `Enable Roads` switch must remain enabled. These story parameters do **not** change the regular campaign's random road generation.
- Story-only road discovery fades in supporting terrain first. It activates nearby roads only when the squad's natural exploration reaches them, preventing auto-reveal of the entire road network.
