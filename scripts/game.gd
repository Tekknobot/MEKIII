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
@onready var roads: TileMap = $Roads

@onready var bake_vp: SubViewport = get_node_or_null("MapBakeViewport")
@onready var bake_root: Node2D = (bake_vp.get_node_or_null("MapBakeRoot") as Node2D) if bake_vp else null
@onready var baked_sprite: Sprite2D = get_node_or_null("MapBakedSprite") as Sprite2D

@export var bake_map_visuals := true

@export var road_pixel_offset := Vector2(-32, 0) # tweak if needed
const ROAD_SIZE := 2 # 64x64 road tile covers 2x2 of your 16x16 grid

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

# Per-battle assist charges
var assist_tnt_charges_left := 0

# Cached placement zone (computed from ally_spawn_size)
var ally_rect_cache: Rect2i

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

# Put this near the top of game.gd (or wherever _build_ui lives)
@export var ui_font_path: String = "res://fonts/magofonts/mago1.ttf"
@export var ui_font_size: int = 18
@export var ui_title_font_size: int = 20

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

	# human2 is optional, but if it's missing we’ll just use human_scene
	var has_h2 := (human2_scene != null)

	for child in units_root.get_children():
		child.queue_free()
	grid.occupied.clear()
	unit_origin.clear()

	var ally_rect := _rect_top_left(ally_spawn_size)
	var enemy_rect := _rect_bottom_right(enemy_spawn_size)

	# ✅ Mechs: top-left
	for i in range(mech_count):
		_spawn_one(mech_scene, ally_rect)

	# ✅ Humans: top-left
	for i in range(human_count):
		_spawn_one(human_scene, ally_rect)

	# ✅ Human2: top-left (only if scene assigned)
	if human2_scene != null:
		for i in range(human2_count):
			_spawn_one(human2_scene, ally_rect)

	# ✅ Zombies: bottom-right
	for i in range(zombie_count):
		_spawn_one(zombie_scene, enemy_rect)

	# Ensure UI + setup zone cache stays correct
	ally_rect_cache = _rect_top_left(ally_spawn_size)
	_refresh_ui_status()

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
	if not ally_rect_cache.has_point(cell):
		return false
	if grid.terrain[cell.x][cell.y] == T_WATER:
		return false

	var u := selected_unit
	var new_origin := cell
	if _is_big_unit(u):
		new_origin = snap_origin_for_unit(cell, u)

	# All footprint cells must be inside the ally zone, on land, and unoccupied (except by itself)
	var old_origin := get_unit_origin(u)
	# Temporarily clear own occupancy
	for c in u.footprint_cells(old_origin):
		if grid.is_occupied(c) and grid.get_occupied(c) == u:
			grid.set_occupied(c, null)

	var ok := true
	for c in u.footprint_cells(new_origin):
		if not grid.in_bounds(c) or not ally_rect_cache.has_point(c):
			ok = false
			break
		if grid.terrain[c.x][c.y] == T_WATER:
			ok = false
			break
		if grid.is_occupied(c):
			ok = false
			break

	# Restore / apply occupancy
	if not ok:
		for c in u.footprint_cells(old_origin):
			grid.set_occupied(c, u)
		return false

	for c in u.footprint_cells(new_origin):
		grid.set_occupied(c, u)
	unit_origin[u] = new_origin
	u.grid_pos = new_origin
	u.global_position = cell_to_world_for_unit(new_origin, u)
	u.update_layering()
	_refresh_ui_status()
	return true

# -----------------------
# Spawn one (UPDATED signature)
# -----------------------
func _spawn_one(scene: PackedScene, region: Rect2i) -> void:
	var tries := 500
	while tries > 0:
		tries -= 1

		var unit := scene.instantiate() as Unit
		if unit == null:
			return

		var origin := _rand_cell_in_rect(region)

		# big units must align
		if _is_big_unit(unit):
			origin = snap_origin_for_unit(origin, unit)

			# if snapping pushed it outside the region, try again
			if not region.has_point(origin):
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
			if grid.is_occupied(c):
				ok = false
				break

		if not ok:
			unit.queue_free()
			continue

		for c in cells:
			grid.set_occupied(c, unit)

		unit.grid_pos = origin
		unit_origin[unit] = origin
		units_root.add_child(unit)

		# ✅ Now apply run bonuses AFTER the unit's own _ready() finishes
		if unit.team == Unit.Team.ALLY:
			unit.call_deferred("apply_run_bonuses", bonus_max_hp, bonus_attack_range, bonus_move_range, bonus_attack_repeats)
			
		unit.global_position = cell_to_world_for_unit(origin, unit)
		unit.update_layering()
		return

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
		await bake_map_to_sprite()
			
	spawn_units()
	ally_rect_cache = _rect_top_left(ally_spawn_size)

	_build_ui()

	if turn_manager != NodePath():
		TM = get_node(turn_manager) as TurnManager
		if TM != null:
			TM.battle_started.connect(_on_battle_started)
			TM.battle_ended.connect(_on_battle_ended)

	# Start in SETUP so the player can reposition allies, then press Start.
	_enter_setup()

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
	rmap.z_index = 1000

func _process(_delta: float) -> void:
	# Only update hover/aim previews when we allow player input.
	if not _can_handle_player_input():
		if tnt_aiming:
			tnt_aiming = false
			tnt_aim_unit = null
			_hide_tnt_curve()
		return

	_update_hovered_cell()
	_update_hovered_unit()
	_update_tnt_aim_preview()

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

	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(240, 0) 

	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ui_root.add_child(v)

	ui_status_label = RichTextLabel.new()
	ui_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ui_status_label.bbcode_enabled = true
	ui_status_label.fit_content = true
	ui_status_label.scroll_active = false

	if ui_font:
		ui_status_label.add_theme_font_override("normal_font", ui_font)
		ui_status_label.add_theme_font_size_override("normal_font_size", ui_font_size)

		# optional (only matters if you ever use [b] or [i] tags)
		ui_status_label.add_theme_font_override("bold_font", ui_font)
		ui_status_label.add_theme_font_override("italics_font", ui_font)
		ui_status_label.add_theme_font_override("bold_italics_font", ui_font)
	v.add_child(ui_status_label)

	ui_start_button = Button.new()
	ui_start_button.text = "Start Battle"
	ui_start_button.pressed.connect(_on_start_pressed)
	if ui_font:
		ui_start_button.add_theme_font_override("font", ui_font)
		ui_start_button.add_theme_font_size_override("font_size", ui_font_size)
	v.add_child(ui_start_button)

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

	ui_reward_buttons.clear()
	var b1 := Button.new(); b1.text = "+1 Max HP"; b1.pressed.connect(func(): _pick_reward(0))
	var b2 := Button.new(); b2.text = "+1 Attack Range"; b2.pressed.connect(func(): _pick_reward(1))
	var b3 := Button.new(); b3.text = "+1 TNT Damage"; b3.pressed.connect(func(): _pick_reward(2))
	var b4 := Button.new(); b4.text = "+1 Attack Repeat";  b4.pressed.connect(func(): _pick_reward(3)) # ✅ NEW

	ui_reward_buttons = [b1, b2, b3, b4]

	for b in ui_reward_buttons:
		if ui_font:
			b.add_theme_font_override("font", ui_font)
			b.add_theme_font_size_override("font_size", ui_font_size)
		rv.add_child(b)

	_refresh_ui_status()

func _refresh_ui_status() -> void:
	if ui_status_label == null:
		return

	var phase := "SETUP"
	if state == GameState.BATTLE:
		phase = "BATTLE"
	elif state == GameState.REWARD:
		phase = "REWARD"

	var lines: Array[String] = []
	lines.append("Round %d , Phase: %s" % [round_index, phase])
	lines.append("Allies: %d  Enemies: %d" % [get_units(Unit.Team.ALLY).size(), get_units(Unit.Team.ENEMY).size()])

	# Avoid special characters and arrow glyphs; keep it plain ASCII.
	# Also avoid calling _get_tnt_damage() if it doesn't exist for some reason.
	var cur_tnt := tnt_damage
	if has_method("_get_tnt_damage"):
		cur_tnt = _get_tnt_damage()

	lines.append(
		"Upgrades: HP +%d, Range +%d, Move +%d, Repeats +%d, TNT +%d (base %d to %d)" %
		[bonus_max_hp, bonus_attack_range, bonus_move_range, bonus_attack_repeats, bonus_tnt_damage, tnt_damage, cur_tnt]
	)

	if state == GameState.SETUP:
		lines.append("[color=#ffd966]BATTLE RULES[/color]: Units move and attack automatically.")
		lines.append("[color=#ff9966]Humans[/color] use [color=#ff4444]TNT[/color] when available.")

	elif state == GameState.BATTLE:
		lines.append("[color=#66ccff]BATTLE IN PROGRESS[/color]")
		lines.append("Units act automatically.")

	elif state == GameState.REWARD:
		lines.append("[color=#66ff66]ROUND COMPLETE[/color]")
		lines.append("Choose an upgrade to continue.")

	ui_status_label.text = "\n".join(lines)


func _enter_setup() -> void:
	state = GameState.SETUP
	set_player_mode(false)
	assist_tnt_charges_left = 0
	ui_start_button.visible = true
	ui_reward_panel.visible = false
	select_unit(null)
	_refresh_ui_status()


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
	else:
		ui_reward_label.text = "Defeat. Choose an upgrade and try again"
	_refresh_ui_status()

func _pick_reward(choice: int) -> void:
	match choice:
		0: bonus_max_hp += 1
		1: bonus_attack_range += 1
		2: bonus_tnt_damage += 1
		3: bonus_attack_repeats += 1   

	# Difficulty ramp
	round_index += 1
	zombie_count += 2

	# ✅ RANDOMIZE SEASON EACH ROUND
	season = Season.values()[rng.randi_range(0, Season.values().size() - 1)]

	# (Optional) also slightly randomize season strength for variety
	season_strength = rng.randf_range(0.55, 0.9)

	# ✅ Rebuild map with new season
	rng.randomize()   # ensures new layout each round
	grid.setup(map_width, map_height)
	generate_map()
	terrain.update_internals()
	_sync_roads_transform()

	if bake_map_visuals:
		# if you already baked before, you may want to re-show tilemaps briefly or just bake again
		terrain.visible = true
		if roads_dl: roads_dl.visible = true
		if roads_dr: roads_dr.visible = true
		if roads_x:  roads_x.visible = true
		await bake_map_to_sprite()

	# Respawn units on new map
	spawn_units()
	_enter_setup()

# -----------------------
# Mouse -> map helpers
# -----------------------
func _update_hovered_cell() -> void:
	var mouse_global := get_global_mouse_position()
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

	for x in range(map_width):
		for y in range(map_height):
			grid.terrain[x][y] = pick_tile_for_season_no_water()

	_ensure_walkable_connected()
	_remove_dead_ends()

	for x in range(map_width):
		for y in range(map_height):
			set_tile_id(Vector2i(x, y), grid.terrain[x][y])
			
	# --- paint roads on separate 64x64 TileMap ---
	if roads != null:
		roads.clear()
	_add_roads()

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
	var cols := int(map_width / ROAD_SIZE) * 2 - 1  # 15
	var rows := int(map_height / ROAD_SIZE) * 2 - 1 # 15

	# pick lane column/row within the road grid
	var margin := 0
	var road_col := rng.randi_range(margin, cols - 1 - margin)
	var road_row := rng.randi_range(margin, rows - 1 - margin)

	# rc -> bitmask (1=DL, 2=DR, 3=intersection)
	var conn := {}

	# vertical lane (DL) within [0, rows-1]
	for ry in range(0, rows):
		var rc := Vector2i(road_col, ry)
		conn[rc] = int(conn.get(rc, 0)) | 1

	# horizontal lane (DR) within [0, cols-1]
	for rx in range(0, cols):
		var rc := Vector2i(rx, road_row)
		conn[rc] = int(conn.get(rc, 0)) | 2

	# force intersection
	var cross := Vector2i(road_col, road_row)
	conn[cross] = 3

	# paint (all rc are guaranteed in-bounds)
	for rc in conn.keys():
		var mask := int(conn[rc])
		if mask == 3:
			roads_x.set_cell(0, rc, ROAD_INTERSECTION, ROAD_ATLAS, 0)
		elif mask == 1:
			roads_dl.set_cell(0, rc, ROAD_DOWN_LEFT, ROAD_ATLAS, 0)
		elif mask == 2:
			roads_dr.set_cell(0, rc, ROAD_DOWN_RIGHT, ROAD_ATLAS, 0)
	
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
	if selected_unit == null:
		draw_unit_hover(hovered_unit)

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

func clear_attack_range() -> void:
	attack_range_small.clear()
	attack_range_big.clear()
	attackable_units.clear()

	attack_range_small.position = attack_offset_small
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

func _unhandled_input(event: InputEvent) -> void:
	# ✅ Press R to hard reset (reload scene)
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.keycode == KEY_R:
			get_tree().reload_current_scene()
			return

	if not _can_handle_player_input():
		return
	if is_moving_unit or is_attacking_unit:
		return
		
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

	pickups_root.add_child(d2)

	var world_pos := terrain.to_global(terrain.map_to_local(spawn_cell))
	world_pos += Vector2(0, -16)
	d2.global_position = world_pos

	d2.z_as_relative = false
	d2.z_index = 300000 + int(world_pos.y)

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

	# ✅ Prefer exact death cell, otherwise find a nearby free cell
	var spawn_cell := Vector2i(-1, -1)

	if _is_pickup_cell_ok(zombie_cell) and not pickups.has(zombie_cell):
		spawn_cell = zombie_cell
	else:
		spawn_cell = _find_free_adjacent_cell(zombie_cell)

	if spawn_cell.x < 0:
		return

	# Don't stack pickups
	if pickups.has(spawn_cell):
		return

	var drop := laser_drop_scene.instantiate()
	var d2 := drop as Node2D
	if d2 == null:
		push_warning("laser_drop_scene root is not Node2D/Area2D; can't render.")
		return

	pickups_root.add_child(d2)

	var world_pos := terrain.to_global(terrain.map_to_local(spawn_cell))
	world_pos += Vector2(0, -16)
	d2.global_position = world_pos

	# ✅ Above tilemaps, still y-sorted
	d2.z_as_relative = false
	d2.z_index = 300000 + int(world_pos.y)

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
		if u != null and u.team == team_id:
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

	# pick up to N random zombies (unique)
	zombies.shuffle()
	var count = min(orbital_hits, zombies.size())

	for i in range(count):
		var z := zombies[i]
		if z == null or not is_instance_valid(z):
			continue

		var hit_pos := z.global_position

		# 1px beam flash
		_spawn_orbital_beam(hit_pos)

		# optional zap sfx
		if sfx_orbital_zap != null:
			play_sfx_poly(sfx_orbital_zap, hit_pos, -4.0, 0.95, 1.05)

		# explosion visual + sfx
		if tnt_explosion_scene != null:
			var boom := tnt_explosion_scene.instantiate() as Node2D
			if boom != null:
				add_child(boom)
				boom.global_position = hit_pos
				boom.z_index = int(hit_pos.y) + 999
				play_sfx_poly(sfx_explosion, hit_pos, -2.0, 0.9, 1.1)

		# kill the zombie
		if is_instance_valid(z):
			await z.take_damage(orbital_damage)

			# ✅ flash on hit (only if still alive)
			if is_instance_valid(z) and z.hp > 0:
				play_sfx_poly(_sfx_hurt_for(z), z.global_position, -5.0)
				await _flash_unit(z)

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

		await t.take_damage(1)

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
	if u == null or path.is_empty():
		return
	if is_moving_unit or is_attacking_unit:
		return
	if not is_instance_valid(u):
		return

	is_moving_unit = true
	_play_anim(u, "move")

	# kill any previous tween
	if move_tween != null and move_tween.is_valid():
		move_tween.kill()

	# path includes start, so skip 0
	for i in range(1, path.size()):
		var step_origin := path[i]
		var step_pos := cell_to_world_for_unit(step_origin, u)

		var from_pos := u.global_position
		_set_facing_from_world_delta(u, from_pos, step_pos)

		move_tween = create_tween()
		move_tween.set_trans(Tween.TRANS_SINE)
		move_tween.set_ease(Tween.EASE_IN_OUT)
		move_tween.tween_property(u, "global_position", step_pos, step_duration)

		await move_tween.finished
		u.update_layering()

	# snap exact
	u.global_position = cell_to_world_for_unit(path[path.size() - 1], u)
	u.update_layering()
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
	# Safety: prevent firing out of range
	if not _in_tnt_range(thrower, target_cell):
		is_attacking_unit = false
		_hide_tnt_curve()
		return
	
	if thrower == null or not is_instance_valid(thrower):
		return
	if is_moving_unit or is_attacking_unit:
		return
	if tnt_projectile_scene == null or tnt_explosion_scene == null:
		push_warning("Assign tnt_projectile_scene and tnt_explosion_scene on the Map/Game node.")
		return

	is_attacking_unit = true

	# Start at the thrower's current world position (slightly above so it doesn't clip the feet)
	var from_pos := thrower.global_position + Vector2(0, -12)

	# Land at the center of the clicked cell
	var to_pos := terrain.to_global(terrain.map_to_local(target_cell))

	# Face the throw direction
	_set_facing_from_world_delta(thrower, from_pos, to_pos)

	# ✅ Draw the preview arc line NOW
	_draw_tnt_curve(from_pos, to_pos, tnt_arc_height)

	# Spawn the TNT projectile
	var proj := tnt_projectile_scene.instantiate() as Node2D
	if proj == null:
		_hide_tnt_curve()
		is_attacking_unit = false
		return
	add_child(proj)
	proj.global_position = from_pos
	proj.z_index = 999999

	play_sfx_poly(sfx_tnt_throw, from_pos, -6.0, 0.95, 1.05)

	# Tween projectile along the exact same arc
	var flight := create_tween()
	flight.set_trans(Tween.TRANS_SINE)
	flight.set_ease(Tween.EASE_IN_OUT)

	var cb := Callable(self, "_tnt_throw_update").bind(proj, from_pos, to_pos, tnt_arc_height, tnt_spin_turns)
	flight.tween_method(cb, 0.0, 1.0, tnt_flight_time)

	await flight.finished

	_hide_tnt_curve()

	if is_instance_valid(proj):
		proj.queue_free()

	# Spawn explosion at landing point
	var boom := tnt_explosion_scene.instantiate() as Node2D
	if boom != null:
		add_child(boom)
		boom.global_position = to_pos
		boom.z_index = 999999
		play_sfx_poly(sfx_explosion, to_pos, -2.0, 0.9, 1.1)

	# Damage units in splash radius (grid distance)
	var victims: Array[Unit] = []
	for child in units_root.get_children():
		var u := child as Unit
		if u == null:
			continue
		if not is_instance_valid(u):
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
		await v.take_damage(_get_tnt_damage())

		var still := vref.get_ref() as Unit
		if still == null or not is_instance_valid(still):
			continue

		# ✅ flash on hit (only if still alive)
		if still.hp > 0:
			play_sfx_poly(_sfx_hurt_for(still), still.global_position, -5.0)
			await _flash_unit(still)


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
		var cell_world := terrain.to_global(terrain.map_to_local(tnt_aim_cell))
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
	var to_pos := terrain.to_global(terrain.map_to_local(tnt_aim_cell))

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
