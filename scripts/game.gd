extends Node2D

# ----------------------------------
# Game flow (adds player engagement)
# ----------------------------------
enum GameState { SETUP, BATTLE, REWARD }
var state: GameState = GameState.SETUP

# IMPORTANT:
# - map_width/map_height are in GRID CELLS (your 16x16 logical map)
# - each cell is one tile in the TileMap (your tiles are 32x32 pixels in the TileSet)
@export var map_width := 16
@export var map_height := 16

# Terrain IDs (also TileSet SOURCE IDs) for Terrain TileMap
const T_DIRT := 0
const T_SANDSTONE := 1
const T_SNOW := 2
const T_GRASS := 3
const T_ICE := 4
const T_WATER := 5

const LAYER_TERRAIN := 0

# --- Roads (drawn on a separate TileMap layer) ---
const LAYER_ROADS := 1

const ROAD_INTERSECTION := 6   # your tile ID 6
const ROAD_DOWN_LEFT := 7      # your tile ID 7
const ROAD_DOWN_RIGHT := 8     # your tile ID 8

const ROAD_ATLAS := Vector2i(0, 0)

# --- Highlight overlay (hover/selection) ---
@onready var highlight: TileMap = $Highlight
const LAYER_HIGHLIGHT := 0
const HOVER_TILE_SMALL_SOURCE_ID := 99   # 1x1 hover tile source id
const HOVER_TILE_BIG_SOURCE_ID := 100    # 2x2 hover tile source id
const HOVER_ATLAS := Vector2i(0, 0)

# --- Movement overlay ---
@onready var move_range: TileMap = $MoveRange
const LAYER_MOVE := 0
const MOVE_TILE_SMALL_SOURCE_ID := 0     # 1x1 move tile source id
const MOVE_TILE_BIG_SOURCE_ID := 1       # 2x2 move tile source id
const MOVE_ATLAS := Vector2i(0, 0)

# --- Attack overlays (split) ---
@onready var attack_range_small: TileMap = $AttackRangeSmall
@onready var attack_range_big: TileMap = $AttackRangeBig
const LAYER_ATTACK := 0
const ATTACK_TILE_SMALL_SOURCE_ID := 0
const ATTACK_TILE_BIG_SOURCE_ID := 1
const ATTACK_ATLAS := Vector2i(0, 0)

# --- Mine placement preview (uses Highlight TileMap) ---
@onready var mine_preview: TileMap = $MinePreview
const LAYER_MINE_PREVIEW := 0
const MINE_PREVIEW_SMALL_SOURCE_ID := 0     # set to your tileset IDs
const MINE_PREVIEW_SMALLX_SOURCE_ID := 1
const MINE_PREVIEW_ATLAS := Vector2i(0, 0)


@export var attack_offset_small := Vector2(0, 0) # small 1x1 offset
@export var attack_offset_big := Vector2(0, 16)   # big 2x2 offset

# store Units instead of origins (avoids origin/offset problems)
var attackable_units := {} # Dictionary[Unit, bool]

enum Season { DIRT, SANDSTONE, SNOW, GRASS, ICE }
@export var season: Season = Season.GRASS
@export_range(0.0, 1.0, 0.05) var season_strength := 0.75

@export_range(0.0, 0.6, 0.01) var target_water := 0.15
@export_range(0.0, 1.0, 0.05) var freeze_water_chance := 0.65
@export_range(0, 2000, 1) var max_fix_iterations := 500
@export_range(0, 999999, 1) var map_seed := 0

# Spawning
@export var human_count := 1
@export var human2_count := 1
@export var mech_count := 2
@export var zombie_count := 9
@export var human_scene: PackedScene
@export var human2_scene: PackedScene
@export var mech_scene: PackedScene
@export var zombie_scene: PackedScene

@export_range(0, 256, 1) var water_tiles_target := 24      # exact number of water tiles you want
@export_range(1, 50, 1) var water_tries_per_tile := 8      # higher = better chance to hit target

# --- Human right-click TNT throw ---
@export var tnt_projectile_scene: PackedScene
@export var tnt_explosion_scene: PackedScene
@export var tnt_arc_height := 80.0   # pixels (higher = more 'in the air')
@export var tnt_flight_time := 1.85   # seconds
@export var tnt_spin_turns := 3.0     # full rotations during flight
@export var tnt_splash_radius := 1    # in grid cells (1 = 3x3 area)
@export var tnt_damage := 2

@onready var terrain: TileMap = $Terrain
@onready var units_root: Node2D = $Units
@onready var pickups_root: Node2D = $Pickups
# --- Roads TileMap (MUST be a separate TileMap with 64x64 TileSet) ---
@onready var roads: TileMap = get_node_or_null("Roads") as TileMap

@onready var bake_vp: SubViewport = get_node_or_null("MapBakeViewport")
@onready var bake_root: Node2D = (bake_vp.get_node_or_null("MapBakeRoot") as Node2D) if bake_vp else null
@onready var baked_sprite: Sprite2D = get_node_or_null("MapBakedSprite") as Sprite2D

@export var bake_map_visuals := true

@export var road_pixel_offset := Vector2(-32, 0) # tweak if needed
const ROAD_SIZE := 2 # 64x64 road tile covers 2x2 of your 16x16 grid

# --- Depth sorting (x+y) ---
const Z_STRUCTURES := 1000
const Z_UNITS := 2000 # keep in sync with Unit.gd

var grid := GridData.new()
var rng := RandomNumberGenerator.new()

# Keep origins for later (selection/highlight will use this later)
var unit_origin := {} # Dictionary: Unit -> Vector2i

var selected_unit: Unit = null
var hovered_unit: Unit = null

# Mouse / move helpers
var hovered_cell: Vector2i = Vector2i(-1, -1)
var reachable_set := {} # Dictionary used like a Set: cell -> true

var move_tween: Tween = null
var is_moving_unit := false
var is_attacking_unit := false

# --- Overlay pixel offsets (match your cursor offsets) ---
@export var hover_offset_1x1 := Vector2(0, 0)
@export var hover_offset_2x2 := Vector2(0, 16)

@export var move_offset_1x1 := Vector2(0, 0)
@export var move_offset_2x2 := Vector2(0, 16)

# -----------------------
# Spawning helpers (regions)
# -----------------------
@export var ally_spawn_size := Vector2i(6, 6)   # top-left area size
@export var enemy_spawn_size := Vector2i(6, 6)  # bottom-right area size

@export var turn_manager: NodePath
var TM: TurnManager = null
var is_player_mode := false

# --- Player engagement (works even in AUTO_BATTLE) ---
@export var allow_player_assist_in_auto := true
@export_range(0, 9, 1) var assist_tnt_charges_per_battle := 1

# Persistent run progression (simple "one more round" loop)
var round_index := 1
var bonus_max_hp := 0
var bonus_attack_range := 0
var bonus_move_range := 0
var bonus_tnt_damage := 0
var bonus_attack_repeats := 0

# Persistent zombie progression (stacks across rounds)
var zombie_bonus_hp := 0
var zombie_bonus_repeats := 0
var zombie_bonus_count:= 0

# Per-battle assist charges
var assist_tnt_charges_left := 0

@export var tnt_curve_points := 24          # more = smoother line
@export var tnt_curve_line_width := 3.0
@export var tnt_curve_show_time := 0.60     # seconds (usually == flight time)

var _tnt_curve_line: Line2D = null

# --- TNT AIM MODE (right-click to arm, left-click to fire) ---
var tnt_aiming := false
var tnt_aim_unit: Unit = null
var tnt_aim_cell: Vector2i = Vector2i(-1, -1)

# --- Minimal UI (created in code so you don't have to wire a scene) ---
var ui_layer: CanvasLayer
var ui_root: Control
var ui_status_label: RichTextLabel
var ui_start_button: Button
var ui_reward_panel: PanelContainer
var ui_reward_label: Label
var ui_reward_buttons: Array[Button] = []

# --- HUD (bottom-right) ---
var hud_root: Control
var hud_panel: PanelContainer
var hud_portrait: TextureRect
var hud_name: Label
var hud_hp_bar: ProgressBar
var hud_target: Unit = null

# --- HUD HP color thresholds ---
@export_range(0.0, 1.0, 0.01) var hud_high_threshold := 0.67
@export_range(0.0, 1.0, 0.01) var hud_mid_threshold := 0.34

@export var hud_hp_color_high := Color(0.25, 0.95, 0.35, 1.0) # green
@export var hud_hp_color_mid  := Color(1.0, 0.9, 0.25, 1.0)  # yellow
@export var hud_hp_color_low  := Color(1.0, 0.25, 0.25, 1.0) # red

# Put this near the top of game.gd (or wherever _build_ui lives)
@export var ui_font_path: String = "res://fonts/magofonts/mago1.ttf"
@export var ui_font_size: int = 16
@export var ui_title_font_size: int = 16

var ui_font: FontFile

@onready var sfx: AudioStreamPlayer2D = $SFX

@export var sfx_human_attack: AudioStream
@export var sfx_zombie_attack: AudioStream

@export var sfx_human_hurt: AudioStream
@export var sfx_zombie_hurt: AudioStream

@export var sfx_human_die: AudioStream
@export var sfx_zombie_die: AudioStream

@export var sfx_explosion: AudioStream
@export var sfx_move: AudioStream # optional

@export var sfx_tnt_throw: AudioStream

@export var sfx_humantwo_attack: AudioStream
@export var sfx_dog_attack: AudioStream

@export var sfx_humantwo_hurt: AudioStream
@export var sfx_dog_hurt: AudioStream

@export var sfx_humantwo_die: AudioStream
@export var sfx_dog_die: AudioStream

@export var sfx_medkit_pickup: AudioStream

# --- Loot drop: Orbital Laser pickup ---
@export var laser_drop_scene: PackedScene          # your prefab
@export_range(0.0, 1.0, 0.05) var laser_drop_chance := 0.35

# --- Loot drop: Medkit pickup ---
@export var medkit_drop_scene: PackedScene
@export_range(0.0, 1.0, 0.05) var medkit_drop_chance := 0.45
@export_range(1, 10, 1) var medkit_heal_amount := 2

# Orbital laser effect
@export var orbital_beam_width := 1.0
@export var orbital_hits := 4                       # how many zombies get zapped
@export var orbital_delay := 0.12                   # time between hits
@export var orbital_damage := 999                   # basically guaranteed kill
@export var orbital_beam_height_px := 1400.0        # tall beam line
@export var sfx_orbital_zap: AudioStream            # optional zap

var pickups := {} # Dictionary[Vector2i, Node2D]  # cell -> pickup instance

@onready var roads_dl: TileMap = $RoadsDL
@onready var roads_dr: TileMap = $RoadsDR
@onready var roads_x: TileMap = $RoadsX
@export var road_pixel_offset_x := Vector2(0, 16) # neutral (center)

@export var road_pixel_offset_dl := Vector2(0, 16)
@export var road_pixel_offset_dr := Vector2(0, 16) # <-- this is the “other direction” offset

# --- Structures / Buildings ---
# NEW: allow multiple building prefabs
@export var building_scenes: Array[PackedScene] = []

# (keep this as a fallback if you want)
@export var building_scene: PackedScene

@export var building_count := 6
@export var building_footprint := Vector2i(1, 1)  # buildings are 2x2 cells

# Optional: keep buildings out of spawn zones
@export var avoid_spawn_zones := true

# Put a Node2D named "Structures" in your scene (sibling to Units/Pickups),
# or we’ll fall back to self.
@onready var structures_root: Node2D = get_node_or_null("Structures") as Node2D

# --- Structure tinting ---
@export var structure_tint_strength := 0.55  # 0 = no tint, 1 = full tint
@export var structure_tint_value_jitter := 0.12  # small brightness variance
@export var structure_tint_sat_jitter := 0.10    # small saturation variance

# A nice readable palette (edit to taste)
@export var structure_tint_palette: Array[Color] = [
	Color("#E07A5F"), # warm clay
	Color("#81B29A"), # sage
	Color("#F2CC8F"), # sand
	Color("#3D405B"), # slate
	Color("#9C89B8"), # lilac
	Color("#F4F1DE"), # off-white
]

var roads_baked_sprite: Sprite2D = null

# --- Destructible structures support ---
var structures := []                       # Array[Node2D]
var structure_by_cell := {}                # Dictionary[Vector2i, Node2D]
var structure_hp := {}                     # Dictionary[Node2D, int]
@export var building_max_hp := 2

@export var hover_outline_shader: Shader = preload("res://shaders/outline_1px.gdshader")
@export var hover_outline_color: Color = Color(1.0, 1.0, 0.25, 1.0) # tweak

var _hover_outlined_unit: Unit = null
var _hover_prev_material := {} # Dictionary[Unit, Material]

var _hover_outlined_structure: Node2D = null
var _hover_prev_structure_material := {} # Dictionary[Node2D, Material]

var _hover_attack_structure: Node2D = null

# -------------------
# Setup drag state
# -------------------
var setup_dragging := false
var setup_drag_unit: Unit = null
var setup_drag_start_origin := Vector2i.ZERO

# --- Landmine mechanic ---
@export var landmine_scene: PackedScene               # your mine prefab (Area2D recommended)
@export var landmine_explosion_scene: PackedScene     # OPTIONAL (leave null to use tnt_explosion_scene)
@export_range(0, 9, 1) var mines_per_battle_base := 3 # starting mines per battle

# persistent upgrade across rounds
var bonus_mines_per_battle := 0

# per-battle charges (reset each battle)
var mines_left := 0

# placement state (SETUP only)
var mine_placing := false

# cell -> mine instance
var mines := {} # Dictionary[Vector2i, Node2D]

var ui_mine_button: Button
var ui_mine_label: Label

var _motion_cancel_token := 0

# Blocked cells for buildings (acts like a Set): cell -> true
var structure_blocked := {}

# Terrain cells covered by ANY road tile (acts like a Set): cell -> true
var road_blocked := {}

# --- Structure action selection (SETUP only) ---
@export var structure_shot_scene: PackedScene          # assign res://scenes/structure_shot.tscn
@export var structure_attack_range := 8
@export var structure_splash_radius := 1
@export var structure_attack_damage := 2

var structure_selecting := false
var structure_can_act := {} # Dictionary[Node2D, bool]

var ui_structure_label: Label
var ui_structure_button: Button

@export var structure_active_cap := 2   # start cap = 2 (what you asked)

func _pick_structure_tint() -> Color:
	if structure_tint_palette == null or structure_tint_palette.is_empty():
		# fallback: random pastel-ish
		var h := rng.randf()
		var s = clamp(rng.randf_range(0.25, 0.55), 0.0, 1.0)
		var v = clamp(rng.randf_range(0.75, 1.0), 0.0, 1.0)
		return Color.from_hsv(h, s, v, 1.0)

	var base := structure_tint_palette[rng.randi_range(0, structure_tint_palette.size() - 1)]

	# jitter slightly so repeats still feel different
	var h := base.h
	var s = clamp(base.s + rng.randf_range(-structure_tint_sat_jitter, structure_tint_sat_jitter), 0.0, 1.0)
	var v = clamp(base.v + rng.randf_range(-structure_tint_value_jitter, structure_tint_value_jitter), 0.0, 1.0)

	return Color.from_hsv(h, s, v, 1.0)

func _apply_structure_tint(b2: Node2D) -> void:
	if b2 == null or not is_instance_valid(b2):
		return

	var tint := _pick_structure_tint()
	var blended := Color.WHITE.lerp(tint, clamp(structure_tint_strength, 0.0, 1.0))

	# store base tint so "active dim/bright" doesn't destroy it
	b2.set_meta("base_tint", blended)
	b2.modulate = blended


func _rect_top_left(size: Vector2i) -> Rect2i:
	return Rect2i(Vector2i(0, 0), size)

func _rect_bottom_right(size: Vector2i) -> Rect2i:
	var pos := Vector2i(map_width - size.x, map_height - size.y)
	return Rect2i(pos, size)

func _rand_cell_in_rect(r: Rect2i) -> Vector2i:
	return Vector2i(
		rng.randi_range(r.position.x, r.position.x + r.size.x - 1),
		rng.randi_range(r.position.y, r.position.y + r.size.y - 1)
	)

# -----------------------
# Units: spawning (UPDATED)
# -----------------------
func spawn_units() -> void:
	# ✅ clear old pickups between battles
	for c in pickups.keys():
		var p = pickups[c]
		if p != null and is_instance_valid(p):
			p.queue_free()
	pickups.clear()

	if human_scene == null or mech_scene == null or zombie_scene == null:
		push_warning("Assign human_scene, mech_scene, and zombie_scene in the Inspector.")
		return

	# wipe old units
	for child in units_root.get_children():
		child.queue_free()
	grid.occupied.clear()
	unit_origin.clear()

	# ---- build zones (4 quadrants) ----
	var zones := _build_spawn_zones()
	if zones.is_empty():
		# fallback: whole map
		zones = [Rect2i(Vector2i(0, 0), Vector2i(map_width, map_height))]

	# pick a random zone for ALLIES
	var ally_zone_idx := rng.randi_range(0, zones.size() - 1)

	# pick a different random zone for ZOMBIES (if possible)
	var zombie_zone_idx := ally_zone_idx
	if zones.size() > 1:
		while zombie_zone_idx == ally_zone_idx:
			zombie_zone_idx = rng.randi_range(0, zones.size() - 1)

	var ally_zone := zones[ally_zone_idx]

	# “spill order”: start at zombie zone, then go to the “next zones”
	# (we rotate the zone list so zombie_zone is first, then the rest in sequence)
	var zombie_zone_order: Array[Rect2i] = []
	for i in range(zones.size()):
		var idx := (zombie_zone_idx + i) % zones.size()
		zombie_zone_order.append(zones[idx])

	# ---- Spawn ALLIES together in ally_zone ----
	# (mechs + humans + human2)
	for i in range(mech_count):
		_spawn_one_in_zone(mech_scene, ally_zone)

	for i in range(human_count):
		_spawn_one_in_zone(human_scene, ally_zone)

	if human2_scene != null:
		for i in range(human2_count):
			_spawn_one_in_zone(human2_scene, ally_zone)

	# ---- Spawn ZOMBIES together in zombie zone, spill into next zones if needed ----
	_spawn_many_spilling(zombie_scene, zombie_count + zombie_bonus_count, zombie_zone_order)

	_update_all_unit_layering()
	_refresh_ui_status()

func _build_spawn_zones() -> Array[Rect2i]:
	# 4 quadrants: TL, TR, BL, BR
	var zones: Array[Rect2i] = []

	# If your map isn't evenly divisible, we floor for safety.
	var half_w = max(1, map_width / 2)
	var half_h = max(1, map_height / 2)

	var tl := Rect2i(Vector2i(0, 0), Vector2i(half_w, half_h))
	var tr := Rect2i(Vector2i(map_width - half_w, 0), Vector2i(half_w, half_h))
	var bl := Rect2i(Vector2i(0, map_height - half_h), Vector2i(half_w, half_h))
	var br := Rect2i(Vector2i(map_width - half_w, map_height - half_h), Vector2i(half_w, half_h))

	zones.append(tl)
	zones.append(tr)
	zones.append(bl)
	zones.append(br)

	# Optional: shuffle zone “identity” a bit (still quadrants, but random order)
	# NOTE: we still “spill into next zone” via rotated order in spawn_units().
	# If you want strict clockwise spill, remove this shuffle.
	zones.shuffle()

	return zones


func _spawn_many_spilling(scene: PackedScene, count: int, zone_order: Array[Rect2i]) -> void:
	if scene == null:
		return
	if count <= 0:
		return
	if zone_order.is_empty():
		return

	var zone_i := 0
	var spawned := 0

	# We’ll try hard, but never infinite loop.
	var global_guard := 6000

	while spawned < count and global_guard > 0:
		global_guard -= 1

		# if we run out of zones, keep using the last one (or wrap; your call)
		zone_i = clampi(zone_i, 0, zone_order.size() - 1)

		var zone := zone_order[zone_i]

		var ok := _spawn_one_in_zone(scene, zone)

		if ok:
			spawned += 1
			continue

		# Could not fit into this zone: spill to next zone
		if zone_i < zone_order.size() - 1:
			zone_i += 1
		else:
			# Nowhere left. We stop (or you could relax rules here).
			push_warning("Not enough space to spawn all units. Spawned %d/%d." % [spawned, count])
			return


func _spawn_one_in_zone(scene: PackedScene, zone: Rect2i) -> bool:
	# Same idea as your _spawn_one, but constrained to a zone.
	var tries := 500
	while tries > 0:
		tries -= 1

		var unit := scene.instantiate() as Unit
		if unit == null:
			return false

		var origin := _rand_cell_in_rect(zone)

		# big units must align
		if _is_big_unit(unit):
			origin = snap_origin_for_unit(origin, unit)

			# if snapping pushed it outside the zone, try again
			if not zone.has_point(origin):
				unit.queue_free()
				continue

		var cells := unit.footprint_cells(origin)

		var ok := true
		for c in cells:
			if not grid.in_bounds(c):
				ok = false
				break
			if grid.terrain[c.x][c.y] == T_WATER:
				ok = false
				break

			# ✅ don't spawn on structure footprints
			if structure_blocked.has(c):
				ok = false
				break

			# ✅ also keep out of roads if you want
			# (you already use road_blocked for mines/buildings; optional for spawns)
			# if road_blocked.has(c):
			# 	ok = false
			# 	break

			if grid.is_occupied(c):
				ok = false
				break

		if not ok:
			unit.queue_free()
			continue

		# commit occupancy
		for c in cells:
			grid.set_occupied(c, unit)

		unit.grid_pos = origin
		unit_origin[unit] = origin
		units_root.add_child(unit)

		# ✅ keep HUD live-updating on HP changes
		if not unit.hp_changed.is_connected(_on_unit_hp_changed):
			unit.hp_changed.connect(_on_unit_hp_changed)

		# ✅ ensure HUD clears if the bound unit dies
		if not unit.died.is_connected(_on_unit_died):
			unit.died.connect(_on_unit_died)

		# ✅ Apply run bonuses AFTER the unit's own _ready() finishes
		if unit.team == Unit.Team.ALLY:
			unit.call_deferred("apply_run_bonuses", bonus_max_hp, bonus_attack_range, bonus_move_range, bonus_attack_repeats)

		# ✅ Enemy scaling (zombies only) — STACKED + PERSISTENT
		if unit is Zombie:
			unit.call_deferred("_apply_hp_bonus_safe", zombie_bonus_hp)
			unit.call_deferred("_apply_repeats_bonus_safe", zombie_bonus_repeats)

		# place in world
		unit.global_position = cell_to_world_for_unit(origin, unit)

		return true

	return false

# -----------------------
# SETUP: reposition allies before starting the battle
# -----------------------
func _setup_place_selected(cell: Vector2i) -> bool:
	if selected_unit == null or not is_instance_valid(selected_unit):
		return false
	if selected_unit.team != Unit.Team.ALLY:
		return false
	if not grid.in_bounds(cell):
		return false

	var u := selected_unit
	var new_origin := cell
	if _is_big_unit(u):
		new_origin = snap_origin_for_unit(cell, u)

	# ✅ Must be inside the precomputed move range
	if not reachable_set.has(new_origin):
		return false

	# basic terrain check
	if grid.terrain[new_origin.x][new_origin.y] == T_WATER:
		return false

	# --- Temporarily clear own occupancy ---
	var old_origin := get_unit_origin(u)
	for c in u.footprint_cells(old_origin):
		if grid.is_occupied(c) and grid.get_occupied(c) == u:
			grid.set_occupied(c, null)

	# --- Validate new footprint ---
	var ok := true
	for c in u.footprint_cells(new_origin):
		if not grid.in_bounds(c):
			ok = false
			break
		if grid.terrain[c.x][c.y] == T_WATER:
			ok = false
			break
		if structure_blocked.has(c):
			ok = false
			break
		if grid.is_occupied(c):
			ok = false
			break

	# --- Restore if failed ---
	if not ok:
		for c in u.footprint_cells(old_origin):
			grid.set_occupied(c, u)
		return false

	# --- Commit new position ---
	for c in u.footprint_cells(new_origin):
		grid.set_occupied(c, u)

	unit_origin[u] = new_origin
	u.grid_pos = new_origin
	u.global_position = cell_to_world_for_unit(new_origin, u)

	_update_all_unit_layering()
	_refresh_ui_status()
	return true
	
func _on_unit_hp_changed(u: Unit) -> void:
	# If HUD is currently showing this unit, refresh immediately
	if hud_target != null and is_instance_valid(hud_target) and hud_target == u:
		_hud_refresh()
		return

	# Optional: if you're hovering this unit, show it + refresh (feels good)
	if hovered_unit != null and is_instance_valid(hovered_unit) and hovered_unit == u:
		_hud_bind(u)  # this will call _hud_refresh()

	_hud_bind(u)

func _unit_sprite(u: Unit) -> AnimatedSprite2D:
	if u == null:
		return null
	# Change this path if your sprite is named differently
	if u.has_node("AnimatedSprite2D"):
		return u.get_node("AnimatedSprite2D") as AnimatedSprite2D
	return null

func _play_anim(u: Unit, anim_name: StringName) -> void:
	var spr := _unit_sprite(u)
	if spr == null:
		return
	if spr.sprite_frames != null and spr.sprite_frames.has_animation(anim_name):
		spr.play(anim_name)

func _play_idle(u: Unit) -> void:
	var spr := _unit_sprite(u)
	if spr == null:
		return
	if spr.sprite_frames != null and spr.sprite_frames.has_animation("idle"):
		spr.play("idle")
	else:
		spr.stop()

func _ready() -> void:
	_seed_rng()
	
	rng.randomize()

	# GridData should be 16x16 here
	grid.setup(map_width, map_height)

	generate_map()
	terrain.update_internals()
	_sync_roads_transform()
	
	if bake_map_visuals:
		#await bake_map_to_sprite()
		await bake_roads_to_sprite()

	spawn_structures()		
	spawn_units()

	_build_ui()
	_build_hud()

	if turn_manager != NodePath():
		TM = get_node(turn_manager) as TurnManager
		if TM != null:
			TM.battle_started.connect(_on_battle_started)
			TM.battle_ended.connect(_on_battle_ended)

	structure_selecting = false	
	_refresh_ui_status()

	# Start in SETUP so the player can reposition allies, then press Start.
	_enter_setup()

func _advance_round_progression() -> void:
	# Move to next round
	round_index += 1

	# --- Zombie HP scales every 3 rounds ---
	# r: 1→0, 2→0, 3→1, 4→1, 5→1, 6→2 ...
	if round_index < 3:
		zombie_bonus_hp = 0
	else:
		zombie_bonus_hp = int(floor((round_index - 1) / 3.0))

	# --- Zombie attack repeats scale every 3 rounds starting at round 2 ---
	# r: 1→0, 2→1, 3→1, 4→1, 5→2, 6→2 ...
	if round_index < 2:
		zombie_bonus_repeats = 0
	else:
		zombie_bonus_repeats = int(floor((round_index - 2) / 3.0)) + 1

	# --- Zombie count scales gently every 2 rounds ---
	# r: 1→0, 2→1, 3→1, 4→2, 5→2, 6→3 ...
	if round_index < 2:
		zombie_bonus_count = 0
	else:
		zombie_bonus_count = int(floor((round_index - 2) / 2.0)) + 1

func _sync_roads_transform() -> void:
	_sync_one_roads_transform(roads_dl, road_pixel_offset_dl)
	_sync_one_roads_transform(roads_dr, road_pixel_offset_dr)
	_sync_one_roads_transform(roads_x,  road_pixel_offset_x)

func _sync_one_roads_transform(rmap: TileMap, px_off: Vector2) -> void:
	if rmap == null:
		return

	var terrain_origin_local := terrain.map_to_local(Vector2i.ZERO)
	var roads_origin_local := rmap.map_to_local(Vector2i.ZERO)

	rmap.position = terrain.position + (terrain_origin_local - roads_origin_local) + px_off

	# ✅ FORCE same z_layer as everything else
	rmap.z_as_relative = false
	rmap.z_index = 1

func _process(_delta: float) -> void:
	# Terrain might get freed during reload/bake/rebuild — bail safely
	if terrain == null or not is_instance_valid(terrain):
		return

	if not _can_handle_player_input():
		if tnt_aiming:
			tnt_aiming = false
			tnt_aim_unit = null
			_hide_tnt_curve()
		return

	_update_hovered_cell()
	_update_hovered_unit()
	_update_tnt_aim_preview()
	_update_structure_hover_outline()

	if state == GameState.SETUP and mine_placing:
		_draw_mine_preview()
	else:
		_clear_mine_preview()
		
	# ✅ SETUP: make dragged unit follow the hovered cell
	if state == GameState.SETUP and setup_dragging and setup_drag_unit != null and is_instance_valid(setup_drag_unit):
		var c := hovered_cell
		if not grid.in_bounds(c):
			return

		var u := setup_drag_unit
		var origin := c
		if _is_big_unit(u):
			origin = snap_origin_for_unit(c, u)

		u.global_position = cell_to_world_for_unit(origin, u)

func _seed_rng() -> void:
	if map_seed == 0:
		rng.randomize()
	else:
		rng.seed = map_seed

func _get_tnt_damage() -> int:
	return int(tnt_damage + bonus_tnt_damage)

func _is_assist_mode() -> bool:
	# Assist mode = AUTO_BATTLE but player can aim/throw TNT a limited number of times.
	return allow_player_assist_in_auto and state == GameState.BATTLE and not is_player_mode

func _can_handle_player_input() -> bool:
	if state == GameState.SETUP:
		return true
	if state == GameState.BATTLE:
		return is_player_mode or _is_assist_mode()
	return false

func _build_ui() -> void:
	# --- load font once ---
	if ui_font == null:
		if ResourceLoader.exists(ui_font_path):
			ui_font = load(ui_font_path) as FontFile
		else:
			push_warning("UI font not found at: %s (using default)" % ui_font_path)

	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)

	ui_root = Control.new()
	ui_root.name = "Root"
	ui_root.anchor_right = 1.0
	ui_root.anchor_bottom = 1.0
	ui_root.offset_left = 16
	ui_root.offset_top = 16
	ui_root.offset_right = -16
	ui_root.offset_bottom = -16
	ui_layer.add_child(ui_root)

	# ✅ PANEL BEHIND (HUD-style)
	var ui_panel := PanelContainer.new()
	ui_panel.name = "UIPanel"
	ui_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ui_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	ui_root.add_child(ui_panel)

	# HUD-like flat style
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.07, 0.07, 0.08, 0.92)
	panel_sb.border_width_left = 1
	panel_sb.border_width_top = 1
	panel_sb.border_width_right = 1
	panel_sb.border_width_bottom = 1
	panel_sb.border_color = Color(0.20, 0.20, 0.22, 0.9)
	panel_sb.corner_radius_top_left = 0
	panel_sb.corner_radius_top_right = 0
	panel_sb.corner_radius_bottom_left = 0
	panel_sb.corner_radius_bottom_right = 0
	ui_panel.add_theme_stylebox_override("panel", panel_sb)

	# ✅ inner padding like HUD
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	ui_panel.add_child(margin)
	ui_panel.custom_minimum_size = Vector2(140, 0)

	# VBox inside margin
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(140, 0)
	v.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	margin.add_child(v)

	# --- status ---
	ui_status_label = RichTextLabel.new()
	ui_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_status_label.bbcode_enabled = true
	ui_status_label.fit_content = true
	ui_status_label.scroll_active = false

	if ui_font:
		ui_status_label.add_theme_font_override("normal_font", ui_font)
		ui_status_label.add_theme_font_size_override("normal_font_size", ui_font_size)
		ui_status_label.add_theme_font_override("bold_font", ui_font)
		ui_status_label.add_theme_font_override("italics_font", ui_font)
		ui_status_label.add_theme_font_override("bold_italics_font", ui_font)
	v.add_child(ui_status_label)

	# --- start button ---
	ui_start_button = Button.new()
	ui_start_button.text = "Start Battle"
	ui_start_button.pressed.connect(_on_start_pressed)
	if ui_font:
		ui_start_button.add_theme_font_override("font", ui_font)
		ui_start_button.add_theme_font_size_override("font_size", ui_font_size)
	v.add_child(ui_start_button)

	# --- Mine placement UI ---
	ui_mine_label = Label.new()
	ui_mine_label.text = "Mines: 0"
	if ui_font:
		ui_mine_label.add_theme_font_override("font", ui_font)
		ui_mine_label.add_theme_font_size_override("font_size", ui_font_size)
	v.add_child(ui_mine_label)

	ui_mine_button = Button.new()
	ui_mine_button.text = "Place Mine"
	ui_mine_button.pressed.connect(_on_mine_button_pressed)
	if ui_font:
		ui_mine_button.add_theme_font_override("font", ui_font)
		ui_mine_button.add_theme_font_size_override("font_size", ui_font_size)
	v.add_child(ui_mine_button)

	# --- Structure selection UI (like mines) ---
	ui_structure_label = Label.new()
	ui_structure_label.text = "Structures: 0/%d active" % [structure_active_cap]
	if ui_font:
		ui_structure_label.add_theme_font_override("font", ui_font)
		ui_structure_label.add_theme_font_size_override("font_size", ui_font_size)
	v.add_child(ui_structure_label)

	ui_structure_button = Button.new()
	ui_structure_button.text = "Select Structures"
	ui_structure_button.pressed.connect(_on_structure_button_pressed)
	if ui_font:
		ui_structure_button.add_theme_font_override("font", ui_font)
		ui_structure_button.add_theme_font_size_override("font_size", ui_font_size)
	v.add_child(ui_structure_button)

	# --- reward panel ---
	ui_reward_panel = PanelContainer.new()
	ui_reward_panel.visible = false
	v.add_child(ui_reward_panel)

	var rv := VBoxContainer.new()
	ui_reward_panel.add_child(rv)

	ui_reward_label = Label.new()
	ui_reward_label.text = "Choose an upgrade"
	if ui_font:
		ui_reward_label.add_theme_font_override("font", ui_font)
		ui_reward_label.add_theme_font_size_override("font_size", ui_title_font_size)
	rv.add_child(ui_reward_label)

	# ✅ Reward buttons (+ turret slot)
	ui_reward_buttons.clear()
	var b1 := Button.new(); b1.text = "+1 Max HP";        b1.pressed.connect(func(): _pick_reward(0))
	var b2 := Button.new(); b2.text = "+1 Attack Range";  b2.pressed.connect(func(): _pick_reward(1))
	var b3 := Button.new(); b3.text = "+1 TNT Damage";    b3.pressed.connect(func(): _pick_reward(2))
	var b4 := Button.new(); b4.text = "+1 Attack Repeat"; b4.pressed.connect(func(): _pick_reward(3))
	var b5 := Button.new(); b5.text = "+1 Mine";          b5.pressed.connect(func(): _pick_reward(4))
	var b6 := Button.new(); b6.text = "+1 Turret Slot";   b6.pressed.connect(func(): _pick_reward(5))

	ui_reward_buttons = [b1, b2, b3, b4, b5, b6]

	for b in ui_reward_buttons:
		if ui_font:
			b.add_theme_font_override("font", ui_font)
			b.add_theme_font_size_override("font_size", ui_font_size)
		rv.add_child(b)

	_refresh_ui_status()
	_update_structure_ui()

func _build_hud() -> void:
	# Put HUD on the SAME CanvasLayer as UI (so it overlays the world)
	if ui_layer == null or not is_instance_valid(ui_layer):
		ui_layer = CanvasLayer.new()
		ui_layer.name = "UI"
		add_child(ui_layer)

	hud_root = Control.new()
	hud_root.name = "HUD"
	hud_root.anchor_left = 1.0
	hud_root.anchor_top = 1.0
	hud_root.anchor_right = 1.0
	hud_root.anchor_bottom = 1.0
	hud_root.offset_left = -320
	hud_root.offset_top = -140
	hud_root.offset_right = -16
	hud_root.offset_bottom = -16
	ui_layer.add_child(hud_root)

	# Panel (background)
	hud_panel = PanelContainer.new()
	hud_panel.name = "Panel"
	hud_panel.size_flags_horizontal = Control.SIZE_FILL
	hud_panel.size_flags_vertical = Control.SIZE_FILL
	hud_root.add_child(hud_panel)

	# Flat panel style (no rounded corners)
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = Color(0.07, 0.07, 0.08, 0.92)
	panel_sb.border_width_left = 1
	panel_sb.border_width_top = 1
	panel_sb.border_width_right = 1
	panel_sb.border_width_bottom = 1
	panel_sb.border_color = Color(0.20, 0.20, 0.22, 0.9)
	panel_sb.corner_radius_top_left = 0
	panel_sb.corner_radius_top_right = 0
	panel_sb.corner_radius_bottom_left = 0
	panel_sb.corner_radius_bottom_right = 0
	hud_panel.add_theme_stylebox_override("panel", panel_sb)

	# ✅ REAL inner padding: MarginContainer inside PanelContainer
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	hud_panel.add_child(margin)

	# Content row goes inside margin
	var h := HBoxContainer.new()
	margin.add_child(h)
	h.custom_minimum_size = Vector2(0, 0)
	h.alignment = BoxContainer.ALIGNMENT_BEGIN
	h.add_theme_constant_override("separation", 10)

	# Portrait
	hud_portrait = TextureRect.new()
	hud_portrait.custom_minimum_size = Vector2(64, 64)
	hud_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(hud_portrait)

	# Right side (name + HP)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	h.add_child(v)

	hud_name = Label.new()
	hud_name.text = ""
	if ui_font:
		hud_name.add_theme_font_override("font", ui_font)
		hud_name.add_theme_font_size_override("font_size", ui_title_font_size)
	v.add_child(hud_name)

	hud_hp_bar = ProgressBar.new()
	hud_hp_bar.min_value = 0
	hud_hp_bar.max_value = 10
	hud_hp_bar.value = 10
	hud_hp_bar.show_percentage = false
	hud_hp_bar.custom_minimum_size = Vector2(160, 14) # ← set width here
	hud_hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	v.add_child(hud_hp_bar)

	# Flat HP bar styles (no rounded corners)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.14, 0.14, 0.16, 1.0)
	bg.corner_radius_top_left = 0
	bg.corner_radius_top_right = 0
	bg.corner_radius_bottom_left = 0
	bg.corner_radius_bottom_right = 0

	var fill := StyleBoxFlat.new()
	fill.bg_color = hud_hp_color_high # start green (your variable)
	fill.corner_radius_top_left = 0
	fill.corner_radius_top_right = 0
	fill.corner_radius_bottom_left = 0
	fill.corner_radius_bottom_right = 0

	hud_hp_bar.add_theme_stylebox_override("background", bg)
	hud_hp_bar.add_theme_stylebox_override("fill", fill)

	# ✅ store reference so we can recolor later
	hud_hp_bar.set_meta("fill_stylebox", fill)

	# Start hidden until bound
	hud_root.visible = false

func _on_structure_button_pressed() -> void:
	mine_placing = false
	
	if state != GameState.SETUP:
		return
	structure_selecting = not structure_selecting
	_update_structure_ui()

func _update_structure_ui() -> void:
	if ui_structure_button != null:
		ui_structure_button.disabled = (state != GameState.SETUP) or (structures.is_empty())
		ui_structure_button.text = ("Select Structures" if not structure_selecting else "Select Structures")

	if ui_structure_label != null:
		var active := 0
		for b in structures:
			if b != null and is_instance_valid(b) and structure_can_act.get(b, false):
				active += 1
				# turning ON: enforce cap
				active = _count_active_structures()
				if active >= structure_active_cap:
					# optional: quick feedback
					if ui_structure_label != null:
						ui_structure_label.text = "Structures: %d/%d active (MAX)" % [active, structure_active_cap]
						structure_selecting = false
						ui_structure_button.disabled = true
					return
					
		active = _count_active_structures()
		ui_structure_label.text = "Structures: %d/%d active" % [active, structure_active_cap]

func _set_structure_active_visual(b: Node2D, active: bool) -> void:
	if b == null or not is_instance_valid(b):
		return

	var base := Color(1, 1, 1, 1)
	if b.has_meta("base_tint"):
		base = b.get_meta("base_tint") as Color

	var mul := (1.0 if active else 0.55)
	b.modulate = Color(base.r * mul, base.g * mul, base.b * mul, base.a)


func _toggle_structure_active(b: Node2D) -> void:
	if b == null or not is_instance_valid(b):
		return
	if not structure_hp.has(b):
		return

	var currently := bool(structure_can_act.get(b, false))

	# turning OFF is always allowed
	if currently:
		structure_can_act[b] = false
		_set_structure_active_visual(b, false)
		_update_structure_ui()
		return

	# turning ON: enforce cap
	var active := _count_active_structures()
	if active >= structure_active_cap:
		# optional: quick feedback
		if ui_structure_label != null:
			ui_structure_label.text = "Structures: %d/%d active (MAX)" % [active, structure_active_cap]
			structure_selecting = false
		return

	structure_can_act[b] = true
	_set_structure_active_visual(b, true)
	_update_structure_ui()

func structure_at_cell(cell: Vector2i) -> Node2D:
	if structure_by_cell.has(cell):
		var b := structure_by_cell[cell] as Node2D
		if b != null and is_instance_valid(b):
			return b
	return null

func get_active_structures(team: int) -> Array[Node2D]:
	# For now: treat all structures as ALLY-side turrets.
	if team != Unit.Team.ALLY:
		return []

	var out: Array[Node2D] = []
	for b in structures:
		if b == null or not is_instance_valid(b):
			continue
		if structure_can_act.get(b, false) and not structure_hp.has(b) == false:
			# if you removed HP entries on demolition, this keeps rubble from shooting
			pass
		# Better: only allow if it still has HP tracked (not demolished)
		if structure_can_act.get(b, false) and structure_hp.has(b):
			out.append(b)
	return out

func _hud_bind(u: Unit) -> void:
	if hud_root == null:
		return

	if u == null or not is_instance_valid(u):
		hud_target = null
		hud_root.visible = false
		return

	hud_target = u
	hud_root.visible = true

	# Name
	hud_name.text = _unit_display_name(u)

	# Portrait texture (you said you already have textures)
	# Option A: set per-unit via meta: u.set_meta("portrait_tex", preload("res://...png"))
	# Option B: if the unit has a Sprite2D/AnimatedSprite2D, reuse its first frame/texture (fallback)
	var tex: Texture2D = null
	if u.has_meta("portrait_tex"):
		tex = u.get_meta("portrait_tex") as Texture2D
	else:
		# fallback tries
		if u.has_node("Portrait") and (u.get_node("Portrait") is TextureRect):
			tex = (u.get_node("Portrait") as TextureRect).texture
	hud_portrait.texture = tex

	_hud_refresh()

func _hud_refresh() -> void:
	if hud_target == null or not is_instance_valid(hud_target):
		_hud_bind(null)
		return

	var cur = max(0, int(hud_target.hp))
	var maxv = max(1, int(hud_target.max_hp))

	hud_hp_bar.max_value = maxv
	hud_hp_bar.value = cur

	# ---- dynamic fill color ----
	var ratio := float(cur) / float(maxv)
	var c: Color

	if ratio >= hud_high_threshold:
		c = hud_hp_color_high
	elif ratio >= hud_mid_threshold:
		c = hud_hp_color_mid
	else:
		c = hud_hp_color_low

	var fill := hud_hp_bar.get_meta("fill_stylebox") as StyleBoxFlat
	if fill != null:
		fill.bg_color = c

	# Optional: dim whole panel if dead
	if cur <= 0:
		hud_panel.modulate = Color(1, 1, 1, 0.5)
	else:
		hud_panel.modulate = Color(1, 1, 1, 1)

func _mine_capacity() -> int:
	return int(mines_per_battle_base + bonus_mines_per_battle)

func _reset_mines_for_new_battle() -> void:
	mines_left = _mine_capacity()
	mine_placing = false
	_update_mine_ui()

func _update_mine_ui() -> void:
	if ui_mine_label != null:
		ui_mine_label.text = "Mines: %d" % mines_left

	if ui_mine_button != null:
		ui_mine_button.disabled = (state != GameState.SETUP) or (mines_left <= 0) or (landmine_scene == null)
		ui_mine_button.text = ("Place Mine" if not mine_placing else "Place Mine")	

func _on_mine_button_pressed() -> void:
	structure_selecting = false
	
	if state != GameState.SETUP:
		return
	if mines_left <= 0:
		return
	if landmine_scene == null:
		push_warning("Assign landmine_scene in Inspector.")
		return

	mine_placing = !mine_placing
	_update_mine_ui()

func _can_place_mine_at(cell: Vector2i) -> bool:
	if not grid.in_bounds(cell):
		return false
	if grid.terrain[cell.x][cell.y] == T_WATER:
		return false
	if structure_blocked.has(cell):
		return false
	if road_blocked.has(cell):
		return false

	# ✅ NEW: don't place on a unit
	if grid.is_occupied(cell):
		return false

	# ✅ NEW: don't place where a pickup exists (optional but usually desired)
	if pickups.has(cell):
		return false

	if mines.has(cell):
		return false

	return true

func _place_mine_at(cell: Vector2i) -> bool:
	if mines_left <= 0:
		return false
	if not _can_place_mine_at(cell):
		return false

	var inst := landmine_scene.instantiate()
	var m := inst as Node2D
	if m == null:
		push_warning("landmine_scene root must be Node2D/Area2D.")
		return false

	add_child(m)

	# position at cell
	var wp := terrain.to_global(terrain.map_to_local(cell)) + Vector2(0, 0)
	m.global_position = wp
	m.z_as_relative = false
	m.z_index = 250000 + int(wp.y) # above map, below units is fine

	# store
	mines[cell] = m

	# connect trigger (works if mine is Area2D)
	if m is Area2D:
		var a := m as Area2D
		a.body_entered.connect(func(body):
			_on_mine_triggered(cell, body)
		)
	elif m.has_signal("body_entered"):
		# fallback if your root isn't Area2D but has signal
		m.connect("body_entered", Callable(self, "_on_mine_triggered").bind(cell))

	mines_left -= 1
	_update_mine_ui()
	return true

func _on_mine_triggered(cell: Vector2i, body: Node) -> void:
	var u := body as Unit
	if u == null:
		return
	if not mines.has(cell):
		return

	var mine = mines[cell]
	mines.erase(cell)

	if mine != null and is_instance_valid(mine):
		mine.queue_free()

	# stop motion so your tweens/AI don't fight explosions
	_cancel_motion_now()
	_interrupt_unit_motion(u)

	# explode visual + sfx
	var boom_scene := (landmine_explosion_scene if landmine_explosion_scene != null else tnt_explosion_scene)
	if boom_scene != null:
		var boom := boom_scene.instantiate() as Node2D
		if boom != null:
			add_child(boom)
			var pos := terrain.to_global(terrain.map_to_local(cell)) + Vector2(0, -16)
			boom.global_position = pos
			boom.z_as_relative = false
			boom.z_index = int(pos.y) + 999
			if sfx_explosion != null:
				play_sfx_poly(sfx_explosion, pos, -2.0, 0.9, 1.1)

	# ✅ damage once
	if is_instance_valid(u):
		await u.take_damage(999)

func _clear_all_mines() -> void:
	# remove instances
	for c in mines.keys():
		var m = mines[c]
		if m != null and is_instance_valid(m):
			m.queue_free()

	mines.clear()

	# exit placement + clear preview + update UI
	mine_placing = false
	_clear_mine_preview()
	_update_mine_ui()

func _refresh_ui_status() -> void:
	if ui_status_label == null:
		return

	var phase := "SETUP"
	if state == GameState.BATTLE:
		phase = "BATTLE"
	elif state == GameState.REWARD:
		phase = "REWARD"

	var lines: Array[String] = []

	# Header
	lines.append("Round %d , Phase: %s" % [round_index, phase])
	lines.append("Allies: %d   Enemies: %d" % [get_units(Unit.Team.ALLY).size(), get_units(Unit.Team.ENEMY).size()])
	lines.append("")

	# Current TNT damage
	var cur_tnt := tnt_damage
	if has_method("_get_tnt_damage"):
		cur_tnt = _get_tnt_damage()

	# ---- Humans ----
	lines.append("[b]Humans[/b]")
	lines.append("  HP:      +%d" % bonus_max_hp)
	lines.append("  Range:   +%d" % bonus_attack_range)
	lines.append("  Move:    +%d" % bonus_move_range)
	lines.append("  Repeats: +%d" % bonus_attack_repeats)
	lines.append("  TNT:     +%d" % [bonus_tnt_damage])
	lines.append("")

	# ---- Zombies (STACKED) ----
	lines.append("[b]Zombies[/b]")
	lines.append("  HP:      +%d" % zombie_bonus_hp)
	lines.append("  Repeats: +%d" % zombie_bonus_repeats)
	lines.append("")

	# ---- Phase info ----
	if state == GameState.SETUP:
		lines.append("[color=#ffd966]SETUP: REPOSITION[/color]")
		lines.append("1. Drag & drop [color=#ff9966]Allies[/color] to adjust your formation.")
		lines.append("2. Press Start Battle when ready.")
	elif state == GameState.BATTLE:
		lines.append("[color=#66ccff]BATTLE IN PROGRESS[/color]")
		lines.append("1. Units move and attack automatically.")
	elif state == GameState.REWARD:
		lines.append("[color=#66ff66]ROUND COMPLETE[/color]")
		lines.append("1. Choose an upgrade to continue.")
		lines.append("2. Zombies scale over rounds — pick wisely.")

	ui_status_label.text = "\n".join(lines)

func _enter_setup() -> void:
	_clear_all_mines()
	
	state = GameState.SETUP
	set_player_mode(false)
	assist_tnt_charges_left = 0
	ui_start_button.visible = true
	ui_reward_panel.visible = false
	select_unit(null)
	_refresh_ui_status()

	_reset_mines_for_new_battle()

	mine_placing = false
	structure_selecting = false
	_update_mine_ui()


func _on_start_pressed() -> void:
	_start_battle()


func _start_battle() -> void:
	state = GameState.BATTLE
	ui_start_button.visible = false
	ui_reward_panel.visible = false
	assist_tnt_charges_left = assist_tnt_charges_per_battle
	select_unit(null)
	set_player_mode(false) # we stay in AUTO_BATTLE, but assist mode can still allow TNT
	_refresh_ui_status()
	
	if TM != null:
		TM.start_battle()

	mine_placing = false
	_update_mine_ui()
	highlight.clear()


func _on_battle_started() -> void:
	# Reset per-battle resources
	assist_tnt_charges_left = assist_tnt_charges_per_battle
	_refresh_ui_status()


func _on_battle_ended(winner_team: int) -> void:
	state = GameState.REWARD
	ui_reward_panel.visible = true
	ui_start_button.visible = false
	select_unit(null)

	if winner_team == Unit.Team.ALLY:
		ui_reward_label.text = "Win! Choose an upgrade for next round"
		ui_reward_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3)) # green
	else:
		ui_reward_label.text = "Defeat. Choose an upgrade and try again"
		ui_reward_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3)) # red

	_refresh_ui_status()

func _pick_reward(choice: int) -> void:
	match choice:
		0:
			bonus_max_hp += 1
			for u in get_units(Unit.Team.ALLY):
				if u and is_instance_valid(u) and u.has_method("apply_run_bonuses"):
					u.apply_run_bonuses(1, 0, 0, 0)

		1:
			bonus_attack_range += 1
			for u in get_units(Unit.Team.ALLY):
				if u and is_instance_valid(u) and u.has_method("apply_run_bonuses"):
					u.apply_run_bonuses(0, 1, 0, 0)

		2:
			bonus_tnt_damage += 1

		3:
			bonus_attack_repeats += 1
			for u in get_units(Unit.Team.ALLY):
				if u and is_instance_valid(u) and u.has_method("apply_run_bonuses"):
					u.apply_run_bonuses(0, 0, 0, 1)

		4:
			bonus_mines_per_battle += 1

		5:
			structure_active_cap += 1

	ui_reward_panel.visible = false
	_begin_next_round_setup()

func _begin_next_round_setup() -> void:
	_advance_round_progression()
	
	_seed_rng()
	
	rng.randomize()

	# GridData should be 16x16 here
	grid.setup(map_width, map_height)	
	
	generate_map()
	terrain.update_internals()
	_sync_roads_transform()

	if bake_map_visuals:
		#await bake_map_to_sprite()
		await bake_roads_to_sprite()

	if turn_manager != NodePath():
		TM = get_node(turn_manager) as TurnManager
		if TM != null:
			TM.battle_started.connect(_on_battle_started)
			TM.battle_ended.connect(_on_battle_ended)

	spawn_structures()		
	spawn_units()
	
	_refresh_ui_status()
	ui_structure_button.disabled = false
	structure_selecting = false
	
	# Start in SETUP so the player can reposition allies, then press Start.
	_enter_setup()


# -----------------------
# Mouse -> map helpers
# -----------------------
func _update_hovered_cell() -> void:
	# If terrain got freed or replaced, reacquire it safely
	if terrain == null or not is_instance_valid(terrain):
		terrain = get_node_or_null("Terrain") as TileMap
		if terrain == null or not is_instance_valid(terrain):
			hovered_cell = Vector2i(-1, -1)
			return

	# ✅ offset the mouse hit point BEFORE mapping to cell
	var mouse_global := get_global_mouse_position() + Vector2(0, 8)
	var local_in_terrain := terrain.to_local(mouse_global)
	hovered_cell = terrain.local_to_map(local_in_terrain)


func _update_hovered_unit() -> void:
	var u := unit_at_cell(hovered_cell)
	set_hovered_unit(u)


# -----------------------
# Terrain placement (ID-only)
# -----------------------
func set_tile_id(cell: Vector2i, tile_id: int) -> void:
	if tile_id < 0 or tile_id > 5:
		terrain.set_cell(LAYER_TERRAIN, cell, -1, Vector2i(-1, -1), -1)
		return
	terrain.set_cell(LAYER_TERRAIN, cell, tile_id, Vector2i(0, 0), 0)


func season_main_tile() -> int:
	match season:
		Season.DIRT: return T_DIRT
		Season.SANDSTONE: return T_SANDSTONE
		Season.SNOW: return T_SNOW
		Season.GRASS: return T_GRASS
		Season.ICE: return T_ICE
	return T_GRASS


func pick_tile_for_season_no_water() -> int:
	var main := season_main_tile()
	if rng.randf() < season_strength:
		return main

	# less random: bias toward "similar" tiles instead of any tile
	match main:
		T_GRASS:
			return (T_DIRT if rng.randf() < 0.7 else T_SANDSTONE)
		T_DIRT:
			return (T_GRASS if rng.randf() < 0.6 else T_SANDSTONE)
		T_SANDSTONE:
			return (T_DIRT if rng.randf() < 0.7 else T_GRASS)
		T_SNOW:
			return (T_ICE if rng.randf() < 0.7 else T_GRASS)
		T_ICE:
			return (T_SNOW if rng.randf() < 0.7 else T_DIRT) # note: you later add water anyway
	return main


func _neighbors8(c: Vector2i) -> Array[Vector2i]:
	return [
		c + Vector2i(1, 0),  c + Vector2i(-1, 0),
		c + Vector2i(0, 1),  c + Vector2i(0, -1),
		c + Vector2i(1, 1),  c + Vector2i(1, -1),
		c + Vector2i(-1, 1), c + Vector2i(-1, -1),
	]


func generate_map() -> void:
	_seed_rng()

	# --- Pick a season before terrain generation ---
	season = Season.values()[rng.randi_range(0, Season.values().size() - 1)]
	
	for x in range(map_width):
		for y in range(map_height):
			grid.terrain[x][y] = pick_tile_for_season_no_water()

	_ensure_walkable_connected()
	_remove_dead_ends()
	_add_water_patches()

	for x in range(map_width):
		for y in range(map_height):
			set_tile_id(Vector2i(x, y), grid.terrain[x][y])
			
	# --- paint roads on separate 64x64 TileMap ---
	if roads != null:
		roads.clear()
	_add_roads()

func _add_water_patches() -> void:
	var want := clampi(water_tiles_target, 0, map_width * map_height)
	if want <= 0:
		return

	var placed := 0
	var attempts = want * max(1, water_tries_per_tile)

	for i in range(attempts):
		if placed >= want:
			break

		var c := Vector2i(
			rng.randi_range(0, map_width - 1),
			rng.randi_range(0, map_height - 1)
		)

		# don't overwrite existing water
		if grid.terrain[c.x][c.y] == T_WATER:
			continue

		# avoid spawn zones (optional)
		if avoid_spawn_zones:
			var ally_r := _rect_top_left(ally_spawn_size)
			var enemy_r := _rect_bottom_right(enemy_spawn_size)
			if ally_r.has_point(c) or enemy_r.has_point(c):
				continue

		var old = grid.terrain[c.x][c.y]
		grid.terrain[c.x][c.y] = T_GRASS

		if _is_walkable_still_connected():
			placed += 1
		else:
			grid.terrain[c.x][c.y] = old

func _is_walkable_still_connected() -> bool:
	# find any walkable start
	var start := Vector2i(-1, -1)
	for x in range(map_width):
		for y in range(map_height):
			if _is_walkable_tile_id(grid.terrain[x][y]):
				start = Vector2i(x, y)
				break
		if start.x >= 0:
			break

	if start.x < 0:
		return false # everything water, not allowed

	var visited := _flood_walkable(start)

	# count total walkable cells
	var total := 0
	for x in range(map_width):
		for y in range(map_height):
			if _is_walkable_tile_id(grid.terrain[x][y]):
				total += 1

	return visited.size() == total

func _to_road_cell(grid_cell: Vector2i) -> Vector2i:
	# 16x16 grid -> 8x8 road tiles (2x2 grid cells per road tile)
	return Vector2i(grid_cell.x / ROAD_SIZE, grid_cell.y / ROAD_SIZE)

func _snap_grid_to_road_anchor(c: Vector2i) -> Vector2i:
	# road tiles sit on even coords (0,2,4,...)
	return Vector2i((c.x / ROAD_SIZE) * ROAD_SIZE, (c.y / ROAD_SIZE) * ROAD_SIZE)

func _road_extras_from_offset(px_off: Vector2) -> Dictionary:
	var extra_left := 0
	var extra_right := 0
	var extra_top := 0
	var extra_bottom := 0

	# If you offset a TileMap RIGHT (+x), its LEFT edge looks short -> add 1 cell on LEFT.
	# If you offset a TileMap LEFT (-x), its RIGHT edge looks short -> add 1 cell on RIGHT.
	if px_off.x > 0.0:
		extra_left = 1
	elif px_off.x < 0.0:
		extra_right = 1

	# Same idea if you ever offset vertically
	if px_off.y > 0.0:
		extra_top = 1
	elif px_off.y < 0.0:
		extra_bottom = 1

	return {"l": extra_left, "r": extra_right, "t": extra_top, "b": extra_bottom}

func _add_roads() -> void:
	if roads_dl == null or roads_dr == null or roads_x == null:
		return

	roads_dl.clear()
	roads_dr.clear()
	roads_x.clear()
	_sync_roads_transform()

	# 16x16 terrain, ROAD_SIZE=2 => 8x8 road grid
	var cols := int(map_width / ROAD_SIZE) * 2 - 1
	var rows := int(map_height / ROAD_SIZE) * 2 - 1

	var margin := 0
	var road_col := rng.randi_range(margin, cols - 1 - margin)
	var road_row := rng.randi_range(margin, rows - 1 - margin)

	var conn := {}
	var min_gap := 3  # road-grid cells apart

	# ✅ Chance that we even add the extra road (0.0..1.0)
	var extra_road_chance := 0.55
	var spawn_extra := rng.randf() < extra_road_chance

	# Decide whether we add a parallel vertical or horizontal lane
	var add_vertical := rng.randi_range(0, 1) == 0

	var extra_col := -1
	var extra_row := -1

	# Only try to pick an extra lane if spawn_extra succeeds
	if spawn_extra:
		# --- pick extra parallel vertical lane ---
		if add_vertical:
			var candidates: Array[int] = []
			for i in range(margin, cols - margin):
				if abs(i - road_col) >= min_gap:
					candidates.append(i)
			if not candidates.is_empty():
				extra_col = candidates[rng.randi_range(0, candidates.size() - 1)]

		# --- pick extra parallel horizontal lane ---
		else:
			var candidates: Array[int] = []
			for i in range(margin, rows - margin):
				if abs(i - road_row) >= min_gap:
					candidates.append(i)
			if not candidates.is_empty():
				extra_row = candidates[rng.randi_range(0, candidates.size() - 1)]

	# --- main vertical lane ---
	for ry in range(rows):
		var rc := Vector2i(road_col, ry)
		conn[rc] = int(conn.get(rc, 0)) | 1

	# --- extra vertical lane ---
	if extra_col != -1:
		for ry in range(rows):
			var rc := Vector2i(extra_col, ry)
			conn[rc] = int(conn.get(rc, 0)) | 1

	# --- main horizontal lane ---
	for rx in range(cols):
		var rc := Vector2i(rx, road_row)
		conn[rc] = int(conn.get(rc, 0)) | 2

	# --- extra horizontal lane ---
	if extra_row != -1:
		for rx in range(cols):
			var rc := Vector2i(rx, extra_row)
			conn[rc] = int(conn.get(rc, 0)) | 2

	# --- force intersections ---
	conn[Vector2i(road_col, road_row)] = 3
	if extra_col != -1:
		conn[Vector2i(extra_col, road_row)] = 3
	if extra_row != -1:
		conn[Vector2i(road_col, extra_row)] = 3
	if extra_col != -1 and extra_row != -1:
		conn[Vector2i(extra_col, extra_row)] = 3

	# --- paint tiles ---
	for rc in conn.keys():
		var mask := int(conn[rc])
		if mask == 3:
			roads_x.set_cell(0, rc, ROAD_INTERSECTION, ROAD_ATLAS, 0)
		elif mask == 1:
			roads_dl.set_cell(0, rc, ROAD_DOWN_LEFT, ROAD_ATLAS, 0)
		elif mask == 2:
			roads_dr.set_cell(0, rc, ROAD_DOWN_RIGHT, ROAD_ATLAS, 0)

	_rebuild_road_blocked()

func _rebuild_road_blocked() -> void:
	road_blocked.clear()

	if terrain == null or not is_instance_valid(terrain):
		return

	var road_maps: Array[TileMap] = []
	if roads_dl != null and is_instance_valid(roads_dl): road_maps.append(roads_dl)
	if roads_dr != null and is_instance_valid(roads_dr): road_maps.append(roads_dr)
	if roads_x  != null and is_instance_valid(roads_x):  road_maps.append(roads_x)

	if road_maps.is_empty():
		return

	# For every road tile, mark the 2x2-ish terrain cells it visually covers.
	# We do this by sampling 4 points around the road tile center (±16px),
	# converting each sample to a terrain cell, and storing it.
	for rmap in road_maps:
		var used := rmap.get_used_cells(0)
		for rc in used:
			_mark_terrain_cells_covered_by_road_tile(rmap, rc)

func _mark_terrain_cells_covered_by_road_tile(rmap: TileMap, rc: Vector2i) -> void:
	# Road tile center in WORLD space
	var road_center_local := rmap.map_to_local(rc)
	var road_center_world := rmap.to_global(road_center_local)

	# 64x64 road covers about 2x2 terrain cells (32x32 each)
	# sample 4 quadrants around the center
	var samples: Array[Vector2] = [
		road_center_world + Vector2(-16, -16),
		road_center_world + Vector2( 16, -16),
		road_center_world + Vector2(-16,  16),
		road_center_world + Vector2( 16,  16),
	]

	for wp in samples:
		var local_in_terrain := terrain.to_local(wp)
		var tc := terrain.local_to_map(local_in_terrain)
		if grid.in_bounds(tc):
			road_blocked[tc] = true

func _build_road_path_2x2(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	# Like your old road path, but steps by 2 so it matches 64x64 tiles.
	if not grid.in_bounds(start) or not grid.in_bounds(goal):
		return []

	start = _snap_grid_to_road_anchor(start)
	goal = _snap_grid_to_road_anchor(goal)

	var path: Array[Vector2i] = []
	var cur := start
	path.append(cur)

	var max_steps := (map_width + map_height) + 50
	while cur != goal and max_steps > 0:
		max_steps -= 1

		var dx := goal.x - cur.x
		var dy := goal.y - cur.y

		var can_x := (dx > 0 and cur.x + ROAD_SIZE <= map_width - ROAD_SIZE)
		var can_y := (dy > 0 and cur.y + ROAD_SIZE <= map_height - ROAD_SIZE)

		if not can_x and not can_y:
			break

		var pick_x := false
		if can_x and can_y:
			var w_x := float(dx) / float(max(dx + dy, 1))
			pick_x = (rng.randf() < w_x)
		elif can_x:
			pick_x = true
		else:
			pick_x = false

		if pick_x:
			cur = Vector2i(cur.x + ROAD_SIZE, cur.y)
		else:
			cur = Vector2i(cur.x, cur.y + ROAD_SIZE)

		path.append(cur)

	return path

func _register_lane_connections(path: Array[Vector2i], conn: Dictionary) -> void:
	if path.is_empty():
		return

	for i in range(path.size() - 1):
		var a := _snap_grid_to_road_anchor(path[i])
		var b := _snap_grid_to_road_anchor(path[i + 1])

		if not conn.has(a):
			conn[a] = {"dl": false, "dr": false}
		if not conn.has(b):
			conn[b] = {"dl": false, "dr": false}

		# a -> b determines lane direction
		if b.x == a.x + ROAD_SIZE and b.y == a.y:
			conn[a]["dr"] = true
			conn[b]["dr"] = true # also mark b so intersections happen naturally
		elif b.y == a.y + ROAD_SIZE and b.x == a.x:
			conn[a]["dl"] = true
			conn[b]["dl"] = true

func _build_road_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	# Creates an "iso-feeling" path by only stepping:
	#  - +x (down-right visually) or
	#  - +y (down-left visually)
	# This matches your two road piece directions (7/8).
	#
	# It also avoids going out of bounds. If we hit water, we still allow it
	# (we'll convert water to land under the road in _add_roads).

	if not grid.in_bounds(start) or not grid.in_bounds(goal):
		return []

	var path: Array[Vector2i] = []
	var cur := start
	path.append(cur)

	# Safety cap so we never infinite loop
	var max_steps := map_width + map_height + 50
	while cur != goal and max_steps > 0:
		max_steps -= 1

		var dx := goal.x - cur.x
		var dy := goal.y - cur.y

		# If one axis is already matched, we must move on the other
		var can_x := (dx > 0 and cur.x + 1 < map_width)
		var can_y := (dy > 0 and cur.y + 1 < map_height)

		if not can_x and not can_y:
			break

		# Bias step choice toward whichever axis is "more behind"
		var pick_x := false
		if can_x and can_y:
			var w_x := float(dx) / float(max(dx + dy, 1))
			pick_x = (rng.randf() < w_x)
		elif can_x:
			pick_x = true
		else:
			pick_x = false

		if pick_x:
			cur = Vector2i(cur.x + 1, cur.y)
		else:
			cur = Vector2i(cur.x, cur.y + 1)

		path.append(cur)

	return path

func _register_road_exits_from_path(path: Array[Vector2i], exits: Dictionary) -> void:
	if path.is_empty():
		return

	# For each cell, look at the NEXT step to decide if this cell "exits" down-left or down-right.
	# Down-right = +x, Down-left = +y
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]

		if not exits.has(a):
			exits[a] = {"dl": false, "dr": false}

		if b.x == a.x + 1 and b.y == a.y:
			exits[a]["dr"] = true
		elif b.y == a.y + 1 and b.x == a.x:
			exits[a]["dl"] = true

	# Also mark the last cell so it gets a tile too (use incoming direction)
	var last := path[path.size() - 1]
	if not exits.has(last):
		exits[last] = {"dl": false, "dr": false}

	if path.size() >= 2:
		var prev := path[path.size() - 2]
		# If we arrived from left, the last piece can be down-right-ish, etc.
		if last.x == prev.x + 1 and last.y == prev.y:
			exits[last]["dr"] = true
		elif last.y == prev.y + 1 and last.x == prev.x:
			exits[last]["dl"] = true

# -----------------------
# Connectivity + dead-end fixer (non-water walkable)
# -----------------------
func _in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < map_width and c.y < map_height


func _neighbors4(c: Vector2i) -> Array[Vector2i]:
	return [
		c + Vector2i(1, 0),
		c + Vector2i(-1, 0),
		c + Vector2i(0, 1),
		c + Vector2i(0, -1),
	]


func _is_walkable_tile_id(tid: int) -> bool:
	return tid != T_WATER


func _count_walkable_neighbors(c: Vector2i) -> int:
	var n := 0
	for nb in _neighbors4(c):
		if _in_bounds(nb) and _is_walkable_tile_id(grid.terrain[nb.x][nb.y]):
			n += 1
	return n


func _flood_walkable(start: Vector2i) -> Dictionary:
	var visited := {}
	if start.x < 0:
		return visited
	if not _is_walkable_tile_id(grid.terrain[start.x][start.y]):
		return visited

	var q: Array[Vector2i] = [start]
	visited[start] = true

	while not q.is_empty():
		var c = q.pop_front()
		for nb in _neighbors4(c):
			if not _in_bounds(nb):
				continue
			if visited.has(nb):
				continue
			if not _is_walkable_tile_id(grid.terrain[nb.x][nb.y]):
				continue
			visited[nb] = true
			q.append(nb)

	return visited


func _walkable_components() -> Array[Dictionary]:
	var seen := {}
	var comps: Array[Dictionary] = []

	for x in range(map_width):
		for y in range(map_height):
			var c := Vector2i(x, y)
			if seen.has(c):
				continue
			if not _is_walkable_tile_id(grid.terrain[x][y]):
				continue

			var comp := _flood_walkable(c)
			for k in comp.keys():
				seen[k] = true
			comps.append(comp)

	return comps


func _ensure_walkable_connected() -> void:
	var iter := 0
	while iter < max_fix_iterations:
		iter += 1
		var comps := _walkable_components()
		if comps.size() <= 1:
			return

		var best_a = comps[0].keys()[0]
		var best_b = comps[1].keys()[0]
		var best_d := 999999

		for i in range(comps.size()):
			for j in range(i + 1, comps.size()):
				for ca in comps[i].keys():
					for cb in comps[j].keys():
						var d = abs(ca.x - cb.x) + abs(ca.y - cb.y)
						if d < best_d:
							best_d = d
							best_a = ca
							best_b = cb

		_carve_bridge(best_a, best_b)


func _carve_bridge(from: Vector2i, to: Vector2i) -> void:
	var main := season_main_tile()
	var c := from

	while c.x != to.x:
		c.x += (1 if to.x > c.x else -1)
		if _in_bounds(c) and grid.terrain[c.x][c.y] == T_WATER:
			grid.terrain[c.x][c.y] = main

	while c.y != to.y:
		c.y += (1 if to.y > c.y else -1)
		if _in_bounds(c) and grid.terrain[c.x][c.y] == T_WATER:
			grid.terrain[c.x][c.y] = main

func _remove_dead_ends() -> void:
	var iter := 0
	var main := season_main_tile()

	while iter < max_fix_iterations:
		iter += 1

		var dead_ends: Array[Vector2i] = []
		for x in range(map_width):
			for y in range(map_height):
				var c := Vector2i(x, y)
				if not _is_walkable_tile_id(grid.terrain[x][y]):
					continue
				if _count_walkable_neighbors(c) <= 1:
					dead_ends.append(c)

		if dead_ends.is_empty():
			return

		for c in dead_ends:
			var candidates: Array[Vector2i] = []
			for nb in _neighbors4(c):
				if _in_bounds(nb) and grid.terrain[nb.x][nb.y] == T_WATER:
					candidates.append(nb)

			if candidates.is_empty():
				continue

			var pick := candidates[rng.randi_range(0, candidates.size() - 1)]
			grid.terrain[pick.x][pick.y] = main

	_ensure_walkable_connected()


# -----------------------
# Unit lookup / origins
# -----------------------
func unit_at_cell(cell: Vector2i) -> Unit:
	if grid.is_occupied(cell):
		return grid.occupied[cell] as Unit
	return null


func get_unit_origin(u: Unit) -> Vector2i:
	if u == null:
		return Vector2i(-1, -1)
	if unit_origin.has(u):
		return unit_origin[u]
	return u.grid_pos


func _is_big_unit(u: Unit) -> bool:
	if u == null:
		return false
	return u.footprint_size.x > 1 or u.footprint_size.y > 1

# -----------------------
# “8x8 feel” snapping for big units
# - map is still 16x16 cells
# - big unit ORIGINS snap to even coords (0,2,4,...)
# -----------------------
func snap_origin_for_unit(cell: Vector2i, u: Unit) -> Vector2i:
	if u == null:
		return cell

	if _is_big_unit(u):
		cell.x = (cell.x / 2) * 2
		cell.y = (cell.y / 2) * 2
		cell.x = clampi(cell.x, 0, map_width - 2)
		cell.y = clampi(cell.y, 0, map_height - 2)
	else:
		cell.x = clampi(cell.x, 0, map_width - 1)
		cell.y = clampi(cell.y, 0, map_height - 1)

	return cell


func _neighbors4_for_unit(c: Vector2i, u: Unit) -> Array[Vector2i]:
	var step := 2 if _is_big_unit(u) else 1
	return [
		c + Vector2i(step, 0),
		c + Vector2i(-step, 0),
		c + Vector2i(0, step),
		c + Vector2i(0, -step),
	]


# -----------------------
# Hover / Selection overlays (small vs big tile switching)
# -----------------------
func clear_selection_highlight() -> void:
	highlight.clear()
	highlight.position = hover_offset_1x1

func clear_move_range() -> void:
	move_range.clear()
	reachable_set.clear()
	move_range.position = move_offset_1x1

func draw_unit_hover(u: Unit) -> void:
	highlight.clear()

	if u == null:
		highlight.position = hover_offset_1x1
		return

	var origin := get_unit_origin(u)
	var big := _is_big_unit(u)

	# ✅ offset the hover overlay TileMap itself
	highlight.position = (hover_offset_2x2 if big else hover_offset_1x1)

	if big:
		# big hover tile is a single 2x2 tile placed at the origin cell
		highlight.set_cell(LAYER_HIGHLIGHT, origin, HOVER_TILE_BIG_SOURCE_ID, HOVER_ATLAS, 0)
	else:
		for c in u.footprint_cells(origin):
			highlight.set_cell(LAYER_HIGHLIGHT, c, HOVER_TILE_SMALL_SOURCE_ID, HOVER_ATLAS, 0)

func set_hovered_unit(u: Unit) -> void:
	if hovered_unit == u:
		return

	hovered_unit = u

	# keep your existing hover tile overlay behavior
	if selected_unit == null:
		draw_unit_hover(hovered_unit)

	# NEW: shader outline hover
	_update_hover_outline()
	
	_hud_bind(u)


func select_unit(u: Unit) -> void:
	selected_unit = u

	if selected_unit != null:
		draw_unit_hover(selected_unit)
		# In assist mode we only need selection for TNT aiming; keep overlays clean.
		if not _is_assist_mode():
			draw_move_range_for_unit(selected_unit)
			draw_attack_range_for_unit(selected_unit)
		else:
			clear_move_range()
			clear_attack_range()
	else:
		clear_selection_highlight()
		clear_move_range()
		clear_attack_range()
		
	_update_hover_outline()

func clear_attack_range() -> void:
	attack_range_small.clear()
	if attack_range_big != null:
		attack_range_big.clear()

	attackable_units.clear()

	# ✅ always keep the small overlay aligned normally
	attack_range_small.position = attack_offset_small

	# ✅ big overlay not used anymore (but keep it parked)
	if attack_range_big != null:
		attack_range_big.position = attack_offset_big


func draw_attack_range_for_unit(attacker: Unit) -> void:
	clear_attack_range()
	if attacker == null:
		return

	for child in units_root.get_children():
		var target := child as Unit
		if target == null:
			continue
		if target == attacker:
			continue

		if _attack_distance(attacker, target) > attacker.attack_range:
			continue

		attackable_units[target] = true

		var target_origin := get_unit_origin(target)

		if _is_big_unit(target):
			target_origin = snap_origin_for_unit(target_origin, target)
			attack_range_big.set_cell(LAYER_ATTACK, target_origin, ATTACK_TILE_BIG_SOURCE_ID, ATTACK_ATLAS, 0)
		else:
			attack_range_small.set_cell(LAYER_ATTACK, target_origin, ATTACK_TILE_SMALL_SOURCE_ID, ATTACK_ATLAS, 0)

func draw_attack_range_for_structure(b: Node2D) -> void:
	clear_attack_range()
	if b == null or not is_instance_valid(b):
		return

	# Building cell (same logic you use in pick_best_structure_target_cell)
	var b_local := terrain.to_local(b.global_position)
	var bcell := terrain.local_to_map(b_local)

	var r := int(structure_attack_range)
	var min_d := 4 # matches your "never closer than 3" rule (d < 4 rejected)

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var d = abs(dx) + abs(dy)
			if d < min_d or d > r:
				continue

			var c := bcell + Vector2i(dx, dy)
			if not grid.in_bounds(c):
				continue

			# Use the same attack overlay tile your unit range uses
			attack_range_small.set_cell(LAYER_ATTACK, c, ATTACK_TILE_SMALL_SOURCE_ID, ATTACK_ATLAS, 0)

func _input(event: InputEvent) -> void:
	# R = reload
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_R:
			get_tree().reload_current_scene()
			return

	if not _can_handle_player_input():
		return
	if is_moving_unit or is_attacking_unit:
		return

	# ✅ SETUP DRAG
	if state != GameState.SETUP:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		# --- Mine placement click (SETUP only) ---
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mine_placing:
			var placed := _place_mine_at(hovered_cell) # make this return true/false if possible
			_update_mine_ui()

			# If we placed and we’re now out of mines (or at max), exit + unpress
			if placed and mines_left <= 0:  # rename to your real vars
				_exit_mine_placing()
			return
			
		# --- Structure selection click (SETUP only) ---
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and structure_selecting:
			var b := structure_at_cell(hovered_cell)
			if b != null:
				_toggle_structure_active(b)
			return

		# --- Deselect on empty cell (SETUP only) ---
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var b := structure_at_cell(hovered_cell)
			var u := unit_at_cell(hovered_cell)

			# If there is nothing under the cursor, clear selection
			if b == null and u == null:
				select_unit(null)
				return

		# Left press = inspect enemy (zombie): show move range, but DO NOT drag
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var u := unit_at_cell(hovered_cell)
			if u != null and is_instance_valid(u) and u.team == Unit.Team.ENEMY:
				# Make sure we are not dragging anything
				setup_dragging = false
				setup_drag_unit = null

				# Select so the hover/selection outline behaves consistently
				selected_unit = u
				draw_unit_hover(u)

				# Show movement range only (as requested)
				draw_move_range_for_unit(u)

				# Optional: keep attack overlay clean during setup inspection
				clear_attack_range()

				return
				
		# Left press = pick up ally unit
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			var u := unit_at_cell(hovered_cell)
			if u != null and is_instance_valid(u) and u.team == Unit.Team.ALLY:
				select_unit(u)
				setup_dragging = true
				setup_drag_unit = u
				setup_drag_start_origin = get_unit_origin(u)
				draw_move_range_for_unit(u)
			return

		# Left release = place
		if mb.button_index == MOUSE_BUTTON_LEFT and (not mb.pressed):
			if setup_dragging and setup_drag_unit != null and is_instance_valid(setup_drag_unit):
				select_unit(setup_drag_unit)

				var placed := _setup_place_selected(hovered_cell)
				if not placed:
					# snap back (your _setup_place_selected already restored occupancy)
					setup_drag_unit.global_position = cell_to_world_for_unit(setup_drag_start_origin, setup_drag_unit)
					setup_drag_unit.grid_pos = setup_drag_start_origin
					unit_origin[setup_drag_unit] = setup_drag_start_origin

				setup_dragging = false
				setup_drag_unit = null
			return

		# Right click = cancel drag
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if setup_dragging and setup_drag_unit != null and is_instance_valid(setup_drag_unit):
				select_unit(setup_drag_unit)
				_setup_place_selected(setup_drag_start_origin)

				setup_dragging = false
				setup_drag_unit = null
			return

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and mine_placing:
			mine_placing = false
			_update_mine_ui()
			return
			
func _exit_mine_placing() -> void:
	mine_placing = false

	if ui_mine_button != null and is_instance_valid(ui_mine_button):
		# force the toggle button to unpress
		ui_mine_button.set_pressed_no_signal(false)
		# optional: prevent re-entering if no mines left
		ui_mine_button.disabled = true

	_update_mine_ui()
	
func try_attack_selected(target: Unit) -> bool:
	if selected_unit == null or target == null:
		return false
	if is_moving_unit or is_attacking_unit:
		return false
	if target == selected_unit:
		return false
	if not is_instance_valid(target):
		return false

	# must be highlighted as attackable this frame
	if not attackable_units.has(target):
		return false

	var attacker := selected_unit

	# safety: also confirm range using footprint-vs-footprint distance
	var dist := _attack_distance(attacker, target)
	if dist > attacker.attack_range:
		return false

	is_attacking_unit = true

	# face target
	_set_facing_from_world_delta(attacker, attacker.global_position, target.global_position)

	# play attack anim repeats + apply damage safely
	var anim_name := _get_attack_anim_name(attacker)
	var repeats = max(attacker.attack_repeats, 1)

	for i in range(repeats):
		if not is_instance_valid(target):
			break

		# play the attacker sound BEFORE anything can free the target
		play_sfx_poly(_sfx_attack_for(attacker), attacker.global_position, -6.0)

		await _play_anim_and_wait(attacker, anim_name)

		if not is_instance_valid(target):
			break

		await target.take_damage(1)

		# hurt sound only if target still exists + is still alive
		if is_instance_valid(target) and target.hp > 0:
			play_sfx_poly(_sfx_hurt_for(target), target.global_position, -5.0)
			await _flash_unit(target)

	_play_idle(attacker)
	is_attacking_unit = false

	# redraw overlays so the highlighted attack tiles stay correct
	# (target may be gone now, but attacker still exists)
	if is_instance_valid(attacker):
		draw_unit_hover(attacker)
		draw_move_range_for_unit(attacker)
		draw_attack_range_for_unit(attacker)

	if is_player_mode and TM != null:
		TM.notify_player_action_complete()

	return true

func _attack_distance(a: Unit, b: Unit) -> int:
	var ao := get_unit_origin(a)
	var bo := get_unit_origin(b)

	var a_cells := a.footprint_cells(ao)
	var b_cells := b.footprint_cells(bo)

	var best := 999999
	for ca in a_cells:
		for cb in b_cells:
			var d = abs(ca.x - cb.x) + abs(ca.y - cb.y)
			if d < best:
				best = d
	return best


func _play_anim_and_wait(u: Unit, anim_name: StringName) -> void:
	if u == null or not is_instance_valid(u):
		await get_tree().create_timer(0.05).timeout
		return

	var spr := _unit_sprite(u)
	if spr == null or not is_instance_valid(spr):
		await get_tree().create_timer(0.05).timeout
		return

	if spr.sprite_frames == null or not spr.sprite_frames.has_animation(anim_name):
		await get_tree().create_timer(0.15).timeout
		return

	spr.play(anim_name)
	await spr.animation_finished


func _flash_unit(u: Unit) -> void:
	var spr := _unit_sprite(u)
	if spr == null:
		return

	# Quick bright flash, then back
	var base := spr.modulate

	var t := create_tween()
	t.tween_property(spr, "modulate", Color(2, 2, 2, base.a), 0.05)
	t.tween_property(spr, "modulate", base, 0.10)
	await t.finished

# -----------------------
# Movement range drawing (small vs big tile switching)
# -----------------------
func draw_move_range_for_unit(u: Unit) -> void:
	clear_move_range()
	if u == null:
		return

	var origin := get_unit_origin(u)
	var big := _is_big_unit(u)

	# ✅ offset the move overlay TileMap itself
	move_range.position = (move_offset_2x2 if big else move_offset_1x1)

	if big:
		origin = snap_origin_for_unit(origin, u)

	var reachable := compute_reachable_origins(u, origin, u.move_range)
	var source_id := (MOVE_TILE_BIG_SOURCE_ID if big else MOVE_TILE_SMALL_SOURCE_ID)

	for cell in reachable:
		reachable_set[cell] = true
		move_range.set_cell(LAYER_MOVE, cell, source_id, MOVE_ATLAS, 0)

# -----------------------
# Moving selected unit on click
# -----------------------
func try_move_selected_to(dest: Vector2i) -> bool:
	if selected_unit == null:
		return false
	if is_moving_unit:
		return false

	var u := selected_unit
	var from_origin := get_unit_origin(u)

	# big units must align to even coords (LOGIC)
	if _is_big_unit(u):
		dest = snap_origin_for_unit(dest, u)

	if not reachable_set.has(dest):
		return false
	if not _can_stand(u, dest):
		return false

	# ✅ Find a path (this is what gives you L-shape turns)
	var path := find_path_origins(u, from_origin, dest, u.move_range)
	if path.is_empty():
		return false

	# --- update grid occupancy immediately (LOGIC commits now) ---
	for c in u.footprint_cells(from_origin):
		if grid.is_occupied(c) and grid.occupied[c] == u:
			grid.occupied.erase(c)

	for c in u.footprint_cells(dest):
		grid.set_occupied(c, u)

	u.grid_pos = dest
	unit_origin[u] = dest

	is_moving_unit = true
	_play_anim(u, "move")

	# If a previous tween exists, kill it
	if move_tween != null and move_tween.is_valid():
		move_tween.kill()

	# Move step-by-step so you can see turns
	# path includes start, so skip index 0
	for i in range(1, path.size()):
		var step_origin := path[i]
		var step_pos := cell_to_world_for_unit(step_origin, u)

		var from_pos := u.global_position
		_set_facing_from_world_delta(u, from_pos, step_pos)

		move_tween = create_tween()
		move_tween.set_trans(Tween.TRANS_SINE)
		move_tween.set_ease(Tween.EASE_IN_OUT)

		# Per-step duration (tweak this)
		var step_duration := 0.18
		move_tween.tween_property(u, "global_position", step_pos, step_duration)

		await move_tween.finished
		_update_all_unit_layering()

		# keep layering correct mid-walk (optional but helps in iso)
		u.update_layering()

	# Ensure final is exact
	u.global_position = cell_to_world_for_unit(dest, u)
	u.update_layering()

	_play_idle(u)
	is_moving_unit = false

	# refresh overlays AFTER arrival
	draw_unit_hover(u)
	draw_move_range_for_unit(u)
	draw_attack_range_for_unit(u)

	if is_player_mode and TM != null:
		TM.notify_player_action_complete()

	return true

# -----------------------
# Pathing helpers
# -----------------------
func _is_cell_walkable(c: Vector2i) -> bool:
	return grid.in_bounds(c) and grid.terrain[c.x][c.y] != T_WATER

func _can_stand(u: Unit, origin: Vector2i) -> bool:
	for c in u.footprint_cells(origin):
		if not _is_cell_walkable(c):
			return false

		# ✅ block buildings
		if structure_blocked.has(c):
			return false

		# unit occupancy (existing)
		if grid.is_occupied(c) and grid.occupied[c] != u:
			return false

	return true

func compute_reachable_origins(u: Unit, start: Vector2i, max_cost: int) -> Array[Vector2i]:
	var dist := {}
	var q: Array[Vector2i] = []

	# big units: ensure start is aligned
	if _is_big_unit(u):
		start = snap_origin_for_unit(start, u)

	if not _can_stand(u, start):
		return []

	dist[start] = 0
	q.append(start)

	while not q.is_empty():
		var cur = q.pop_front()
		var cur_d: int = dist[cur]

		if cur_d >= max_cost:
			continue

		for nb in _neighbors4_for_unit(cur, u):
			var nd := cur_d + 1
			if nd > max_cost:
				continue

			if _is_big_unit(u):
				nb = snap_origin_for_unit(nb, u)

			if dist.has(nb) and dist[nb] <= nd:
				continue
			if not _can_stand(u, nb):
				continue

			dist[nb] = nd
			q.append(nb)

	var out: Array[Vector2i] = []
	for k in dist.keys():
		out.append(k)
	return out

func cell_to_world_for_unit(origin: Vector2i, u: Unit) -> Vector2:
	var p00 := terrain.map_to_local(origin) # center of origin cell (in terrain local space)

	if _is_big_unit(u):
		# center of 2x2 footprint = midpoint between origin cell and (origin+1, origin+1)
		var p11 := terrain.map_to_local(origin + Vector2i(1, 1))
		var mid := (p00 + p11) * 0.5
		return terrain.to_global(mid)

	return terrain.to_global(p00)

func _set_facing_from_world_delta(u: Unit, from_pos: Vector2, to_pos: Vector2) -> void:
	var spr := _unit_sprite(u)
	if spr == null:
		return

	var dx := to_pos.x - from_pos.x
	if abs(dx) < 0.01:
		return # don't change facing if basically no horizontal movement

	# default facing LEFT => flip_h=false
	# moving RIGHT => flip_h=true
	spr.flip_h = (dx > 0.0)

func _get_attack_anim_name(attacker: Unit) -> StringName:
	# Default for all Units
	var anim: StringName = attacker.attack_anim

	# ✅ If this unit is a Zombie, use its zombie-specific anim if it exists
	# (You can name it whatever you want in Zombie.gd — this handles both common options)
	if attacker is Zombie:
		if attacker.has_meta("zombie_attack_anim"):
			anim = attacker.zombie_attack_anim
		elif attacker.has_meta("bite_anim"):
			anim = attacker.bite_anim
		elif attacker.has_meta("attack"):
			# fallback: if Zombie just uses the same attack_anim, keep it
			anim = attacker.attack_anim

	return anim

func _on_unit_died(u: Unit) -> void:
	if u == null:
		return

	# play death sfx at the unit position (before it disappears)
	if is_instance_valid(u):
		play_sfx_poly(_sfx_die_for(u), u.global_position, -4.0)

	# cache origin BEFORE we erase tracking
	var origin := get_unit_origin(u)

	# Remove from grid occupancy
	for c in u.footprint_cells(origin):
		if grid.is_occupied(c) and grid.occupied[c] == u:
			grid.occupied.erase(c)

	# Remove from tracking
	unit_origin.erase(u)

	# If selected / hovered
	if selected_unit == u:
		select_unit(null)
	if hovered_unit == u:
		set_hovered_unit(null)

	# ✅ Zombie drops (choose one)
	if u is Zombie:
		_try_spawn_medkit_drop(origin) # try medkit first
		_try_spawn_laser_drop(origin)  # then laser

func _try_spawn_medkit_drop(zombie_cell: Vector2i) -> void:
	if medkit_drop_scene == null:
		return
	if rng.randf() > medkit_drop_chance:
		return

	var spawn_cell := Vector2i(-1, -1)

	if _is_pickup_cell_ok(zombie_cell) and not pickups.has(zombie_cell):
		spawn_cell = zombie_cell
	else:
		spawn_cell = _find_free_adjacent_cell(zombie_cell)

	if spawn_cell.x < 0:
		return
	if pickups.has(spawn_cell):
		return

	var drop := medkit_drop_scene.instantiate()
	var d2 := drop as Node2D
	if d2 == null:
		push_warning("medkit_drop_scene root is not Node2D/Area2D; can't render.")
		return

	# tag it so _collect_pickup_at knows what it is
	d2.set_meta("pickup_kind", "medkit")

	# --- Robust: lock the intended grid cell + z now (don't derive from world pos later) ---
	d2.set_meta("pickup_cell", spawn_cell)

	# Your usual layering practice: x+y sum
	var z_base := 2
	d2.z_as_relative = false
	d2.z_index = int(z_base + spawn_cell.x + spawn_cell.y)

	pickups_root.add_child(d2)

	# Place in world (visual offset is fine now; z is already correct)
	var world_pos := terrain.to_global(terrain.map_to_local(spawn_cell))
	world_pos += Vector2(0, -16)
	d2.global_position = world_pos

	d2.visible = true
	d2.modulate = Color(1, 1, 1, 1)

	pickups[spawn_cell] = d2

	# quick pop-in
	d2.scale = Vector2.ONE * 0.85
	var t := create_tween()
	t.tween_property(d2, "scale", Vector2.ONE, 0.12)


func _try_spawn_laser_drop(zombie_cell: Vector2i) -> void:
	if laser_drop_scene == null:
		return
	if rng.randf() > laser_drop_chance:
		return

	var spawn_cell := Vector2i(-1, -1)

	if _is_pickup_cell_ok(zombie_cell) and not pickups.has(zombie_cell):
		spawn_cell = zombie_cell
	else:
		spawn_cell = _find_free_adjacent_cell(zombie_cell)

	if spawn_cell.x < 0:
		return
	if pickups.has(spawn_cell):
		return

	var drop := laser_drop_scene.instantiate()
	var d2 := drop as Node2D
	if d2 == null:
		push_warning("laser_drop_scene root is not Node2D/Area2D; can't render.")
		return

	# --- Robust: lock the intended grid cell + z now (don't derive from world pos later) ---
	d2.set_meta("pickup_cell", spawn_cell)

	# Your usual layering practice: x+y sum
	var z_base := 2
	d2.z_as_relative = false
	d2.z_index = int(z_base + spawn_cell.x + spawn_cell.y)

	pickups_root.add_child(d2)

	# Place in world (visual offset is fine now; z is already correct)
	var world_pos := terrain.to_global(terrain.map_to_local(spawn_cell))
	world_pos += Vector2(0, -16)
	d2.global_position = world_pos

	d2.visible = true
	d2.modulate = Color(1, 1, 1, 1)

	pickups[spawn_cell] = d2

	# quick pop-in
	d2.scale = Vector2.ONE * 0.85
	var t := create_tween()
	t.tween_property(d2, "scale", Vector2.ONE, 0.12)

func _is_pickup_cell_ok(c: Vector2i) -> bool:
	if not grid.in_bounds(c):
		return false
	if grid.terrain[c.x][c.y] == T_WATER:
		return false
	# don't spawn on an occupied tile (unit standing there)
	if grid.is_occupied(c):
		return false
	return true

func _find_free_adjacent_cell(center: Vector2i) -> Vector2i:
	# 4-neighbors first, then diagonals (so it feels "adjacent")
	var candidates := [
		center + Vector2i(1, 0),
		center + Vector2i(-1, 0),
		center + Vector2i(0, 1),
		center + Vector2i(0, -1),

		center + Vector2i(1, 1),
		center + Vector2i(1, -1),
		center + Vector2i(-1, 1),
		center + Vector2i(-1, -1),
	]

	# randomize so it doesn’t always go to the same side
	candidates.shuffle()

	for c in candidates:
		if _is_pickup_cell_ok(c) and not pickups.has(c):
			return c

	return Vector2i(-1, -1)

func get_units(team_id: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for child in units_root.get_children():
		var u := child as Unit
		if u == null:
			continue
		if u.is_queued_for_deletion():
			continue
		if u.team == team_id:
			out.append(u)
	return out

func get_enemies_of(u: Unit) -> Array[Unit]:
	return get_units(Unit.Team.ENEMY if u.team == Unit.Team.ALLY else Unit.Team.ALLY)

func nearest_enemy(u: Unit) -> Unit:
	var enemies := get_enemies_of(u)
	if enemies.is_empty():
		return null

	var best: Unit = null
	var best_d := 999999
	for e in enemies:
		var d := _attack_distance(u, e)
		if d < best_d:
			best_d = d
			best = e
	return best

func ai_take_turn(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return
	if is_moving_unit or is_attacking_unit:
		return

	# -----------------------
	# ✅ Humans: prioritize pickups
	# -----------------------
	if (u is Human) or (u is HumanTwo):
		var pc := _nearest_pickup_cell(u)
		if pc.x >= 0:
			if get_unit_origin(u) == pc:
				await _collect_pickup_at(pc, u)
				return

			var goal := best_reachable_toward_cell(u, pc)
			if goal != get_unit_origin(u):
				await perform_move(u, goal)

			if is_instance_valid(u) and get_unit_origin(u) == pc:
				await _collect_pickup_at(pc, u)
			return


	# -----------------------
	# Normal enemy targeting
	# -----------------------
	var enemy := nearest_enemy(u)
	if enemy == null:
		return

	# 1) Attack if already in range
	if _attack_distance(u, enemy) <= u.attack_range:
		await perform_attack(u, enemy)
		return

	# 2) Otherwise move toward the enemy
	var goal2 := best_reachable_toward_enemy(u, enemy)
	if goal2 == get_unit_origin(u):
		return

	await perform_move(u, goal2)

	# 3) After moving, try attack again
	if enemy != null and is_instance_valid(enemy):
		if _attack_distance(u, enemy) <= u.attack_range:
			await perform_attack(u, enemy)

func _nearest_pickup_cell(u: Unit) -> Vector2i:
	if pickups.is_empty():
		return Vector2i(-1, -1)

	var from := get_unit_origin(u)
	var best := Vector2i(-1, -1)
	var best_d := 999999

	for cell in pickups.keys():
		var d = abs(cell.x - from.x) + abs(cell.y - from.y)
		if d < best_d:
			best_d = d
			best = cell

	return best

func best_reachable_toward_cell(u: Unit, target_cell: Vector2i) -> Vector2i:
	var start := get_unit_origin(u)
	if _is_big_unit(u):
		start = snap_origin_for_unit(start, u)

	var reachable := compute_reachable_origins(u, start, u.move_range)
	if reachable.is_empty():
		return start

	var best := start
	var best_d := 999999
	for r in reachable:
		if not _can_stand(u, r):
			continue
		var d = abs(r.x - target_cell.x) + abs(r.y - target_cell.y)
		if d < best_d:
			best_d = d
			best = r
	return best

func _collect_pickup_at(cell: Vector2i, collector: Unit) -> void:
	if not pickups.has(cell):
		return

	var drop = pickups[cell]
	pickups.erase(cell)

	# figure out what it is BEFORE we free it
	var kind := ""
	if drop != null and is_instance_valid(drop) and drop.has_meta("pickup_kind"):
		kind = str(drop.get_meta("pickup_kind"))

	# fade out and remove
	if drop != null and is_instance_valid(drop):
		var t := create_tween()
		t.tween_property(drop, "modulate:a", 0.0, 0.18)
		await t.finished
		if is_instance_valid(drop):
			drop.queue_free()

	# ✅ apply effect
	if kind == "medkit":
		if collector != null and is_instance_valid(collector):
			var before := int(collector.hp)
			collector.hp = min(int(collector.max_hp), int(collector.hp) + int(medkit_heal_amount))

			# ✅ only play if it actually healed (prevents pickup spam at full HP)
			if int(collector.hp) > before:
				if sfx_medkit_pickup != null:
					play_sfx_poly(sfx_medkit_pickup, collector.global_position, -6.0, 0.95, 1.05)
				await _flash_unit(collector)
		return

	# default = laser (your existing behavior)
	await _orbital_laser_strike()

func _orbital_laser_strike() -> void:
	var zombies := get_units(Unit.Team.ENEMY)
	if zombies.is_empty():
		return

	zombies.shuffle()
	var count = min(orbital_hits, zombies.size())

	for i in range(count):
		var z := zombies[i]
		if z == null or not is_instance_valid(z) or z.is_queued_for_deletion():
			continue

		# ✅ stop any in-progress movement so it can’t “finish its tween” after death
		_interrupt_unit_motion(z)

		var hit_pos := z.global_position

		_spawn_orbital_beam(hit_pos)

		if sfx_orbital_zap != null:
			play_sfx_poly(sfx_orbital_zap, hit_pos, -4.0, 0.95, 1.05)

		if tnt_explosion_scene != null:
			var boom := tnt_explosion_scene.instantiate() as Node2D
			if boom != null:
				add_child(boom)
				boom.global_position = hit_pos
				boom.z_as_relative = false
				boom.z_index = int(hit_pos.y) + 999
				if sfx_explosion != null:
					play_sfx_poly(sfx_explosion, hit_pos, -2.0, 0.9, 1.1)

		# ✅ kill safely
		if is_instance_valid(z) and not z.is_queued_for_deletion():
			await z.take_damage(orbital_damage)

		await get_tree().create_timer(orbital_delay).timeout

func _spawn_orbital_beam(hit_pos: Vector2) -> void:
	var line := Line2D.new()
	line.top_level = true
	line.z_as_relative = false
	line.width = orbital_beam_width
	line.z_index = int(hit_pos.y) + 1000
	line.default_color = Color(1, 0, 0, 1) # red

	# tall vertical line centered on hit_pos
	line.add_point(Vector2(hit_pos.x, hit_pos.y - orbital_beam_height_px))
	line.add_point(Vector2(hit_pos.x, hit_pos.y - 16))

	add_child(line)

	# flash super quick then remove
	var t := create_tween()
	t.tween_property(line, "modulate:a", 0.0, 0.08)
	t.finished.connect(func():
		if is_instance_valid(line):
			line.queue_free()
	)

func perform_attack(attacker: Unit, target: Unit) -> void:
	if attacker == null or target == null:
		return
	if is_moving_unit or is_attacking_unit:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return

	# range check (footprint vs footprint)
	if _attack_distance(attacker, target) > attacker.attack_range:
		return

	is_attacking_unit = true
	_set_facing_from_world_delta(attacker, attacker.global_position, target.global_position)

	_hud_bind(attacker)
	_hud_refresh()

	var anim_name := _get_attack_anim_name(attacker)
	var repeats = max(attacker.attack_repeats, 1)

	# Use a weakref so we can safely re-fetch the object after awaits
	var target_ref = weakref(target)

	for i in range(repeats):
		# attacker could also die mid-chain
		if not is_instance_valid(attacker):
			break

		var t := target_ref.get_ref() as Unit
		if t == null or not is_instance_valid(t):
			break

		# Attack SFX before anything can free the target
		play_sfx_poly(_sfx_attack_for(attacker), attacker.global_position, -6.0)

		await _play_anim_and_wait(attacker, anim_name)

		# Re-fetch target AFTER await (it may have been freed)
		t = target_ref.get_ref() as Unit
		if t == null or not is_instance_valid(t):
			break

		_hud_refresh()

		await t.take_damage(1)

		_hud_refresh()
		
		# Re-fetch again (take_damage might free it)
		t = target_ref.get_ref() as Unit
		if t == null or not is_instance_valid(t):
			break

		if t.hp > 0:
			play_sfx_poly(_sfx_hurt_for(t), t.global_position, -5.0)
			await _flash_unit(t)

	if is_instance_valid(attacker):
		_play_idle(attacker)
	is_attacking_unit = false

func perform_move(u: Unit, dest: Vector2i) -> void:
	if u == null:
		return
	if is_moving_unit or is_attacking_unit:
		return
	if not is_instance_valid(u):
		return

	var from_origin := get_unit_origin(u)

	if _is_big_unit(u):
		dest = snap_origin_for_unit(dest, u)

	if not _can_stand(u, dest):
		return

	# ✅ PATH: use the same BFS path
	var path := find_path_origins(u, from_origin, dest, u.move_range)
	if path.is_empty():
		return

	# LOGIC commit to final destination immediately
	for c in u.footprint_cells(from_origin):
		if grid.is_occupied(c) and grid.occupied[c] == u:
			grid.occupied.erase(c)

	for c in u.footprint_cells(dest):
		grid.set_occupied(c, u)

	u.grid_pos = dest
	unit_origin[u] = dest

	# VISUAL: follow the path (shows corners)
	await move_unit_along_path(u, path, 0.18)

func find_path_origins(u: Unit, start: Vector2i, goal: Vector2i, max_cost: int) -> Array[Vector2i]:
	# Returns a list of origins INCLUDING start and goal.
	# If no path, returns [].

	if u == null:
		return []

	# Big units: force aligned origins
	if _is_big_unit(u):
		start = snap_origin_for_unit(start, u)
		goal = snap_origin_for_unit(goal, u)

	if start == goal:
		return [start]

	# Standard BFS (uniform cost) within max_cost
	var came_from := {}      # Dictionary: Vector2i -> Vector2i
	var dist := {}           # Dictionary: Vector2i -> int
	var q: Array[Vector2i] = []

	# start must be standable
	if not _can_stand(u, start):
		return []
	# goal must be standable too
	if not _can_stand(u, goal):
		return []

	dist[start] = 0
	q.append(start)

	while not q.is_empty():
		var cur = q.pop_front()
		var cur_d: int = dist[cur]

		if cur == goal:
			break

		if cur_d >= max_cost:
			continue

		for nb in _neighbors4_for_unit(cur, u):
			var nd := cur_d + 1
			if nd > max_cost:
				continue

			if _is_big_unit(u):
				nb = snap_origin_for_unit(nb, u)

			if dist.has(nb):
				continue

			if not _can_stand(u, nb):
				continue

			dist[nb] = nd
			came_from[nb] = cur
			q.append(nb)

	if not dist.has(goal):
		return []

	# Reconstruct path
	var path: Array[Vector2i] = []
	var cur := goal
	path.append(cur)
	while cur != start:
		cur = came_from[cur]
		path.append(cur)
	path.reverse()
	return path

func move_unit_along_path(u: Unit, path: Array[Vector2i], step_duration := 0.18) -> void:
	_hud_bind(u)

	if u == null or path.is_empty():
		return
	if is_moving_unit or is_attacking_unit:
		return
	if not is_instance_valid(u) or u.is_queued_for_deletion():
		return

	is_moving_unit = true
	_play_anim(u, "move")

	# kill any previous tween
	if move_tween != null and move_tween.is_valid():
		move_tween.kill()
		move_tween = null

	# path includes start, so skip 0
	for i in range(1, path.size()):
		# ✅ if unit died during previous step, stop NOW
		if _unit_dead_or_freeing(u):
			is_moving_unit = false
			return

		var step_origin := path[i]
		var step_pos := cell_to_world_for_unit(step_origin, u)

		var from_pos := u.global_position
		_set_facing_from_world_delta(u, from_pos, step_pos)

		move_tween = create_tween()
		move_tween.set_trans(Tween.TRANS_SINE)
		move_tween.set_ease(Tween.EASE_IN_OUT)
		move_tween.tween_property(u, "global_position", step_pos, step_duration)

		# ✅ let Unit know what tween is moving it (so death can cancel it)
		if u.has_method("set_motion_tween"):
			u.call("set_motion_tween", move_tween)

		_hud_refresh()

		var token := _motion_cancel_token
		await _await_tween_or_cancel(move_tween, token)

		# ✅ cancelled or unit died while awaiting
		if _motion_cancel_token != token or _unit_dead_or_freeing(u):
			is_moving_unit = false
			return

		u.update_layering()

	# ✅ final snap only if still alive
	if _unit_dead_or_freeing(u):
		is_moving_unit = false
		return

	u.global_position = cell_to_world_for_unit(path[path.size() - 1], u)
	_update_all_unit_layering()
	_play_idle(u)

	is_moving_unit = false

func best_reachable_toward_enemy(u: Unit, enemy: Unit) -> Vector2i:
	# Choose a reachable origin (within move_range) that minimizes distance to enemy footprint.
	var start := get_unit_origin(u)
	if _is_big_unit(u):
		start = snap_origin_for_unit(start, u)

	var reachable := compute_reachable_origins(u, start, u.move_range)
	if reachable.is_empty():
		return start

	var best := start
	var best_d := 999999

	for r in reachable:
		# Skip illegal stand tiles (reachable should already be standable, but keep safe)
		if not _can_stand(u, r):
			continue

		# Measure distance from this hypothetical origin to enemy footprint
		var d := _attack_distance_from_origin(u, r, enemy)
		if d < best_d:
			best_d = d
			best = r

	return best


func _attack_distance_from_origin(a: Unit, a_origin: Vector2i, b: Unit) -> int:
	var bo := get_unit_origin(b)
	var a_cells := a.footprint_cells(a_origin)
	var b_cells := b.footprint_cells(bo)

	var best := 999999
	for ca in a_cells:
		for cb in b_cells:
			var d = abs(ca.x - cb.x) + abs(ca.y - cb.y)
			if d < best:
				best = d
	return best

func perform_human_tnt_throw(thrower: Unit, target_cell: Vector2i, target_unit: Unit) -> void:
	# --- Guards ---
	if thrower == null or not is_instance_valid(thrower):
		return
	if is_moving_unit or is_attacking_unit:
		return
	if tnt_projectile_scene == null or tnt_explosion_scene == null:
		push_warning("Assign tnt_projectile_scene and tnt_explosion_scene on the Map/Game node.")
		return

	# Range gate
	if not _in_tnt_range(thrower, target_cell):
		_hide_tnt_curve()
		is_attacking_unit = false
		return

	is_attacking_unit = true

	# Start / end positions
	var from_pos := thrower.global_position + Vector2(0, -12)
	var to_pos := terrain.to_global(terrain.map_to_local(target_cell)) + Vector2(0, -16)

	# Face the throw direction
	_set_facing_from_world_delta(thrower, from_pos, to_pos)

	# Draw preview curve
	_draw_tnt_curve(from_pos, to_pos, tnt_arc_height)

	# Spawn projectile
	var proj := tnt_projectile_scene.instantiate() as Node2D
	if proj == null:
		_hide_tnt_curve()
		is_attacking_unit = false
		return

	add_child(proj)
	proj.global_position = from_pos
	proj.z_index = 999999

	if sfx_tnt_throw != null:
		play_sfx_poly(sfx_tnt_throw, from_pos, -6.0, 0.95, 1.05)

	# Fly along arc
	var flight := create_tween()
	flight.set_trans(Tween.TRANS_SINE)
	flight.set_ease(Tween.EASE_IN_OUT)

	var cb := Callable(self, "_tnt_throw_update").bind(proj, from_pos, to_pos, tnt_arc_height, tnt_spin_turns)
	flight.tween_method(cb, 0.0, 1.0, tnt_flight_time)

	await flight.finished

	_hide_tnt_curve()

	if is_instance_valid(proj):
		proj.queue_free()

	# Explosion
	var boom := tnt_explosion_scene.instantiate() as Node2D
	if boom != null:
		add_child(boom)
		boom.global_position = to_pos
		boom.z_as_relative = false
		boom.z_index = int(to_pos.y) + 999
		if sfx_explosion != null:
			play_sfx_poly(sfx_explosion, to_pos, -2.0, 0.9, 1.1)

	# Damage structures (freed-safe)
	var hit_cells := _splash_cells(target_cell, tnt_splash_radius)
	for c in hit_cells:
		if not structure_by_cell.has(c):
			continue

		var raw = structure_by_cell[c]
		if raw == null or not is_instance_valid(raw):
			# stale refs only
			structure_by_cell.erase(c)
			# NOTE: only erase blocked if it's truly stale (you want rubble to stay blocking)
			structure_blocked.erase(c)
			continue

		var b := raw as Node2D
		if b == null:
			structure_by_cell.erase(c)
			structure_blocked.erase(c)
			continue

		var hit_pos := terrain.to_global(terrain.map_to_local(c))
		_damage_structure(b, _get_tnt_damage(), hit_pos)

	# Damage units in splash radius
	var victims: Array[Unit] = []
	for child in units_root.get_children():
		var u := child as Unit
		if u == null or not is_instance_valid(u):
			continue
		if u == thrower:
			continue

		var u_cell := get_unit_origin(u)
		var d = abs(u_cell.x - target_cell.x) + abs(u_cell.y - target_cell.y)
		if d <= tnt_splash_radius:
			victims.append(u)

	for v in victims:
		if v == null or not is_instance_valid(v):
			continue

		var vref = weakref(v)
		_interrupt_unit_motion(v)
		await v.take_damage(_get_tnt_damage())

		var still := vref.get_ref() as Unit
		if still == null or not is_instance_valid(still):
			continue

		if still.hp > 0:
			play_sfx_poly(_sfx_hurt_for(still), still.global_position, -5.0)
			await _flash_unit(still)

	# Done
	is_attacking_unit = false

	if is_player_mode and TM != null:
		TM.notify_player_action_complete()

func set_player_mode(enabled: bool) -> void:
	is_player_mode = enabled

	# ✅ Hard reset overlays + TNT preview when leaving player mode
	if not enabled:
		selected_unit = null
		hovered_unit = null
		hovered_cell = Vector2i(-1, -1)

		clear_selection_highlight()
		clear_move_range()
		clear_attack_range()

		tnt_aiming = false
		tnt_aim_unit = null
		_hide_tnt_curve()
		
	if _hover_outlined_unit != null:
		_clear_hover_outline(_hover_outlined_unit)	

func _tnt_throw_update(t: float, proj: Node2D, from_pos: Vector2, to_pos: Vector2, arc_height: float, spin_turns: float) -> void:
	if proj == null or not is_instance_valid(proj):
		return

	# position along straight line
	var p := from_pos.lerp(to_pos, t)

	# parabolic "up" bump that peaks at t=0.5
	var bump := 4.0 * t * (1.0 - t) * arc_height
	p.y -= bump

	proj.global_position = p
	proj.rotation = t * TAU * spin_turns

	# ✅ Keep TNT always ABOVE the curve using same target-cell depth + 1
	# (uses tnt_aim_cell during aim OR falls back to impact position near end)
	if tnt_aim_cell.x >= 0 and grid.in_bounds(tnt_aim_cell):
		var cell_world := terrain.to_global(terrain.map_to_local(tnt_aim_cell)) + Vector2(0, -16)
		proj.z_index = int(cell_world.y) + 1
	else:
		# fallback: use current world y so it still sorts reasonably
		proj.z_index = int(proj.global_position.y) + 1

func _ensure_tnt_curve_line() -> Line2D:
	if _tnt_curve_line != null and is_instance_valid(_tnt_curve_line):
		return _tnt_curve_line

	var line := Line2D.new()
	line.name = "TNTArcLine"
	line.width = tnt_curve_line_width
	line.top_level = true
	line.z_as_relative = false
	line.visible = false

	add_child(line)

	_tnt_curve_line = line
	return line
	
func _arc_point(from_pos: Vector2, to_pos: Vector2, t: float, arc_height: float) -> Vector2:
	var p := from_pos.lerp(to_pos, t)
	var bump := 4.0 * t * (1.0 - t) * arc_height
	p.y -= bump
	return p

func _draw_tnt_curve(from_pos: Vector2, to_pos: Vector2, arc_height: float) -> void:
	var line := _ensure_tnt_curve_line()

	# ✅ Depth based on TARGET CELL world-y (iso-friendly, no sort_stride needed)
	if tnt_aim_cell.x >= 0 and grid.in_bounds(tnt_aim_cell):
		var cell_world := terrain.to_global(terrain.map_to_local(tnt_aim_cell))
		line.z_index = int(cell_world.y) # curve depth = target cell depth

	line.clear_points()

	var n = max(4, tnt_curve_points)
	for i in range(n):
		var t := float(i) / float(n - 1)
		line.add_point(_arc_point(from_pos, to_pos, t, arc_height))

	line.visible = false

func _hide_tnt_curve() -> void:
	if _tnt_curve_line != null and is_instance_valid(_tnt_curve_line):
		_tnt_curve_line.visible = false
		_tnt_curve_line.clear_points()

func _update_tnt_aim_preview() -> void:
	if not tnt_aiming:
		return
	if tnt_aim_unit == null or not is_instance_valid(tnt_aim_unit):
		tnt_aiming = false
		tnt_aim_unit = null
		_hide_tnt_curve()
		return

	_update_hovered_cell()
	if not grid.in_bounds(hovered_cell):
		_hide_tnt_curve()
		tnt_aim_cell = Vector2i(-1, -1)
		return

	# NEW: block aiming if out of range
	if not _in_tnt_range(tnt_aim_unit, hovered_cell):
		_hide_tnt_curve()
		return

	# Only redraw when the target cell changes (prevents constant point churn)
	if hovered_cell == tnt_aim_cell:
		return

	tnt_aim_cell = hovered_cell

	var from_pos := tnt_aim_unit.global_position + Vector2(0, -12)
	var to_pos := terrain.to_global(terrain.map_to_local(tnt_aim_cell)) + Vector2(0, -16)

	_set_facing_from_world_delta(tnt_aim_unit, from_pos, to_pos)
	_draw_tnt_curve(from_pos, to_pos, tnt_arc_height)

func play_sfx(stream: AudioStream, world_pos: Vector2, vol_db := -6.0, pitch_min := 0.95, pitch_max := 1.05) -> void:
	if stream == null:
		return
	if sfx == null or not is_instance_valid(sfx):
		return
	sfx.stream = stream
	sfx.global_position = world_pos
	sfx.volume_db = vol_db
	sfx.pitch_scale = randf_range(pitch_min, pitch_max) # tiny variation feels nicer
	sfx.play()

func play_sfx_poly(stream: AudioStream, world_pos: Vector2, vol_db := -6.0, pitch_min := 0.95, pitch_max := 1.05) -> void:
	if stream == null:
		return

	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.global_position = world_pos
	p.volume_db = vol_db
	p.pitch_scale = randf_range(pitch_min, pitch_max)

	add_child(p)
	p.play()

	# cleanup when finished
	p.finished.connect(func():
		if is_instance_valid(p):
			p.queue_free()
	)

func _sfx_attack_for(u: Unit) -> AudioStream:
	if u is Human:
		return sfx_human_attack
	if u is HumanTwo:
		return sfx_humantwo_attack
	if u is Mech:
		return sfx_dog_attack
	if u is Zombie:
		return sfx_zombie_attack
	return null

func _sfx_hurt_for(u: Unit) -> AudioStream:
	if u is Human:
		return sfx_human_hurt
	if u is HumanTwo:
		return sfx_humantwo_hurt
	if u is Mech:
		return sfx_dog_hurt
	if u is Zombie:
		return sfx_zombie_hurt
	return null

func _sfx_die_for(u: Unit) -> AudioStream:
	if u is Human:
		return sfx_human_die
	if u is HumanTwo:
		return sfx_humantwo_die
	if u is Mech:
		return sfx_dog_die
	if u is Zombie:
		return sfx_zombie_die
	return null


func _can_unit_aim_tnt(u: Unit) -> bool:
	return u != null and (u is Human or u is HumanTwo)

func _map_pixel_size() -> Vector2i:
	var cell_px := terrain.tile_set.tile_size # should be 32x32
	return Vector2i(map_width * cell_px.x, map_height * cell_px.y)

func _tilemap_local_bounds_px(tm: TileMap) -> Rect2:
	# Pixel bounds of the used cells, in *that TileMap's local space*
	if tm == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var used: Rect2i = tm.get_used_rect()
	if used.size == Vector2i.ZERO:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	# Convert the 4 corners of the used rect to local pixel coords
	var p0 := tm.map_to_local(used.position)
	var p1 := tm.map_to_local(used.position + Vector2i(used.size.x, 0))
	var p2 := tm.map_to_local(used.position + Vector2i(0, used.size.y))
	var p3 := tm.map_to_local(used.position + used.size)

	var minx = min(p0.x, p1.x, p2.x, p3.x)
	var maxx = max(p0.x, p1.x, p2.x, p3.x)
	var miny = min(p0.y, p1.y, p2.y, p3.y)
	var maxy = max(p0.y, p1.y, p2.y, p3.y)

	return Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny))


func _union_rect(a: Rect2, b: Rect2) -> Rect2:
	if a.size == Vector2.ZERO:
		return b
	if b.size == Vector2.ZERO:
		return a
	var pos := Vector2(min(a.position.x, b.position.x), min(a.position.y, b.position.y))
	var end := Vector2(max(a.end.x, b.end.x), max(a.end.y, b.end.y))
	return Rect2(pos, end - pos)


func bake_map_to_sprite() -> void:
	if not bake_map_visuals:
		return
	if terrain == null:
		return

	# --- ensure nodes exist ---
	if bake_vp == null:
		bake_vp = SubViewport.new()
		bake_vp.name = "MapBakeViewport"
		add_child(bake_vp)

	if bake_root == null:
		bake_root = Node2D.new()
		bake_root.name = "MapBakeRoot"
		bake_vp.add_child(bake_root)

	if baked_sprite == null:
		baked_sprite = Sprite2D.new()
		baked_sprite.name = "MapBakedSprite"
		add_child(baked_sprite)
		# ✅ ensure baked map is drawn FIRST (behind units/pickups)
		move_child(baked_sprite, 0)

	# Clear previous bake children
	for ch in bake_root.get_children():
		ch.queue_free()

	# --- compute union bounds (in TERRAIN local pixels) ---
	var bounds := _tilemap_local_bounds_px(terrain)
	if roads_dl: bounds = _union_rect(bounds, _tilemap_local_bounds_px(roads_dl))
	if roads_dr: bounds = _union_rect(bounds, _tilemap_local_bounds_px(roads_dr))
	if roads_x:  bounds = _union_rect(bounds, _tilemap_local_bounds_px(roads_x))

	# Add padding so edges don’t clip (important for isometric / big tiles)
	var pad := Vector2(128, 128)
	bounds.position -= pad
	bounds.size += pad * 2.0

	var vp_size := Vector2i(ceil(bounds.size.x), ceil(bounds.size.y))
	vp_size.x = max(vp_size.x, 4)
	vp_size.y = max(vp_size.y, 4)

	# --- configure viewport ---
	bake_vp.size = vp_size
	bake_vp.transparent_bg = true
	bake_vp.disable_3d = true
	bake_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Shift everything so bounds.position becomes (0,0) in the viewport
	bake_root.position = -bounds.position

	# --- duplicate visuals into viewport ---
	var t_copy := terrain.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as TileMap
	bake_root.add_child(t_copy)
	t_copy.position = terrain.position  # LOCAL position, not global
	t_copy.rotation = terrain.rotation
	t_copy.scale = terrain.scale

	if roads_dl:
		var dl_copy := roads_dl.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as TileMap
		bake_root.add_child(dl_copy)
		dl_copy.position = roads_dl.position
		dl_copy.rotation = roads_dl.rotation
		dl_copy.scale = roads_dl.scale

	if roads_dr:
		var dr_copy := roads_dr.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as TileMap
		bake_root.add_child(dr_copy)
		dr_copy.position = roads_dr.position
		dr_copy.rotation = roads_dr.rotation
		dr_copy.scale = roads_dr.scale

	if roads_x:
		var x_copy := roads_x.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as TileMap
		bake_root.add_child(x_copy)
		x_copy.position = roads_x.position
		x_copy.rotation = roads_x.rotation
		x_copy.scale = roads_x.scale

	# Let viewport render
	await get_tree().process_frame
	await get_tree().process_frame

	# Assign baked texture
	baked_sprite.texture = bake_vp.get_texture()
	baked_sprite.centered = false
	baked_sprite.z_as_relative = false
	baked_sprite.z_index = -1000000

	# Place the sprite so it matches the original world position of bounds.position
	# bounds.position is in TERRAIN LOCAL pixels → convert to world
	var world_top_left := terrain.to_global(bounds.position)
	baked_sprite.global_position = world_top_left

	# Hide originals
	terrain.visible = false
	if roads_dl: roads_dl.visible = false
	if roads_dr: roads_dr.visible = false
	if roads_x:  roads_x.visible = false

func _in_tnt_range(thrower: Unit, cell: Vector2i) -> bool:
	if thrower == null or not is_instance_valid(thrower):
		return false

	var from := get_unit_origin(thrower)
	var best := 999999

	# measure from any footprint cell (works for big units too)
	for fc in thrower.footprint_cells(from):
		var d = abs(fc.x - cell.x) + abs(fc.y - cell.y)
		best = min(best, d)

	return best <= int(thrower.tnt_throw_range)

func _pick_ai_tnt_target_cell(thrower: Unit) -> Vector2i:
	if thrower == null or not is_instance_valid(thrower):
		return Vector2i(-1, -1)

	# Prefer hitting enemies; choose the one that would splash the most units
	var enemies := get_enemies_of(thrower)
	if enemies.is_empty():
		return Vector2i(-1, -1)

	var best_cell := Vector2i(-1, -1)
	var best_score := -999999

	for e in enemies:
		if e == null or not is_instance_valid(e):
			continue

		var cell := get_unit_origin(e)

		# ✅ range gating (this is the important part)
		if not _in_tnt_range(thrower, cell):
			continue

		# optional: don’t throw on water / invalid
		if not grid.in_bounds(cell):
			continue

		# Score: how many victims would get hit (splash)
		var score := 0
		for other in units_root.get_children():
			var ou := other as Unit
			if ou == null or not is_instance_valid(ou):
				continue
			if ou == thrower:
				continue

			var ou_cell := get_unit_origin(ou)
			var d = abs(ou_cell.x - cell.x) + abs(ou_cell.y - cell.y)
			if d <= tnt_splash_radius:
				# prefer hitting enemies, avoid allies
				score += (3 if ou.team != thrower.team else -4)

		if score > best_score:
			best_score = score
			best_cell = cell

	return best_cell

func _zombie_hp_bonus_for_round(r: int) -> int:
	# +1 at round 3, 6, 9, ...
	return int(floor(max(r - 1, 0) / 3.0))

func _zombie_repeats_bonus_for_round(r: int) -> int:
	# 2 => 1, 5 => 2, 8 => 3, ...
	if r % 3 != 2:
		return 0
	return int(floor(r / 3.0)) + 1

func spawn_structures() -> void:
	structures.clear()
	structure_by_cell.clear()
	structure_hp.clear()
	structure_can_act.clear()

	if structures_root == null:
		structures_root = self
	for ch in structures_root.get_children():
		ch.queue_free()

	structure_blocked.clear()

	var size := building_footprint

	# --- Tier spawn counters ---
	var tier_counts : Array[int] = []
	tier_counts.resize(building_scenes.size())
	for i in range(tier_counts.size()):
		tier_counts[i] = 0

	const MAX_PER_TIER := 3

	# --- Build candidate origin cells ---
	var candidates: Array[Vector2i] = []
	for x in range(map_width - size.x + 1):
		for y in range(map_height - size.y + 1):
			var c := Vector2i(x, y)
			if not _is_structure_origin_ok(c, size):
				continue
			candidates.append(c)

	candidates.shuffle()

	var placed := 0
	var tries := 0

	while placed < building_count and tries < 5000 and not candidates.is_empty():
		tries += 1
		var origin: Vector2i = candidates.pop_back()

		if _is_structure_blocked(origin, size):
			continue

		# --- Pick next allowed tier ---
		var picked_tier := -1
		for t in range(building_scenes.size()):
			if tier_counts[t] < MAX_PER_TIER and building_scenes[t] != null:
				picked_tier = t
				break

		# No tiers left under cap → stop spawning
		if picked_tier == -1:
			break

		var scene := building_scenes[picked_tier]
		var b = scene.instantiate()
		var b2 := b as Node2D
		if b2 == null:
			continue

		structures_root.add_child(b2)
		_apply_structure_tint(b2)

		if b2.has_method("set_origin"):
			b2.call("set_origin", origin, terrain)
		else:
			var world_pos := terrain.to_global(terrain.map_to_local(origin))
			b2.global_position = world_pos
			b2.z_as_relative = false
			b2.z_index = Z_STRUCTURES + _depth_key_for_footprint(origin, size)

		# --- Track ---
		structures.append(b2)
		structure_hp[b2] = int(building_max_hp)
		structure_can_act[b2] = false
		_set_structure_active_visual(b2, false)
		_update_structure_ui()
		_mark_structure_blocked(origin, size, b2)

		placed += 1
		tier_counts[picked_tier] += 1

func _pick_building_scene() -> PackedScene:
	# Prefer the array, fall back to single scene.
	if building_scenes != null and building_scenes.size() > 0:
		# Filter out nulls just in case
		var valid: Array[PackedScene] = []
		for s in building_scenes:
			if s != null:
				valid.append(s)

		if valid.size() > 0:
			return valid[rng.randi_range(0, valid.size() - 1)]

	return building_scene

func _is_structure_origin_ok(origin: Vector2i, size: Vector2i) -> bool:
	# inside _is_structure_origin_ok(origin, size):
	if size == Vector2i(1, 1):
		if _cell_has_road(origin):
			return false
				
	# footprint must be in bounds
	if origin.x < 0 or origin.y < 0:
		return false
	if origin.x + size.x - 1 >= map_width:
		return false
	if origin.y + size.y - 1 >= map_height:
		return false

	# optionally avoid ally/enemy spawn rectangles so battles don’t start jammed
	if avoid_spawn_zones:
		var ally_r := _rect_top_left(ally_spawn_size)
		var enemy_r := _rect_bottom_right(enemy_spawn_size)
		# If ANY footprint cell touches a spawn zone, reject
		for dx in range(size.x):
			for dy in range(size.y):
				var c := origin + Vector2i(dx, dy)
				if ally_r.has_point(c) or enemy_r.has_point(c):
					return false

	# check all footprint cells
	for dx in range(size.x):
		for dy in range(size.y):
			var c := origin + Vector2i(dx, dy)

			if not grid.in_bounds(c):
				return false
			if grid.terrain[c.x][c.y] == T_WATER:
				return false

			# don't place on units / occupied tiles
			if grid.is_occupied(c):
				return false

			# ✅ don't place on roads (road tiles are 2x2 cells)
			if road_blocked.has(c):
				return false

	return true

func _cell_has_road(c: Vector2i) -> bool:
	# Robust road overlap test for 1x1 structures:
	# sample multiple points inside the terrain cell so offsets + 64x64 road tiles can't slip through.
	if terrain == null or not is_instance_valid(terrain):
		return false

	var road_maps: Array[TileMap] = []
	if roads_dl != null and is_instance_valid(roads_dl): road_maps.append(roads_dl)
	if roads_dr != null and is_instance_valid(roads_dr): road_maps.append(roads_dr)
	if roads_x  != null and is_instance_valid(roads_x):  road_maps.append(roads_x)
	if road_maps.is_empty():
		return false

	var tile_sz: Vector2 = Vector2(32, 32)
	if terrain.tile_set != null:
		tile_sz = terrain.tile_set.tile_size

	# terrain.map_to_local gives cell center in local space (Godot 4)
	var center_local := terrain.map_to_local(c)
	var center_world := terrain.to_global(center_local)

	# sample 5 points: center + 4 corners (inset a bit so we don't land exactly on borders)
	var inset := 6.0
	var hx := tile_sz.x * 0.5 - inset
	var hy := tile_sz.y * 0.5 - inset

	var samples: Array[Vector2] = [
		center_world,
		center_world + Vector2(-hx, -hy),
		center_world + Vector2( hx, -hy),
		center_world + Vector2(-hx,  hy),
		center_world + Vector2( hx,  hy),
	]

	for rmap in road_maps:
		# If any sample point lands inside a road cell that has a tile, we consider it blocked.
		for wp in samples:
			var local_in_road := rmap.to_local(wp)
			var rc := rmap.local_to_map(local_in_road)
			if rmap.get_cell_source_id(0, rc) != -1:
				return true

	return false

func _is_structure_blocked(origin: Vector2i, size: Vector2i) -> bool:
	for dx in range(size.x):
		for dy in range(size.y):
			if structure_blocked.has(origin + Vector2i(dx, dy)):
				return true
	return false

func _mark_structure_blocked(origin: Vector2i, size: Vector2i, b2: Node2D) -> void:
	for dx in range(size.x):
		for dy in range(size.y):
			var c := origin + Vector2i(dx, dy)
			structure_blocked[c] = true
			structure_by_cell[c] = b2


func _depth_key(cell: Vector2i) -> int:
	# Requirement: use x+y sum for depth sorting.
	return cell.x + cell.y

func _depth_key_for_footprint(origin: Vector2i, size: Vector2i) -> int:
	# Use the bottom-right "feet" cell of the footprint for stable sorting.
	var bottom := origin + Vector2i(size.x - 1, size.y - 1)
	return _depth_key(bottom)


func _tilemap_used_bounds_in_terrain_local(tm: TileMap) -> Rect2:
	# Returns bounds of tm's used cells, expressed in TERRAIN LOCAL pixel space.
	if tm == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	var used: Rect2i = tm.get_used_rect()
	if used.size == Vector2i.ZERO:
		return Rect2(Vector2.ZERO, Vector2.ZERO)

	# 4 corners in the TileMap's local pixel space
	var p0 := tm.map_to_local(used.position)
	var p1 := tm.map_to_local(used.position + Vector2i(used.size.x, 0))
	var p2 := tm.map_to_local(used.position + Vector2i(0, used.size.y))
	var p3 := tm.map_to_local(used.position + used.size)

	# Convert each to TERRAIN local space (via global)
	var g0 := terrain.to_local(tm.to_global(p0))
	var g1 := terrain.to_local(tm.to_global(p1))
	var g2 := terrain.to_local(tm.to_global(p2))
	var g3 := terrain.to_local(tm.to_global(p3))

	var minx = min(g0.x, g1.x, g2.x, g3.x)
	var maxx = max(g0.x, g1.x, g2.x, g3.x)
	var miny = min(g0.y, g1.y, g2.y, g3.y)
	var maxy = max(g0.y, g1.y, g2.y, g3.y)

	return Rect2(Vector2(minx, miny), Vector2(maxx - minx, maxy - miny))

func bake_roads_to_sprite() -> void:
	if terrain == null or not is_instance_valid(terrain):
		return

	# ensure nodes exist
	if bake_vp == null:
		bake_vp = SubViewport.new()
		bake_vp.name = "RoadBakeViewport"
		add_child(bake_vp)

	if bake_root == null:
		bake_root = Node2D.new()
		bake_root.name = "RoadBakeRoot"
		bake_vp.add_child(bake_root)

	if roads_baked_sprite == null:
		roads_baked_sprite = Sprite2D.new()
		roads_baked_sprite.name = "RoadsBakedSprite"
		add_child(roads_baked_sprite)

	# Clear previous bake children
	for ch in bake_root.get_children():
		ch.queue_free()

	# Compute bounds in TERRAIN local space for the THREE road maps
	var bounds := Rect2(Vector2.ZERO, Vector2.ZERO)
	var first := true
	for rmap in [roads_dl, roads_dr, roads_x]:
		if rmap == null or not is_instance_valid(rmap):
			continue
		var b := _tilemap_used_bounds_in_terrain_local(rmap)
		if b.size == Vector2.ZERO:
			continue
		bounds = b if first else _union_rect(bounds, b)
		first = false

	if first:
		return # nothing to bake

	# Padding to avoid clipping
	var pad := Vector2(128, 128)
	bounds.position -= pad
	bounds.size += pad * 2.0

	var vp_size := Vector2i(ceil(bounds.size.x), ceil(bounds.size.y))
	vp_size.x = max(vp_size.x, 4)
	vp_size.y = max(vp_size.y, 4)

	bake_vp.size = vp_size
	bake_vp.transparent_bg = true
	bake_vp.disable_3d = true
	bake_vp.render_target_update_mode = SubViewport.UPDATE_ONCE

	# Shift bake_root so bounds.position maps to (0,0) in viewport
	bake_root.position = -bounds.position

	# Duplicate ONLY roads into viewport
	for rmap in [roads_dl, roads_dr, roads_x]:
		if rmap == null or not is_instance_valid(rmap):
			continue
		var copy := rmap.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as TileMap
		bake_root.add_child(copy)
		copy.position = rmap.position
		copy.rotation = rmap.rotation
		copy.scale = rmap.scale

	# Render
	await get_tree().process_frame
	await get_tree().process_frame

	# Assign baked texture
	roads_baked_sprite.texture = bake_vp.get_texture()
	roads_baked_sprite.centered = false
	roads_baked_sprite.z_as_relative = false
	roads_baked_sprite.z_index = 0  # same as your road z, but now it's a sprite

	# Place sprite so it matches world position of bounds.position (terrain local -> world)
	roads_baked_sprite.global_position = terrain.to_global(bounds.position)

	# Hide the live road tilemaps (terrain stays visible)
	if roads_dl: roads_dl.visible = false
	if roads_dr: roads_dr.visible = false
	if roads_x:  roads_x.visible = false

func _splash_cells(center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var c := center + Vector2i(dx, dy)
			if grid.in_bounds(c) and abs(dx) + abs(dy) <= r:
				out.append(c)
	return out

func _damage_structure(b: Node2D, dmg: int, hit_world_pos: Vector2) -> void:
	if b == null or not is_instance_valid(b):
		return
	if not structure_hp.has(b):
		return

	structure_hp[b] = int(structure_hp[b]) - int(dmg)

	# quick feedback
	var t := create_tween()
	t.tween_property(b, "modulate", Color(2, 2, 2, 1), 0.05)
	t.tween_property(b, "modulate", Color(1, 1, 1, 1), 0.10)

	if int(structure_hp[b]) > 0:
		return

	# "explode"
	if tnt_explosion_scene != null:
		var boom := tnt_explosion_scene.instantiate() as Node2D
		if boom != null:
			add_child(boom)
			boom.global_position = hit_world_pos
			boom.z_as_relative = false
			boom.z_index = int(hit_world_pos.y) + 999
			if sfx_explosion != null:
				play_sfx_poly(sfx_explosion, hit_world_pos, -2.0, 0.9, 1.1)
				
	if int(structure_hp[b]) > 0:
		return

	# ✅ tell the building to visually demolish itself (if it knows how)
	if b.has_method("set_demolished"):
		b.call("set_demolished", true)
	elif b.has_method("demolish"):
		b.call("demolish")
	else:
		# fallback: try switching AnimatedSprite2D anim names
		if b.has_node("AnimatedSprite2D"):
			var spr := b.get_node("AnimatedSprite2D") as AnimatedSprite2D
			if spr and spr.sprite_frames:
				if spr.sprite_frames.has_animation("demolished"):
					spr.play("demolished")
				elif spr.sprite_frames.has_animation("destroyed"):
					spr.play("destroyed")

	# ❌ DO NOT unblock cells on demolition (rubble stays blocking)
	# We keep structure_blocked + structure_by_cell intact so units cannot walk through rubble.
	# (Optional) If you ever want rubble to stop taking damage, we’ll handle that below.

	# ✅ structure is demolished — splash zombies in 3x3 (radius 1) or bigger
	# building footprint is 2x2, so use its ORIGIN cell (top-left) as the splash center
	var origin := Vector2i(-1, -1)
	for k in structure_by_cell.keys():
		if structure_by_cell[k] == b:
			origin = k
			break

	if origin.x >= 0:
		# radius=1 => 3x3, radius=2 => 5x5, radius=3 => 7x7
		await _damage_units_near_structure(origin, 1, _get_tnt_damage(), hit_world_pos)

	# ✅ keep it on map as rubble (don’t queue_free)
	structure_hp.erase(b)
	if structures.has(b):
		structures.erase(b)
	return

func _update_all_unit_layering() -> void:
	if units_root == null:
		return
	for ch in units_root.get_children():
		var u := ch as Unit
		if u != null and is_instance_valid(u):
			u.update_layering()

func _damage_units_near_structure(struct_origin: Vector2i, radius: int, dmg: int, source_world_pos: Vector2) -> void:
	if dmg <= 0:
		return

	var hit_cells := _splash_cells(struct_origin, radius)

	# collect victims first (so we can await safely)
	var victims: Array[Unit] = []
	for child in units_root.get_children():
		var u := child as Unit
		if u == null or not is_instance_valid(u):
			continue
		if not (u is Zombie):
			continue

		var uo := get_unit_origin(u)
		# if any of the unit's footprint cells are in the hit set, count it
		var in_range := false
		for fc in u.footprint_cells(uo):
			if hit_cells.has(fc):
				in_range = true
				break
		if in_range:
			victims.append(u)

	# apply damage
	for z in victims:
		if z == null or not is_instance_valid(z):
			continue

		var zref = weakref(z)
		await z.take_damage(dmg)

		var still := zref.get_ref() as Unit
		if still != null and is_instance_valid(still) and still.hp > 0:
			play_sfx_poly(_sfx_hurt_for(still), still.global_position, -5.0)
			await _flash_unit(still)

func _get_unit_canvas_sprite(u: Unit) -> CanvasItem:
	# You currently use AnimatedSprite2D, but this keeps it flexible.
	if u == null or not is_instance_valid(u):
		return null
	if u.has_node("AnimatedSprite2D"):
		return u.get_node("AnimatedSprite2D") as AnimatedSprite2D
	return null

func _apply_hover_outline(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return

	var spr := _get_unit_canvas_sprite(u)
	if spr == null:
		return

	# Save previous material once
	if not _hover_prev_material.has(u):
		_hover_prev_material[u] = spr.material

	var mat := ShaderMaterial.new()
	mat.shader = hover_outline_shader
	mat.set_shader_parameter("outline_color", hover_outline_color)
	mat.set_shader_parameter("thickness_px", 1.0)

	spr.material = mat
	_hover_outlined_unit = u

func _clear_hover_outline(u: Unit) -> void:
	if u == null:
		return

	# If it got freed, just forget it
	if not is_instance_valid(u):
		_hover_prev_material.erase(u)
		if _hover_outlined_unit == u:
			_hover_outlined_unit = null
		return

	var spr := _get_unit_canvas_sprite(u)
	if spr == null:
		return

	# Restore previous material if we stored one
	if _hover_prev_material.has(u):
		spr.material = _hover_prev_material[u]
		_hover_prev_material.erase(u)
	else:
		spr.material = null

	if _hover_outlined_unit == u:
		_hover_outlined_unit = null

func _update_hover_outline() -> void:
	# During SETUP drag, keep outline on the dragged unit (even though it's "selected")
	var want: Unit = null

	if state == GameState.SETUP and setup_dragging and setup_drag_unit != null and is_instance_valid(setup_drag_unit):
		want = setup_drag_unit
	else:
		# normal hover behavior
		if hovered_unit != null and is_instance_valid(hovered_unit):
			want = hovered_unit

	# If nothing wanted, clear any current outline
	if want == null:
		if _hover_outlined_unit != null:
			_clear_hover_outline(_hover_outlined_unit)
		return

	# If outline target changed, swap it
	if _hover_outlined_unit != null and _hover_outlined_unit != want:
		_clear_hover_outline(_hover_outlined_unit)

	if _hover_outlined_unit != want:
		_apply_hover_outline(want)

func _clear_mine_preview() -> void:
	if mine_preview != null:
		mine_preview.clear()

func _draw_mine_preview() -> void:
	if mine_preview == null:
		return
	mine_preview.clear()

	if not mine_placing:
		return
	if not grid.in_bounds(hovered_cell):
		return

	# ✅ keep mine preview grid-aligned
	mine_preview.position = Vector2.ZERO

	var ok := _can_place_mine_at(hovered_cell)
	var sid := (MINE_PREVIEW_SMALL_SOURCE_ID if ok else MINE_PREVIEW_SMALLX_SOURCE_ID)
	mine_preview.set_cell(LAYER_MINE_PREVIEW, hovered_cell, sid, MINE_PREVIEW_ATLAS, 0)

func _interrupt_unit_motion(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return

	# Stop current tween so we don't keep dragging a "dead" unit around
	if move_tween != null and move_tween.is_valid():
		move_tween.kill()
		move_tween = null

	# ✅ Stop unit-side movement tweens too (if Unit implements it)
	if u.has_method("cancel_motion"):
		u.call("cancel_motion")
		
	# Reset flags so flow can recover
	is_moving_unit = false
	is_attacking_unit = false

	# Optional: clear selection if the selected unit just got nuked
	if selected_unit == u:
		select_unit(null)

func _cancel_motion_now() -> void:
	_motion_cancel_token += 1

	# kill current tween if any
	if move_tween != null and move_tween.is_valid():
		move_tween.kill()
		move_tween = null

	# clear flags so AI/turn logic can continue
	is_moving_unit = false
	is_attacking_unit = false


func _await_tween_or_cancel(t: Tween, token: int) -> void:
	# Wait until:
	# - tween stops running, OR
	# - motion gets cancelled (token changes), OR
	# - tween becomes invalid, OR
	# - this node is leaving the tree (so get_tree() becomes null)
	while true:
		if _motion_cancel_token != token:
			return
		if t == null or not t.is_valid():
			return
		if not t.is_running():
			return
		if not is_inside_tree():
			return

		# ✅ safest frame-yield in Godot 4 (doesn't require get_tree().process_frame)
		await get_tree().create_timer(0.0).timeout

func _unit_display_name(u: Unit) -> String:
	if u == null:
		return ""
	# Prefer meta, then name, then class
	if u.has_meta("display_name"):
		return str(u.get_meta("display_name"))
	if u.name != "":
		return u.name
	return u.get_class()

func _unit_dead_or_freeing(u: Unit) -> bool:
	return u == null or (not is_instance_valid(u)) or u.is_queued_for_deletion() or int(u.hp) <= 0

func perform_structure_attack(b: Node2D, target_cell: Vector2i) -> void:
	if b == null or not is_instance_valid(b):
		return
	if not structure_hp.has(b):
		return # demolished rubble can't shoot
	if structure_shot_scene == null:
		push_warning("Assign structure_shot_scene (StructureShot.tscn) in Inspector.")
		return
	if not grid.in_bounds(target_cell):
		return

	# start = building position (you can offset if you want a muzzle point)
	var start_world := b.global_position

	# end = center of target cell
	var end_world := terrain.to_global(terrain.map_to_local(target_cell))

	# 1) animate 1px line growing outward
	var shot := structure_shot_scene.instantiate() as Node2D
	add_child(shot)
	shot.z_as_relative = false
	shot.z_index = int(max(start_world.y, end_world.y)) + 2000

	if shot.has_method("fire"):
		shot.call("fire", start_world, end_world)
		await shot.finished
	shot.queue_free()

	# 2) explosion visual (reuse your TNT boom)
	if tnt_explosion_scene != null:
		var boom := tnt_explosion_scene.instantiate() as Node2D
		if boom != null:
			add_child(boom)
			end_world += Vector2(0, -16)
			boom.global_position = end_world
			boom.z_as_relative = false
			boom.z_index = int(end_world.y) + 999
			if sfx_explosion != null:
				play_sfx_poly(sfx_explosion, end_world, -2.0, 0.9, 1.1)

	# 3) apply damage (zombies only, like your structure demolition splash)
	await _damage_units_near_structure(target_cell, int(structure_splash_radius), int(structure_attack_damage), end_world)

func pick_best_structure_target_cell(b: Node2D) -> Vector2i:
	# Pick closest zombie within range, but never closer than 3 cells
	if b == null or not is_instance_valid(b):
		return Vector2i(-1, -1)

	var best := Vector2i(-1, -1)
	var best_d := 999999

	# Get building cell
	var b_local := terrain.to_local(b.global_position)
	var bcell := terrain.local_to_map(b_local)

	for child in units_root.get_children():
		var u := child as Unit
		if u == null or not is_instance_valid(u):
			continue
		if not (u is Zombie):
			continue

		var uc := get_unit_origin(u)
		var d = abs(uc.x - bcell.x) + abs(uc.y - bcell.y)

		# ✅ must be at least 3 cells away
		if d < 4:
			continue

		# ✅ must still be within attack range
		if d > int(structure_attack_range):
			continue

		# pick closest valid target
		if d < best_d:
			best_d = d
			best = uc

	return best

func _count_active_structures() -> int:
	var n := 0
	for b in structures:
		if b != null and is_instance_valid(b) and structure_can_act.get(b, false) and structure_hp.has(b):
			n += 1
	return n

func upgrade_structure_slot() -> void:
	structure_active_cap += 1
	_update_structure_ui()

func _get_structure_canvas_sprite(b: Node2D) -> CanvasItem:
	if b == null or not is_instance_valid(b):
		return null

	# common visual nodes in building scenes
	for name in ["AnimatedSprite2D", "Sprite2D", "Sprite", "Art", "Body", "Visual"]:
		if b.has_node(name):
			var n = b.get_node(name)
			if n is CanvasItem:
				return n as CanvasItem

	# fallback: first CanvasItem child
	for ch in b.get_children():
		if ch is CanvasItem:
			return ch as CanvasItem

	return null

func _apply_hover_outline_structure(b: Node2D) -> void:
	if b == null or not is_instance_valid(b):
		return

	var spr := _get_structure_canvas_sprite(b)
	if spr == null:
		return

	if not _hover_prev_structure_material.has(b):
		_hover_prev_structure_material[b] = spr.material

	var mat := ShaderMaterial.new()
	mat.shader = hover_outline_shader
	mat.set_shader_parameter("outline_color", hover_outline_color)
	mat.set_shader_parameter("thickness_px", 1.0)

	spr.material = mat
	_hover_outlined_structure = b


func _clear_hover_outline_structure(b: Node2D) -> void:
	if b == null:
		return

	if not is_instance_valid(b):
		_hover_prev_structure_material.erase(b)
		if _hover_outlined_structure == b:
			_hover_outlined_structure = null
		return

	var spr := _get_structure_canvas_sprite(b)
	if spr == null:
		return

	if _hover_prev_structure_material.has(b):
		spr.material = _hover_prev_structure_material[b]
		_hover_prev_structure_material.erase(b)
	else:
		spr.material = null

	if _hover_outlined_structure == b:
		_hover_outlined_structure = null

func _update_structure_hover_outline() -> void:
	# Only when picking structures in SETUP
	if not (state == GameState.SETUP and structure_selecting):
		if _hover_outlined_structure != null:
			_clear_hover_outline_structure(_hover_outlined_structure)
			_hover_outlined_structure = null

		if _hover_attack_structure != null:
			clear_attack_range()
			_hover_attack_structure = null
		return

	var want: Node2D = null
	var b := structure_at_cell(hovered_cell)
	if b != null and is_instance_valid(b) and structure_hp.has(b):
		want = b

	# Nothing hovered -> clear outline + clear attack overlay
	if want == null:
		if _hover_outlined_structure != null:
			_clear_hover_outline_structure(_hover_outlined_structure)
			_hover_outlined_structure = null

		if _hover_attack_structure != null:
			clear_attack_range()
			_hover_attack_structure = null
		return

	# Hover changed -> swap outline, redraw attack overlay
	if _hover_outlined_structure != null and _hover_outlined_structure != want:
		_clear_hover_outline_structure(_hover_outlined_structure)
		_hover_outlined_structure = null

	if _hover_outlined_structure != want:
		_apply_hover_outline_structure(want)
		_hover_outlined_structure = want

	# Attack range overlay (only redraw when changed)
	if _hover_attack_structure != want:
		draw_attack_range_for_structure(want)
		_hover_attack_structure = want
