extends Node
class_name MapController

@export var camera: Camera2D
@export var terrain_path: NodePath
@export var units_root_path: NodePath
@export var overlay_root_path: NodePath

@export var ally_scenes: Array[PackedScene] = []
@export var enemy_zombie_scene: PackedScene
@export var enemy_elite_mech_scene: PackedScene 

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
var _recruits_spawned_at: Dictionary = {}   # Vector2i -> true

@export var recruit_buildings_needed := 0

var _secured_unique_ids: Dictionary = {}   # instance_id -> true
var _secured_count := 0

# --- Recruit from remaining ally_scenes (unique) ---
var _recruit_pool: Array[PackedScene] = []    # leftover ally scenes not used yet (mutable)
var _used_ally_scenes: Array[PackedScene] = [] # starting + recruited (tracks uniqueness)

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

signal tutorial_event(id: StringName, payload: Dictionary)

var special_unit: Unit = null

# --- Bomber drop-in ---
@export var bomber_scene: PackedScene
@export var bomber_y_offscreen := -520.0         # start/end Y above camera
@export var bomber_arrive_time := 0.45
@export var bomber_depart_time := 0.40
@export var bomber_hover_px := 18.0              # tiny hover bob while dropping (optional)

@export var drop_fall_time := 0.22
@export var drop_land_pop_time := 0.10
@export var drop_land_pop_px := 10.0
@export var drop_sfx := &"drop_thump"
@export var bomber_sfx_in := &"bomber_in"
@export var bomber_sfx_out := &"bomber_out"

@export var evac_enabled := true
@export var evac_pickup_time := 0.22
@export var evac_fade_time := 0.18
@export var evac_lift_px := 160.0
@export var evac_pause_between := 0.05
@export var evac_sfx_pickup := &"bomber_pickup"   # add to sfx_streams if you want

const UNIQUE_GROUP := "UniqueBuilding"

@export var recruit_pulse_time := 0.08
@export var recruit_pulse_loops := 3
@export var recruit_pulse_boost := Color(0.0, 0.329, 1.0, 1.0)

@export var recruit_fx_loops := 2
@export var recruit_fx_in_time := 0.10
@export var recruit_fx_hold_time := 0.04
@export var recruit_fx_out_time := 0.18

@export var recruit_fx_color := Color(0.0, 0.9, 1.0, 1.0)   # cyan glow
@export var recruit_fx_alpha_min := 0.70                   # shimmer low
@export var recruit_fx_scale_mul := 1.04                   # tiny pop (safe)

# -------------------------------------------------
# FLOPPY DROP TUNING (pity + pressure scaling)
# -------------------------------------------------
@export var floppy_base_chance := 0.10          # starting chance per zombie kill
@export var floppy_pity_step := 0.10            # added each miss
@export var floppy_pressure_bonus := 0.25       # extra chance at 100% infestation
@export var floppy_pity_cap := 0.90             # don't exceed this before pressure bonus
@export var infestation_limit_for_drops := 32   # match your zombie lose limit

# -------------------------------------------------
# FLOPPY DROP (kill-gated)
# -------------------------------------------------
var floppy_kills_left: int = -1
var floppy_drop_index: int = 0
var zombies_killed_this_map: int = 0

@export var floppy_curve_combat: Array[int] = [4, 6, 8]
@export var floppy_curve_elite:  Array[int] = [6, 8, 10]
@export var floppy_curve_event:  Array[int] = [5, 7, 9]
@export var floppy_curve_boss:   Array[int] = [999] # handled differently if you want phases

var _floppy_pity_accum := 0.0
var _floppy_misses := 0

# -------------------------
# Boss intent overlay
# -------------------------
var _boss_intent_tiles: Array[Node] = []

func boss_clear_intents() -> void:
	for n in _boss_intent_tiles:
		if n != null and is_instance_valid(n):
			n.queue_free()
	_boss_intent_tiles.clear()

func boss_show_intents(cells: Array[Vector2i]) -> void:
	boss_clear_intents()
	if attack_tile_scene == null or overlay_root == null or terrain == null:
		return

	for c in cells:
		var t := attack_tile_scene.instantiate()
		overlay_root.add_child(t)

		# ✅ Use TileMap for exact placement
		t.position = terrain.map_to_local(c)

		# ✅ Layer by grid sum (same rule as units / weakpoints)
		t.z_index = _z_from_cell(c)

		t.set_meta("boss_intent", true)
		_boss_intent_tiles.append(t)

func _z_from_cell(c: Vector2i) -> int:
	# Intent tiles should sit:
	# - above terrain
	# - below units (adjust base if needed)
	var base := 0
	return base + (c.x + c.y)

func _count_zombies_alive() -> int:
	var n := 0
	for uu in get_all_units():
		if uu == null or not is_instance_valid(uu):
			continue
		if uu.hp <= 0:
			continue
		if uu.team == Unit.Team.ENEMY:
			n += 1
	return n

func _roll_floppy_drop() -> bool:
	# Stop rolling if we don't need parts anymore
	if _team_floppy_total_allies() >= beacon_parts_needed:
		_floppy_pity_accum = 0.0
		_floppy_misses = 0
		return false

	var zombies := _count_zombies_alive()
	var limit = max(1, infestation_limit_for_drops)
	var pressure = clamp(float(zombies) / float(limit), 0.0, 1.0)

	# chance grows as you miss + increases under pressure
	var chance = floppy_base_chance + _floppy_pity_accum + (pressure * floppy_pressure_bonus)
	chance = clamp(chance, 0.0, 1.0)

	if randf() <= chance:
		_floppy_pity_accum = 0.0
		_floppy_misses = 0
		return true

	_floppy_misses += 1
	_floppy_pity_accum = min(floppy_pity_cap, _floppy_pity_accum + floppy_pity_step)
	return false

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

	# Fully exhausted
	if (not has_move_left) and (not has_attack_left):
		_set_unit_tint(u, tint_exhausted)
		_stop_pulse(u)
		return

	# ✅ BOTH left: do NOT pulse (this is the “start of turn / just selected” state)
	if has_move_left and has_attack_left:
		_set_unit_tint(u, Color(1, 1, 1, 1))
		_stop_pulse(u)
		return

	# ✅ Attack left ONLY (meaning they must have moved already): PULSE
	if has_attack_left and moved:
		_set_unit_tint(u, tint_attack_left)
		_start_pulse(u)
		return

	# Move left ONLY (they attacked without moving, or whatever your rules allow)
	if has_move_left:
		_set_unit_tint(u, tint_move_left)
		_stop_pulse(u)
		return

	# Fallback safety
	_stop_pulse(u)

func _stop_all_pulses() -> void:
	var keys := _pulse_tw_by_unit.keys() # snapshot

	for k in keys:
		# IMPORTANT: don't do `k is Object` because k might be a freed instance
		if typeof(k) != TYPE_OBJECT:
			var tw0 = _pulse_tw_by_unit.get(k, null)
			_pulse_tw_by_unit.erase(k)
			if tw0 != null and (tw0 is Tween) and is_instance_valid(tw0):
				(tw0 as Tween).kill()
			continue

		if not is_instance_valid(k):
			var tw = _pulse_tw_by_unit.get(k, null)
			_pulse_tw_by_unit.erase(k)
			if is_instance_valid(tw):
				(tw as Tween).kill()
			continue

		# k is live
		var u := k as Unit
		_stop_pulse(u)

	_pulse_tw_by_unit.clear()

func _prune_pulse_dict() -> void:
	var keys: Array = _pulse_tw_by_unit.keys() # snapshot

	for k in keys:
		# value first (safe)
		var tw = _pulse_tw_by_unit.get(k, null)

		# Key validity WITHOUT casting
		if typeof(k) != TYPE_OBJECT or not is_instance_valid(k):
			_pulse_tw_by_unit.erase(k)

			# Kill tween safely too
			if typeof(tw) == TYPE_OBJECT and is_instance_valid(tw) and tw is Tween:
				(tw as Tween).kill()
			continue

		# Optional: prune dead tween values too
		if tw != null and (typeof(tw) != TYPE_OBJECT or not is_instance_valid(tw) or not (tw is Tween)):
			_pulse_tw_by_unit.erase(k)


func _apply_turn_indicators_all_allies() -> void:
	_prune_pulse_dict()
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
	if u == null or not is_instance_valid(u):
		# still try to kill tween if dictionary uses a dead key elsewhere
		return

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
	_used_ally_scenes.clear()
	_recruits_spawned_at.clear()
	_recruit_pool.clear()

	_secured_unique_ids.clear()
	_secured_count = 0

	recruit_round_stamp += 1
	_randomize_beacon_cell()

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	# ✅ NEW: reserve boss/weakpoint cells BEFORE picking allies
	var reserved_boss: Dictionary = {} # Vector2i -> true
	var rs := get_tree().root.get_node_or_null("RunStateNode")
	var is_boss_mission = (rs != null and ("mission_node_type" in rs) and rs.mission_node_type == &"boss")

	if is_boss_mission:
		# Option A: if your Game/BossController provides explicit cells:
		# set game_ref.weakpoint_reserved_cells = [Vector2i(...), ...]
		if game_ref != null and ("weakpoint_reserved_cells" in game_ref):
			for c in game_ref.weakpoint_reserved_cells:
				reserved_boss[c] = true

		# Option B (fallback): reserve a top band so boss always has space
		# (tune the number; 3–5 rows usually enough)
		for x in range(int(grid.w)):
			for y in range(0, 4):
				reserved_boss[Vector2i(x, y)] = true

	var valid_cells: Array[Vector2i] = []

	var start_n = min(ally_count, ally_scenes.size())

	# Prefer near beacon if you want; otherwise use a top-left-ish point or center
	var prefer := Vector2i(int(grid.w / 2), int(grid.h / 2))
	# If you have a beacon cell variable, use that instead:
	# prefer = beacon_cell

	var comp_cells := _pick_component_for_allies(valid_cells, start_n, prefer)
	if comp_cells.is_empty() or comp_cells.size() < start_n:
		# Fallback: just use all valid_cells (but you’ll still risk islands)
		# Better: bail or log
		push_warning("No connected component large enough for ally spawns.")
	else:
		valid_cells = comp_cells
	
	var w := int(grid.w)
	var h := int(grid.h)

	for x in range(w):
		for y in range(h):
			var c := Vector2i(x, y)
			if not _is_walkable(c):
				continue
			if structure_blocked.has(c):
				continue
			# ✅ NEW: keep allies out of boss-reserved cells
			if reserved_boss.has(c):
				continue
			valid_cells.append(c)

	if valid_cells.is_empty():
		return

	# ---------------------------------------------------
	# 1) Pick ally cluster center + choose ally cells (cells only, no units yet)
	# ---------------------------------------------------
	var cluster_center: Vector2i = valid_cells.pick_random()

	valid_cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da = abs(a.x - cluster_center.x) + abs(a.y - cluster_center.y)
		var db = abs(b.x - cluster_center.x) + abs(b.y - cluster_center.y)
		return da < db
	)

	var near := valid_cells.duplicate()
	var chosen_cells: Array[Vector2i] = []

	for i in range(start_n):
		var chosen := Vector2i(-1, -1)

		for idx in range(near.size()):
			var cand: Vector2i = near[idx]
			var ok := true
			for ucell in chosen_cells:
				var dx = abs(cand.x - ucell.x)
				var dy = abs(cand.y - ucell.y)
				if max(dx, dy) <= 1:
					ok = false
					break
			if ok:
				chosen = cand
				near.remove_at(idx)
				break

		if chosen.x < 0:
			if near.is_empty():
				break
			chosen = near.pop_front()

		chosen_cells.append(chosen)

	# ---------------------------------------------------
	# 1.5) Reserve ally cells so enemies can never spawn there
	# ---------------------------------------------------
	var reserved_ally: Dictionary = {} # cell -> true
	for c in chosen_cells:
		reserved_ally[c] = true

	# ---------------------------------------------------
	# 2) Zombies FIRST (based on far center from cluster_center)
	# ---------------------------------------------------
	var enemy_center := _pick_far_center(valid_cells, cluster_center)

	var enemy_zone_radius := 16
	var enemy_zone_cells := _cells_within_radius(valid_cells, enemy_center, enemy_zone_radius)
	if enemy_zone_cells.size() < max_zombies:
		enemy_zone_cells = valid_cells.duplicate()

	# ✅ Remove reserved ally cells from enemy spawn zone up-front
	enemy_zone_cells = enemy_zone_cells.filter(func(c: Vector2i) -> bool:
		return not reserved_ally.has(c)
	)

	_rebuild_recruit_pool_from_allies()

	var is_elite_mission = (rs != null and ("mission_node_type" in rs) and rs.mission_node_type == &"elite")

	# If elite mission, spawn one fewer normal zombie so total pressure stays similar
	var zombies_to_spawn := max_zombies
	if is_elite_mission:
		zombies_to_spawn = maxi(0, max_zombies - 1)

	_spawn_zombies_in_clusters(enemy_zone_cells, zombies_to_spawn, reserved_ally)

	# Spawn the EliteMech in the enemy zone
	if is_elite_mission:
		_spawn_elite_mech_in_zone(enemy_zone_cells, structure_blocked, reserved_ally)

	# ---------------------------------------------------
	# 3) Allies AFTER (bomber drop)
	# ---------------------------------------------------
	var drop_center_cell := cluster_center
	if not chosen_cells.is_empty():
		drop_center_cell = chosen_cells[0]

	var drop_center_world := _cell_world(drop_center_cell)
	_sfx(bomber_sfx_in, sfx_volume_world, 1.0, drop_center_world)

	var bomber := _spawn_bomber(drop_center_world.x, drop_center_world.y)
	if bomber != null:
		await _tween_node_global_pos(
			bomber,
			bomber.global_position,
			drop_center_world + Vector2(0, -bomber_hover_px),
			bomber_arrive_time
		)

	for i in range(chosen_cells.size()):
		var cell_i := chosen_cells[i]
		var scene := ally_scenes[i]
		if scene == null:
			continue

		var u := scene.instantiate() as Unit
		if scene != null and scene.resource_path != "":
			u.set_meta("scene_path", scene.resource_path)
		
		if u == null:
			continue

		units_root.add_child(u)
		_apply_runstate_upgrades_to_unit(u)
		_wire_unit_signals(u)

		u.team = Unit.Team.ALLY

		# ✅ Apply RunState upgrades to THIS unit
		if rs != null and rs.has_method("apply_upgrades_to_unit"):
			rs.apply_upgrades_to_unit(u)

		# ✅ Now clamp hp to new max
		u.hp = u.max_hp

		units_by_cell[cell_i] = u

		if not _used_ally_scenes.has(scene):
			_used_ally_scenes.append(scene)

		if bomber != null:
			await _drop_unit_from_bomber(u, bomber, cell_i)
		else:
			u.set_cell(cell_i, terrain)
			_set_unit_depth_from_world(u, u.global_position)

	# ---------------------------------------------------
	# 4) Weakpoints LAST (boss mission only)
	# ---------------------------------------------------
	if is_boss_mission:
		_spawn_weakpoints_last(structure_blocked, reserved_boss, reserved_ally)

	if bomber != null and is_instance_valid(bomber):
		_sfx(bomber_sfx_out, sfx_volume_world, 1.0, bomber.global_position)
		await _tween_node_global_pos(
			bomber,
			bomber.global_position,
			bomber.global_position + Vector2(0, bomber_y_offscreen),
			bomber_depart_time
		)
		bomber.queue_free()

	print("Spawned allies:", ally_count, "zombies:", max_zombies)

	apply_run_upgrades()

	if TM != null and TM.has_method("on_units_spawned"):
		TM.on_units_spawned()

	_ensure_beacon_marker()

func _neighbors4(c: Vector2i) -> Array[Vector2i]:
	return [c + Vector2i(1,0), c + Vector2i(-1,0), c + Vector2i(0,1), c + Vector2i(0,-1)]

func _build_walkable_set(valid_cells: Array[Vector2i]) -> Dictionary:
	var s: Dictionary = {}
	for c in valid_cells:
		s[c] = true
	return s

func _flood_component(start: Vector2i, walkable: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not walkable.has(start):
		return out

	var q: Array[Vector2i] = [start]
	var seen: Dictionary = { start: true }

	while not q.is_empty():
		var cur = q.pop_front()
		out.append(cur)

		for nb in _neighbors4(cur):
			if not walkable.has(nb):
				continue
			if seen.has(nb):
				continue
			seen[nb] = true
			q.append(nb)

	return out

func _pick_component_for_allies(valid_cells: Array[Vector2i], need: int, prefer_near: Vector2i) -> Array[Vector2i]:
	# Returns ONLY the cells in the chosen component (guaranteed size >= need if possible).
	if valid_cells.is_empty():
		return []

	var walkable := _build_walkable_set(valid_cells)

	# Find all components
	var visited: Dictionary = {}
	var comps: Array = [] # each item: {"cells":Array[Vector2i], "size":int, "center_dist":int}

	for c in valid_cells:
		if visited.has(c):
			continue
		var comp := _flood_component(c, walkable)
		for cc in comp:
			visited[cc] = true

		var size := comp.size()
		var best_dist := 1_000_000
		# distance of this component to prefer_near (use closest cell)
		for cc in comp:
			var d = abs(cc.x - prefer_near.x) + abs(cc.y - prefer_near.y)
			if d < best_dist:
				best_dist = d

		comps.append({"cells": comp, "size": size, "dist": best_dist})

	# Prefer:
	# 1) components that can fit all allies
	# 2) larger components
	# 3) closer to prefer_near (optional nice feel)
	comps.sort_custom(func(a, b) -> bool:
		var asz := int(a["size"])
		var bsz := int(b["size"])
		var aok := (asz >= need)
		var bok := (bsz >= need)
		if aok != bok:
			return aok # true sorts first
		if asz != bsz:
			return asz > bsz
		return int(a["dist"]) < int(b["dist"])
	)

	return comps[0]["cells"] if comps.size() > 0 else []

func _spawn_weakpoints_last(structure_blocked: Dictionary, reserved_boss: Dictionary, reserved_ally: Dictionary) -> void:
	# Only if boss controller exists and has a spawn API
	if game_ref == null:
		return

	var boss := game_ref.get_node_or_null("BossController")
	if boss == null:
		# fallback: maybe it's named differently or on root
		boss = get_tree().current_scene.get_node_or_null("BossController")
	if boss == null:
		return

	# --- Build an "occupied" set ---
	var occupied: Dictionary = {} # Vector2i -> true

	# 1) any unit cell (allies, zombies, elites, etc.)
	for c in units_by_cell.keys():
		occupied[c] = true

	# 2) structures blocked
	for c in structure_blocked.keys():
		occupied[c] = true

	# 3) reserved ally drop cells (extra safety)
	for c in reserved_ally.keys():
		occupied[c] = true

	# 4) beacon cell (so weakpoints never steal it)
	if beacon_cell != Vector2i.ZERO:
		occupied[beacon_cell] = true

	# --- Build candidate cells: boss-reserved band minus occupied ---
	var candidates: Array[Vector2i] = []
	for c in reserved_boss.keys():
		# bounds + walkable check (depends on your rules; keep if you want weakpoints on non-walkable tiles)
		if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
			continue
		if not _is_walkable(c):
			continue
		if occupied.has(c):
			continue
		candidates.append(c)

	# If the boss band got crowded, fall back to any valid walkable cell not occupied
	if candidates.is_empty():
		var w := int(grid.w)
		var h := int(grid.h)
		for x in range(w):
			for y in range(h):
				var c := Vector2i(x, y)
				if not _is_walkable(c):
					continue
				if structure_blocked.has(c):
					continue
				if occupied.has(c):
					continue
				candidates.append(c)

	if candidates.is_empty():
		push_warning("No valid cells available to spawn weakpoints.")
		return

	# --- Tell BossController what it may use ---
	# Prefer passing candidates if your BossController supports it.
	# Option A: BossController has spawn_weakpoints_from_candidates(candidates)
	if boss.has_method("spawn_weakpoints_from_candidates"):
		boss.call("spawn_weakpoints_from_candidates", candidates)
		return

	# Option B: You set a property and call spawn()
	if "weakpoint_spawn_candidates" in boss:
		boss.weakpoint_spawn_candidates = candidates

	if boss.has_method("spawn_weakpoints"):
		boss.call("spawn_weakpoints")

func _spawn_elite_mech_in_zone(zone_cells: Array[Vector2i], structure_blocked: Dictionary, reserved_ally: Dictionary = {}) -> bool:
	if units_root == null or terrain == null:
		return false

	var scene := enemy_elite_mech_scene
	if scene == null:
		push_warning("MapController: enemy_elite_mech_scene not assigned; skipping elite spawn.")
		return false

	# Build valid spawn list
	var valid: Array[Vector2i] = []
	for c in zone_cells:
		if reserved_ally.has(c):
			continue
		if not _is_walkable(c):
			continue
		if structure_blocked.has(c):
			continue
		if units_by_cell.has(c):
			continue
		valid.append(c)

	if valid.is_empty():
		push_warning("MapController: no valid cells to spawn EliteMech.")
		return false

	var cell: Vector2i = valid.pick_random()

	var u := scene.instantiate() as Unit
	if scene != null and scene.resource_path != "":
		u.set_meta("scene_path", scene.resource_path)
	
	if u == null:
		return false

	units_root.add_child(u)
	_wire_unit_signals(u)

	u.team = Unit.Team.ENEMY
	u.hp = u.max_hp

	u.set_cell(cell, terrain)
	units_by_cell[cell] = u
	_set_unit_depth_from_world(u, u.global_position)

	# Fade in (same vibe as zombies)
	var ci := _get_unit_render_node(u)
	if ci != null and is_instance_valid(ci):
		var m := ci.modulate
		m.a = 0.0
		ci.modulate = m

		var tw := create_tween()
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(ci, "modulate:a", 1.0, enemy_fade_time)

	return true

func _spawn_zombies_in_clusters(zone_cells: Array[Vector2i], total: int, reserved_ally: Dictionary = {}) -> void:
	if total <= 0 or zone_cells.is_empty():
		return

	# Remove reserved ally cells from the pool (extra safety)
	zone_cells = zone_cells.filter(func(c: Vector2i) -> bool:
		return not reserved_ally.has(c)
	)

	zone_cells.shuffle()

	# Build multiple clusters, but keep spawning until we hit TOTAL
	var remaining := total
	var max_cluster_size := 4  # tweak: bigger = tighter blobs

	while remaining > 0 and not zone_cells.is_empty():
		# pick an anchor
		var anchor: Vector2i = zone_cells.pop_back()

		# ✅ guard: never spawn on reserved/occupied
		if reserved_ally.has(anchor) or units_by_cell.has(anchor) or (not _is_walkable(anchor)):
			continue

		# Only decrement remaining if we successfully spawned
		if _spawn_unit_walkable(anchor, Unit.Team.ENEMY):
			remaining -= 1
		else:
			continue

		if remaining <= 0:
			break

		# decide how many more for this cluster
		var want = min(remaining, randi_range(1, max_cluster_size - 1))

		# pick nearest cells to anchor from remaining pool
		var near := _neighbors_sorted_by_distance(zone_cells, anchor, 6)

		while want > 0 and not near.is_empty():
			var c: Vector2i = near.pop_front()

			# ✅ guard: never spawn on reserved/occupied
			if reserved_ally.has(c) or units_by_cell.has(c) or (not _is_walkable(c)):
				# still remove from pool so we don't keep re-trying it forever
				var idx0 := zone_cells.find(c)
				if idx0 != -1:
					zone_cells.remove_at(idx0)
				continue

			# spawn (only count if success)
			if _spawn_unit_walkable(c, Unit.Team.ENEMY):
				remaining -= 1
				want -= 1

			# remove from zone pool so it can't be used again
			var idx := zone_cells.find(c)
			if idx != -1:
				zone_cells.remove_at(idx)

			if remaining <= 0:
				break

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

func _spawn_unit_walkable(preferred: Vector2i, team: int, reserved_ally: Dictionary = {}) -> bool:
	var c := _find_nearest_open_walkable(preferred, reserved_ally)
	if c.x < 0:
		push_warning("MapController: no WALKABLE open land found near %s" % [preferred])
		return false

	# Final safety: never allow enemies to use reserved ally cells
	if team != Unit.Team.ALLY and reserved_ally.has(c):
		return false

	var scene: PackedScene

	if team == Unit.Team.ALLY:
		if ally_scenes.is_empty():
			push_error("MapController: ally_scenes is empty.")
			return false
		scene = ally_scenes.pick_random()
	else:
		scene = enemy_zombie_scene
		if scene == null:
			push_error("MapController: enemy_zombie_scene not assigned.")
			return false

	var inst := scene.instantiate()
	var u := inst as Unit
	if u == null:
		push_error("MapController: scene root is not a Unit (must extend Unit).")
		return false

	units_root.add_child(u)
	_wire_unit_signals(u)

	u.team = team
	u.hp = u.max_hp

	u.set_cell(c, terrain)
	units_by_cell[c] = u

	print("Spawned", ("ALLY" if team == Unit.Team.ALLY else "ZOMBIE"), "at", c, "world", u.global_position)
	return true

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

func _find_nearest_open_walkable(preferred: Vector2i, reserved_ally: Dictionary = {}, max_r: int = 12) -> Vector2i:
	# Check preferred first
	if _is_walkable(preferred) and (not units_by_cell.has(preferred)) and (not reserved_ally.has(preferred)):
		return preferred

	# Expand outward in Manhattan rings
	for r in range(1, max_r + 1):
		for dx in range(-r, r + 1):
			var dy = r - abs(dx)

			var c1 := preferred + Vector2i(dx, dy)
			if _is_walkable(c1) and (not units_by_cell.has(c1)) and (not reserved_ally.has(c1)):
				return c1

			if dy != 0:
				var c2 := preferred + Vector2i(dx, -dy)
				if _is_walkable(c2) and (not units_by_cell.has(c2)) and (not reserved_ally.has(c2)):
					return c2

	return Vector2i(-1, -1)

func _mouse_to_cell_no_offset() -> Vector2i:
	if terrain == null:
		return Vector2i.ZERO

	var mouse_view := get_viewport().get_mouse_position()
	var mouse_world := get_viewport().get_canvas_transform().affine_inverse() * mouse_view
	var local := terrain.to_local(mouse_world)
	return terrain.local_to_map(local)

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
				emit_signal("tutorial_event", &"attack_mode_disarmed", {})
			else:
				_set_aim_mode(AimMode.ATTACK)
				_refresh_overlays()
				_sfx(&"ui_arm_attack", sfx_volume_ui, 1.0)
				# --- Tutorial hook ---
				emit_signal("tutorial_event", &"attack_mode_armed", {"cell": (selected.cell if (selected != null and is_instance_valid(selected)) else Vector2i(-1, -1))})
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
					emit_signal("tutorial_event", &"attack_denied_tm_gate", {"cell": selected.cell})
					_set_aim_mode(AimMode.MOVE)
					return

			# Enemy in range -> attack
			if clicked != null and is_instance_valid(clicked) and clicked.team != selected.team and _in_attack_range(selected, clicked.cell):
				if _unit_has_attacked(selected):
					_sfx(&"ui_denied", sfx_volume_ui, 1.0)
					emit_signal("tutorial_event", &"attack_denied_already_attacked", {"cell": selected.cell})
					_set_aim_mode(AimMode.MOVE)
					return

				var atk_from := selected.cell
				var atk_to := clicked.cell
				await _do_attack(selected, clicked)
				# --- Tutorial hook ---
				emit_signal("tutorial_event", &"ally_attacked", {"from": atk_from, "to": atk_to})
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

			# Gate phase (special counts as attack action for most specials)
			if TM != null:
				if not TM.player_input_allowed() or not TM.can_attack(u):
					# For mines, you might still want to stay armed even if gated,
					# but safest is to bail back to MOVE:
					_set_aim_mode(AimMode.MOVE)
					return

			# Only fire if clicked a valid special cell
			if valid_special_cells.has(cell):
				var sid := String(special_id).to_lower().replace(" ", "_")

				# ✅ MINES: place repeatedly, DO NOT exit SPECIAL, DO NOT mark attacked
				if sid == "mines" and (u is Mech):
					var before := mines_by_cell.size()
					await _perform_special(u, sid, cell) # calls perform_place_mine

					var placed := mines_by_cell.size() > before
					if placed:
						# keep your "mines doesn't consume attacked" system
						if u.has_method("mine_placed_one"):
							u.call("mine_placed_one")
						# stay armed and refresh tiles
						aim_mode = AimMode.SPECIAL
						_refresh_overlays()
						emit_signal("aim_changed", int(aim_mode), special_id)

					# Even if not placed (clicked weirdly), stay in SPECIAL so user can try again
					return

				# ✅ SLAM: click ANY slam tile → clamp to a valid aim cell so it always triggers
				if sid == "slam":
					var origin := u.cell
					var dx := cell.x - origin.x
					var dy := cell.y - origin.y

					# pick cardinal axis like M1 does
					var dir := Vector2i.ZERO
					if abs(dx) >= abs(dy):
						dir = Vector2i(sign(dx), 0)
					else:
						dir = Vector2i(0, sign(dy))
					if dir == Vector2i.ZERO:
						dir = Vector2i(0, 1)

					# read min + max from the unit
					var min_d := 1
					if u.has_method("get_special_min_distance"):
						min_d = int(u.call("get_special_min_distance", "slam"))
					elif "slam_min_safe_dist" in u:
						min_d = int(u.slam_min_safe_dist)

					var max_r := 4
					if u.has_method("get_special_range"):
						max_r = int(u.call("get_special_range", "slam"))
					elif "slam_range" in u:
						max_r = int(u.slam_range)

					var dist = abs(dx) + abs(dy)
					var use_d = clamp(dist, min_d, max_r)
					var aim_cell = origin + dir * use_d

					await _perform_special(u, "slam", aim_cell)

					_set_unit_attacked(u, true)
					_apply_turn_indicator(u)
					if TM != null and TM.has_method("notify_player_attacked"):
						TM.notify_player_attacked(u)

					_set_aim_mode(AimMode.MOVE)
					return


				# ✅ All other specials: normal behavior (consume attack + exit)
				await _perform_special(u, sid, cell)

				_set_unit_attacked(u, true)
				_apply_turn_indicator(u)
				if TM != null and TM.has_method("notify_player_attacked"):
					TM.notify_player_attacked(u)

			# ✅ Exit special mode on left-click for non-mines (or invalid cell)
			_set_aim_mode(AimMode.MOVE)
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
		await u.call("perform_stim", self)

	elif id == "sunder" and u.has_method("perform_sunder"):
		await u.call("perform_sunder", self, target_cell) # ✅ NEW

	elif id == "pounce" and u.has_method("perform_pounce"):
		await u.call("perform_pounce", self, target_cell)

	elif id == "volley" and u.has_method("perform_volley"):
		await u.call("perform_volley", self, target_cell)

	elif id == "cannon" and u.has_method("perform_cannon"):
		await u.call("perform_cannon", self, target_cell)

	elif id == "quake" and u.has_method("perform_quake"):
		await u.call("perform_quake", self, target_cell)
		
	elif id == "nova" and u.has_method("perform_nova"):
		await u.call("perform_nova", self, target_cell)

	elif id == "web" and u.has_method("perform_web"):
		await u.call("perform_web", self, target_cell)

	elif id == "slam" and u.has_method("perform_slam"):
		await u.call("perform_slam", self, target_cell)

	elif id == "laser_grid" and u.has_method("perform_laser_grid"):
		await u.call("perform_laser_grid", self, target_cell)

	elif id == "overcharge" and u.has_method("perform_overcharge"):
		await u.call("perform_overcharge", self, target_cell)		
		
	elif id == "barrage" and u.has_method("perform_barrage"):
		await u.call("perform_barrage", self, target_cell)

	elif id == "railgun" and u.has_method("perform_railgun"):
		await u.call("perform_railgun", self, target_cell)

	elif id == "malfunction" and u.has_method("perform_malfunction"):
		await u.call("perform_malfunction", self, target_cell)

	elif id == "storm" and u.has_method("perform_storm"):
		await u.call("perform_storm", self, target_cell)
		
	elif id == "artillery_strike" and u.has_method("perform_artillery_strike"):
		await u.call("perform_artillery_strike", self, target_cell)

	elif id == "laser_sweep" and u.has_method("perform_laser_sweep"):
		await u.call("perform_laser_sweep", self, target_cell)
									
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
	if not units_by_cell.has(c):
		return null

	var v = units_by_cell[c]   # DO NOT cast yet

	# If not an object anymore, or freed → clean dictionary
	if v == null or typeof(v) != TYPE_OBJECT or not is_instance_valid(v):
		units_by_cell.erase(c)
		return null

	# Now it is safe to cast
	var u := v as Unit
	if u == null:
		units_by_cell.erase(c)
		return null

	return u


func _select(u: Unit) -> void:
	if TM != null and not TM.can_select(u):
		return
	if selected == u:
		return

	_unselect()
	selected = u
	selected.set_selected(true)

	#_debug_print_unit(u)

	_sfx(&"ui_select", sfx_volume_ui, 1.0)

	if u.team == Unit.Team.ALLY and not ally_select_lines.is_empty():
		_say(u, ally_select_lines.pick_random())

	_refresh_overlays()
	_apply_turn_indicators_all_allies()
	emit_signal("selection_changed", selected)
	emit_signal("aim_changed", int(aim_mode), special_id)

	# --- Tutorial hook ---
	emit_signal("tutorial_event", &"ally_selected", {"cell": u.cell})

func _debug_print_unit(u: Object) -> void:
	var has_prop := ("display_name" in u)
	var disp_val := "<none>"
	if has_prop:
		disp_val = str(u.display_name)

	var meta_val := "<none>"
	if u.has_meta("display_name"):
		meta_val = str(u.get_meta("display_name"))

	var script_val := "<no script>"
	if u.get_script() != null:
		script_val = str(u.get_script())

	var gd_val := "<no method>"
	if u.has_method("get_display_name"):
		gd_val = str(u.call("get_display_name"))

	print(
		"[SELECT] node=", u,
		" class=", u.get_class(),
		" script=", script_val,
		" name=", u.name,
		" has_display_name_prop=", has_prop,
		" display_name=", disp_val,
		" meta_display_name=", meta_val,
		" get_display_name=", gd_val
	)

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

	var v = units_by_cell[cell]

	if v == null or not (v is Object) or not is_instance_valid(v):
		units_by_cell.erase(cell)
		return

	var u := v as Unit
	if u == null:
		units_by_cell.erase(cell)
		return

	if u.hp <= 0:
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

	if not is_inside_tree():
		return
	if attacker == null or not is_instance_valid(attacker):
		return

	if not await _safe_wait(attack_anim_lock_time):
		return

	_cleanup_dead_at(def_cell)
	_play_idle_anim(attacker)


func _safe_tree() -> SceneTree:
	var t := get_tree()
	if t != null:
		return t
	# Fallback: still works even if this node left the tree, as long as the game is running
	return Engine.get_main_loop() as SceneTree

func _safe_wait(seconds: float) -> bool:
	if seconds <= 0.0:
		return true
	var t := _safe_tree()
	if t == null:
		return false
	await t.create_timer(seconds).timeout
	return true

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
			if c != origin and unit_at_cell(c) != null:
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

	var id := special.to_lower().replace(" ", "_")

	var r := 0
	if u.has_method("get_special_range"):
		r = int(u.get_special_range(id))
	if r <= 0:
		return

	var origin := u.cell

	var structure_blocked: Dictionary = {}
	if game_ref != null and "structure_blocked" in game_ref:
		structure_blocked = game_ref.structure_blocked

	# Optional: if you want SLAM preview constants to match M1 exactly
	var slam_side_len := 5
	var slam_depth := 5
	var slam_layers_inward := 4

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := origin + Vector2i(dx, dy)

			# bounds
			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue

			# -------------------------------------------------
			# RANGE SHAPE RULES
			# -------------------------------------------------
			if id == "sunder":
				# straight line only (no diagonals), not self
				if not (dx == 0 or dy == 0):
					continue
				var dist_su = abs(dx) + abs(dy)
				if dist_su <= 0:
					continue
				if dist_su > r:
					continue
			else:
				# default diamond manhattan range
				if abs(dx) + abs(dy) > r:
					continue

			# -------------------------------------------------
			# MIN SAFE DISTANCE (where applicable)
			# -------------------------------------------------
			# Helper: manhattan from origin to c
			var dist = abs(c.x - origin.x) + abs(c.y - origin.y)

			if id == "malfunction":
				var min_mf := 1
				if u.has_method("get_special_min_distance"):
					min_mf = int(u.call("get_special_min_distance", "malfunction"))
				elif "malfunction_min_safe_dist" in u:
					min_mf = int(u.malfunction_min_safe_dist)
				if dist < min_mf:
					continue

			if id == "storm":
				var min_st := 1
				if u.has_method("get_special_min_distance"):
					min_st = int(u.call("get_special_min_distance", "storm"))
				elif "storm_min_safe_dist" in u:
					min_st = int(u.storm_min_safe_dist)
				if dist < min_st:
					continue

			if id == "barrage":
				var min_b := 1
				if u.has_method("get_special_min_distance"):
					min_b = int(u.call("get_special_min_distance", "barrage"))
				elif "barrage_min_safe_dist" in u:
					min_b = int(u.barrage_min_safe_dist)
				if dist < min_b:
					continue

			if id == "railgun":
				var min_rg := 1
				if u.has_method("get_special_min_distance"):
					min_rg = int(u.call("get_special_min_distance", "railgun"))
				elif "railgun_min_safe_dist" in u:
					min_rg = int(u.railgun_min_safe_dist)
				if dist < min_rg:
					continue

			if id == "laser_grid":
				var min_lg := 1
				if u.has_method("get_special_min_distance"):
					min_lg = int(u.call("get_special_min_distance", "laser_grid"))
				elif "laser_grid_min_safe_dist" in u:
					min_lg = int(u.laser_grid_min_safe_dist)
				if dist < min_lg:
					continue

			if id == "overcharge":
				var min_oc := 1
				if u.has_method("get_special_min_distance"):
					min_oc = int(u.call("get_special_min_distance", "overcharge"))
				elif "overcharge_min_safe_dist" in u:
					min_oc = int(u.overcharge_min_safe_dist)
				if dist < min_oc:
					continue

			if id == "nova":
				var min_n := 1
				if u.has_method("get_special_min_distance"):
					min_n = int(u.call("get_special_min_distance", "nova"))
				elif "nova_min_safe_dist" in u:
					min_n = int(u.nova_min_safe_dist)
				if dist < min_n:
					continue

			if id == "web":
				var min_w := 1
				if u.has_method("get_special_min_distance"):
					min_w = int(u.call("get_special_min_distance", "web"))
				elif "web_min_safe_dist" in u:
					min_w = int(u.web_min_safe_dist)
				if dist < min_w:
					continue

			if id == "quake":
				var min_q := 1
				if u.has_method("get_special_min_distance"):
					min_q = int(u.call("get_special_min_distance", "quake"))
				elif "quake_min_safe_dist" in u:
					min_q = int(u.quake_min_safe_dist)
				if dist < min_q:
					continue

			if id == "slam":
				continue

			# -------------------------------------------------
			# TARGETING MODE
			# -------------------------------------------------
			if id == "mines":
				# empty-only placement
				if structure_blocked.has(c):
					continue
				if not _is_walkable(c):
					continue
				if units_by_cell.has(c):
					continue
				if mines_by_cell.has(c):
					continue

			elif id == "hellfire":
				# allow enemy unit target OR empty placement
				var tgt := unit_at_cell(c)
				if tgt != null and is_instance_valid(tgt):
					if ("team" in tgt) and tgt.team == u.team:
						continue
				else:
					if structure_blocked.has(c):
						continue
					if not _is_walkable(c):
						continue
					if units_by_cell.has(c):
						continue

			elif id == "slam":
				# ✅ SLAM selects a direction: allow EMPTY or ENEMY (but not allies)
				var tgt_sl := unit_at_cell(c)
				if tgt_sl != null and is_instance_valid(tgt_sl) and ("team" in tgt_sl) and tgt_sl.team == u.team:
					continue
				# empty is fine

			elif id == "artillery_strike":
				# ✅ can target ANY cell in range (empty or occupied)
				# (optional: disallow self)
				if c == origin:
					continue

			elif id == "laser_sweep":
				# ✅ click any cell to pick a cardinal direction (doesn't need a unit)
				if c == origin:
					continue

			else:
				# enemy-only for all other specials
				var tgt2 := unit_at_cell(c)
				if tgt2 == null or not is_instance_valid(tgt2):
					continue
				if not ("team" in tgt2):
					continue
				if tgt2.team == u.team:
					continue

			# -------------------------------------------------
			# PER-SPECIAL EXTRA VALIDITY RULES
			# -------------------------------------------------
			if id == "sunder" and structure_blocked.has(c):
				continue

			if id == "cannon":
				if not _has_clear_attack_path(origin, c):
					continue

			# -------------------------------------------------
			# MARK VALID + DRAW OVERLAY TILE (CLICKABLE CELLS)
			# -------------------------------------------------
			valid_special_cells[c] = true

			var t := attack_tile_scene.instantiate() as Node2D
			_ensure_overlay_subroots()
			if overlay_tiles_root == null:
				return

			overlay_tiles_root.add_child(t)
			t.global_position = terrain.to_global(terrain.map_to_local(c))
			t.z_as_relative = false
			t.z_index = 0 + (c.x + c.y)

	# -------------------------------------------------
	# EXTRA OVERLAY: SLAM shows affected footprint in ALL 4 directions
	# -------------------------------------------------
	# -------------------------------------------------
	# SLAM: clickable tiles = AFFECTED footprint in ALL 4 directions
	# -------------------------------------------------
	if id == "slam":
		var start_sl := 1
		if u.has_method("get_special_min_distance"):
			start_sl = int(u.call("get_special_min_distance", "slam"))
		elif "slam_min_safe_dist" in u:
			start_sl = int(u.slam_min_safe_dist)

		var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
		var affected: Dictionary = {}

		for ddir in dirs:
			var set_for_dir := _slam_affected_cells_for_dir(origin, ddir, start_sl, slam_side_len, slam_depth, slam_layers_inward)
			for k in set_for_dir.keys():
				if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(k):
					continue
				affected[k] = true

		# Now: mark these as valid + draw overlay tiles (THIS is what will be clickable)
		for k in affected.keys():
			valid_special_cells[k] = true

			var t2 := attack_tile_scene.instantiate() as Node2D
			_ensure_overlay_subroots()
			if overlay_tiles_root == null:
				return
			overlay_tiles_root.add_child(t2)
			t2.global_position = terrain.to_global(terrain.map_to_local(k))
			t2.z_as_relative = false
			t2.z_index = 0 + (k.x + k.y)

func _slam_affected_cells_for_dir(origin: Vector2i, dir: Vector2i, start: int, side_len: int, depth: int, layers_inward: int) -> Dictionary:
	var perp := Vector2i(-dir.y, dir.x)
	var base := origin + dir * start

	var out: Dictionary = {}

	for layer in range(layers_inward):
		var inset := layer
		var cur_w := side_len - inset * 2
		var cur_d := depth    - inset * 2
		if cur_w <= 0 or cur_d <= 0:
			break

		var half_w := int((cur_w - 1) / 2)
		var layer_base := base + dir * inset

		for v in range(cur_d):
			for u in range(-half_w, half_w + 1):
				var on_perimeter := (v == 0 or v == cur_d - 1 or u == -half_w or u == half_w)
				if not on_perimeter:
					continue
				var c := layer_base + dir * v + perp * u
				out[c] = true

	return out

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
			emit_signal("tutorial_event", &"move_denied_already_moved", {"cell": selected.cell})
			return
		
	# Hard gates FIRST (PLAYER ONLY)
	if TM != null and selected != null and is_instance_valid(selected) and selected.team == Unit.Team.ALLY:
		if not TM.player_input_allowed():
			emit_signal("tutorial_event", &"move_denied_input_locked", {"cell": selected.cell})
			return
		if not TM.can_move(selected):
			emit_signal("tutorial_event", &"move_denied_tm_gate", {"cell": selected.cell})
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
	
	# ✅ Check if this is a CarBot (or any unit with custom step animation)
	var is_carbot := u.has_method("play_move_step_anim")
	
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
	
	# ✅ Only play default move anim if NOT CarBot
	if not is_carbot:
		_play_move_anim(u, true)
	else:
		if u.has_method("car_start_move_sfx"):
			u.call("car_start_move_sfx")

	var step_time := _duration_for_step()
	for step_cell in path:
		var from_world := u.global_position
		var to_world := _cell_world(step_cell)
		
		# ✅ Use true GRID direction for per-step anim (turns included)
		if is_carbot:
			var grid_dir: Vector2i = step_cell - u.cell
			if u.has_method("play_move_step_anim_grid"):
				u.call("play_move_step_anim_grid", grid_dir, terrain)
			else:
				u.call("play_move_step_anim", from_world, to_world)
		else:
			_face_unit_for_step(u, from_world, to_world)

		if u.has_method("car_step_sfx"):
			u.call("car_step_sfx")

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
		# ✅ IMPORTANT: update logical cell each step so next step_dir is correct
		if u != null and is_instance_valid(u):
			u.cell = step_cell
			
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
	
	# ✅ Only play default end anim if NOT CarBot
	if not is_carbot:
		_play_move_anim(u, false)
	else:
		# CarBot returns to idle
		if u.has_method("play_idle_anim"):
			u.call("play_idle_anim")
		if u.has_method("car_end_move_sfx"):
			u.call("car_end_move_sfx")

	_sfx(&"move_end", sfx_volume_world, 1.0, _cell_world(target))
	
	_is_moving = false
	# ✅ Mark move spent (IMPORTANT)
	if u.team == Unit.Team.ALLY and TM != null and TM.has_method("notify_player_moved"):
		TM.notify_player_moved(u)
	# --- Tutorial hook ---
	if u != null and is_instance_valid(u) and u.team == Unit.Team.ALLY:
		emit_signal("tutorial_event", &"ally_moved", {"from": from_cell, "to": target})
	if u != null and is_instance_valid(u) and u.team == Unit.Team.ALLY:
		if not _unit_has_attacked(u):
			aim_mode = AimMode.ATTACK
		else:
			aim_mode = AimMode.MOVE
		_refresh_overlays()
	emit_signal("aim_changed", int(aim_mode), special_id)
	
func _find_anim_sprite(root: Node) -> AnimatedSprite2D:
	if root == null:
		return null

	# breadth-first search so we find the closest one first
	var q: Array[Node] = [root]
	while not q.is_empty():
		var n = q.pop_front()

		if n is AnimatedSprite2D:
			return n as AnimatedSprite2D

		for ch in n.get_children():
			if ch is Node:
				q.append(ch)

	return null

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

	# MapController convention: dx > 0 means "facing right"
	var facing_right := dx > 0.0

	# ✅ Best: unit-defined facing hook (CarBot will use this)
	if u.has_method("set_facing_right"):
		u.call("set_facing_right", facing_right)
		_sync_ghost_facing(u)
		return

	# ✅ Otherwise: flip the actual render node (recursive)
	var src := _get_unit_render_node(u)
	if src is Sprite2D:
		(src as Sprite2D).flip_h = facing_right
	elif src is AnimatedSprite2D:
		(src as AnimatedSprite2D).flip_h = facing_right

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
	if c != origin and unit_at_cell(c) != null:
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

func _wait_for_attack_anim(u: Unit, max_frames := 90) -> void:
	if u == null or not is_instance_valid(u):
		return

	var ap := u.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		return

	# If you're not sure which anim is playing, just wait until it stops or timeout.
	var frames := 0
	while frames < max_frames:
		if not is_instance_valid(ap):
			return
		if not ap.is_playing():
			return
		frames += 1
		await get_tree().process_frame
	# timeout fallback:
	return

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

	# Must be inside tree to await frames safely
	if not is_inside_tree():
		return

	var tree := get_tree()
	if tree == null:
		return

	# Temporarily select the unit so _move_selected_to works
	var prev := selected
	selected = u

	_clear_overlay()
	valid_move_cells.clear()
	valid_move_cells[target] = true

	_move_selected_to(target)

	# Wait until movement finishes, but bail if scene reloads / node exits
	var safety := 240  # ~4 seconds @ 60fps, adjust if your moves are longer
	while _is_moving and safety > 0:
		# if we got removed (scene reload), stop cleanly
		if not is_inside_tree():
			return
		if tree == null:
			return
		await tree.process_frame
		safety -= 1

	# Restore selection if still valid
	if is_instance_valid(prev):
		selected = prev
	else:
		selected = null

# AI / scripted move that does NOT consume move/attack flags
# (no _set_unit_moved, no TM.notify_player_moved, no aim_mode changes)
func ai_move_free(u: Unit, target: Vector2i) -> void:
	if u == null or not is_instance_valid(u):
		return
	if u.hp <= 0:
		return
	if _is_moving:
		return
	if not is_inside_tree():
		return
	if terrain == null or grid == null:
		return
	if not grid.in_bounds(target):
		return

	var from_cell := u.cell
	if from_cell == target:
		return

	# Block moving into occupied cells
	if units_by_cell.has(target):
		var occ = units_by_cell[target]
		if occ != null and is_instance_valid(occ) and occ != u:
			return

	# Build an L path (your existing logic)
	var path := _pick_clear_L_path(from_cell, target)
	if path.is_empty():
		return

	_is_moving = true
	_clear_overlay()

	# Reserve destination in the board dictionary
	units_by_cell.erase(from_cell)
	units_by_cell[target] = u

	# CarBot (or any unit with step anim hooks)
	var is_carbot := u.has_method("play_move_step_anim")

	if not is_carbot:
		_play_move_anim(u, true)
	else:
		if u.has_method("car_start_move_sfx"):
			u.call("car_start_move_sfx")

	var step_time := _duration_for_step()
	var uid := u.get_instance_id()

	for step_cell in path:
		if u == null or not is_instance_valid(u):
			_is_moving = false
			return

		var from_world := u.global_position
		var to_world := _cell_world(step_cell)

		# Drive anim per-step
		if is_carbot:
			var grid_dir: Vector2i = step_cell - u.cell
			if u.has_method("play_move_step_anim_grid"):
				u.call("play_move_step_anim_grid", grid_dir, terrain)
			else:
				u.call("play_move_step_anim", from_world, to_world)
		else:
			_face_unit_for_step(u, from_world, to_world)

		if u.has_method("car_step_sfx"):
			u.call("car_step_sfx")

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

		# Keep logical cell in sync so turns animate correctly
		if u != null and is_instance_valid(u):
			u.cell = step_cell

	# Snap final / update tile cell
	if u == null or not is_instance_valid(u):
		_is_moving = false
		return

	u.set_cell(target, terrain)

	# IMPORTANT: do game interactions, but do NOT set moved/attacked flags
	await _check_overwatch_trigger(u, target)
	await _trigger_mine_if_present_id(uid)
	try_collect_pickup(u)
	_check_and_trigger_beacon_sweep()

	if u == null or not is_instance_valid(u):
		_is_moving = false
		return

	if not is_carbot:
		_play_move_anim(u, false)
	else:
		if u.has_method("play_idle_anim"):
			u.call("play_idle_anim")
		if u.has_method("car_end_move_sfx"):
			u.call("car_end_move_sfx")

	_is_moving = false

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
		
	# ✅ If we stepped onto a pickup, let it be visible briefly, then collect
	if pickups_by_cell.has(to_cell):
		_delayed_collect_pickup(u, to_cell)
	else:
		# normal: nothing to collect
		pass

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

func _delayed_collect_pickup(u: Unit, c: Vector2i) -> void:
	# Fire-and-forget coroutine (doesn't block movement tween)
	_delayed_collect_pickup_async(u, c)


func _delayed_collect_pickup_async(u: Unit, c: Vector2i) -> void:
	# If the pickup node exists, force it visible "on top" for the flash
	var p = pickups_by_cell.get(c, null)
	if p != null and is_instance_valid(p) and p is Node2D:
		var n := p as Node2D
		n.visible = true
		# pop above units for the moment (tweak if you want)
		n.z_as_relative = false
		n.z_index = 9999

	# Wait a couple frames so the player sees it
	await get_tree().process_frame
	await get_tree().process_frame
	# Optional: also wait a tiny time (tweak 0.05–0.12)
	await get_tree().create_timer(0.88).timeout

	# Unit might be dead/freed now
	if u == null or not is_instance_valid(u) or u.hp <= 0:
		return

	# Pickup might have been collected already
	if not pickups_by_cell.has(c):
		return

	try_collect_pickup(u)

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


func _wait_frames_on_unit(u: Node, frames: int) -> void:
	if frames <= 0:
		return
	if u == null or not is_instance_valid(u):
		return
	if not u.is_inside_tree():
		return

	var st := u.get_tree()
	if st == null:
		return

	while frames > 0:
		if u == null or not is_instance_valid(u):
			return
		if not u.is_inside_tree():
			return
		await st.process_frame
		frames -= 1


func _play_death_and_wait(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return
	if not u.is_inside_tree():
		return

	# Preferred: unit-defined death handler (if you have one)
	if u.has_method("play_death_anim"):
		u.call("play_death_anim")
		if u.has_method("wait_death_anim"):
			# Important: this wait method must also avoid get_tree() on a dead caller
			await u.call("wait_death_anim")
			return
		# else fall through to sprite wait

	var a := u.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a == null or a.sprite_frames == null:
		# No anim; small feel-delay without timers
		await _wait_frames_on_unit(u, 8) # ~0.13s @ 60fps
		return

	var played := false
	if a.sprite_frames.has_animation("death"):
		a.play("death")
		played = true
	elif a.sprite_frames.has_animation("die"):
		a.play("die")
		played = true

	if played:
		# Call SFX safely (don't assume _play_sfx uses get_tree() on a null caller)
		if u.has_method("_play_sfx"):
			u.call("_play_sfx", &"unit_death")
	else:
		await _wait_frames_on_unit(u, 8)
		return

	# Wait until the animation finishes (or a safe timeout)
	var done := false
	var cb := func() -> void: done = true
	var callable := Callable(cb)

	# Guard: AnimatedSprite2D may vanish if unit is freed mid-wait
	if a != null and is_instance_valid(a):
		if not a.animation_finished.is_connected(callable):
			a.animation_finished.connect(callable)

	var max_frames := 30 # ~0.5s @ 60fps
	while not done and max_frames > 0:
		if u == null or not is_instance_valid(u) or not u.is_inside_tree():
			return
		# Use *unit's* SceneTree, not the caller’s
		var st := u.get_tree()
		if st == null:
			return
		await st.process_frame
		max_frames -= 1

	# Cleanup signal connection if still valid
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
		# disarm aim + clear tiles (same as you want)
		aim_mode = AimMode.MOVE
		special_id = &""
		valid_special_cells.clear()
		_clear_overlay()

		var u := selected
		if u == null or not is_instance_valid(u):
			return

		# Optional: check cooldown/permission on the unit itself
		if u.has_method("can_use_special"):
			var ok := true

			# try StringName first
			var r1 = u.call("can_use_special", StringName(id))
			if r1 is bool:
				ok = bool(r1)
			else:
				# fallback: try String
				var r2 = u.call("can_use_special", String(id))
				if r2 is bool:
					ok = bool(r2)

			if not ok:
				_refresh_overlays()
				emit_signal("aim_changed", int(aim_mode), special_id)
				return

		# ✅ Stim should NOT require "attack available" and should NOT consume attack.
		# Only gate on input lock / phase.
		if TM != null and not TM.player_input_allowed():
			_refresh_overlays()
			emit_signal("aim_changed", int(aim_mode), special_id)
			return

		await _perform_special(u, id, u.cell)

		# ✅ DO NOT: _set_unit_attacked(u, true)
		# ✅ DO NOT: TM.notify_player_attacked(u)
		# Turn indicator stays based on move/attack flags (unchanged)

		# After stim, keep whatever aim makes sense:
		# - if they still have attack, default to ATTACK so you can immediately click a zombie
		# - otherwise MOVE
		if not _unit_has_attacked(u):
			aim_mode = AimMode.ATTACK
		else:
			aim_mode = AimMode.MOVE

		_refresh_overlays()
		emit_signal("aim_changed", int(aim_mode), special_id)
		return

	# ✅ Toggle off if same special pressed again
	if aim_mode == AimMode.SPECIAL and String(special_id).to_lower() == "mines" and selected is Mech:
		var mech := selected as Mech
		var c := _mouse_to_cell()
		if c.x < 0:
			return

		var before := mines_by_cell.size()
		mech.perform_place_mine(self, c)
		var placed := mines_by_cell.size() > before

		if placed:
			mech.mine_placed_one() # keeps special_cd["mines"]=0
			# stay in special and refresh tiles
			aim_mode = AimMode.SPECIAL
			_refresh_overlays()

		return

	# ✅ Turn on SPECIAL aim + show range immediately
	aim_mode = AimMode.SPECIAL
	special_id = StringName(id)
	special_unit = selected
	
	# start the session
	if special_unit is Mech:
		(special_unit as Mech).begin_mine_special()
			
	_refresh_overlays()
	emit_signal("aim_changed", int(aim_mode), special_id)
	emit_signal("tutorial_event", &"special_mode_armed", {"id": id, "cell": selected.cell})

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
		"sunder":
			return u.has_method("perform_sunder")
		"pounce":
			return u.has_method("perform_pounce")
		"volley":
			return u.has_method("perform_volley")
		"cannon":
			return u.has_method("perform_cannon")
		"quake":
			return u.has_method("perform_quake")
		"nova":
			return u.has_method("perform_nova")
		"web":
			return u.has_method("perform_web")
		"slam":
			return u.has_method("perform_slam")
		"laser_grid":
			return u.has_method("perform_laser_grid")
		"overcharge":
			return u.has_method("perform_overcharge")
		"barrage":
			return u.has_method("perform_barrage")
		"railgun":
			return u.has_method("perform_railgun")
		"malfunction":
			return u.has_method("perform_malfunction")
		"storm":
			return u.has_method("perform_storm")
		"artillery_strike":
			return u.has_method("perform_artillery_strike")
		"laser_sweep":
			return u.has_method("perform_laser_sweep")
				
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

		emit_signal("tutorial_event", &"mine_picked_up", {"cell": c, "team": mine_team})
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
		_remove_unit_from_board(u) # remove using the unit instance
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
		emit_signal("tutorial_event", &"overwatch_cleared", {"cell": u.cell})
		return

	if r <= 0:
		r = u.attack_range + 3

	overwatch_by_unit[u] = {"range": r, "turns": int(turns)}
	emit_signal("tutorial_event", &"overwatch_set", {"cell": u.cell, "range": r, "turns": int(turns)})
	
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
		
		# ✅ If overwatch killed it, force the unit to fully die + free
		if is_instance_valid(t) and ("hp" in t) and int(t.hp) <= 0:
			await t._die()		

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
	var keys1 := overwatch_by_unit.keys() # snapshot
	for k in keys1:
		# SAFE: no `is`, no `as` yet
		if not is_instance_valid(k):
			overwatch_by_unit.erase(k)
			continue

		# (Optional) If you want to ensure keys are actually Units:
		# Now safe to use `is`
		if not (k is Unit):
			overwatch_by_unit.erase(k)
			continue

	# ----- overwatch_ghost_by_unit -----
	var keys2 := overwatch_ghost_by_unit.keys() # snapshot
	for k in keys2:
		# SAFE: validate key BEFORE doing anything else with it
		if not is_instance_valid(k):
			overwatch_ghost_by_unit.erase(k)
			continue

		# (Optional) enforce Unit keys
		if not (k is Unit):
			overwatch_ghost_by_unit.erase(k)
			continue

		# Now it's safe to read the value using k
		var g := overwatch_ghost_by_unit.get(k, null) as CanvasItem
		if not is_instance_valid(g):
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
	if u is Mech and (u as Mech).placing_mines:
		return false	
	return u != null and is_instance_valid(u) and u.has_meta(META_ATTACKED) and bool(u.get_meta(META_ATTACKED))

func _set_unit_moved(u: Unit, v: bool) -> void:
	if u != null and is_instance_valid(u):
		u.set_meta(META_MOVED, v)

func _set_unit_attacked(u: Unit, v: bool) -> void:
	if u != null and is_instance_valid(u):
		u.set_meta(META_ATTACKED, v)

func reset_turn_flags_for_allies() -> void:
	_stop_all_pulses()
	
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
	
	# ✅ REGISTER KILL (ringout bypasses take_damage/on_unit_died)
	# Do this BEFORE playing death/removing.
	if d.team == Unit.Team.ENEMY:
		# 1) If you have an existing death handler, call it:
		if has_method("on_unit_died"):
			on_unit_died(d)
		elif has_method("_on_unit_died"):
			on_unit_died(d)

		# 2) If TurnManager listens to tutorial_event to refresh infestation HUD:
		if has_signal("tutorial_event"):
			emit_signal("tutorial_event", &"enemy_died", {"cell": def_cell, "killer": attacker.get_instance_id()})
	
	await _play_death_and_wait(d)

	# ✅ Remove by CELL (does not pass freed Unit into typed function)
	_remove_unit_from_board_at_cell(def_cell)

	_is_moving = false

# ---------------------------------------------------------
# Cool “unique building pulse” during recruitment
# - flashes / pulses the building’s modulate (neon-ish)
# - works even if _structure_at_cell() returns a child node
# - safe: restores original modulate at the end
# ---------------------------------------------------------

func _on_unique_recruit_pulse(struct_node: Node) -> void:
	# Find the unique building root (walk up parents)
	var root: Node = struct_node
	while root != null and is_instance_valid(root) and not root.is_in_group(UNIQUE_GROUP):
		root = root.get_parent()
	if root == null or not is_instance_valid(root):
		return

	# Pick a CanvasItem target (what we actually modulate)
	var target: CanvasItem = null

	# Prefer an obvious sprite node
	var spr := root.get_node_or_null("Sprite2D")
	if spr is CanvasItem:
		target = spr as CanvasItem

	# Fallback: first CanvasItem descendant
	if target == null:
		target = _find_first_canvasitem_descendant(root)

	# Last fallback: root itself if it’s a CanvasItem
	if target == null and (root is CanvasItem):
		target = root as CanvasItem

	if target == null or not is_instance_valid(target):
		return

	# Stop any previous FX tween
	if target.has_meta("unique_fx_tw"):
		var old = target.get_meta("unique_fx_tw")
		if old is Tween and is_instance_valid(old):
			(old as Tween).kill()
		target.set_meta("unique_fx_tw", null)

	# Store base state once per target
	if not target.has_meta("unique_fx_base_mod"):
		target.set_meta("unique_fx_base_mod", target.modulate)
	if (target is Node2D) and not target.has_meta("unique_fx_base_scale"):
		target.set_meta("unique_fx_base_scale", (target as Node2D).scale)

	var base_mod: Color = target.get_meta("unique_fx_base_mod")
	var base_a := base_mod.a

	var base_scale := Vector2.ONE
	var can_scale := (target is Node2D)
	if can_scale:
		base_scale = target.get_meta("unique_fx_base_scale")

	# Compute boosted color (additive-ish but clamped)
	var boosted := Color(
		clamp(base_mod.r + recruit_fx_color.r, 0.0, 1.0),
		clamp(base_mod.g + recruit_fx_color.g, 0.0, 1.0),
		clamp(base_mod.b + recruit_fx_color.b, 0.0, 1.0),
		base_a
	)

	# Tiny alpha shimmer endpoints
	var a_low = clamp(base_a * recruit_fx_alpha_min, 0.0, 1.0)
	var a_hi := base_a

	# Scale pop endpoint
	var scale_hi := base_scale * recruit_fx_scale_mul

	var tw := create_tween()
	target.set_meta("unique_fx_tw", tw)

	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)

	for i in range(recruit_fx_loops):
		# CHARGE: color up + alpha down slightly (shimmer)
		tw.tween_property(target, "modulate", boosted, max(0.01, recruit_fx_in_time))
		tw.parallel().tween_property(target, "modulate:a", a_low, max(0.01, recruit_fx_in_time))

		# POP: quick scale up then settle (if Node2D)
		if can_scale:
			tw.parallel().tween_property(target, "scale", scale_hi, max(0.01, recruit_fx_in_time * 0.70))

		# HOLD
		tw.tween_interval(max(0.01, recruit_fx_hold_time))

		# SETTLE: color back + alpha back
		tw.tween_property(target, "modulate", base_mod, max(0.01, recruit_fx_out_time))
		tw.parallel().tween_property(target, "modulate:a", a_hi, max(0.01, recruit_fx_out_time))

		if can_scale:
			tw.parallel().tween_property(target, "scale", base_scale, max(0.01, recruit_fx_out_time))

	# Ensure final exact restore
	tw.tween_callback(func():
		if target != null and is_instance_valid(target):
			target.modulate = base_mod
			if can_scale and target is Node2D:
				(target as Node2D).scale = base_scale
			target.set_meta("unique_fx_tw", null)
	)

	await tw.finished

# ---------------------------------------------------------
# Full recruit function (UNIQUE ONLY) with the pulse
# ---------------------------------------------------------
func _try_recruit_near_structure(mover: Unit) -> void:
	if not recruit_enabled:
		return
	if mover == null or not is_instance_valid(mover):
		return
	if mover.team != Unit.Team.ALLY:
		return
	if terrain == null or units_root == null or grid == null:
		return

	# Only block if BOTH sources are empty
	var rs := _rs()
	var has_rs_pool := (rs != null and rs.has_method("take_random_recruit_scene"))
	if not has_rs_pool and ally_scenes.is_empty():
		return

	var s_cell := _find_adjacent_structure_cell(mover.cell)
	if s_cell.x < -100:
		return

	var s := _structure_at_cell(s_cell)
	if s == null or not is_instance_valid(s):
		return

	# Walk up to a UNIQUE building root (group-based)
	var root: Node = s
	while root != null and is_instance_valid(root) and not root.is_in_group(UNIQUE_GROUP):
		root = root.get_parent()
	if root == null or not is_instance_valid(root):
		return

	# ----------------------------
	# ✅ NEW: Secure-per-mission gate
	# ----------------------------
	var rid := int(root.get_instance_id())
	if _secured_unique_ids.has(rid):
		return

	_secured_unique_ids[rid] = true
	_secured_count += 1

	# ✨ Pulse the unique building to confirm capture
	await _on_unique_recruit_pulse(root)

	# Not enough yet → stop (no recruit)
	if _secured_count < recruit_buildings_needed:
		push_warning("RECRUIT: secured " + str(_secured_count) + "/" + str(recruit_buildings_needed) + " (pulse only)")
		return

	# We hit 3/3 → consume and spawn 1 recruit
	_secured_count -= recruit_buildings_needed

	var spawn_cell := _find_open_adjacent_to_structure(s_cell)
	if spawn_cell.x < 0:
		return

	_say(mover, "RECRUIT INBOUND")
	_spawn_recruited_ally_fadein(spawn_cell)
	
func _find_adjacent_structure_cell(cell: Vector2i) -> Vector2i:
	# Use the authoritative structure_blocked dictionary (footprint coverage)
	if game_ref == null or not ("structure_blocked" in game_ref):
		return Vector2i(-999, -999)

	var sb: Dictionary = game_ref.structure_blocked

	# check 8-neighbors around the mover to see if any is a structure-blocked cell
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var c := cell + Vector2i(dx, dy)
			if grid != null and grid.has_method("in_bounds") and not grid.in_bounds(c):
				continue
			if sb.has(c):
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
			if _recruits_spawned_at.has(c): 
				continue
				
			candidates.append(c)

	if candidates.is_empty():
		return Vector2i(-1, -1)

	# Prefer closer-to-player-ish: pick random is fine, but you can sort if you want
	return candidates.pick_random()

func _spawn_recruited_ally_fadein(spawn_cell: Vector2i) -> void:
	# one recruit per cell ever
	if _recruits_spawned_at.has(spawn_cell):
		return
	_recruits_spawned_at[spawn_cell] = true

	if terrain == null or units_root == null or grid == null:
		return
	if units_by_cell.has(spawn_cell):
		return

	var scene: PackedScene = null

	# ✅ Preferred: pull from RunState pool (persists across regens)
	var rs := _rs()
	if rs != null and rs.has_method("take_random_recruit_scene"):
		scene = rs.call("take_random_recruit_scene")

	# Fallback: old local pool behavior
	if scene == null:
		if ally_scenes.is_empty():
			push_warning("Recruit: ally_scenes is empty (assign ally scenes in inspector) and RunState pool gave nothing.")
			return

		if _recruit_pool.is_empty():
			_rebuild_recruit_pool_from_allies()

		if _recruit_pool.is_empty():
			push_warning("Recruit: no unique allies left to recruit.")
			return

		var idx := randi() % _recruit_pool.size()
		scene = _recruit_pool[idx]
		_recruit_pool.remove_at(idx)

	if scene == null:
		push_warning("Recruit: got null recruit scene.")
		return

	# ✅ NEW: Recruit becomes part of the run roster/squad
	var rs2 := _rs()
	if rs2 != null and rs2.has_method("recruit_joined_team") and scene != null:
		rs2.call("recruit_joined_team", scene.resource_path)

	var u := scene.instantiate() as Unit
	if scene != null and scene.resource_path != "":
		u.set_meta("scene_path", scene.resource_path)
	
	if u == null:
		push_warning("Recruit: ally scene root must extend Unit.")
		return

	units_root.add_child(u)
	_wire_unit_signals(u)
	u.team = Unit.Team.ALLY
	u.hp = u.max_hp
	u.global_position.y -= 720

	# ✅ register occupancy BEFORE the drop (matches your spawn_units pattern)
	units_by_cell[spawn_cell] = u

	emit_signal("tutorial_event", &"recruit_spawned", {"cell": spawn_cell})

	# -------------------------------------------------------
	# ✅ BOMBER DROP recruit (same as your initial deployment)
	# -------------------------------------------------------
	var target_world := _cell_world(spawn_cell)

	# If bomber scene isn’t assigned, hard-fallback to instant placement
	if bomber_scene == null:
		u.set_cell(spawn_cell, terrain)
		_set_unit_depth_from_world(u, u.global_position)
		_say(u, "Recruited!")
		_apply_turn_indicators_all_allies()
		if TM != null:
			if TM.has_method("on_units_spawned"):
				TM.on_units_spawned()
			if TM.has_method("_update_special_buttons"):
				TM._update_special_buttons()
		return

	_sfx(bomber_sfx_in, sfx_volume_world, 1.0, target_world)

	var bomber := _spawn_bomber(target_world.x, target_world.y)
	if bomber != null:
		await _tween_node_global_pos(
			bomber,
			bomber.global_position,
			target_world + Vector2(0, -bomber_hover_px),
			bomber_arrive_time
		)

	# Drop the unit (this function sets cell + plays drop_sfx)
	if bomber != null:
		await _drop_unit_from_bomber(u, bomber, spawn_cell)
	else:
		u.set_cell(spawn_cell, terrain)
		_set_unit_depth_from_world(u, u.global_position)

	_say(u, "Recruited!")

	# Bomber exits
	if bomber != null and is_instance_valid(bomber):
		_sfx(bomber_sfx_out, sfx_volume_world, 1.0, bomber.global_position)
		await _tween_node_global_pos(
			bomber,
			bomber.global_position,
			bomber.global_position + Vector2(0, bomber_y_offscreen),
			bomber_depart_time
		)
		bomber.queue_free()

	# Finish hooks (same as your old fade-in finish)
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

	p.add_to_group("Drops")

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

	# Only allies can collect mission pickups
	if uu.team != Unit.Team.ALLY:
		return

	var p = pickups_by_cell[c]
	pickups_by_cell.erase(c)

	# ✅ PLAY PICKUP SFX (cell-world position is best)
	if has_method("_sfx"):
		_sfx(&"pickup_floppy", 1.0, randf_range(0.95, 1.05), _cell_world(c))

	# ✅ Only increment for allies
	beacon_parts_collected += 1

	if p != null and is_instance_valid(p):
		p.queue_free()

	emit_signal("pickup_collected", uu, c)
	emit_signal("tutorial_event", &"pickup_collected", {
		"cell": c,
		"beacon_parts_collected": beacon_parts_collected,
		"beacon_parts_needed": beacon_parts_needed
	})

func on_unit_died(u: Unit) -> void:
	if u == null:
		return

	# -------------------------
	# ENEMY death (your existing behavior)
	# -------------------------
	if u.team == Unit.Team.ENEMY:
		emit_signal("tutorial_event", &"enemy_died", {"cell": u.cell})

		if _team_floppy_total_allies() >= beacon_parts_needed:
			_floppy_pity_accum = 0.0
			_floppy_misses = 0
			return

		zombies_killed_this_map += 1

		# Stop dropping if we already have enough parts
		if _team_floppy_total_allies() < beacon_parts_needed:
			if floppy_kills_left > 0:
				floppy_kills_left -= 1

			if floppy_kills_left == 0:
				spawn_pickup_at(u.cell, floppy_pickup_scene)

				# advance to next threshold
				floppy_drop_index += 1

				# choose next from curve (repeat last value if you want)
				var rs := _rs()
				var node_type = (&"combat" if rs == null else rs.mission_node_type)
				var diff := (0.0 if rs == null else float(rs.mission_difficulty))
				var mult = lerp(0.90, 1.20, clamp(diff, 0.0, 1.0))

				var curve := floppy_curve_combat
				if node_type == &"elite":
					curve = floppy_curve_elite
				elif node_type == &"event":
					curve = floppy_curve_event
				elif node_type == &"boss":
					curve = floppy_curve_boss

				var idx = min(floppy_drop_index, curve.size() - 1)
				floppy_kills_left = int(round(float(curve[idx]) * mult))

		var part_id = u.get_meta("boss_part_id", null)
		if part_id != null:
			var dmg := int(u.get_meta("boss_damage_on_destroy", 3))
			var tm := get_tree().root.get_node_or_null("TurnManager")
			if tm != null and tm.boss != null and is_instance_valid(tm.boss):
				tm.boss.on_weakpoint_destroyed(part_id, dmg)

		return

	# -------------------------
	# ALLY death (NEW: permadeath)
	# -------------------------
	if u.team == Unit.Team.ALLY:
		emit_signal("tutorial_event", &"ally_died", {"cell": u.cell})

		var rs := _rs()
		if rs != null and rs.has_method("mark_dead"):
			var p := ""
			if u.has_meta("scene_path"):
				p = str(u.get_meta("scene_path"))

			if p == "":
				push_warning("Permadeath: ally died but has no scene_path meta. Make sure all ally spawns set_meta('scene_path', scene.resource_path).")
			else:
				rs.call("mark_dead", p)			
		return	

func get_kills_until_next_floppy() -> int:
	return floppy_kills_left

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
		boom.global_position.y -= 8

		# kill zombie
		z.take_damage(999)

		# small delay so it reads
		await get_tree().create_timer(0.1).timeout

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
	if _beacon_sweep_started:
		return

	# 1) ARM the beacon if enough parts collected (banked + carried)
	if not beacon_ready:
		var total := beacon_parts_collected
		if total >= beacon_parts_needed:
			beacon_ready = true
			_sfx(&"beacon_ready", 1.0, 1.0, _cell_world(beacon_cell))
			_update_beacon_marker()
			emit_signal("tutorial_event", &"beacon_ready", {"cell": beacon_cell, "parts_needed": beacon_parts_needed})
		else:
			return

	# 2) If armed, check for ally standing on beacon
	var carrier := _any_ally_on_beacon()
	if carrier == null:
		return

	# 3) Trigger sweep
	_beacon_sweep_started = true
	emit_signal("tutorial_event", &"beacon_upload_started", {"cell": beacon_cell})
	_sfx(&"beacon_upload", 1.0, 1.0, _cell_world(beacon_cell))

	# clear carried parts (optional)
	for u in get_all_units():
		if u != null and is_instance_valid(u) and u.team == Unit.Team.ALLY and ("floppy_parts" in u):
			u.set("floppy_parts", 0)

	call_deferred("_run_satellite_sweep_async")

func _run_satellite_sweep_async() -> void:
	await satellite_sweep()
	emit_signal("tutorial_event", &"satellite_sweep_finished", {})

	await _extract_allies_with_bomber()
	emit_signal("tutorial_event", &"extraction_finished", {})

func _extract_allies_with_bomber() -> void:
	if not evac_enabled:
		return

	if bomber_scene == null:
		# No bomber? Just end cleanly (or do instant removal if you prefer)
		return

	# Snapshot allies that still exist
	var allies: Array[Unit] = []
	for u in get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team != Unit.Team.ALLY:
			continue
		# Optional: skip evac of special objects like RecruitBot if you want
		allies.append(u)

	if allies.is_empty():
		return

	# Lock inputs while extracting
	_is_moving = true
	_clear_overlay()
	selected = null

	# Optional: stable order (closest to beacon first feels good)
	allies.sort_custom(func(a: Unit, b: Unit) -> bool:
		var da = abs(a.cell.x - beacon_cell.x) + abs(a.cell.y - beacon_cell.y)
		var db = abs(b.cell.x - beacon_cell.x) + abs(b.cell.y - beacon_cell.y)
		return da < db
	)

	# Spawn ONE bomber, reuse it
	var first_world := allies[0].global_position
	_sfx(bomber_sfx_in, sfx_volume_world, 1.0, first_world)

	var bomber := _spawn_bomber(first_world.x, first_world.y)
	if bomber != null:
		await _tween_node_global_pos(
			bomber,
			bomber.global_position,
			first_world + Vector2(0, -bomber_hover_px),
			bomber_arrive_time
		)

	# Visit and extract each ally
	for u in allies:
		if u == null or not is_instance_valid(u):
			continue

		var uid := u.get_instance_id()
		var target_world := u.global_position

		# Move bomber above this ally
		if bomber != null and is_instance_valid(bomber):
			await _tween_node_global_pos(
				bomber,
				bomber.global_position,
				target_world + Vector2(0, -bomber_hover_px),
				max(0.05, bomber_arrive_time * 0.75)
			)

		# Pick up ally (lift + fade), then remove from board
		await _evac_pickup_unit(uid)

		if evac_pause_between > 0.0:
			await get_tree().create_timer(evac_pause_between).timeout

	# Bomber exits
	if bomber != null and is_instance_valid(bomber):
		_sfx(bomber_sfx_out, sfx_volume_world, 1.0, bomber.global_position)
		await _tween_node_global_pos(
			bomber,
			bomber.global_position,
			bomber.global_position + Vector2(0, bomber_y_offscreen),
			bomber_depart_time
		)
		bomber.queue_free()

	_is_moving = false


func _evac_pickup_unit(uid: int) -> void:
	var obj := instance_from_id(uid)
	if obj == null or not is_instance_valid(obj) or not (obj is Unit):
		return

	var u := obj as Unit
	if u.team != Unit.Team.ALLY:
		return

	_sfx(evac_sfx_pickup, sfx_volume_world, randf_range(0.95, 1.05), u.global_position)

	# Choose what to animate (visual if present, otherwise the unit node)
	var visual := _get_unit_visual_node(u)
	if visual == null or not is_instance_valid(visual):
		visual = u

	# Fade target (CanvasItem), if any
	var ci := _get_unit_render_node(u)

	var start_pos := visual.global_position
	var end_pos := start_pos + Vector2(0, -evac_lift_px)

	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN)

	tw.tween_property(visual, "global_position", end_pos, max(0.01, evac_pickup_time))

	if ci != null and is_instance_valid(ci):
		tw.parallel().tween_property(ci, "modulate:a", 0.0, max(0.01, evac_fade_time))

	await tw.finished

	# Remove from units_by_cell safely (don’t assume u.cell still maps to u)
	_remove_unit_from_board(u)

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
	line.z_index = 2 + (cell.x + cell.y)

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
	_init_floppy_kill_curve()

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
	emit_signal("tutorial_event", &"beacon_cell_set", {"cell": beacon_cell})
	
	# keep marker in sync
	_clear_beacon_marker()     # ensures old marker is removed if any
	_ensure_beacon_marker()    # spawns marker at new beacon_cell (and pulses if ready)

func apply_run_upgrades() -> void:
	var counts: Dictionary = {}

	var rs := _rs()
	if rs != null and ("run_upgrade_counts" in rs):
		counts = rs.run_upgrade_counts

	# fallback: old behavior (if you ever stored upgrades on game_ref)
	if counts.is_empty() and game_ref != null and is_instance_valid(game_ref) and ("run_upgrade_counts" in game_ref):
		counts = game_ref.run_upgrade_counts

	if counts.is_empty():
		return

	for u in get_all_units():
		if u == null or not is_instance_valid(u): continue
		if u.team != Unit.Team.ALLY: continue

		for id in counts.keys():
			var n := int(counts[id])

			match id:
				# -------------------------
				# GLOBAL (all allies)
				# -------------------------
				&"all_hp_plus_1":
					u.max_hp += 1 * n
					u.hp = min(u.hp + 1 * n, u.max_hp)
				&"all_move_plus_1":
					u.move_range += 1 * n
				&"all_dmg_plus_1":
					u.attack_damage += 1 * n

				# -------------------------
				# SOLDIER (Human)
				# -------------------------
				&"soldier_move_plus_1":
					if u is Human: u.move_range += 1 * n
				&"soldier_range_plus_1":
					if u is Human: u.attack_range += 1 * n
				&"soldier_dmg_plus_1":
					if u is Human: u.attack_damage += 1 * n

				# -------------------------
				# MERCENARY (HumanTwo)
				# -------------------------
				&"merc_move_plus_1":
					if u is HumanTwo: u.move_range += 1 * n
				&"merc_range_plus_1":
					if u is HumanTwo: u.blade_range += 1 * n
				&"merc_dmg_plus_1":
					if u is HumanTwo: u.attack_damage += 1 * n

				# -------------------------
				# ROBODOG (Mech)
				# -------------------------
				&"dog_hp_plus_2":
					if u is Mech:
						u.max_hp += 2 * n
						u.hp = min(u.hp + 2 * n, u.max_hp)
				&"dog_move_plus_1":
					if u is Mech: u.move_range += 1 * n
				&"dog_dmg_plus_1":
					if u is Mech: u.attack_damage += 1 * n

				# -------------------------
				# R1
				# -------------------------
				&"r1_hp_plus_1":
					if u is R1:
						u.max_hp += 1 * n
						u.hp = min(u.hp + 1 * n, u.max_hp)
				&"r1_move_plus_1":
					if u is R1: u.move_range += 1 * n
				&"r1_range_plus_1":
					if u is R1: u.attack_range += 1 * n
				&"r1_dmg_plus_1":
					if u is R1: u.attack_damage += 1 * n

				# -------------------------
				# R2
				# -------------------------
				&"r2_hp_plus_1":
					if u is R2:
						u.max_hp += 1 * n
						u.hp = min(u.hp + 1 * n, u.max_hp)
				&"r2_move_plus_1":
					if u is R2: u.move_range += 1 * n
				&"r2_range_plus_1":
					if u is R2: u.attack_range += 1 * n
				&"r2_dmg_plus_1":
					if u is R2: u.attack_damage += 1 * n

				# -------------------------
				# M1
				# -------------------------
				&"m1_hp_plus_1":
					if u is M1:
						u.max_hp += 1 * n
						u.hp = min(u.hp + 1 * n, u.max_hp)
				&"m1_move_plus_1":
					if u is M1: u.move_range += 1 * n
				&"m1_range_plus_1":
					if u is M1: u.attack_range += 1 * n
				&"m1_dmg_plus_1":
					if u is M1: u.attack_damage += 1 * n

				# -------------------------
				# M2
				# -------------------------
				&"m2_hp_plus_1":
					if u is M2:
						u.max_hp += 1 * n
						u.hp = min(u.hp + 1 * n, u.max_hp)
				&"m2_move_plus_1":
					if u is M2: u.move_range += 1 * n
				&"m2_range_plus_1":
					if u is M2: u.attack_range += 1 * n
				&"m2_dmg_plus_1":
					if u is M2: u.attack_damage += 1 * n

				# -------------------------
				# S2
				# -------------------------
				&"s2_hp_plus_1":
					if u is S2:
						u.max_hp += 1 * n
						u.hp = min(u.hp + 1 * n, u.max_hp)
				&"s2_move_plus_1":
					if u is S2: u.move_range += 1 * n
				&"s2_range_plus_1":
					if u is S2: u.attack_range += 1 * n
				&"s2_dmg_plus_1":
					if u is S2: u.attack_damage += 1 * n

				# -------------------------
				# RecruitBot
				# -------------------------
				&"recruitbot_hp_plus_1":
					if u is RecruitBot:
						u.max_hp += 1 * n
						u.hp = min(u.hp + 1 * n, u.max_hp)
				&"recruitbot_move_plus_1":
					if u is RecruitBot: u.move_range += 1 * n
				&"recruitbot_range_plus_1":
					if u is RecruitBot: u.attack_range += 1 * n
				&"recruitbot_dmg_plus_1":
					if u is RecruitBot: u.attack_damage += 1 * n

				# -------------------------
				# S3 (Arachnobot)
				# -------------------------
				&"arachno_hp_plus_1":
					if u is S3:
						u.max_hp += 1 * n
						u.hp = min(u.hp + 1 * n, u.max_hp)

				&"arachno_move_plus_1":
					if u is S3:
						u.move_range += 1 * n

				&"arachno_dmg_plus_1":
					if u is S3:
						# Boost both basic + special damage if those vars exist
						u.attack_damage += 1 * n
						if "basic_melee_damage" in u:
							u.basic_melee_damage += 1 * n
						if "nova_damage" in u:
							u.nova_damage += 1 * n
						if "aftershock_damage" in u:
							u.aftershock_damage += 1 * n

				&"arachno_range_plus_1":
					if u is S3:
						# Special targeting range (NOVA)
						if "nova_range" in u:
							u.nova_range += 1 * n
						else:
							# fallback if you later rename it
							u.attack_range += 1 * n

				# -------------------------
				# COBRUH A.I.
				# -------------------------
				&"cobruh_hp_plus_2":
					if u is CarBot:
						u.max_hp += 2 * n
						u.hp = min(u.hp + 2 * n, u.max_hp)

				&"cobruh_dmg_plus_1":
					if u is CarBot:
						u.attack_damage += 1 * n

				# -------------------------
				# SCANNERZ (S1)
				# -------------------------
				&"scannerz_hp_plus_1":
					if u is S1:
						u.max_hp += 1 * n
						u.hp = min(u.hp + 1 * n, u.max_hp)

				&"scannerz_move_plus_1":
					if u is S1:
						u.move_range += 1 * n

				&"scannerz_dmg_plus_1":
					if u is S1:
						u.attack_damage += 1 * n

				&"scannerz_laser_grid_range_plus_1":
					if u is S1:
						# your S1 uses grid_range
						u.grid_range += 1 * n

				&"scannerz_overcharge_range_plus_1":
					if u is S1:
						# your S1 uses overcharge_range
						u.overcharge_range += 1 * n

				# -------------------------
				# MARV (M3)
				# -------------------------
				&"marv_hp_plus_2":
					if u is M3:
						u.max_hp += 2 * n
						u.hp = min(u.hp + 2 * n, u.max_hp)

				&"marv_move_plus_1":
					if u is M3:
						u.move_range += 1 * n

				&"marv_dmg_plus_1":
					if u is M3:
						u.attack_damage += 1 * n
						# Optional: also boost special damages if you want upgrades to feel "real"
						if "artillery_damage" in u:
							u.artillery_damage += 1 * n
						if "laser_damage" in u:
							u.laser_damage += 1 * n

				&"marv_artillery_strike_range_plus_1":
					if u is M3:
						if "artillery_range" in u:
							u.artillery_range += 1 * n
						else:
							u.attack_range += 1 * n # fallback

				&"marv_laser_sweep_range_plus_1":
					if u is M3:
						if "laser_range" in u:
							u.laser_range += 1 * n
						else:
							u.attack_range += 1 * n # fallback


					
func reset_for_regen() -> void:
	# ---------------------------
	# Stop anything mid-action
	# ---------------------------
	_is_moving = false
	selected = null
	aim_mode = AimMode.MOVE
	special_id = &""

	valid_move_cells.clear()
	valid_special_cells.clear()

	# ---------------------------
	# Clear PICKUPS / DROPS
	# ---------------------------
	for c in pickups_by_cell.keys():
		var n = pickups_by_cell.get(c, null)
		if n != null and (typeof(n) == TYPE_OBJECT) and is_instance_valid(n):
			(n as Node).queue_free()
	pickups_by_cell.clear()

	# ---------------------------
	# Clear MINES (logical + nodes)
	# ---------------------------
	for c in mine_nodes_by_cell.keys():
		var n2 = mine_nodes_by_cell.get(c, null)
		if n2 != null and (typeof(n2) == TYPE_OBJECT) and is_instance_valid(n2):
			(n2 as Node).queue_free()
	mine_nodes_by_cell.clear()
	mines_by_cell.clear()

	# ---------------------------
	# Reset BEACON state
	# ---------------------------
	beacon_parts_collected = 0
	beacon_ready = false
	_beacon_sweep_started = false

	# Kill beacon pulse tween if running
	if _beacon_pulse_tw != null and is_instance_valid(_beacon_pulse_tw):
		_beacon_pulse_tw.kill()
	_beacon_pulse_tw = null

	# Remove marker node if exists
	if beacon_marker_node != null and is_instance_valid(beacon_marker_node):
		beacon_marker_node.queue_free()
	beacon_marker_node = null

func _rebuild_recruit_pool_from_allies() -> void:
	_recruit_pool.clear()

	# Add any ally scene that is NOT already used this run
	for sc in ally_scenes:
		if sc == null:
			continue
		if _used_ally_scenes.has(sc):
			continue
		_recruit_pool.append(sc)

	_recruit_pool.shuffle()

func reset_recruit_pool() -> void:
	_rebuild_recruit_pool_from_allies()

func apply_recruit_pool_from_runstate(rs: Node) -> void:
	if rs == null:
		return

	_used_ally_scenes.clear()
	_recruit_pool.clear()

	# 1) Mark ONLY the starting squad as used (if provided)
	if "starting_squad_paths" in rs:
		for p in rs.starting_squad_paths:
			var res := load(str(p))
			if res is PackedScene and not _used_ally_scenes.has(res):
				_used_ally_scenes.append(res)

	# 2) Build recruit pool from explicit remaining paths (best)
	if "recruit_pool_paths" in rs:
		for p in rs.recruit_pool_paths:
			var res2 := load(str(p))
			if res2 is PackedScene:
				# optional: also exclude anything marked used
				if not _used_ally_scenes.has(res2):
					_recruit_pool.append(res2)

	_recruit_pool.shuffle()

	# 3) Fallback: if runstate didn't provide recruit pool, build from ally_scenes
	if _recruit_pool.is_empty():
		_rebuild_recruit_pool_from_allies()

func _rs() -> Node:
	var r := get_tree().root
	var rs := r.get_node_or_null("RunStateNode")
	if rs != null:
		return rs
	rs = r.get_node_or_null("RunState")
	if rs != null:
		return rs
	return null

func _spawn_bomber(world_x: float, world_y: float) -> Node2D:
	if bomber_scene == null:
		return null
	var b := bomber_scene.instantiate() as Node2D
	if b == null:
		return null

	# Put bomber in overlays so it’s “above” the map visually
	var parent: Node = overlay_root if (overlay_root != null and is_instance_valid(overlay_root)) else self
	parent.add_child(b)

	# Start offscreen (same x, high y)
	b.global_position = Vector2(world_x, world_y + bomber_y_offscreen)

	# Keep on top
	b.z_as_relative = false
	b.z_index = 999999

	return b

func _tween_node_global_pos(n: Node2D, from: Vector2, to: Vector2, t: float) -> void:
	if n == null or not is_instance_valid(n):
		return
	n.global_position = from
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(n, "global_position", to, max(0.01, t))
	await tw.finished

func _drop_unit_from_bomber(u: Unit, bomber: Node2D, target_cell: Vector2i) -> void:
	if u == null or not is_instance_valid(u) or bomber == null or not is_instance_valid(bomber):
		return
	if terrain == null:
		return

	var target_world := _cell_world(target_cell)

	# Start at bomber “belly”
	u.global_position = bomber.global_position
	_set_unit_depth_from_world(u, u.global_position)

	# Quick fall
	var fall_tw := create_tween()
	fall_tw.set_trans(Tween.TRANS_SINE)
	fall_tw.set_ease(Tween.EASE_IN)
	fall_tw.tween_property(u, "global_position", target_world, max(0.01, drop_fall_time))
	await fall_tw.finished

	# Lock to cell + depth
	u.set_cell(target_cell, terrain)
	_set_unit_depth_from_world(u, u.global_position)

	# Landing pop (visual node if available)
	var vis := _get_unit_visual_node(u)
	if vis != null and is_instance_valid(vis):
		var base := vis.position
		vis.position = base + Vector2(0, -drop_land_pop_px)
		var pop := create_tween()
		pop.set_trans(Tween.TRANS_SINE)
		pop.set_ease(Tween.EASE_OUT)
		pop.tween_property(vis, "position", base, max(0.01, drop_land_pop_time))
		await pop.finished

	_sfx(drop_sfx, sfx_volume_world, randf_range(0.95, 1.05), target_world)

func _apply_runstate_upgrades_to_unit(u: Unit) -> void:
	var rs := get_tree().root.get_node_or_null("RunState")
	if rs == null:
		return

	# Example global upgrades
	if rs.run_upgrade_counts.get(&"all_hp_plus_1", 0) > 0:
		var n := int(rs.run_upgrade_counts[&"all_hp_plus_1"])
		u.max_hp += n
		u.hp = min(u.hp + n, u.max_hp)

	if rs.run_upgrade_counts.get(&"all_move_plus_1", 0) > 0:
		u.move_range += int(rs.run_upgrade_counts[&"all_move_plus_1"])

	if rs.run_upgrade_counts.get(&"all_dmg_plus_1", 0) > 0:
		u.attack_damage += int(rs.run_upgrade_counts[&"all_dmg_plus_1"])

func _init_floppy_kill_curve() -> void:
	zombies_killed_this_map = 0
	floppy_drop_index = 0

	var rs := _rs()
	var node_type := &"combat"
	var diff := 0.0
	if rs != null:
		if "mission_node_type" in rs:
			node_type = rs.mission_node_type
		if "mission_difficulty" in rs:
			diff = float(rs.mission_difficulty) # 0..1

	var curve: Array[int] = floppy_curve_combat
	if node_type == &"elite":
		curve = floppy_curve_elite
	elif node_type == &"event":
		curve = floppy_curve_event
	elif node_type == &"boss":
		curve = floppy_curve_boss

	# Difficulty nudge (light touch!)
	# 0..1 => 0.9x .. 1.2x
	var mult = lerp(0.90, 1.20, clamp(diff, 0.0, 1.0))

	# First target
	if curve.is_empty():
		floppy_kills_left = -1
	else:
		floppy_kills_left = int(round(float(curve[0]) * mult))
