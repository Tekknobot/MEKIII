extends Node
class_name MapController

@export var terrain_path: NodePath
@export var units_root_path: NodePath
@export var overlay_root_path: NodePath

@export var ally_scenes: Array[PackedScene] = []
@export var enemy_zombie_scene: PackedScene

@export var move_tile_scene: PackedScene
@export var attack_tile_scene: PackedScene

var grid

var terrain: TileMap
var units_root: Node2D
var overlay_root: Node2D

var units_by_cell: Dictionary = {}  # Vector2i -> Unit
var selected: Unit = null

var game_ref: Node = null

enum AimMode { MOVE, ATTACK, SPECIAL }

var special_id: StringName = &""
var valid_special_cells: Dictionary = {} # Vector2i -> true

# --- Mines (logical) ---
var mines_by_cell: Dictionary = {} # Vector2i -> {"team": int, "damage": int}

var aim_mode: AimMode = AimMode.MOVE

@export var mouse_offset := Vector2(0, 8)

var valid_move_cells: Dictionary = {} # Vector2i -> true (for current selected)
@export var move_speed_cells_per_sec := 4.0

var _is_moving := false

@export var attack_flash_time := 0.10
@export var attack_anim_lock_time := 0.18   # small pause so attack feels visible

@export var max_zombies: int = 8
var _start_max_zombies := 8
@export var ally_count: int = 3

@export var turn_manager_path: NodePath
@onready var TM: TurnManager = get_node_or_null(turn_manager_path) as TurnManager

signal selection_changed(unit: Unit)
signal aim_changed(mode: int, special_id: StringName)

@export var explosion_scene: PackedScene

@export var explosion_y_offset_px := -16.0
@export var explosion_anim_name := "explode"
@export var explosion_fallback_seconds := 9.0

@export var mine_scene: PackedScene
@export var mine_y_offset_px := -16.0

var mine_nodes_by_cell: Dictionary = {} # Vector2i -> Node2D

# --------------------------
# SFX (simple dispatcher)
# --------------------------
@export var sfx_player_path: NodePath
@onready var SFX := get_node_or_null(sfx_player_path)

# Optional: volume scalars if you want
@export var sfx_volume_ui := 0.8
@export var sfx_volume_world := 1.0

# Assign in Inspector: { "ui_select": <AudioStream>, "attack_swing": <AudioStream>, ... }
@export var sfx_streams: Dictionary = {}

# --------------------------
# Structures (damage + explode)
# --------------------------
@export var structure_hit_damage := 1                 # damage per explosion hit
@export var structure_flash_time := 0.8
@export var structure_splash_radius := 1              # cells
@export var structure_explosion_splash_damage := 1    # damage to units in splash
@export var structure_demolished_anim := "demolished" # animation name to play on death

# Optional: if your structures are tagged in a group, set it here. Leave blank to scan all children.
@export var structure_group_name := "Structures"

@export var tnt_splash_radius := 1              # cells (Manhattan)
@export var tnt_structure_damage := 2           # per TNT hit to structures
@export var tnt_unit_splash_damage := 2         # per TNT hit to units (or set from your TNT item)

# --------------------------
# Speech bubbles
# --------------------------
@export var bubble_enabled := true
@export var bubble_duration := 0.75
@export var bubble_fade_time := 0.12
@export var bubble_y_offset_px := -52.0   # above unit
@export var bubble_min_width := 90.0

# Lines (edit in Inspector)
@export var ally_lines: Array[String] = [
	"On it!",
	"Moving!",
	"Here We go!",
	"Copy that.",
	"Advancing!"
]

@export var ally_select_lines: Array[String] = [
	"Awaiting orders.",
	"Ready.",
	"Standing by.",
	"Yes, sir.",
	"Command?"
]

@export var enemy_lines: Array[String] = [
	"GRRR!",
	"RAAAH!",
	"Fresh meat!",
	"....",
	"HSSSS!"
]

# Track 1 bubble per unit (prevents spam)
var _bubble_by_unit: Dictionary = {} # Unit -> CanvasItem
# Speech bubbles (UI)
@export var bubble_ui_root_path: NodePath   # assign to a Control under a CanvasLayer (ex: /root/MapManager/UILayer/Bubbles)
@onready var bubble_ui_root: Control = get_node_or_null(bubble_ui_root_path) as Control

@export var bubble_font: Font               # drag your .ttf/.otf or FontFile here
@export var bubble_font_size := 14

@export var bubble_board_color := Color(1, 1, 1, 0.95)  # white board
@export var bubble_text_color := Color(1, 1, 1, 1.0)     # white font
@export var bubble_type_speed_cps := 40.0                # chars per second
@export var bubble_max_width := 180.0                    # wrap width (px)

@export var bubble_voice_player_path: NodePath
@onready var bubble_voice_player := get_node_or_null(bubble_voice_player_path) as AudioStreamPlayer

@export var bubble_voice_stream: AudioStream  # assign a short "blip" wav/ogg (20–80ms)
@export var bubble_voice_volume := 0.65
@export var bubble_voice_pitch_base := 1.0
@export var bubble_voice_pitch_jitter := 0.12
@export var bubble_voice_space_chance := 0.15
@export var bubble_voice_punct_chance := 0.55
@export var bubble_voice_bus := "Master"

# --- Overwatch ---
var overwatch_by_unit: Dictionary = {}  # Unit -> {"range": int}

@export var sfx_overwatch_on := &"ui_overwatch_on"
@export var sfx_overwatch_shot := &"overwatch_shot"

var overwatch_ghost_by_unit: Dictionary = {} # Unit -> Node2D
@export var overwatch_ghost_offset := Vector2(0, -26)
@export var overwatch_ghost_color := Color(0.2, 1.0, 1.0, 0.65)

# --- Overlay sub-roots (so _clear_overlay doesn't nuke ghosts) ---
var overlay_tiles_root: Node2D = null
var overlay_ghosts_root: Node2D = null

# -----------------------------------
# Turn indicators (tint + pulse)
# -----------------------------------
@export var tint_move_left := Color(0.80, 0.95, 1.00, 1.0)      # bluish
@export var tint_attack_left := Color(1.00, 0.92, 0.75, 1.0)    # warm
@export var tint_exhausted := Color(0.55, 0.55, 0.55, 1.0)      # dark gray
@export var pulse_scale := 1.08
@export var pulse_time := 0.22

@export var enemy_fade_time := 1.6

@export var ringout_push_px := 16.0          # how far to shove off-map visually
@export var ringout_push_time := 0.18        # shove duration
@export var ringout_fade_time := 0.22        # optional fade out after shove
@export var ringout_drop_px := 10.0          # optional little drop while leaving

@export var recruit_enabled: bool = true
@export var recruit_once_per_structure_per_round: bool = true
@export var recruit_fade_time: float = 1.55
@export var recruit_sfx: StringName = &"recruit_spawn"
var recruit_round_stamp: int = 0

@export var recruit_bot_scene: PackedScene   # drag RecruitBot.tscn here

@export var sfx_missile_launch := &"missile_launch"
@export var sfx_missile_whizz := &"missile_whizz" # optional
@export var missile_line_alpha_start := 0.85
@export var missile_line_alpha_end := 0.10

# --- Pickups (logical) ---
var pickups_by_cell: Dictionary = {} # Vector2i -> Node (pickup instance)
signal pickup_collected(u: Unit, cell: Vector2i)

@export var floppy_pickup_scene: PackedScene
@export var beacon_parts_needed := 3
var beacon_parts_collected := 0

@export var beacon_cell := Vector2i(7, 7) # set in inspector or choose at runtime
var beacon_ready := false

@export var beacon_marker_scene: PackedScene   # assign BeaconMarker.tscn (Node2D) in Inspector
@export var beacon_marker_y_offset_px := -8.0
@export var beacon_marker_z_base := 2          # above terrain, below units if you want
var beacon_marker_node: Node2D = null
var _beacon_sweep_started := false

@export var sat_beam_height_px := 600.0     # how far "space" is above the map
@export var sat_beam_flash_time := 0.06     # how long beam stays visible
@export var sat_beam_fade_time := 0.10      # fade-out duration
@export var sat_beam_z_boost := 100000      # ensure beam is above everything

var _beacon_pulse_tw: Tween = null

@export var beacon_pulse_min_a := 0.25
@export var beacon_pulse_max_a := 1.0
@export var beacon_pulse_time := 0.35

func _sfx(cue: StringName, vol := 1.0, pitch := 1.0, world_pos: Variant = null) -> void:
	if SFX == null:
		return

	# ✅ If SFX is just an AudioStreamPlayer(2D/3D): do one-shot spawn so sounds can overlap.
	if (SFX is AudioStreamPlayer) or (SFX is AudioStreamPlayer2D) or (SFX is AudioStreamPlayer3D):
		var stream := sfx_streams.get(String(cue), null) as AudioStream
		if stream == null:
			return

		var p: Node
		if SFX is AudioStreamPlayer:
			p = AudioStreamPlayer.new()
		elif SFX is AudioStreamPlayer3D:
			p = AudioStreamPlayer3D.new()
		else:
			p = AudioStreamPlayer2D.new()

		# Common setup
		p.stream = stream
		p.pitch_scale = max(0.01, float(pitch))
		p.volume_db = linear_to_db(clamp(float(vol), 0.0, 2.0))
		p.bus = SFX.bus

		# Position only for spatial players
		if p is AudioStreamPlayer2D:
			(p as AudioStreamPlayer2D).global_position = (world_pos if (world_pos is Vector2) else (SFX as AudioStreamPlayer2D).global_position)
		elif p is AudioStreamPlayer3D:
			# If you ever use 3D, you can pass Vector3. Otherwise it’ll just use SFX position.
			(p as AudioStreamPlayer3D).global_position = (SFX as AudioStreamPlayer3D).global_position

		SFX.add_child(p)

		# Free after play
		p.finished.connect(func():
			if p != null and is_instance_valid(p):
				p.queue_free()
		)

		p.play()
		return

	# ✅ Otherwise, treat SFX as a custom "manager" node
	if SFX.has_method("play_sfx_poly"):
		SFX.call("play_sfx_poly", String(cue), float(vol), float(pitch))
		return
	if SFX.has_method("play_sfx"):
		SFX.call("play_sfx", String(cue), float(vol), float(pitch))
		return
	if SFX.has_method("play_named"):
		SFX.call("play_named", String(cue), float(vol), float(pitch))
		return
	if SFX.has_method("play"):
		# Custom manager might accept a cue name
		SFX.call("play", String(cue))
		return

var _pulse_tw_by_unit: Dictionary = {} # Unit -> Tween

func _apply_turn_indicator(u: Unit) -> void:
	if u == null or not is_instance_valid(u): return
	if u.team != Unit.Team.ALLY: return

	var moved := _unit_has_moved(u)
	var attacked := _unit_has_attacked(u)

	var has_move_left := not moved
	var has_attack_left := not attacked

	if (not has_move_left) and (not has_attack_left):
		_set_unit_tint(u, tint_exhausted)
		_stop_pulse(u)
		return

	# both left: your choice — I’d pulse + warm tint (feels “ready”)
	if has_move_left and has_attack_left:
		_set_unit_tint(u, Color(1,1,1,1)) # or pick a special “ready” tint
		_start_pulse(u)
		return

	if has_attack_left:
		_set_unit_tint(u, tint_attack_left)
		_start_pulse(u)
	else:
		_set_unit_tint(u, tint_move_left)
		_stop_pulse(u)

func _apply_turn_indicators_all_allies() -> void:
	for u in get_all_units():
		if u != null and is_instance_valid(u) and u.team == Unit.Team.ALLY:
			_apply_turn_indicator(u)

func _set_unit_tint(u: Unit, tint: Color) -> void:
	# Tint the first render CanvasItem we can find
	var ci: CanvasItem = _get_unit_render_node(u)
	if ci != null and is_instance_valid(ci):
		ci.modulate = tint

func _start_pulse(u: Unit) -> void:
	_stop_pulse(u)

	var visual := _get_unit_visual_node(u)
	if visual == null or not is_instance_valid(visual):
		return

	# Store base scale so we always return cleanly
	if not visual.has_meta("pulse_base_scale"):
		visual.set_meta("pulse_base_scale", visual.scale)

	var base_scale: Vector2 = visual.get_meta("pulse_base_scale")
	visual.scale = base_scale

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.set_loops()

	tw.tween_property(visual, "scale", base_scale * pulse_scale, pulse_time)
	tw.tween_property(visual, "scale", base_scale, pulse_time)

	_pulse_tw_by_unit[u] = tw

func _stop_pulse(u: Unit) -> void:
	if _pulse_tw_by_unit.has(u):
		var tw = _pulse_tw_by_unit[u]
		_pulse_tw_by_unit.erase(u)
		if tw != null and (tw is Tween) and is_instance_valid(tw):
			(tw as Tween).kill()

	var visual := _get_unit_visual_node(u)
	if visual != null and is_instance_valid(visual) and visual.has_meta("pulse_base_scale"):
		visual.scale = visual.get_meta("pulse_base_scale")

func _ready() -> void:
	_start_max_zombies = max_zombies
	# --------------------------
	# Speech blip audio setup
	# --------------------------
	if bubble_voice_player == null or not is_instance_valid(bubble_voice_player):
		bubble_voice_player = AudioStreamPlayer.new()
		bubble_voice_player.name = "BubbleVoicePlayer"
		bubble_voice_player.bus = bubble_voice_bus
		add_child(bubble_voice_player)
	
	add_to_group("MapController")
	pickup_collected.connect(_on_pickup_collected)
		
	terrain = get_node_or_null(terrain_path) as TileMap
	units_root = get_node_or_null(units_root_path) as Node2D
	overlay_root = get_node_or_null(overlay_root_path) as Node2D

	if terrain == null:
		push_error("MapController: terrain_path not set or invalid.")
	if units_root == null:
		push_error("MapController: units_root_path not set or invalid. Add a Node2D named 'Units' and assign it.")
	if overlay_root == null:
		push_error("MapController: overlay_root_path not set or invalid. Add a Node2D named 'Overlays' and assign it.")
	if ally_scenes.is_empty():
		push_error("MapController: ally_scenes is empty. Add 3 ally scenes in Inspector.")
	else:
		for i in range(ally_scenes.size()):
			if ally_scenes[i] == null:
				push_error("MapController: ally_scenes[%d] is null." % i)
	if enemy_zombie_scene == null:
		push_error("MapController: enemy_zombie_scene is not assigned in Inspector.")
	if move_tile_scene == null:
		push_warning("MapController: move_tile_scene is not assigned (move overlay won't show).")
	if attack_tile_scene == null:
		push_warning("MapController: attack_tile_scene is not assigned (attack overlay won't show).")

	overlay_root = get_node_or_null(overlay_root_path) as Node2D
	_ensure_overlay_subroots()
	_ensure_beacon_marker()
	
func setup(game) -> void:
	game_ref = game
	grid = game.grid

func spawn_units() -> void:
	if terrain == null or units_root == null or grid == null:
		return

	clear_all()
	reset_beacon_state()
	recruit_round_stamp += 1
	_randomize_beacon_cell()
	
	# Structure-blocked cells from Game
	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	# --- Build list of all valid walkable + unblocked cells ---
	var valid_cells: Array[Vector2i] = []
	var w := int(grid.w)
	var h := int(grid.h)

	for x in range(w):
		for y in range(h):
			var c := Vector2i(x,y)
			if not _is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			valid_cells.append(c)

	if valid_cells.is_empty():
		return

	# ---------------------------------------------------
	# 1) Pick a random "ally cluster center"
	# ---------------------------------------------------
	var cluster_center = valid_cells.pick_random()

	# Sort valid cells by distance to cluster center
	valid_cells.sort_custom(func(a:Vector2i, b:Vector2i) -> bool:
		var da = abs(a.x - cluster_center.x) + abs(a.y - cluster_center.y)
		var db = abs(b.x - cluster_center.x) + abs(b.y - cluster_center.y)
		return da < db
	)

	# --- Spawn allies close together BUT spaced by 1 tile ---
	# Build a "near" list (already sorted by distance) and pick cells that aren't adjacent.
	var near := valid_cells.duplicate()
	var used: Array[Vector2i] = []

	for i in range(min(ally_scenes.size(), near.size())):
		var chosen := Vector2i(-1, -1)

		# Find the first cell that is NOT adjacent to any already chosen ally cell
		for idx in range(near.size()):
			var cand = near[idx]
			var ok := true
			for ucell in used:
				var dx = abs(cand.x - ucell.x)
				var dy = abs(cand.y - ucell.y)
				# Block adjacency including diagonals (Chebyshev distance <= 1)
				if max(dx, dy) <= 1:
					ok = false
					break
			if ok:
				chosen = cand
				near.remove_at(idx)
				break

		# Fallback if we couldn't find a spaced cell (rare on tiny maps)
		if chosen.x < 0:
			chosen = near.pop_front()

		used.append(chosen)
		_spawn_specific_ally(chosen, ally_scenes[i])

	# Remove chosen ally cells from valid_cells so enemies don't spawn there
	for c in used:
		var k := valid_cells.find(c)
		if k != -1:
			valid_cells.remove_at(k)

	# ---------------------------------------------------
	# 2) Zombies: far zone + clusters
	# ---------------------------------------------------
	var enemy_center := _pick_far_center(valid_cells, cluster_center)

	# Build an enemy-zone pool near enemy_center (tweak radius)
	var enemy_zone_radius := 16
	var enemy_zone_cells := _cells_within_radius(valid_cells, enemy_center, enemy_zone_radius)

	# If the zone is too small, fall back to all remaining valid cells
	if enemy_zone_cells.size() < max_zombies:
		enemy_zone_cells = valid_cells.duplicate()

	_spawn_zombies_in_clusters(enemy_zone_cells, max_zombies)

	print("Spawned allies:", ally_count, "zombies:", max_zombies)

	# ✅ Now that units exist, auto-select + update buttons
	if TM != null and TM.has_method("on_units_spawned"):
		TM.on_units_spawned()

	_ensure_beacon_marker()

func _pick_far_center(cells: Array[Vector2i], from_center: Vector2i) -> Vector2i:
	if cells.is_empty():
		return Vector2i(-1, -1)

	var best := cells[0]
	var best_d := -1
	for c in cells:
		var d = abs(c.x - from_center.x) + abs(c.y - from_center.y)
		if d > best_d:
			best_d = d
			best = c
	return best


func _cells_within_radius(cells: Array[Vector2i], center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		var d = abs(c.x - center.x) + abs(c.y - center.y)
		if d <= r:
			out.append(c)
	return out


func _spawn_zombies_in_clusters(zone_cells: Array[Vector2i], total: int) -> void:
	if total <= 0 or zone_cells.is_empty():
		return

	zone_cells.shuffle()

	# Build multiple clusters, but keep spawning until we hit TOTAL
	var remaining := total
	var max_cluster_size := 4  # tweak: bigger = tighter blobs

	while remaining > 0 and not zone_cells.is_empty():
		# pick an anchor
		var anchor = zone_cells.pop_back()
		_spawn_unit_walkable(anchor, Unit.Team.ENEMY)
		remaining -= 1
		if remaining <= 0:
			break

		# decide how many more for this cluster
		var want = min(remaining, randi_range(1, max_cluster_size - 1))

		# pick nearest cells to anchor from remaining pool
		var near := _neighbors_sorted_by_distance(zone_cells, anchor, 6)

		while want > 0 and not near.is_empty():
			var c = near.pop_front()
			_spawn_unit_walkable(c, Unit.Team.ENEMY)
			remaining -= 1
			want -= 1

			# remove from zone pool so it can't be used again
			var idx := zone_cells.find(c)
			if idx != -1:
				zone_cells.remove_at(idx)

			if remaining <= 0:
				break


func _neighbors_sorted_by_distance(cells: Array[Vector2i], anchor: Vector2i, max_r: int) -> Array[Vector2i]:
	var near: Array[Vector2i] = []
	for c in cells:
		var d = abs(c.x - anchor.x) + abs(c.y - anchor.y)
		if d > 0 and d <= max_r:
			near.append(c)

	near.sort_custom(func(a:Vector2i, b:Vector2i) -> bool:
		var da = abs(a.x - anchor.x) + abs(a.y - anchor.y)
		var db = abs(b.x - anchor.x) + abs(b.y - anchor.y)
		return da < db
	)
	return near

func _spawn_specific_ally(preferred: Vector2i, scene: PackedScene) -> void:
	var c := _find_nearest_open_walkable(preferred)
	if c.x < 0:
		push_warning("MapController: no WALKABLE open land found near %s" % [preferred])
		return

	if scene == null:
		push_error("MapController: ally scene is null.")
		return

	var inst := scene.instantiate()
	var u := inst as Unit
	if u == null:
		push_error("MapController: ally scene root is not a Unit.")
		return

	units_root.add_child(u)
	_wire_unit_signals(u)
	
	u.team = Unit.Team.ALLY
	u.hp = u.max_hp
	u.set_cell(c, terrain)
	units_by_cell[c] = u

	print("Spawned ALLY", scene.resource_path.get_file(), "at", c)

func clear_all() -> void:
	if units_root:
		for ch in units_root.get_children():
			ch.queue_free()
	units_by_cell.clear()
	_clear_overlay()
	selected = null

	for n in mine_nodes_by_cell.values():
		if n != null and is_instance_valid(n):
			n.queue_free()
	mine_nodes_by_cell.clear()
	mines_by_cell.clear()
	_clear_beacon_marker()

func _spawn_unit_walkable(preferred: Vector2i, team: int) -> void:
	var c := _find_nearest_open_walkable(preferred)
	if c.x < 0:
		push_warning("MapController: no WALKABLE open land found near %s" % [preferred])
		return

	var scene: PackedScene

	if team == Unit.Team.ALLY:
		if ally_scenes.is_empty():
			push_error("MapController: ally_scenes is empty.")
			return
		scene = ally_scenes.pick_random()
	else:
		scene = enemy_zombie_scene
		if scene == null:
			push_error("MapController: enemy_zombie_scene not assigned.")
			return

	var inst := scene.instantiate()
	var u := inst as Unit
	if u == null:
		push_error("MapController: scene root is not a Unit (must extend Unit).")
		return

	units_root.add_child(u)
	_wire_unit_signals(u)
	
	u.team = team
	u.hp = u.max_hp

	u.set_cell(c, terrain)
	units_by_cell[c] = u

	print("Spawned", ("ALLY" if team == Unit.Team.ALLY else "ZOMBIE"), "at", c, "world", u.global_position)

# --------------------------
# Walkable + placement search
# --------------------------
func _is_walkable(c: Vector2i) -> bool:
	if grid == null or not grid.has_method("in_bounds"):
		return false
	if not grid.in_bounds(c):
		return false
	# T_WATER == 5 in your Game
	return grid.terrain[c.x][c.y] != 5

func _find_nearest_open_walkable(start: Vector2i) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)

	var w := int(grid.w) if "w" in grid else 0
	var h := int(grid.h) if "h" in grid else 0
	if w <= 0 or h <= 0:
		return Vector2i(-1, -1)

	var best := Vector2i(-1, -1)
	var best_d := 999999

	for x in range(w):
		for y in range(h):
			var c := Vector2i(x, y)
			if not _is_walkable(c):
				continue
			if units_by_cell.has(c):
				continue
			var d = abs(start.x - c.x) + abs(start.y - c.y)
			if d < best_d:
				best_d = d
				best = c

	return best

# --------------------------
# Input: select + attack
# --------------------------
func _unhandled_input(event: InputEvent) -> void:
	if _is_moving:
		return

	if event is InputEventMouseButton and event.pressed:
		# Right click = ATTACK mode (arm)
		if event.button_index == MOUSE_BUTTON_RIGHT:
			# Toggle attack preview on/off
			if aim_mode == AimMode.ATTACK:
				_set_aim_mode(AimMode.MOVE)
				_refresh_overlays()
			else:
				_set_aim_mode(AimMode.ATTACK)
				_refresh_overlays()
				_sfx(&"ui_arm_attack", sfx_volume_ui, 1.0)
			return


		# Only left click below
		if event.button_index != MOUSE_BUTTON_LEFT:
			return

		var cell := _mouse_to_cell()
		if cell.x < 0:
			_unselect()
			return

		var clicked := unit_at_cell(cell)

		# If nothing selected yet: left click selects (MOVE mode)
		if selected == null:
			aim_mode = AimMode.MOVE
			if clicked != null:
				_select(clicked)
			return

		# -------------------------
		# ATTACK MODE: left click attacks OR selects friendlies
		# -------------------------
		if aim_mode == AimMode.ATTACK:
			if selected == null or not is_instance_valid(selected):
				_set_aim_mode(AimMode.MOVE)
				return

			# ✅ NEW: allow selecting other ALLIES while in attack mode
			if clicked != null and is_instance_valid(clicked) and clicked.team == selected.team:
				_select(clicked)              # selection_changed + refresh_overlays happens inside
				_set_aim_mode(AimMode.MOVE)   # optional: makes selection feel normal
				return

			# Gate phase + per-turn attack
			if TM != null:
				if not TM.player_input_allowed() or not TM.can_attack(selected):
					_set_aim_mode(AimMode.MOVE)
					return

			# Enemy in range -> attack
			if clicked != null and is_instance_valid(clicked) and clicked.team != selected.team and _in_attack_range(selected, clicked.cell):
				if _unit_has_attacked(selected):
					_sfx(&"ui_denied", sfx_volume_ui, 1.0)
					_set_aim_mode(AimMode.MOVE)
					return

				await _do_attack(selected, clicked)
				_set_unit_attacked(selected, true)
				_apply_turn_indicator(selected)

				if TM != null and TM.has_method("notify_player_attacked"):
					TM.notify_player_attacked(selected)

			# ✅ Always cancel attack preview on ANY left-click that didn't select a friendly
			_set_aim_mode(AimMode.MOVE)
			return

		# -------------------------
		# SPECIAL MODE: left click uses special, never moves
		# -------------------------
		if aim_mode == AimMode.SPECIAL:
			if selected == null or not is_instance_valid(selected):
				_set_aim_mode(AimMode.MOVE)
				return

			var u := selected

			# Gate phase + special counts as attack action
			if TM != null:
				if not TM.player_input_allowed() or not TM.can_attack(u):
					_set_aim_mode(AimMode.MOVE)
					return

			# Only fire if clicked a valid special cell
			if valid_special_cells.has(cell):
				await _perform_special(u, String(special_id), cell)

				_set_unit_attacked(u, true)
				_apply_turn_indicator(u)
				if TM != null and TM.has_method("notify_player_attacked"):
					TM.notify_player_attacked(u)

			# ✅ Always exit special mode on left-click (even if invalid cell)
			_set_aim_mode(AimMode.MOVE)
			return


			aim_mode = AimMode.MOVE
			special_id = &""
			_refresh_overlays()
			emit_signal("aim_changed", int(aim_mode), special_id)
			return

		# -------------------------
		# MOVE MODE behavior (ALLIES ONLY)
		# -------------------------
		if _is_valid_move_target(cell):
			# ✅ only player-controlled allies can move via clicks
			if selected == null or not is_instance_valid(selected) or selected.team != Unit.Team.ALLY:
				_sfx(&"ui_denied", sfx_volume_ui, 1.0) # optional
				return
			_move_selected_to(cell)
			return

		if clicked != null:
			if clicked == selected:
				_refresh_overlays()
				emit_signal("aim_changed", int(aim_mode), special_id)
				return
			_select(clicked)
			return

		_unselect()

func _perform_special(u: Unit, id: String, target_cell: Vector2i) -> void:
	if u == null or not is_instance_valid(u):
		return

	id = id.to_lower()

	_is_moving = true
	_clear_overlay()

	# -------------------------
	# Mark cooldowns (ONLY here)
	# -------------------------
	if u.has_method("mark_special_used"):
		if id == "hellfire":
			u.mark_special_used(id, 2)
		elif id == "blade":
			u.mark_special_used(id, 2)
		elif id == "mines":
			u.mark_special_used(id, 1)
		elif id == "overwatch":
			u.mark_special_used(id, 2)
		elif id == "suppress":
			u.mark_special_used(id, 1)
		elif id == "stim" and u.has_method("perform_stim"):
			await u.call("perform_stim", self)
			
	# -------------------------
	# Execute special
	# -------------------------
	if id == "hellfire" and u.has_method("perform_hellfire"):
		await u.call("perform_hellfire", self, target_cell)

	elif id == "blade" and u.has_method("perform_blade"):
		await u.call("perform_blade", self, target_cell)

	elif id == "mines" and u.has_method("perform_place_mine"):
		await u.call("perform_place_mine", self, target_cell)

	elif id == "overwatch" and u.has_method("perform_overwatch"):
		await u.call("perform_overwatch", self)

	elif id == "suppress" and u.has_method("perform_suppress"):
		await u.call("perform_suppress", self, target_cell)

	elif id == "stim" and u.has_method("perform_stim"):
		u.mark_special_used(id, 3)

	_is_moving = false

func _mouse_to_cell() -> Vector2i:
	if terrain == null:
		return Vector2i(-1, -1)

	# ✅ Match GridCursor math exactly
	var mouse_global := get_viewport().get_mouse_position()
	mouse_global = get_viewport().get_canvas_transform().affine_inverse() * mouse_global
	mouse_global += mouse_offset

	var local := terrain.to_local(mouse_global)
	var cell := terrain.local_to_map(local)

	if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(cell):
		return Vector2i(-1, -1)

	return cell

func unit_at_cell(c: Vector2i) -> Unit:
	if units_by_cell.has(c):
		var u := units_by_cell[c] as Unit
		if u and is_instance_valid(u):
			return u
		units_by_cell.erase(c)
	return null

func _select(u: Unit) -> void:
	if TM != null and not TM.can_select(u):
		return
	if selected == u:
		return

	_unselect()
	selected = u
	selected.set_selected(true)

	_sfx(&"ui_select", sfx_volume_ui, 1.0)

	if u.team == Unit.Team.ALLY and not ally_select_lines.is_empty():
		_say(u, ally_select_lines.pick_random())

	_refresh_overlays()
	_apply_turn_indicators_all_allies()
	emit_signal("selection_changed", selected)
	emit_signal("aim_changed", int(aim_mode), special_id)


func _unselect() -> void:
	if selected and is_instance_valid(selected):
		_sfx(&"ui_deselect", sfx_volume_ui, 1.0)
		selected.set_selected(false)
			
	if selected and is_instance_valid(selected):
		selected.set_selected(false)
	selected = null
	_clear_overlay()

	emit_signal("selection_changed", null)
	emit_signal("aim_changed", int(aim_mode), special_id)


func _in_attack_range(attacker: Unit, target_cell: Vector2i) -> bool:
	var d = abs(attacker.cell.x - target_cell.x) + abs(attacker.cell.y - target_cell.y)
	if d > attacker.attack_range:
		return false

	# ✅ must have clear attack path (structures block)
	return _has_clear_attack_path(attacker.cell, target_cell)

func _has_clear_attack_path(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if from_cell == to_cell:
		return true

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	# Build two L paths (x->y and y->x), like your move logic
	var p1 := _build_L_path(from_cell, to_cell, true)
	var p2 := _build_L_path(from_cell, to_cell, false)

	# A path is clear if NONE of the intermediate cells (excluding destination) are blocked by structures.
	if _path_clear_of_structures(p1, to_cell, structure_blocked):
		return true
	if _path_clear_of_structures(p2, to_cell, structure_blocked):
		return true

	return false

func _path_clear_of_structures(path: Array[Vector2i], dest: Vector2i, structure_blocked: Dictionary) -> bool:
	for c in path:
		# allow hitting the destination even if it's "occupied" by a unit
		if c == dest:
			continue
		if structure_blocked.has(c):
			return false
	return true

func _play_attack_anim(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return

	# Preferred: unit-defined helpers
	if u.has_method("play_attack_anim"):
		u.call("play_attack_anim")
		return

	# Fallback: AnimatedSprite2D with "attack"
	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a == null:
		return
	if a.sprite_frames != null and a.sprite_frames.has_animation("attack"):
		a.play("attack")

func _play_idle_anim(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return
	if u.has_method("play_idle_anim"):
		u.call("play_idle_anim")
		return

	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a == null:
		return
	if a.sprite_frames != null and a.sprite_frames.has_animation("idle"):
		a.play("idle")

func _flash_unit_white(u: Unit, t: float) -> void:
	if u == null or not is_instance_valid(u):
		return

	var ci: CanvasItem = null

	var spr := u.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		ci = spr
	else:
		var anim := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if anim != null:
			ci = anim
		else:
			for ch in u.get_children():
				if ch is CanvasItem:
					ci = ch as CanvasItem
					break

	if ci == null:
		return

	# If a previous flash is running, kill it and restore the original color
	if ci.has_meta("flash_tw"):
		var old = ci.get_meta("flash_tw")
		if old != null and (old is Tween) and is_instance_valid(old):
			(old as Tween).kill()
		ci.set_meta("flash_tw", null)

	if ci.has_meta("flash_base"):
		var base_restore = ci.get_meta("flash_base")
		if base_restore is Color:
			ci.modulate = base_restore

	# Decide what "normal" is:
	# - If we already have a stored base, keep using it
	# - Otherwise capture the current (true) normal
	var base: Color
	if ci.has_meta("flash_base") and (ci.get_meta("flash_base") is Color):
		base = ci.get_meta("flash_base") as Color
	else:
		base = ci.modulate
		ci.set_meta("flash_base", base)

	var peak := Color(
		min(base.r * 2.2, 2.0),
		min(base.g * 2.2, 2.0),
		min(base.b * 2.2, 2.0),
		base.a
	)

	var tw := create_tween()
	ci.set_meta("flash_tw", tw)

	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(ci, "modulate", peak, max(0.01, t * 0.35))
	tw.set_ease(Tween.EASE_IN)
	tw.tween_property(ci, "modulate", base, max(0.01, t * 0.65))

	tw.finished.connect(func():
		if ci != null and is_instance_valid(ci):
			ci.modulate = base
			ci.set_meta("flash_tw", null)
	)

func _flash_canvasitem_white(ci: CanvasItem, t: float) -> void:
	if ci == null or not is_instance_valid(ci):
		return

	var prev: Color = ci.modulate

	# Brighten (not pure white) so it reads even with darker sprites
	var peak := Color(
		min(prev.r * 2.0, 2.0),
		min(prev.g * 2.0, 2.0),
		min(prev.b * 2.0, 2.0),
		prev.a
	)

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)

	# Fade up quickly
	tw.tween_property(ci, "modulate", peak, max(0.01, t * 0.35))

	# Fade back a bit slower
	tw.set_ease(Tween.EASE_IN)
	tw.tween_property(ci, "modulate", prev, max(0.01, t * 0.65))

func _cleanup_dead_at(cell: Vector2i) -> void:
	if not units_by_cell.has(cell):
		return

	var v = units_by_cell[cell]  # <-- DO NOT cast yet

	# Freed or not even an Object anymore -> remove
	if v == null or not (v is Object) or not is_instance_valid(v):
		units_by_cell.erase(cell)
		return

	# Now it's safe to cast/use as Unit
	var u := v as Unit
	if u == null or u.hp <= 0:
		units_by_cell.erase(cell)

func _do_attack(attacker: Unit, defender: Unit) -> void:
	if attacker == null or defender == null:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	var def_cell := defender.cell  # ✅ store before defender can die/free

	_face_unit_toward_world(attacker, defender.global_position)
	_face_unit_toward_world(defender, attacker.global_position)
	
	_sfx(&"attack_swing", sfx_volume_world, randf_range(0.95, 1.05), attacker.global_position)
	_play_attack_anim(attacker)

	_flash_unit_white(defender, attack_flash_time)
	_jitter_unit(defender, 3.0, 6, attack_flash_time)
	var dmg := attacker.get_attack_damage() if attacker.has_method("get_attack_damage") else attacker.attack_damage
	defender.take_damage(dmg)

	_sfx(&"attack_hit", sfx_volume_world, randf_range(0.95, 1.05), defender.global_position)

	await _wait_for_attack_anim(attacker)
	await get_tree().create_timer(attack_anim_lock_time).timeout

	# ✅ defender might be freed now, so never pass it as a typed arg
	_cleanup_dead_at(def_cell)

	_play_idle_anim(attacker)


# --------------------------
# Overlay helpers
# --------------------------
func _clear_overlay() -> void:
	if overlay_root == null or not is_instance_valid(overlay_root):
		return

	_ensure_overlay_subroots()

	# ✅ only clear move/attack/special tiles
	if overlay_tiles_root != null and is_instance_valid(overlay_tiles_root):
		for ch in overlay_tiles_root.get_children():
			ch.queue_free()


func _draw_move_range(u: Unit) -> void:
	if move_tile_scene == null:
		return
	_ensure_overlay_subroots()
	if overlay_tiles_root == null:
		return

	valid_move_cells.clear()

	var r := u.get_move_range() if u.has_method("get_move_range") else u.move_range
	var origin := u.cell

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := origin + Vector2i(dx, dy)

			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue
			if abs(dx) + abs(dy) > r:
				continue

			if not _is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			if c != origin and units_by_cell.has(c):
				continue

			# Only consider it valid if an L path exists
			if _pick_clear_L_path(origin, c).is_empty():
				continue

			valid_move_cells[c] = true

			var t := move_tile_scene.instantiate() as Node2D
			overlay_tiles_root.add_child(t)

			t.global_position = terrain.to_global(terrain.map_to_local(c))
			t.z_as_relative = false
			t.z_index = 0 + (c.x + c.y)

func _draw_attack_range(u: Unit) -> void:
	if attack_tile_scene == null:
		return

	_ensure_overlay_subroots()
	if overlay_tiles_root == null:
		return

	var r := u.attack_range
	var origin := u.cell

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := origin + Vector2i(dx, dy)

			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue
			if abs(dx) + abs(dy) > r:
				continue
			if not _is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			if not _has_clear_attack_path(origin, c):
				continue

			var t := attack_tile_scene.instantiate() as Node2D
			overlay_tiles_root.add_child(t) # ✅ IMPORTANT
			t.global_position = terrain.to_global(terrain.map_to_local(c))
			t.z_as_relative = false
			t.z_index = 0 + (c.x + c.y)

func _refresh_overlays() -> void:
	_clear_overlay()
	valid_move_cells.clear()
	valid_special_cells.clear()

	if selected == null or not is_instance_valid(selected):
		return

	# 🚫 If unit already attacked, NEVER show special tiles
	if _unit_has_attacked(selected) and aim_mode == AimMode.SPECIAL:
		return

	# SPECIAL aim stays SPECIAL
	if aim_mode == AimMode.SPECIAL:
		_draw_special_range(selected, String(special_id))
		emit_signal("aim_changed", int(aim_mode), special_id)
		return

	var has_moved := _unit_has_moved(selected)
	var has_attacked := _unit_has_attacked(selected)

	# What overlays are even possible?
	var can_show_move := (not has_moved)
	var can_show_attack := (not has_attacked)

	# -----------------------------------
	# Respect player's chosen aim_mode when possible
	# -----------------------------------
	if aim_mode == AimMode.ATTACK:
		if can_show_attack:
			_draw_attack_range(selected)
		else:
			# nothing meaningful to show; fall back
			aim_mode = AimMode.MOVE
			if can_show_move:
				_draw_move_range(selected)
	elif aim_mode == AimMode.MOVE:
		if can_show_move:
			_draw_move_range(selected)
		elif can_show_attack:
			# ✅ auto-switch only when move is no longer possible
			aim_mode = AimMode.ATTACK
			_draw_attack_range(selected)

	emit_signal("aim_changed", int(aim_mode), special_id)

func _set_aim_mode(m: AimMode) -> void:
	aim_mode = m
	if m != AimMode.SPECIAL:
		special_id = &""
		valid_special_cells.clear()
	_refresh_overlays()
	emit_signal("aim_changed", int(aim_mode), special_id)

func _draw_special_range(u: Unit, special: String) -> void:
	if overlay_root == null or attack_tile_scene == null:
		return
	if u == null or not is_instance_valid(u):
		return

	var id := special.to_lower()

	# ✅ range comes from the unit class
	var r := 0
	if u.has_method("get_special_range"):
		r = int(u.get_special_range(id))
	if r <= 0:
		return

	var origin := u.cell

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := origin + Vector2i(dx, dy)

			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue
			if abs(dx) + abs(dy) > r:
				continue
			if not _is_walkable(c):
				continue

			# --- per-special validity (your existing logic) ---
			if id == "blade":
				var tgt := unit_at_cell(c)
				if tgt == null:
					continue
				if tgt.team == u.team:
					continue

			elif id == "mines":
				if structure_blocked.has(c):
					continue
				if units_by_cell.has(c):
					continue
				if mines_by_cell.has(c):
					continue

			elif id == "suppress":
				var tgt := unit_at_cell(c)
				if tgt == null:
					continue
				if tgt.team == u.team:
					continue

			valid_special_cells[c] = true

			var t := attack_tile_scene.instantiate() as Node2D
			_ensure_overlay_subroots()
			if overlay_tiles_root == null:
				return
			overlay_tiles_root.add_child(t)

			t.global_position = terrain.to_global(terrain.map_to_local(c))
			t.z_as_relative = false
			t.z_index = 0 + (c.x + c.y)

func _is_valid_move_target(c: Vector2i) -> bool:
	return selected != null and is_instance_valid(selected) and valid_move_cells.has(c)

func _play_move_anim(u: Unit, moving: bool) -> void:
	if u == null or not is_instance_valid(u):
		return

	# Preferred: unit-defined helpers
	if moving and u.has_method("play_move_anim"):
		u.call("play_move_anim")
		return
	if (not moving) and u.has_method("play_idle_anim"):
		u.call("play_idle_anim")
		return

	# Fallback: AnimatedSprite2D with "move"/"idle"
	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a == null:
		return
	if moving:
		if a.sprite_frames != null and a.sprite_frames.has_animation("move"):
			a.play("move")
	else:
		if a.sprite_frames != null and a.sprite_frames.has_animation("idle"):
			a.play("idle")

func _set_unit_depth_from_world(u: Unit, world_pos: Vector2) -> void:
	# Convert world pos to an approximate cell, then apply x+y sum.
	# This keeps depth stable while sliding between tiles.
	if u == null or not is_instance_valid(u):
		return
	if terrain == null:
		return

	var local := terrain.to_local(world_pos)
	var c := terrain.local_to_map(local)

	u.z_as_relative = false
	# Match your Unit.gd base if you use one (default I suggested was 200000)
	var base := 200000
	if "z_base" in u:
		base = int(u.z_base)
	var per := 1
	if "z_per_cell" in u:
		per = int(u.z_per_cell)

	u.z_index = base + ((c.x + c.y) * per)

func _move_selected_to(target: Vector2i) -> void:
	# ✅ Per-unit move lock
	if selected != null and is_instance_valid(selected) and selected.team == Unit.Team.ALLY:
		if _unit_has_moved(selected):
			_sfx(&"ui_denied", sfx_volume_ui, 1.0)
			return

		
	# Hard gates FIRST (PLAYER ONLY)
	if TM != null and selected != null and is_instance_valid(selected) and selected.team == Unit.Team.ALLY:
		if not TM.player_input_allowed():
			return
		if not TM.can_move(selected):
			return

	if _is_moving:
		return
	if selected == null or not is_instance_valid(selected):
		return
	if not _is_valid_move_target(target):
		return

	var u := selected
	var uid := u.get_instance_id()
	var from_cell := u.cell

	# L path
	var path := _pick_clear_L_path(from_cell, target)
	if path.is_empty():
		return

	_is_moving = true
	_sfx(&"move_start", sfx_volume_world, 1.0, _cell_world(from_cell))
	_say(u) # <-- NEW: say something before moving
	#await get_tree().create_timer(0.38).timeout
	_clear_overlay()

	# Reserve destination
	units_by_cell.erase(from_cell)
	units_by_cell[target] = u

	_play_move_anim(u, true)

	var step_time := _duration_for_step()
	for step_cell in path:
		var from_world := u.global_position
		var to_world := _cell_world(step_cell)

		_face_unit_for_step(u, from_world, to_world)

		_sfx(&"move_step", sfx_volume_world * 0.55, randf_range(0.95, 1.05), to_world)
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_LINEAR)
		tw.set_ease(Tween.EASE_IN_OUT)

		uid = u.get_instance_id()

		tw.tween_method(func(p: Vector2):
			var uu := instance_from_id(uid) as Unit
			if uu == null or not is_instance_valid(uu):
				return
			uu.global_position = p
			_set_unit_depth_from_world(uu, p)
		, from_world, to_world, step_time)


		if is_overwatching(u):
			_update_overwatch_ghost_pos(u)

		await tw.finished

		# Unit may have died/freed during the step
		if u == null or not is_instance_valid(u):
			_is_moving = false
			_refresh_overlays()
			emit_signal("aim_changed", int(aim_mode), special_id)
			return

		# Overwatch trigger: enemy entering a new step cell
		#await _check_overwatch_trigger(u, step_cell)

	u.set_cell(target, terrain)
	
	# After move complete + mines resolved:
	if u != null and is_instance_valid(u) and u.team == Unit.Team.ALLY:
		_try_recruit_near_structure(u)

	if u.team == Unit.Team.ALLY:
		_set_unit_moved(u, true)

	_apply_turn_indicator(u)

	# ✅ Overwatch triggers once, when mover finishes movement
	await _check_overwatch_trigger(u, target)

	await _trigger_mine_if_present_id(uid)

	try_collect_pickup(u)
	_check_and_trigger_beacon_sweep()
	
	# Mine might have killed / freed the mover (knockback, collision, etc.)
	if u == null or not is_instance_valid(u):
		_is_moving = false
		_refresh_overlays()
		emit_signal("aim_changed", int(aim_mode), special_id)
		return
	
	_play_move_anim(u, false)
	_sfx(&"move_end", sfx_volume_world, 1.0, _cell_world(target))
	
	_is_moving = false

	# ✅ Mark move spent (IMPORTANT)
	if u.team == Unit.Team.ALLY and TM != null and TM.has_method("notify_player_moved"):
		TM.notify_player_moved(u)

	if u != null and is_instance_valid(u) and u.team == Unit.Team.ALLY:
		if not _unit_has_attacked(u):
			aim_mode = AimMode.ATTACK
		else:
			aim_mode = AimMode.MOVE
		_refresh_overlays()

	emit_signal("aim_changed", int(aim_mode), special_id)


func reset_turn_flags_for_enemies() -> void:
	for u in get_all_units():
		if u != null and is_instance_valid(u) and u.team == Unit.Team.ENEMY:
			_set_unit_moved(u, false)
			_set_unit_attacked(u, false)

func _trigger_mine_if_present_id(uid: int) -> void:
	var obj := instance_from_id(uid)
	if obj == null or not is_instance_valid(obj):
		return
	if not (obj is Unit):
		return
	_trigger_mine_if_present(obj as Unit)

func _face_unit_for_step(u: Unit, from_world: Vector2, to_world: Vector2) -> void:
	if u == null or not is_instance_valid(u):
		return

	var dx := to_world.x - from_world.x
	if abs(dx) < 0.001:
		return

	# Default faces LEFT, so flip when moving RIGHT
	var flip := dx > 0.0

	# Try a few common child names first
	var spr := u.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		spr.flip_h = flip
		return

	var anim := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		anim.flip_h = flip
		return

	# Generic fallback: find the first Sprite2D / AnimatedSprite2D anywhere under the unit
	for ch in u.get_children():
		if ch is Sprite2D:
			(ch as Sprite2D).flip_h = flip
			return
		if ch is AnimatedSprite2D:
			(ch as AnimatedSprite2D).flip_h = flip
			return

	_sync_ghost_facing(u)

func _is_blocked_for_move(c: Vector2i, origin: Vector2i) -> bool:
	# blocks: out of bounds, water, structures, occupied (except origin)
	if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
		return true
	if not _is_walkable(c):
		return true

	# structures
	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked
	if structure_blocked.has(c):
		return true

	# occupied (allow starting cell)
	if c != origin and units_by_cell.has(c):
		return true

	return false


func _build_L_path(from_cell: Vector2i, to_cell: Vector2i, x_first: bool) -> Array[Vector2i]:
	# Returns cells visited INCLUDING the destination, EXCLUDING the start.
	var path: Array[Vector2i] = []
	var c := from_cell

	if x_first:
		while c.x != to_cell.x:
			c.x += (1 if to_cell.x > c.x else -1)
			path.append(c)
		while c.y != to_cell.y:
			c.y += (1 if to_cell.y > c.y else -1)
			path.append(c)
	else:
		while c.y != to_cell.y:
			c.y += (1 if to_cell.y > c.y else -1)
			path.append(c)
		while c.x != to_cell.x:
			c.x += (1 if to_cell.x > c.x else -1)
			path.append(c)

	return path


func _pick_clear_L_path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var p1 := _build_L_path(from_cell, to_cell, true)   # X then Y
	var p2 := _build_L_path(from_cell, to_cell, false)  # Y then X

	# Check p1
	var ok1 := true
	for step in p1:
		if _is_blocked_for_move(step, from_cell):
			ok1 = false
			break

	# Check p2
	var ok2 := true
	for step in p2:
		if _is_blocked_for_move(step, from_cell):
			ok2 = false
			break

	# Prefer the one that works; if both work, pick shorter (they're same length usually)
	if ok1:
		return p1
	if ok2:
		return p2
	return []


func _cell_world(c: Vector2i) -> Vector2:
	return terrain.to_global(terrain.map_to_local(c))


func _duration_for_step() -> float:
	# One cell move duration based on your cells/sec.
	return max(0.04, 1.0 / move_speed_cells_per_sec)

func _face_unit_toward_world(u: Unit, look_at_world: Vector2) -> void:
	if u == null or not is_instance_valid(u):
		return

	var dx := look_at_world.x - u.global_position.x
	if abs(dx) < 0.001:
		return

	# Default faces LEFT, so flip when looking RIGHT
	var flip := dx > 0.0

	# Try common child names first
	var spr := u.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		spr.flip_h = flip
		return

	var anim := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		anim.flip_h = flip
		return

	# Generic fallback: find first Sprite2D / AnimatedSprite2D child
	for ch in u.get_children():
		if ch is Sprite2D:
			(ch as Sprite2D).flip_h = flip
			return
		if ch is AnimatedSprite2D:
			(ch as AnimatedSprite2D).flip_h = flip
			return
	
	_sync_ghost_facing(u)

func _jitter_unit(u: Unit, strength := 3.0, shakes := 6, total_time := 0.12) -> void:
	if u == null or not is_instance_valid(u):
		return

	var original := u.global_position
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.set_ease(Tween.EASE_IN_OUT)

	var step_time := total_time / float(shakes * 2)

	for i in range(shakes):
		var offset := Vector2(
			randf_range(-strength, strength),
			randf_range(-strength, strength)
		)
		tw.tween_property(u, "global_position", original + offset, step_time)
		tw.tween_property(u, "global_position", original, step_time)

	# Safety snap at end
	tw.tween_callback(func():
		if u != null and is_instance_valid(u):
			u.global_position = original
	)

func _get_attack_anim_length(u: Unit) -> float:
	# If the Unit exposes a custom duration, use it
	if "attack_anim_time" in u:
		return float(u.attack_anim_time)

	# If AnimatedSprite2D exists and has "attack", estimate from FPS + frame count
	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a != null and a.sprite_frames != null and a.sprite_frames.has_animation("attack"):
		var fps := float(a.sprite_frames.get_animation_speed("attack"))
		var frames := a.sprite_frames.get_frame_count("attack")
		if fps > 0.0 and frames > 0:
			return frames / fps

	# fallback
	return attack_anim_lock_time

func _wait_for_attack_anim(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return

	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	var fallback := _get_attack_anim_length(u)

	# No AnimatedSprite2D attack anim -> just wait fallback time
	if a == null or a.sprite_frames == null or not a.sprite_frames.has_animation("attack"):
		await get_tree().create_timer(max(0.01, fallback)).timeout
		return

	# If attack isn't currently playing, just time fallback
	if a.animation != "attack":
		await get_tree().create_timer(max(0.01, fallback)).timeout
		return

	var done := false
	var cb := func() -> void:
		done = true

	var callable := Callable(cb)

	# Connect once
	if not a.animation_finished.is_connected(callable):
		a.animation_finished.connect(callable)

	# Wait until finished OR timeout
	var t := 0.0
	while not done and t < fallback + 0.25:
		await get_tree().process_frame
		t += get_process_delta_time()

	# Disconnect safely
	if a != null and is_instance_valid(a) and a.animation_finished.is_connected(callable):
		a.animation_finished.disconnect(callable)

func get_all_units() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units_by_cell.values():
		if u != null and is_instance_valid(u):
			out.append(u)
	return out

# used by TurnManager AI
func can_attack_cell(attacker: Unit, target_cell: Vector2i) -> bool:
	return _in_attack_range(attacker, target_cell)

func ai_reachable_cells(u: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if u == null or not is_instance_valid(u):
		return out
	if u.hp <= 0:
		return out

	if u == null or not is_instance_valid(u):
		return out

	var r := u.get_move_range() if u.has_method("get_move_range") else u.move_range
	var origin := u.cell

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := origin + Vector2i(dx, dy)

			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue
			if abs(dx) + abs(dy) > r:
				continue
			if not _is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			if c != origin and units_by_cell.has(c):
				continue
			if _pick_clear_L_path(origin, c).is_empty():
				continue

			out.append(c)

	return out

func ai_move(u: Unit, target: Vector2i) -> void:
	if u == null or not is_instance_valid(u):
		return
	if u.hp <= 0:
		return
	if _is_moving:
		return
		
	# Drive the existing move logic safely:
	if u == null or not is_instance_valid(u):
		return
	if _is_moving:
		return

	# Temporarily select the unit so _move_selected_to works
	var prev := selected
	selected = u
	_clear_overlay()
	valid_move_cells.clear()
	valid_move_cells[target] = true

	_move_selected_to(target)
	# wait until movement finishes
	while _is_moving:
		await get_tree().process_frame

	selected = prev

func ai_attack(attacker: Unit, defender: Unit) -> void:
	if attacker == null or defender == null:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return
	await _do_attack(attacker, defender)

func set_unit_exhausted(u: Unit, exhausted: bool) -> void:
	if u == null or not is_instance_valid(u):
		return

	var mul := 0.55 if exhausted else 1.0
	var tint := Color(mul, mul, mul, 1.0)

	# Try common visuals
	var spr := u.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		spr.modulate = tint
		return

	var anim := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		anim.modulate = tint
		return

	# Fallback: first CanvasItem child
	for ch in u.get_children():
		if ch is CanvasItem:
			(ch as CanvasItem).modulate = tint
			return

func _is_knockback_melee_attacker(u: Unit) -> bool:
	if u == null or not is_instance_valid(u):
		return false

	# 1) Best: use meta flag if you can set it on the unit scenes
	if u.has_meta("melee_knockback") and bool(u.get_meta("melee_knockback")):
		return true

	# 2) Robust fallback: match script file name (works even without class_name)
	var sc = u.get_script()
	if sc != null:
		var path := str(sc.resource_path).to_lower()
		if path.ends_with("humantwo.gd") or path.ends_with("human_two.gd") or path.ends_with("human2.gd"):
			return true
		if path.ends_with("mech.gd"):
			return true

	# 3) Last fallback: match scene/node name (your log shows humantwo.tscn)
	var n := String(u.name).to_lower()
	if n.contains("humantwo") or n.contains("human2"):
		return true
	if n.contains("mech"):
		return true

	return false

func _knockback_destination(attacker_cell: Vector2i, defender_cell: Vector2i) -> Vector2i:
	# Push 1 tile in the direction from attacker -> defender (normalized to -1/0/1 per axis)
	var dx := defender_cell.x - attacker_cell.x
	var dy := defender_cell.y - attacker_cell.y

	var sx := 0
	var sy := 0
	if dx > 0: sx = 1
	elif dx < 0: sx = -1
	if dy > 0: sy = 1
	elif dy < 0: sy = -1

	return defender_cell + Vector2i(sx, sy)


func _cell_is_free_for_knockback(c: Vector2i) -> bool:
	if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
		return false
	if not _is_walkable(c):
		return false

	# structures block
	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked
	if structure_blocked.has(c):
		return false

	# units block
	if units_by_cell.has(c):
		return false

	return true

func _push_unit_to_cell(u: Unit, to_cell: Vector2i) -> void:
	if u == null or not is_instance_valid(u):
		return
	if terrain == null:
		return

	var from_cell := u.cell
	if from_cell == to_cell:
		return

	var from_world := _cell_world(from_cell)
	var to_world := _cell_world(to_cell)

	if units_by_cell.has(from_cell) and units_by_cell[from_cell] == u:
		units_by_cell.erase(from_cell)
	units_by_cell[to_cell] = u

	u.set_cell(to_cell, terrain)
	if is_overwatching(u):
		_update_overwatch_ghost_pos(u)
	
	_set_unit_depth_from_world(u, to_world)

	await _trigger_mine_if_present(u)

	# ✅ IMPORTANT: u may be dead/freed now
	if u == null or not is_instance_valid(u):
		if units_by_cell.has(to_cell):
			var v = units_by_cell[to_cell]
			if v == null or not (v is Object) or not is_instance_valid(v):
				units_by_cell.erase(to_cell)
		return

	var visual := _get_unit_visual_node(u)
	if visual == null or not is_instance_valid(visual):
		return

	var offset := from_world - to_world
	visual.position += offset

	var step_time = max(0.04, 1.0 / move_speed_cells_per_sec) * 0.6

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "position", visual.position - offset, step_time)

	await tw.finished

func _try_melee_knockback(attacker: Unit, defender: Unit) -> void:
	if attacker == null or defender == null:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	# Must be adjacent (including diagonals)
	var dx = abs(attacker.cell.x - defender.cell.x)
	var dy = abs(attacker.cell.y - defender.cell.y)
	if max(dx, dy) != 1:
		return

	if not _is_knockback_melee_attacker(attacker):
		return

	# Defender must still be alive
	if defender.hp <= 0:
		return

	var dest := _knockback_destination(attacker.cell, defender.cell)

	# -----------------------------------------
	# ✅ NEW: zombies can be shoved OFF-MAP
	# -----------------------------------------
	var in_bounds := true
	if grid != null and grid.has_method("in_bounds"):
		in_bounds = grid.in_bounds(dest)

	if not in_bounds:
		# Only zombies get "ring-out" death
		if _is_zombie(defender):
			await _ringout_push_and_die(attacker, defender)
			_is_moving = true

			# Small hit feedback before dying
			_flash_unit_white(defender, max(attack_flash_time, 0.12))
			_jitter_unit(defender, 3.5, 6, 0.14)

			# Kill + play death anim, then remove from board
			defender.hp = 0

			var victim := defender  # keep a local ref
			await _play_death_and_wait(victim)

			# ✅ If the death function freed it, don't touch it anymore
			if victim == null or not is_instance_valid(victim):
				_is_moving = false
				return

			_remove_unit_from_board(victim)

			_is_moving = false
		return

	# Normal knockback rules still apply in-bounds
	if not _is_walkable(dest):
		return

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked
	if structure_blocked.has(dest):
		return

	# -------------------------
	# Allow "collision" only into OTHER ZOMBIES
	# -------------------------
	var occupant := unit_at_cell(dest)

	if occupant != null and is_instance_valid(occupant):
		# Only allow knockback INTO a zombie, and ONLY when defender is also a zombie
		if _is_zombie(defender) and _is_zombie(occupant):
			_is_moving = true

			await _push_unit_to_cell(defender, dest)

			_flash_unit_white(defender, max(attack_flash_time, 0.12))
			_flash_unit_white(occupant, max(attack_flash_time, 0.12))

			await get_tree().create_timer(0.06).timeout

			defender.hp = 0
			occupant.hp = 0

			await _play_death_and_wait(defender)
			await _play_death_and_wait(occupant)

			_remove_unit_from_board(defender)
			_remove_unit_from_board(occupant)

			_is_moving = false
		return

	# Empty destination => normal shove
	_is_moving = true
	await _push_unit_to_cell(defender, dest)
	_is_moving = false

func _get_unit_visual_node(u: Unit) -> Node2D:
	# Prefer a dedicated Visual root if you have one
	var v := u.get_node_or_null("Visual") as Node2D
	if v != null:
		return v

	# Otherwise try common render nodes (they are Node2D)
	var s := u.get_node_or_null("Sprite2D") as Node2D
	if s != null:
		return s

	var a := u.get_node_or_null("AnimatedSprite2D") as Node2D
	if a != null:
		return a

	# Last resort: if the Unit itself is safe to offset (no snap), return u
	return u

func _is_zombie(u: Unit) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	if u.team != Unit.Team.ENEMY:
		return false

	# Prefer class_name if you have it
	if u.is_class("Zombie"):
		return true

	# Robust fallback: script file name
	var sc = u.get_script()
	if sc != null:
		var p := String(sc.resource_path).to_lower()
		if p.ends_with("zombie.gd"):
			return true

	# Last fallback: node name
	var n := String(u.name).to_lower()
	return n.contains("zombie")


func _play_death_and_wait(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return

	# Preferred: unit-defined death handler (if you have one)
	if u.has_method("play_death_anim"):
		u.call("play_death_anim")
		# If you also expose a wait method:
		if u.has_method("wait_death_anim"):
			await u.call("wait_death_anim")
			return
		# else fall through to sprite wait

	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a == null or a.sprite_frames == null:
		# No anim; just a short delay so it still “feels” like it happened
		await get_tree().create_timer(0.12).timeout
		return

	if a.sprite_frames.has_animation("death"):
		a.play("death")
		u._play_sfx("unit_death")
	elif a.sprite_frames.has_animation("die"):
		a.play("die")
		u._play_sfx("unit_death")
	else:
		await get_tree().create_timer(0.12).timeout
		return

	# Wait until the animation finishes (or a safe timeout)
	var done := false
	var cb := func() -> void: done = true
	var callable := Callable(cb)

	if not a.animation_finished.is_connected(callable):
		a.animation_finished.connect(callable)

	var t := 0.0
	while not done and t < 0.5:
		await get_tree().process_frame
		t += get_process_delta_time()

	if a != null and is_instance_valid(a) and a.animation_finished.is_connected(callable):
		a.animation_finished.disconnect(callable)


func _remove_unit_from_board_at_cell(cell: Vector2i) -> void:
	if not units_by_cell.has(cell):
		return

	var v = units_by_cell[cell] # don't cast yet
	units_by_cell.erase(cell)

	if v == null or not (v is Object) or not is_instance_valid(v):
		return

	var u := v as Unit
	if u != null and is_instance_valid(u):
		u.queue_free()

func _remove_unit_from_board(u: Unit) -> void:
	if u == null:
		return

	# remove from units_by_cell safely
	for k in units_by_cell.keys():
		if units_by_cell[k] == u:
			units_by_cell.erase(k)
			break

	if is_instance_valid(u):
		u.queue_free()

func activate_special(id: String) -> void:
	if selected == null or not is_instance_valid(selected):
		return
	if _is_moving:
		return
	if TM != null and not TM.player_input_allowed():
		return

	id = id.to_lower()

	# ✅ Only require "unit supports this special" for preview
	if not _unit_can_use_special(selected, id):
		return

	# Specials that execute instantly (no targeting)
	if id == "overwatch":
		# ✅ ALWAYS disarm special aim + clear special tiles
		aim_mode = AimMode.MOVE
		special_id = &""
		valid_special_cells.clear()
		_clear_overlay()

		var u := selected
		if u == null or not is_instance_valid(u):
			return

		# 🔁 Toggle OFF if already overwatching
		if is_overwatching(u):
			clear_overwatch(u)
			_refresh_overlays()
			emit_signal("aim_changed", int(aim_mode), special_id)
			return

		# Otherwise toggle ON
		if u.has_method("can_use_special") and not u.can_use_special(id):
			_refresh_overlays()
			emit_signal("aim_changed", int(aim_mode), special_id)
			return

		await _perform_special(u, id, u.cell) # dummy cell

		if _unit_has_attacked(u):
			aim_mode = AimMode.MOVE
			special_id = &""
			_sfx(&"ui_denied", sfx_volume_ui, 1.0)
			_refresh_overlays()
			emit_signal("aim_changed", int(aim_mode), special_id)
			return
		
		_set_unit_attacked(u, true)
				
		if TM != null and TM.has_method("notify_player_attacked"):
			TM.notify_player_attacked(u)
		
		_refresh_overlays()
		emit_signal("aim_changed", int(aim_mode), special_id)
		return

	if id == "stim":
		aim_mode = AimMode.MOVE
		special_id = &""
		valid_special_cells.clear()
		_clear_overlay()
		var u := selected
		if u == null or not is_instance_valid(u):
			return
		if u.has_method("can_use_special") and not u.can_use_special(id):
			_refresh_overlays()
			emit_signal("aim_changed", int(aim_mode), special_id)
			return
		await _perform_special(u, id, u.cell)
		_refresh_overlays()
		emit_signal("aim_changed", int(aim_mode), special_id)
		return

	# ✅ Toggle off if same special pressed again
	if aim_mode == AimMode.SPECIAL and String(special_id).to_lower() == id:
		aim_mode = AimMode.MOVE
		special_id = &""
		_refresh_overlays()
		emit_signal("aim_changed", int(aim_mode), special_id)
		return

	# ✅ Turn on SPECIAL aim + show range immediately
	aim_mode = AimMode.SPECIAL
	special_id = StringName(id)
	_refresh_overlays()
	emit_signal("aim_changed", int(aim_mode), special_id)

func _unit_can_use_special(u: Unit, id: String) -> bool:
	if u == null or not is_instance_valid(u):
		return false

	match id:
		"hellfire":
			return u.has_method("perform_hellfire")
		"blade":
			return u.has_method("perform_blade")
		"mines":
			return u.has_method("perform_place_mine")
		"overwatch":
			return u.has_method("perform_overwatch")
		"suppress":
			return u.has_method("perform_suppress")
		"stim":
			return u.has_method("perform_stim")

	return false

func select_unit(u: Unit) -> void:
	_select(u)

func _trigger_mine_if_present(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return

	var c := u.cell
	if not mines_by_cell.has(c):
		return

	var data = mines_by_cell[c]
	var mine_team := int(data.get("team", Unit.Team.ALLY))

	# -------------------------
	# ✅ FRIENDLY MINE: PICK UP (no explosion)
	# -------------------------
	if u.team == mine_team:
		# remove mine from board
		mines_by_cell.erase(c)
		remove_mine_visual(c)

		# optional pickup sound (add this key to sfx_streams)
		_sfx(&"mine_pickup", sfx_volume_ui, randf_range(0.95, 1.05), _cell_world(c))

		# give mine back to the unit if it supports it
		# (supports multiple possible APIs so you can match your Unit scripts)
		if u.has_method("add_mine"):
			u.call("add_mine", 1)
		elif u.has_method("add_mines"):
			u.call("add_mines", 1)
		elif u.has_method("gain_mine"):
			u.call("gain_mine", 1)
		elif u.has_method("give_mine"):
			u.call("give_mine", 1)
		elif u.has_method("add_special_charge"):
			u.call("add_special_charge", "mines", 1)
		elif u.has_method("add_special_ammo"):
			u.call("add_special_ammo", "mines", 1)
		# else: silently just pick it up (still useful even without inventory)

		return

	# -------------------------
	# ✅ ENEMY ON MINE: DETONATE
	# -------------------------
	mines_by_cell.erase(c)

	remove_mine_visual(c)
	_sfx(&"mine_trigger", sfx_volume_world, 1.0, _cell_world(c))
	spawn_explosion_at_cell(c)

	var dmg := int(data.get("damage", 2))

	_flash_unit_white(u, max(attack_flash_time, 0.12))
	_jitter_unit(u, 3.5, 6, 0.14)
	u.take_damage(dmg)

	if u != null and is_instance_valid(u) and u.hp <= 0:
		await _play_death_and_wait(u)
		_remove_unit_from_board_at_cell(c)
		return

	_cleanup_dead_at(c)

func spawn_explosion_at_cell(cell: Vector2i) -> void:
	if explosion_scene == null or terrain == null:
		return

	var fx := explosion_scene.instantiate() as Node2D
	if fx == null:
		return

	# ✅ NEW: explosions also apply splash + structure damage
	# (keeps all explosions consistent: mines, hellfire, etc.)
	await _apply_splash_damage(cell, structure_splash_radius, structure_explosion_splash_damage)
	_apply_structure_splash_damage(cell, structure_splash_radius, structure_hit_damage)

	if overlay_root != null:
		overlay_root.add_child(fx)
	else:
		add_child(fx)

	# Position in world (+16px feet offset)
	var world_pos := terrain.to_global(terrain.map_to_local(cell))
	world_pos += Vector2(0, explosion_y_offset_px)
	fx.global_position = world_pos
	_sfx(&"explosion_small", sfx_volume_world, randf_range(0.95, 1.05), world_pos)
	
	# Depth using grid-space (recomputed after offset)
	var local := terrain.to_local(world_pos)
	var depth_cell := terrain.local_to_map(local)

	fx.z_as_relative = false
	fx.z_index = 2 + (depth_cell.x + depth_cell.y)

	# Play animation and wait for it to finish
	var a := fx.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a != null and a.sprite_frames != null and a.sprite_frames.has_animation(explosion_anim_name):
		a.play(explosion_anim_name)
		await a.animation_finished
	else:
		# fallback if no anim
		await get_tree().create_timer(explosion_fallback_seconds).timeout

	if fx != null and is_instance_valid(fx):
		fx.queue_free()

func launch_projectile_arc(
	from_cell: Vector2i,
	to_cell: Vector2i,
	projectile_scene: PackedScene,
	flight_time := 0.35,
	arc_height_px := 42.0,
	spin_turns := 1.25,
) -> void:
	if projectile_scene == null or terrain == null:
		return

	var p := projectile_scene.instantiate() as Node2D
	if p == null:
		return

	# Put it in overlays so it's above terrain
	if overlay_root != null:
		overlay_root.add_child(p)
	else:
		add_child(p)

	var start := terrain.to_global(terrain.map_to_local(from_cell)) + Vector2(0, 0)
	var end := terrain.to_global(terrain.map_to_local(to_cell)) + Vector2(0, -8)

	# Ensure consistent depth system while moving
	p.z_as_relative = false

	var start_rot := p.rotation
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.set_ease(Tween.EASE_IN_OUT)

	tw.tween_method(func(t: float) -> void:
		# Parabola arc: peaks in the middle
		var pos := start.lerp(end, t)
		var peak := 4.0 * t * (1.0 - t)          # 0..1..0
		pos.y -= arc_height_px * peak

		p.global_position = pos

		# Depth from grid (local_to_map), so it sorts like everything else
		var local := terrain.to_local(pos)
		var c := terrain.local_to_map(local)
		p.z_index = 1 + (c.x + c.y)

		# Spin while flying
		p.rotation = start_rot + (TAU * spin_turns * t)
	, 0.0, 1.0, max(0.01, flight_time))

	await tw.finished

	if p != null and is_instance_valid(p):
		p.queue_free()

func place_mine_visual(cell: Vector2i) -> void:
	if mine_scene == null or terrain == null:
		return
	if mine_nodes_by_cell.has(cell):
		return

	var mine := mine_scene.instantiate() as Node2D
	if mine == null:
		return

	# Put mines under overlays (so overlays still show on top), but above terrain
	# If you have a dedicated root for props/mines, use it; otherwise units_root is OK.
	var parent: Node = units_root if units_root != null else self
	parent.add_child(mine)

	var world := terrain.to_global(terrain.map_to_local(cell)) + Vector2(0, mine_y_offset_px)
	mine.global_position = world
	_sfx(&"mine_place", sfx_volume_world, 1.0, world)
	
	# Depth from grid (local_to_map) so it matches iso sorting
	var local := terrain.to_local(world)
	var depth_cell := terrain.local_to_map(local)

	mine.z_as_relative = false
	mine.z_index = 1 + (depth_cell.x + depth_cell.y)  # tweak base if needed

	mine_nodes_by_cell[cell] = mine

func remove_mine_visual(cell: Vector2i) -> void:
	if not mine_nodes_by_cell.has(cell):
		return
	var n := mine_nodes_by_cell[cell] as Node2D
	mine_nodes_by_cell.erase(cell)
	if n != null and is_instance_valid(n):
		n.queue_free()

func _trigger_structure_explosion(center: Vector2i) -> void:
	# Visual FX + SFX
	spawn_explosion_at_cell(center)

	# Splash damage to units in radius (including center)
	_apply_splash_damage(center, structure_splash_radius, structure_explosion_splash_damage)

	# Also damage structures in radius (including center)
	_apply_structure_splash_damage(center, structure_splash_radius, structure_hit_damage)


func _apply_splash_damage(center: Vector2i, radius: int, dmg: int) -> void:
	if dmg <= 0:
		return

	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dy)
			# Manhattan splash
			if abs(dx) + abs(dy) > radius:
				continue
			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue

			var u := unit_at_cell(c)
			if u == null or not is_instance_valid(u):
				continue

			_flash_unit_white(u, max(attack_flash_time, 0.12))
			_jitter_unit(u, 2.5, 5, 0.10)
			u.take_damage(dmg)

			if u != null and is_instance_valid(u) and u.hp <= 0:
				await _play_death_and_wait(u)
				_remove_unit_from_board_at_cell(c)
			else:
				_cleanup_dead_at(c)


func _apply_structure_splash_damage(center: Vector2i, radius: int, dmg: int) -> void:
	if dmg <= 0:
		return

	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dy)
			if abs(dx) + abs(dy) > radius:
				continue
			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue

			_damage_structure_at_cell(c, dmg)

func _damage_structure_at_cell(cell: Vector2i, dmg: int) -> void:
	_damage_structure_only_at_cell(cell, dmg)

func _node_cell(n: Node) -> Vector2i:
	if n == null:
		return Vector2i(-999, -999)
	if n.has_method("get_cell"):
		var c = n.call("get_cell")
		if c is Vector2i: return c
	if "cell" in n:
		var c2 = n.get("cell")
		if c2 is Vector2i: return c2
	if n.has_meta("cell"):
		var c3 = n.get_meta("cell")
		if c3 is Vector2i: return c3
	return Vector2i(-999, -999)

func _structure_at_cell(cell: Vector2i) -> Node:
	if structure_group_name != "" and get_tree() != null:
		for n in get_tree().get_nodes_in_group(structure_group_name):
			if n == null or not is_instance_valid(n):
				continue

			# ✅ Preferred: structures report footprint occupancy
			if n.has_method("occupies_cell") and bool(n.call("occupies_cell", cell)):
				return n

			# ✅ Fallback: single-cell structures (origin only)
			if _node_cell(n) == cell:
				return n

	return null


func _flash_structure_white(s: Node, t: float) -> void:
	if s == null or not is_instance_valid(s):
		return
	var spr := s.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		_flash_canvasitem_white(spr, t); return
	var anim := s.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		_flash_canvasitem_white(anim, t); return
	for ch in s.get_children():
		if ch is CanvasItem:
			_flash_canvasitem_white(ch as CanvasItem, t); return

func _play_structure_demolished(s: Node) -> void:
	if s == null or not is_instance_valid(s):
		return
	var a := s.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a != null and a.sprite_frames != null and a.sprite_frames.has_animation(structure_demolished_anim):
		a.play(structure_demolished_anim)
		return
	var ap := s.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap != null and ap.has_animation(structure_demolished_anim):
		ap.play(structure_demolished_anim)
		return
	if s.has_method("set_demolished"):
		s.call("set_demolished", true)

func _damage_structure_only_at_cell(cell: Vector2i, dmg: int) -> void:
	var s := _structure_at_cell(cell)
	if s == null or not is_instance_valid(s):
		return

	_flash_structure_white(s, 0.10)

	# Apply damage
	var died := false
	if s.has_method("apply_damage"):
		s.call("apply_damage", dmg)
		if "hp" in s:
			died = int(s.get("hp")) <= 0
	elif s.has_method("take_damage"):
		s.call("take_damage", dmg)
		if "hp" in s:
			died = int(s.get("hp")) <= 0
	elif "hp" in s:
		var hp := int(s.get("hp"))
		hp -= dmg
		s.set("hp", hp)
		died = hp <= 0

	if died:
		_play_structure_demolished(s)
		# ✅ DO NOT free occupancy when demolished.
		# Leave game_ref.structure_blocked as-is so rubble still blocks movement/LOS.
		return

func _pick_bubble_line(u: Unit) -> String:
	# Optional override per-unit:
	# u.set_meta("bubble_lines", ["hi", "lol"])  (Array[String])
	if u != null and u.has_meta("bubble_lines"):
		var v = u.get_meta("bubble_lines")
		if v is Array and not (v as Array).is_empty():
			return String((v as Array).pick_random())

	# Default by team
	if u != null and u.team == Unit.Team.ENEMY:
		return enemy_lines.pick_random() if not enemy_lines.is_empty() else ""
	return ally_lines.pick_random() if not ally_lines.is_empty() else ""


func _kill_bubble(u: Unit) -> void:
	if not _bubble_by_unit.has(u):
		return
	var b = _bubble_by_unit[u]
	_bubble_by_unit.erase(u)
	if b != null and (b is Object) and is_instance_valid(b):
		b.queue_free()

func _say(u: Unit, text: String = "") -> void:
	if not bubble_enabled:
		return
	if u == null or not is_instance_valid(u):
		return
	if bubble_ui_root == null or not is_instance_valid(bubble_ui_root):
		push_warning("SpeechBubble: bubble_ui_root_path not set / invalid")
		return

	_kill_bubble(u)

	if text.strip_edges() == "":
		text = _pick_bubble_line(u)
	text = text.strip_edges()
	if text == "":
		return

	# -------------------------
	# Build UI bubble
	# -------------------------
	var panel := PanelContainer.new()
	panel.name = "SpeechBubble"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.modulate = bubble_board_color

	# Padding (bubble margins)
	panel.add_theme_constant_override("padding_left", 7)
	panel.add_theme_constant_override("padding_right", 7)
	panel.add_theme_constant_override("padding_top", 5)
	panel.add_theme_constant_override("padding_bottom", 5)

	# Content wrapper so PanelContainer sizes itself
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Font + white text
	if bubble_font != null:
		label.add_theme_font_override("font", bubble_font)
	label.add_theme_font_size_override("font_size", bubble_font_size)
	label.add_theme_color_override("font_color", bubble_text_color)

	# Start empty for typewriter
	label.text = ""
	
	vb.add_child(label)
	label.custom_minimum_size = Vector2(bubble_min_width, 0)

	bubble_ui_root.add_child(panel)
	_bubble_by_unit[u] = panel

	# -------------------------
	# Position (world -> UI)
	# -------------------------
	var ui_pos := _world_to_ui(u.global_position + Vector2(0, bubble_y_offset_px))
	panel.position = ui_pos

	# Wait one frame so Control sizes itself, then center it
	await get_tree().process_frame
	panel.position.x -= panel.size.x * 0.5

	# -------------------------
	# Typewriter effect
	# -------------------------
	var cps = max(1.0, bubble_type_speed_cps)
	var delay = 1.0 / cps

	var wrapped := false

	# Reveal characters over time.
	# If unit gets freed, stop cleanly.
	for i in range(text.length()):
		# pre-check
		if u == null or not is_instance_valid(u):
			break
		if panel == null or not is_instance_valid(panel):
			break

		label.text = text.substr(0, i + 1)

		# Choose style based on unit type (infantry vs merc)
		var style := 0
		if u != null and is_instance_valid(u) and u.has_meta("voice_style"):
			style = int(u.get_meta("voice_style")) # 0 infantry, 1 merc

		_bubble_voice_tick(text.substr(i, 1), style)

		await get_tree().process_frame

		# ✅ post-await re-check (panel can die during await)
		if u == null or not is_instance_valid(u):
			break
		if panel == null or not is_instance_valid(panel):
			break

		# If it grows too wide, clamp width once and let autowrap handle the rest
		if not wrapped and bubble_max_width > 0.0:
			var w := panel.size.x
			if w > bubble_max_width:
				wrapped = true
				label.custom_minimum_size.x = bubble_max_width
				await get_tree().process_frame

				# ✅ re-check again after await
				if u == null or not is_instance_valid(u):
					break
				if panel == null or not is_instance_valid(panel):
					break

		# Reposition + center
		panel.position = _world_to_ui(u.global_position + Vector2(0, bubble_y_offset_px))
		panel.position.x -= panel.size.x * 0.5

		await get_tree().create_timer(delay).timeout

	# -------------------------
	# Hold + fade + cleanup
	# -------------------------
	if panel == null or not is_instance_valid(panel):
		return

	if panel == null or not is_instance_valid(panel):
		return

	var tw := create_tween()
	tw.tween_interval(max(0.01, bubble_duration))
	tw.tween_property(panel, "modulate:a", 0.0, max(0.01, bubble_fade_time))
	tw.finished.connect(func():
		if u != null and is_instance_valid(u):
			_kill_bubble(u)
		elif panel != null and is_instance_valid(panel):
			panel.queue_free()
	)

func _world_to_ui(p_world: Vector2) -> Vector2:
	# world -> canvas (screen-ish) coords
	var canvas_pos := get_viewport().get_canvas_transform() * p_world
	# canvas -> bubble_ui_root local coords
	return bubble_ui_root.get_global_transform_with_canvas().affine_inverse() * canvas_pos

func _bubble_voice_tick(ch: String, voice_style := 0) -> void:
	if bubble_voice_stream == null:
		return

	if ch == " " and randf() > bubble_voice_space_chance:
		return
	if (ch == "." or ch == "!" or ch == "?" or ch == ",") and randf() > bubble_voice_punct_chance:
		return

	var p := AudioStreamPlayer.new()
	p.stream = bubble_voice_stream
	p.bus = bubble_voice_bus
	p.volume_db = linear_to_db(clamp(bubble_voice_volume, 0.0, 2.0))

	var base := bubble_voice_pitch_base * (0.98 if voice_style == 0 else 0.92)
	var jitter := randf_range(-bubble_voice_pitch_jitter, bubble_voice_pitch_jitter)

	var lower := ch.to_lower()
	if lower in ["a","e","i","o","u"]:
		jitter += 0.05

	p.pitch_scale = max(0.05, base + jitter)

	add_child(p)
	p.finished.connect(func():
		if p != null and is_instance_valid(p):
			p.queue_free()
	)

	p.play()

func set_overwatch(u: Unit, enabled: bool, r: int = 0, turns := 1) -> void:
	_prune_overwatch_dicts()
	if u == null or not is_instance_valid(u):
		return

	if not enabled:
		overwatch_by_unit.erase(u)
		_remove_overwatch_ghost(u)
		return

	if r <= 0:
		r = u.attack_range + 3

	overwatch_by_unit[u] = {"range": r, "turns": int(turns)}

	_add_overwatch_ghost(u)
	_update_overwatch_ghost_pos(u)

	_sfx(sfx_overwatch_on, sfx_volume_ui, 1.0)
	_say(u, "Overwatch set.")


func is_overwatching(u: Unit) -> bool:
	return u != null and is_instance_valid(u) and overwatch_by_unit.has(u)

func clear_overwatch(u: Unit) -> void:
	if u == null:
		return
	overwatch_by_unit.erase(u)
	_remove_overwatch_ghost(u)

func _check_overwatch_trigger(_mover: Unit, _entered_cell: Vector2i) -> void:
	_prune_overwatch_dicts()

	# Build safe watcher list
	var watchers: Array[Unit] = []
	for k in overwatch_by_unit.keys():
		var w := k as Unit
		if w != null and is_instance_valid(w) and w.team == Unit.Team.ALLY:
			watchers.append(w)

	# Optional: stable order (closest-to-center doesn’t matter now)
	watchers.sort_custom(func(a: Unit, b: Unit) -> bool:
		return (a.cell.x + a.cell.y) < (b.cell.x + b.cell.y)
	)

	# Fire: each watcher takes ONE overwatch shot, but can pick ANY enemy in range.
	for w in watchers:
		if w == null or not is_instance_valid(w):
			continue
		if not overwatch_by_unit.has(w):
			continue

		var targets := _enemies_in_overwatch_range(w)
		if targets.is_empty():
			continue

		# Pick a target (closest)
		var t := targets[0]
		if t == null or not is_instance_valid(t) or t.hp <= 0:
			continue

		_face_unit_toward_world(w, t.global_position)
		_sync_ghost_facing(w)

		_say(w, "Contact!")
		_sfx(sfx_overwatch_shot, sfx_volume_world, randf_range(0.95, 1.05), w.global_position)

		await _do_attack(w, t)

func _get_unit_render_node(u: Unit) -> CanvasItem:
	if u == null or not is_instance_valid(u):
		return null

	# Fast paths
	var spr := u.get_node_or_null("Sprite2D") as Sprite2D
	if spr != null:
		return spr
	var anim := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		return anim

	# ✅ Recursive search (handles Visual/Skeleton/etc)
	return _find_first_canvasitem_descendant(u)

func _find_first_canvasitem_descendant(n: Node) -> CanvasItem:
	for ch in n.get_children():
		if ch is CanvasItem:
			return ch as CanvasItem
		var deeper := _find_first_canvasitem_descendant(ch)
		if deeper != null:
			return deeper
	return null

func _add_overwatch_ghost(u: Unit) -> void:
	_prune_overwatch_dicts()

	if u == null or not is_instance_valid(u):
		return
	if overwatch_ghost_by_unit.has(u):
		# already has one, just ensure it still exists
		var existing := overwatch_ghost_by_unit[u] as CanvasItem
		if existing != null and is_instance_valid(existing):
			_update_overwatch_ghost_pos(u)
			return
		overwatch_ghost_by_unit.erase(u)

	_ensure_overlay_subroots()
	if overlay_ghosts_root == null:
		return

	var src := _get_unit_render_node(u)
	if src == null or not is_instance_valid(src):
		return

	var ghost := src.duplicate() as CanvasItem
	if ghost == null:
		return

	ghost.name = "OverwatchGhost"
	ghost.modulate = overwatch_ghost_color
	ghost.visible = true
	ghost.show()
	ghost.z_as_relative = false

	# ✅ Put ghost somewhere that _clear_overlay() will NOT delete
	overlay_ghosts_root.add_child(ghost)

	# ✅ keep it ALWAYS above units
	ghost.z_index = 1 + (u.cell.x + u.cell.y)

	overwatch_ghost_by_unit[u] = ghost
	_update_overwatch_ghost_pos(u)

func _remove_overwatch_ghost(u: Unit) -> void:
	_prune_overwatch_dicts()

	if u == null:
		return
	if not overwatch_ghost_by_unit.has(u):
		return

	var g := overwatch_ghost_by_unit[u] as CanvasItem
	overwatch_ghost_by_unit.erase(u)
	if g != null and is_instance_valid(g):
		g.queue_free()


func _update_overwatch_ghost_pos(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return
	if not overwatch_ghost_by_unit.has(u):
		return

	var g := overwatch_ghost_by_unit[u] as CanvasItem
	if g == null or not is_instance_valid(g):
		return

	# ✅ position works for CanvasItem too
	g.global_position = u.global_position + overwatch_ghost_offset

	# ✅ DO NOT crush z_index back down to 1+(x+y)
	g.z_as_relative = false
	g.z_index = 1 + (u.cell.x + u.cell.y)

	_sync_ghost_facing(u)

func _ensure_overlay_subroots() -> void:
	if overlay_root == null or not is_instance_valid(overlay_root):
		return

	overlay_tiles_root = overlay_root.get_node_or_null("Tiles") as Node2D
	if overlay_tiles_root == null:
		overlay_tiles_root = Node2D.new()
		overlay_tiles_root.name = "Tiles"
		overlay_root.add_child(overlay_tiles_root)

	overlay_ghosts_root = overlay_root.get_node_or_null("Ghosts") as Node2D
	if overlay_ghosts_root == null:
		overlay_ghosts_root = Node2D.new()
		overlay_ghosts_root.name = "Ghosts"
		overlay_root.add_child(overlay_ghosts_root)

func _prune_overwatch_dicts() -> void:
	# ----- overwatch_by_unit -----
	var keys1: Array = overwatch_by_unit.keys() # snapshot
	for k in keys1:
		# If the key isn't even an Object, remove it
		if not (k is Object):
			overwatch_by_unit.erase(k)
			continue

		var obj := k as Object
		if not is_instance_valid(obj):
			overwatch_by_unit.erase(k)
			continue

		# Only now is it safe to treat it like a Unit (optional)
		# if not (obj is Unit):
		#     overwatch_by_unit.erase(k)

	# ----- overwatch_ghost_by_unit -----
	var keys2: Array = overwatch_ghost_by_unit.keys() # snapshot
	for k in keys2:
		# Grab ghost first using the raw key (doesn't require casting)
		var g := overwatch_ghost_by_unit.get(k, null) as CanvasItem

		# Key validity checks WITHOUT casting to Unit
		if not (k is Object) or not is_instance_valid(k as Object):
			overwatch_ghost_by_unit.erase(k)
			if g != null and is_instance_valid(g):
				g.queue_free()
			continue

		# Now validate the ghost
		if g == null or not is_instance_valid(g):
			overwatch_ghost_by_unit.erase(k)
			continue

func _sync_ghost_facing(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return
	if not overwatch_ghost_by_unit.has(u):
		return

	var ghost := overwatch_ghost_by_unit[u] as CanvasItem
	if ghost == null or not is_instance_valid(ghost):
		return

	# Get render node of real unit
	var src := _get_unit_render_node(u)
	if src == null or not is_instance_valid(src):
		return

	# Copy horizontal flip if available
	if src is Sprite2D and ghost is Sprite2D:
		(ghost as Sprite2D).flip_h = (src as Sprite2D).flip_h
	elif src is AnimatedSprite2D and ghost is AnimatedSprite2D:
		(ghost as AnimatedSprite2D).flip_h = (src as AnimatedSprite2D).flip_h

func _enemies_in_overwatch_range(w: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	if w == null or not is_instance_valid(w):
		return out
	if not overwatch_by_unit.has(w):
		return out

	var data = overwatch_by_unit[w]
	var r := int(data.get("range", w.attack_range))

	for e in get_all_units():
		if e == null or not is_instance_valid(e):
			continue
		if e.team != Unit.Team.ENEMY:
			continue

		var d = abs(w.cell.x - e.cell.x) + abs(w.cell.y - e.cell.y)
		if d > r:
			continue
		if not _has_clear_attack_path(w.cell, e.cell):
			continue

		out.append(e)

	# Optional: closest first
	out.sort_custom(func(a: Unit, b: Unit) -> bool:
		var da = abs(w.cell.x - a.cell.x) + abs(w.cell.y - a.cell.y)
		var db = abs(w.cell.x - b.cell.x) + abs(w.cell.y - b.cell.y)
		return da < db
	)
	return out

func tick_overwatch_turn() -> void:
	_prune_overwatch_dicts()

	var to_clear: Array[Unit] = []

	for k in overwatch_by_unit.keys():
		var u := k as Unit
		if u == null or not is_instance_valid(u):
			continue

		var data = overwatch_by_unit[u]
		var t := int(data.get("turns", 1)) - 1

		if t <= 0:
			to_clear.append(u)
		else:
			data["turns"] = t
			overwatch_by_unit[u] = data

	for u in to_clear:
		clear_overwatch(u)

const META_MOVED := &"turn_moved"
const META_ATTACKED := &"turn_attacked"

func _unit_has_moved(u: Unit) -> bool:
	return u != null and is_instance_valid(u) and u.has_meta(META_MOVED) and bool(u.get_meta(META_MOVED))

func _unit_has_attacked(u: Unit) -> bool:
	return u != null and is_instance_valid(u) and u.has_meta(META_ATTACKED) and bool(u.get_meta(META_ATTACKED))

func _set_unit_moved(u: Unit, v: bool) -> void:
	if u != null and is_instance_valid(u):
		u.set_meta(META_MOVED, v)

func _set_unit_attacked(u: Unit, v: bool) -> void:
	if u != null and is_instance_valid(u):
		u.set_meta(META_ATTACKED, v)

func reset_turn_flags_for_allies() -> void:
	for u in get_all_units():
		if u != null and is_instance_valid(u) and u.team == Unit.Team.ALLY:
			_set_unit_moved(u, false)
			_set_unit_attacked(u, false)
			# optional tint reset
			set_unit_exhausted(u, false)
	
	_apply_turn_indicators_all_allies()

func _all_allies_done() -> bool:
	for u in get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team != Unit.Team.ALLY:
			continue
		if not _unit_has_moved(u) or not _unit_has_attacked(u):
			return false
	return true

func _edge_spawn_ok(c: Vector2i, structure_blocked: Dictionary) -> bool:
	if not _is_walkable(c):
		return false
	if structure_blocked.has(c):
		return false
	if units_by_cell.has(c):
		return false
	return true

func spawn_edge_road_zombie() -> bool:
	if enemy_zombie_scene == null or units_root == null or terrain == null or grid == null:
		return false

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	var w := int(grid.w)
	var h := int(grid.h)
	if w <= 0 or h <= 0:
		return false

	var best_cell := Vector2i(-1, -1)
	var max_inset := int(min(w, h) / 2)

	for inset in range(max_inset + 1):
		var min_x := inset
		var min_y := inset
		var max_x := (w - 1) - inset
		var max_y := (h - 1) - inset

		if min_x > max_x or min_y > max_y:
			break

		var ring: Array[Vector2i] = []

		for x in range(min_x, max_x + 1):
			ring.append(Vector2i(x, min_y))
			if max_y != min_y:
				ring.append(Vector2i(x, max_y))

		for y in range(min_y + 1, max_y):
			ring.append(Vector2i(min_x, y))
			if max_x != min_x:
				ring.append(Vector2i(max_x, y))

		var valid: Array[Vector2i] = []
		for c in ring:
			if _edge_spawn_ok(c, structure_blocked):
				valid.append(c)

		if not valid.is_empty():
			best_cell = valid.pick_random()
			break

	if best_cell.x < 0:
		return false

	var z := enemy_zombie_scene.instantiate() as Unit
	if z == null:
		return false

	units_root.add_child(z)

	# ✅ FIX: connect died signal so parts/pickups can drop
	_wire_unit_signals(z)

	z.team = Unit.Team.ENEMY
	z.hp = z.max_hp

	z.set_cell(best_cell, terrain)
	units_by_cell[best_cell] = z
	_set_unit_depth_from_world(z, z.global_position)

	var ci := _get_unit_render_node(z)
	if ci != null and is_instance_valid(ci):
		var m := ci.modulate
		m.a = 0.0
		ci.modulate = m

		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(ci, "modulate:a", 1.0, enemy_fade_time)

	return true

func _is_road_tile(cell: Vector2i) -> bool:
	# Roads are tracked logically in Game.gd (terrain cell coverage).
	if game_ref == null:
		return false
	if not ("road_blocked" in game_ref):
		return false
	var rb: Dictionary = game_ref.road_blocked
	return rb.has(cell)

func _ringout_dir_world(attacker: Unit, defender: Unit) -> Vector2:
	# Direction from attacker -> defender, in world space
	var a := _cell_world(attacker.cell)
	var d := _cell_world(defender.cell)
	var v := (d - a)
	if v.length() < 0.001:
		v = Vector2(1, 0)
	return v.normalized()

func _ringout_push_and_die(attacker: Unit, defender: Unit) -> void:
	if attacker == null or defender == null:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	_is_moving = true

	var def_cell: Vector2i = defender.cell          # ✅ capture BEFORE awaits
	var def_id: int = defender.get_instance_id()     # ✅ capture BEFORE awaits

	_flash_unit_white(defender, max(attack_flash_time, 0.12))

	var visual := _get_unit_visual_node(defender)
	if visual == null or not is_instance_valid(visual):
		visual = defender

	var from := visual.global_position
	var dir := _ringout_dir_world(attacker, defender)
	var to := from + dir * ringout_push_px + Vector2(0, ringout_drop_px)

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)

	tw.tween_method(func(p: Vector2) -> void:
		var uu := instance_from_id(def_id)
		if uu == null or not is_instance_valid(uu):
			return
		if not (uu is Unit):
			return
		var uuu := uu as Unit

		var vv := _get_unit_visual_node(uuu)
		if vv == null or not is_instance_valid(vv):
			vv = uuu

		vv.global_position = p
		_set_unit_depth_from_world(uuu, p)
	, from, to, max(0.01, ringout_push_time))

	# Optional fade (safe: re-check inside)
	var ci := _get_unit_render_node(defender)
	if ci != null and is_instance_valid(ci):
		tw.parallel().tween_property(ci, "modulate:a", 0.0, max(0.01, ringout_fade_time))

	await tw.finished

	# ✅ Re-acquire defender safely AFTER await
	var obj := instance_from_id(def_id)
	if obj == null or not is_instance_valid(obj) or not (obj is Unit):
		_is_moving = false
		# If dictionary still has junk, this cleans it:
		_cleanup_dead_at(def_cell)
		return

	var d := obj as Unit
	d.hp = 0
	await _play_death_and_wait(d)

	# ✅ Remove by CELL (does not pass freed Unit into typed function)
	_remove_unit_from_board_at_cell(def_cell)

	_is_moving = false

func _try_recruit_near_structure(mover: Unit) -> void:
	if not recruit_enabled:
		return
	if mover == null or not is_instance_valid(mover):
		return
	if mover.team != Unit.Team.ALLY:
		return
	if ally_scenes.is_empty():
		return
	if terrain == null or units_root == null or grid == null:
		return

	# Find an adjacent structure cell (8-neighbors)
	var s_cell := _find_adjacent_structure_cell(mover.cell)
	if s_cell.x < -100:
		return

	# Optional: only recruit once per structure per round
	if recruit_once_per_structure_per_round:
		var s := _structure_at_cell(s_cell)
		if s != null and is_instance_valid(s):
			var stamp: int = int(s.get_meta("recruit_stamp", -999))
			if stamp == recruit_round_stamp:
				return
			s.set_meta("recruit_stamp", recruit_round_stamp)

	# Find an open adjacent tile to the structure (spawn location)
	var spawn_cell := _find_open_adjacent_to_structure(s_cell)
	if spawn_cell.x < 0:
		return

	_spawn_recruited_ally_fadein(spawn_cell)


func _find_adjacent_structure_cell(cell: Vector2i) -> Vector2i:
	# check 8-neighbors around the mover to see if any is occupied by a structure footprint
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var c := cell + Vector2i(dx, dy)
			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue
			var s := _structure_at_cell(c)
			if s != null and is_instance_valid(s):
				return c
	return Vector2i(-999, -999)


func _find_open_adjacent_to_structure(s_cell: Vector2i) -> Vector2i:
	# Use structure-blocked dict if you have it
	var structure_blocked: Dictionary = {} as Dictionary

	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	var candidates: Array[Vector2i] = []
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var c := s_cell + Vector2i(dx, dy)

			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue
			if not _is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			if units_by_cell.has(c):
				continue
			if mines_by_cell.has(c):
				continue

			candidates.append(c)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	# Prefer closer-to-player-ish: pick random is fine, but you can sort if you want
	return candidates.pick_random()

func _spawn_recruited_ally_fadein(spawn_cell: Vector2i) -> void:
	if recruit_bot_scene == null:
		push_warning("Recruit: recruit_bot_scene not assigned.")
		return
	if terrain == null or units_root == null:
		return
	if units_by_cell.has(spawn_cell):
		return

	var u := recruit_bot_scene.instantiate() as Unit
	if u == null:
		push_warning("Recruit: recruit_bot_scene root must extend Unit.")
		return

	units_root.add_child(u)
	_wire_unit_signals(u)
	u.team = Unit.Team.ALLY
	u.hp = u.max_hp

	# Put on grid first
	u.set_cell(spawn_cell, terrain)
	units_by_cell[spawn_cell] = u
	_set_unit_depth_from_world(u, u.global_position)

	# Fade in (fade the render node, not the Unit)
	var ci := _get_unit_render_node(u)
	if ci != null and is_instance_valid(ci):
		var m := ci.modulate
		m.a = 0.0
		ci.modulate = m

	_sfx(recruit_sfx, sfx_volume_world, randf_range(0.95, 1.05), _cell_world(spawn_cell))
	_say(u, "Recruited!")

	if ci != null and is_instance_valid(ci):
		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(ci, "modulate:a", 1.0, max(0.01, recruit_fade_time))

		tw.finished.connect(func():
			_apply_turn_indicators_all_allies()
			if TM != null:
				if TM.has_method("on_units_spawned"):
					TM.on_units_spawned()
				if TM.has_method("_update_special_buttons"):
					TM._update_special_buttons()
		)
	else:
		_apply_turn_indicators_all_allies()
		if TM != null:
			if TM.has_method("on_units_spawned"):
				TM.on_units_spawned()
			if TM.has_method("_update_special_buttons"):
				TM._update_special_buttons()

func get_all_enemies() -> Array[Unit]:
	var out: Array[Unit] = []
	for u in get_all_units():
		if u != null and is_instance_valid(u) and u.team == Unit.Team.ENEMY:
			out.append(u)
	return out


func fire_support_missile_curve_async(
	from_cell: Vector2i,
	to_cell: Vector2i,
	flight_time := 1.35,
	arc_height_px := 84.0,
	steps := 28
) -> Tween:
	if terrain == null:
		return null

	var parent_node: Node2D = overlay_root if (overlay_root != null and is_instance_valid(overlay_root)) else self

	var line := Line2D.new()
	line.width = 1.0
	line.antialiased = true
	line.z_as_relative = false
	line.default_color = Color(1, 1, 1, 1)
	line.modulate.a = missile_line_alpha_start
	line.z_index = 2 + (from_cell.x + from_cell.y)
	parent_node.add_child(line)

	var start_w := terrain.to_global(terrain.map_to_local(from_cell))
	var end_w := terrain.to_global(terrain.map_to_local(to_cell))
	var start := parent_node.to_local(start_w)
	start.y -= 8
	var end := parent_node.to_local(end_w)

	var steps_i = max(8, int(steps))

	var curve: Array[Vector2] = []
	curve.resize(steps_i + 1)
	for i in range(steps_i + 1):
		var t := float(i) / float(steps_i)
		var pos := start.lerp(end, t)
		var peak := 4.0 * t * (1.0 - t)
		pos.y -= arc_height_px * peak
		curve[i] = pos

	line.clear_points()
	line.add_point(curve[0])
	line.add_point(curve[0])

	_sfx(sfx_missile_launch, sfx_volume_world, randf_range(0.95, 1.05), start_w)

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.set_ease(Tween.EASE_IN_OUT)

	tw.parallel().tween_property(line, "modulate:a", missile_line_alpha_end, max(0.01, flight_time))

	tw.parallel().tween_method(func(tt: float) -> void:
		if line == null or not is_instance_valid(line):
			return

		var last_i = clamp(int(floor(tt * steps_i)), 0, steps_i)

		# keep last point as tip
		while (line.get_point_count() - 1) < (last_i + 1):
			line.add_point(curve[line.get_point_count() - 1])

		var tip := start.lerp(end, tt)
		var peak := 4.0 * tt * (1.0 - tt)
		tip.y -= arc_height_px * peak
		line.set_point_position(line.get_point_count() - 1, tip)

		var tip_w := parent_node.to_global(tip)
		var local_in_terrain := terrain.to_local(tip_w)
		var c := terrain.local_to_map(local_in_terrain)
		line.z_index = 10000 + (c.x + c.y)
	, 0.0, 1.0, max(0.01, flight_time))

	tw.finished.connect(func():
		if line != null and is_instance_valid(line):
			line.queue_free()
	)

	return tw

func run_recruit_support_phase() -> void:
	var recruits: Array[RecruitBot] = []
	for u in get_all_units():
		if u != null and is_instance_valid(u) and u is RecruitBot:
			recruits.append(u as RecruitBot)

	if recruits.is_empty():
		return

	# Optional: stable order
	recruits.sort_custom(func(a: RecruitBot, b: RecruitBot) -> bool:
		return (a.cell.x + a.cell.y) < (b.cell.x + b.cell.y)
	)

	# Run each recruit once
	for r in recruits:
		if r == null or not is_instance_valid(r):
			continue
		# Don’t double-fire if already acted (in case you call this twice)
		if _unit_has_attacked(r):
			continue

		await r.auto_support_action(self)

func spawn_pickup_at(cell: Vector2i, pickup_scene: PackedScene) -> void:
	if pickup_scene == null:
		return
	if cell.x < 0:
		return
	if pickups_by_cell.has(cell):
		return

	# ✅ Allow spawning on a cell that is currently occupied by a unit that is dying/dead
	if units_by_cell.has(cell):
		var v = units_by_cell[cell]
		if v != null and (v is Unit) and is_instance_valid(v):
			var uu := v as Unit
			# if still alive, don't spawn on top of it
			if uu.hp > 0:
				return
		# if it's invalid / freed / hp<=0, allow

	var p := pickup_scene.instantiate()
	add_child(p) # or pickups_root if you have one
	p.global_position = _cell_world(cell)
	p.global_position.y -= 16
	p.set_meta("cell", cell)
	pickups_by_cell[cell] = p

	# depth align (same rule as units)
	if p is Node2D:
		var n := p as Node2D
		n.z_as_relative = false
		n.z_index = 1 + (cell.x + cell.y)

func try_collect_pickup(u: Variant) -> void:
	# ✅ accept freed references safely
	if u == null or not (u is Unit) or not is_instance_valid(u):
		return
	var uu := u as Unit

	var c := uu.cell
	if not pickups_by_cell.has(c):
		return

	var p = pickups_by_cell[c]
	pickups_by_cell.erase(c)
	if p != null and is_instance_valid(p):
		p.queue_free()

	emit_signal("pickup_collected", uu, c)

func on_unit_died(u: Unit) -> void:
	if u == null:
		return
	# only zombies
	if u.team != Unit.Team.ENEMY:
		return

	# only drop until beacon is complete
	if beacon_parts_collected >= beacon_parts_needed:
		return

	# drop chance (or guarantee)
	var drop_chance := 0.25
	if randf() <= drop_chance:
		spawn_pickup_at(u.cell, floppy_pickup_scene)

func _on_pickup_collected(u: Unit, cell: Vector2i) -> void:
	# give the unit a floppy
	u.floppy_parts += 1
	_sfx(&"pickup_floppy", 1.0, randf_range(0.95, 1.05), _cell_world(u.cell))

	_check_and_trigger_beacon_sweep()

func try_deliver_to_beacon(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return
	if u.team != Unit.Team.ALLY:
		return
	if u.cell != beacon_cell:
		return
	if u.floppy_parts <= 0:
		return
	if beacon_ready:
		return

	# deliver everything the unit has
	beacon_parts_collected += u.floppy_parts
	u.floppy_parts = 0

	_sfx(&"beacon_upload", 1.0, 1.0, _cell_world(beacon_cell))

	if beacon_parts_collected >= beacon_parts_needed:
		beacon_ready = true
		_update_beacon_marker()
		_sfx(&"beacon_ready", 1.0, 1.0, _cell_world(beacon_cell))

func satellite_sweep() -> void:
	# snapshot the list (important)
	var zombies: Array = []
	for u in get_all_units():
		if u != null and is_instance_valid(u) and u.team == Unit.Team.ENEMY:
			zombies.append(u)

	# preload once
	var boom_scene := preload("res://scenes/explosion.tscn")

	# dramatic sequence
	for z in zombies:
		if z == null or not is_instance_valid(z):
			continue

		var p := _cell_world(z.cell)

		# ✅ beam from space down to zombie
		_spawn_sat_beam(p)

		# laser sfx + optional laser fx scene
		_sfx(&"sat_laser", 1.0, randf_range(0.95, 1.05), p)

		# explosion (your existing explosion scene)
		var boom = boom_scene.instantiate()
		add_child(boom)
		boom.global_position = p

		# kill zombie
		z.take_damage(999)

		# small delay so it reads
		await get_tree().create_timer(0.05).timeout

func _wire_unit_signals(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return

	# If you used "on_unit_died" (no underscore), connect to that.
	if u.has_signal("died"):
		var cb := Callable(self, "on_unit_died")
		if not u.died.is_connected(cb):
			u.died.connect(cb)

func _ensure_beacon_marker() -> void:
	if terrain == null:
		return
	if beacon_cell.x < 0:
		return
	if beacon_marker_scene == null:
		return

	# If it exists, just update position/depth
	if beacon_marker_node != null and is_instance_valid(beacon_marker_node):
		_update_beacon_marker()
		return

	var n := beacon_marker_scene.instantiate() as Node2D
	if n == null:
		return

	# Parent choice:
	# - overlay_root if you want it above roads/terrain overlays
	# - units_root if you want it to depth-sort with units
	var parent: Node = overlay_root if (overlay_root != null and is_instance_valid(overlay_root)) else self
	parent.add_child(n)

	beacon_marker_node = n
	beacon_marker_node.name = "BeaconMarker"

	# Tell marker the authoritative cell if it wants it
	beacon_marker_node.set_meta("beacon_cell", beacon_cell)

	_update_beacon_marker()

func _update_beacon_marker() -> void:
	if beacon_marker_node == null or not is_instance_valid(beacon_marker_node):
		return
	if terrain == null:
		return

	var world := _cell_world(beacon_cell) + Vector2(0, beacon_marker_y_offset_px)
	beacon_marker_node.global_position = world

	# Depth: x+y sum, consistent with everything else
	beacon_marker_node.z_as_relative = false
	beacon_marker_node.z_index = int(beacon_marker_z_base + beacon_cell.x + beacon_cell.y)

	# Optional: visually indicate "ready"
	if beacon_marker_node.has_method("set_ready"):
		beacon_marker_node.call("set_ready", beacon_ready)

	# ✅ Pulse when ready
	if beacon_ready:
		_start_beacon_pulse()
	else:
		_stop_beacon_pulse()

func _clear_beacon_marker() -> void:
	if beacon_marker_node != null and is_instance_valid(beacon_marker_node):
		beacon_marker_node.queue_free()
	beacon_marker_node = null
	_stop_beacon_pulse()
	
func _team_floppy_total_allies() -> int:
	var total := 0
	for u in get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team != Unit.Team.ALLY:
			continue
		# only count if the property exists
		if "floppy_parts" in u:
			total += int(u.get("floppy_parts"))
	return total

func _any_ally_on_beacon() -> Unit:
	for u in get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team != Unit.Team.ALLY:
			continue
		if u.cell == beacon_cell:
			return u
	return null

func _check_and_trigger_beacon_sweep() -> void:
	# Already fired? stop
	if _beacon_sweep_started:
		return

	# ----------------------------
	# 1) ARM the beacon if enough parts collected
	# ----------------------------
	if not beacon_ready:
		var team_total := _team_floppy_total_allies()
		if team_total >= beacon_parts_needed:
			beacon_ready = true
			_sfx(&"beacon_ready", 1.0, 1.0, _cell_world(beacon_cell))
			_update_beacon_marker()   # start pulsing
		else:
			return   # not armed yet, nothing else to do

	# ----------------------------
	# 2) If armed, check for ally standing on beacon
	# ----------------------------
	var carrier := _any_ally_on_beacon()
	if carrier == null:
		return

	# ----------------------------
	# 3) Trigger sweep
	# ----------------------------
	_beacon_sweep_started = true

	_sfx(&"beacon_upload", 1.0, 1.0, _cell_world(beacon_cell))

	# Optional: clear floppy parts after upload
	for u in get_all_units():
		if u != null and is_instance_valid(u) and u.team == Unit.Team.ALLY and ("floppy_parts" in u):
			u.set("floppy_parts", 0)

	# Fire sweep async
	call_deferred("_run_satellite_sweep_async")

func _run_satellite_sweep_async() -> void:
	await satellite_sweep()

func _spawn_sat_beam(world_hit: Vector2) -> void:
	var parent_node: Node2D = overlay_root if (overlay_root != null and is_instance_valid(overlay_root)) else self

	var line := Line2D.new()
	line.width = 1.0
	line.antialiased = false
	line.z_as_relative = false
	line.default_color = Color(1, 0, 0, 1)

	# ✅ compute cell from world_hit
	var cell := Vector2i.ZERO
	if terrain != null and is_instance_valid(terrain):
		var local := terrain.to_local(world_hit)
		cell = terrain.local_to_map(local)

	# ✅ depth (or keep sat_beam_z_boost if you want ALWAYS on top)
	line.z_index = 1 + (cell.x + cell.y)

	parent_node.add_child(line)

	var start_w := world_hit + Vector2(0, -sat_beam_height_px)
	var a := parent_node.to_local(start_w)
	var b := parent_node.to_local(world_hit)

	line.clear_points()
	line.add_point(a)
	line.add_point(b)

	line.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(max(0.01, sat_beam_flash_time))
	tw.tween_property(line, "modulate:a", 0.0, max(0.01, sat_beam_fade_time))
	tw.finished.connect(func():
		if line != null and is_instance_valid(line):
			line.queue_free()
	)

func _stop_beacon_pulse() -> void:
	if _beacon_pulse_tw != null and is_instance_valid(_beacon_pulse_tw):
		_beacon_pulse_tw.kill()
	_beacon_pulse_tw = null

	if beacon_marker_node != null and is_instance_valid(beacon_marker_node):
		beacon_marker_node.modulate.a = 1.0


func _start_beacon_pulse() -> void:
	if beacon_marker_node == null or not is_instance_valid(beacon_marker_node):
		return

	_stop_beacon_pulse()

	# Ensure visible start
	beacon_marker_node.modulate.a = beacon_pulse_max_a

	var tw := create_tween()
	tw.set_loops()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)

	tw.tween_property(beacon_marker_node, "modulate:a", beacon_pulse_min_a, max(0.01, beacon_pulse_time))
	tw.tween_property(beacon_marker_node, "modulate:a", beacon_pulse_max_a, max(0.01, beacon_pulse_time))

	_beacon_pulse_tw = tw

func reset_beacon_state() -> void:
	# logical counters
	beacon_parts_collected = 0
	beacon_ready = false
	_beacon_sweep_started = false

	# clear any carried parts on allies (optional but usually desired on reset)
	for u in get_all_units():
		if u != null and is_instance_valid(u) and u.team == Unit.Team.ALLY and ("floppy_parts" in u):
			u.set("floppy_parts", 0)

	# visuals
	_update_beacon_marker()  # will stop pulsing because beacon_ready=false

func _pick_random_walkable_beacon_cell() -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)

	# Structure-blocked cells from Game
	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	var w := int(grid.w)
	var h := int(grid.h)
	if w <= 0 or h <= 0:
		return Vector2i(-1, -1)

	var candidates: Array[Vector2i] = []
	for x in range(w):
		for y in range(h):
			var c := Vector2i(x, y)
			if not _is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			if units_by_cell.has(c): # don't place beacon under units
				continue
			if mines_by_cell.has(c): # optional: don't overlap mines
				continue
			candidates.append(c)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	return candidates.pick_random()


func _randomize_beacon_cell() -> void:
	var c := _pick_random_walkable_beacon_cell()
	if c.x < 0:
		return

	beacon_cell = c

	# keep marker in sync
	_clear_beacon_marker()     # ensures old marker is removed if any
	_ensure_beacon_marker()    # spawns marker at new beacon_cell (and pulses if ready)
