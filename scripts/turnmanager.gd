extends Node
class_name TurnManager

@export var map_controller_path: NodePath
@export var end_turn_button_path: NodePath
@export var menu_button_path: NodePath
@onready var menu_button := get_node_or_null(menu_button_path) as Button

# Set this to your actual title scene path
@export var title_scene_path: String = "res://scenes/title_screen.tscn"

@export var zombie_limit: int = 32
@export var show_infestation_hud: bool = true
@export var zombie_portrait_tex: Texture2D = preload("res://sprites/Portraits/zombie_port.png") # change if needed
@export var zombie_vision: int = 2

@export var infestation_title_font: Font
@export var infestation_body_font: Font
@export var infestation_button_font: Font

@export var infestation_title_font_size: int = 16
@export var infestation_body_font_size: int = 16
@export var infestation_button_font_size: int = 16

@export var infestation_portrait_size: int = 48

var infestation_hud: InfestationHUD = null
var _game_over_triggered: bool = false
# (No import needed in Godot; class_name InfestationHUD will resolve)

var loss_checks_enabled: bool = false
var _had_any_allies: bool = false
var _spawn_wait_tries: int = 0
const _SPAWN_WAIT_MAX_TRIES := 90  # ~1.5s at 60fps

@onready var M: MapController = get_node(map_controller_path)
@onready var end_turn_button := get_node_or_null(end_turn_button_path)

@export var hellfire_button_path: NodePath
@export var blade_button_path: NodePath
@export var mines_button_path: NodePath
@export var overwatch_button_path: NodePath
@export var suppress_button_path: NodePath
@export var stim_button_path: NodePath
@export var sunder_button_path: NodePath
@export var pounce_button_path: NodePath
@export var volley_button_path: NodePath
@export var cannon_button_path: NodePath
@export var quake_button_path: NodePath
@export var nova_button_path: NodePath
@export var web_button_path: NodePath
@export var slam_button_path: NodePath
@export var laser_grid_button_path: NodePath
@export var overcharge_button_path: NodePath
@export var barrage_button_path: NodePath
@export var railgun_button_path: NodePath
@export var malfunction_button_path: NodePath
@export var storm_button_path: NodePath
@export var artillery_strike_button_path: NodePath
@export var laser_sweep_button_path: NodePath

@onready var suppress_button := get_node_or_null(suppress_button_path)
@onready var stim_button := get_node_or_null(stim_button_path)
@onready var overwatch_button := get_node_or_null(overwatch_button_path)
@onready var hellfire_button := get_node_or_null(hellfire_button_path)
@onready var blade_button := get_node_or_null(blade_button_path)
@onready var mines_button := get_node_or_null(mines_button_path)
@onready var sunder_button := get_node_or_null(sunder_button_path)
@onready var pounce_button := get_node_or_null(pounce_button_path)
@onready var volley_button := get_node_or_null(volley_button_path)
@onready var cannon_button := get_node_or_null(cannon_button_path)
@onready var quake_button := get_node_or_null(quake_button_path)
@onready var nova_button := get_node_or_null(nova_button_path)
@onready var web_button := get_node_or_null(web_button_path)
@onready var slam_button := get_node_or_null(slam_button_path)
@onready var laser_grid_button := get_node_or_null(laser_grid_button_path)
@onready var overcharge_button := get_node_or_null(overcharge_button_path)
@onready var barrage_button := get_node_or_null(barrage_button_path)
@onready var railgun_button := get_node_or_null(railgun_button_path)
@onready var malfunction_button := get_node_or_null(malfunction_button_path) 
@onready var storm_button := get_node_or_null(storm_button_path) 
@onready var artillery_strike_button := get_node_or_null(artillery_strike_button_path)
@onready var laser_sweep_button := get_node_or_null(laser_sweep_button_path)

enum Phase { PLAYER, ENEMY, BUSY }
var phase: Phase = Phase.PLAYER

# Per-ally action state
var _moved: Dictionary = {}   # Unit -> bool
var _attacked: Dictionary = {}# Unit -> bool

var enemy_spawn_count := 2   # how many edge zombies to spawn per round
var round_index := 1  # Round 1 at game start

# --- Beacon pacing ---
@export var beacon_deadline_round := 12  # "must be done by end of Round 12" (tune this)

# --- Enemy wave spawning ---
@export var spawn_base := 3              # Round 1 adds +3 (tune)
@export var spawn_per_round := 1         # +1 per round
@export var spawn_bonus_every := 3       # every 3 rounds add extra
@export var spawn_bonus_amount := 2      # how many extra on bonus rounds
@export var spawn_cap := 32              # hard safety cap

signal tutorial_event(id: StringName, payload: Dictionary)

@export var end_game_panel_script: Script

var end_panel: EndGamePanelRuntime

@export var end_game_panel_path: NodePath

@export var boss_mode_enabled: bool = false
@export var boss_controller_scene: PackedScene  # scene that has BossController + your big sprite

var boss: BossController = null

# -------------------------
# EVENT: Titan Overwatch
# -------------------------
@export var titan_event_enabled := true

@export var titan_turns_to_survive := 3
@export var titan_strikes_per_turn := 6
@export var titan_strike_damage := 2

@export var titan_warn_time := 0.35 # seconds before impact

# Optional: show your Titan mech art off-map during the event
@export var titan_mech_scene: PackedScene
var titan_mech: Node2D = null

# Optional: spawn explosions (recommended if you have a prefab)
@export var titan_explosion_scene: PackedScene

# Optional: sound hook if MapController has _sfx(name, ...)
@export var titan_sfx_fire: StringName = &"bullet"
@export var titan_sfx_explode: StringName = &"explosion_small"

var _is_titan_event := false
var _titan_turns_left := 0
var _titan_rng := RandomNumberGenerator.new()

# warning markers we spawn each turn
var _titan_markers: Array[Node2D] = []

var _event_turn := 0
@export var event_base_cells := 1
@export var event_max_cells := 16

enum EventPattern { SCATTER, LINE, CROSS, RING }

var _titan_autorun_started := false

var _pending_return_to_overworld := false
var _pending_event_success := false

enum MissionState { DROP, SCRAMBLE, EVAC }

func _pick_pattern() -> int:
	# early turns: simple; later: nastier
	if _event_turn <= 1:
		return EventPattern.SCATTER
	elif _event_turn == 2:
		return _titan_rng.randi_range(0, 1) # scatter/line
	elif _event_turn == 3:
		return _titan_rng.randi_range(1, 2) # line/cross
	else:
		return _titan_rng.randi_range(1, 3) # line/cross/ring

func _pattern_candidates(pattern: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []

	var game_map := get_tree().get_first_node_in_group("GameMap")

	# pick an anchor on the board
	var cx := _titan_rng.randi_range(0, game_map.map_width - 1)
	var cy := _titan_rng.randi_range(0, game_map.map_height - 1)
	var c := Vector2i(cx, cy)

	match pattern:
		EventPattern.SCATTER:
			# whole board candidates
			for x in range(game_map.map_width):
				for y in range(game_map.map_height):
					out.append(Vector2i(x, y))

		EventPattern.LINE:
			var horiz := _titan_rng.randi() % 2 == 0
			if horiz:
				for x in range(game_map.map_width):
					out.append(Vector2i(x, c.y))
			else:
				for y in range(game_map.map_height):
					out.append(Vector2i(c.x, y))

		EventPattern.CROSS:
			for x in range(game_map.map_width):
				out.append(Vector2i(x, c.y))
			for y in range(game_map.map_height):
				out.append(Vector2i(c.x, y))

		EventPattern.RING:
			# diamond ring at radius 2–4 (scales with turns)
			var r := clampi(2 + _event_turn, 2, 4)
			for dx in range(-r, r + 1):
				var dy = r - abs(dx)
				out.append(c + Vector2i(dx,  dy))
				out.append(c + Vector2i(dx, -dy))

	# filter: in bounds, not blocked (optional)
	var filtered: Array[Vector2i] = []
	for cell in out:
		if cell.x < 0 or cell.y < 0 or cell.x >= game_map.map_width or cell.y >= game_map.map_height:
			continue
		filtered.append(cell)

	return filtered

func _choose_cells(cands: Array[Vector2i], count: int) -> Array[Vector2i]:
	var pool := cands.duplicate()
	pool.shuffle()
	var picked: Array[Vector2i] = []
	for cell in pool:
		if picked.size() >= count:
			break
		# optional: avoid allies so it's "fair", or DO target allies to be mean
		picked.append(cell)
	return picked

func _ready() -> void:
	end_panel = EndGamePanelRuntime.new()

	# -------------------------------------------------
	# Reuse HUD fonts for Mission Failed panel
	# -------------------------------------------------
	end_panel.title_font = infestation_title_font
	end_panel.body_font = infestation_body_font
	end_panel.button_font = infestation_button_font

	# Scale up sizes for a full-screen panel
	end_panel.title_font_size = infestation_title_font_size * 2
	end_panel.body_font_size = infestation_body_font_size * 1.25
	end_panel.button_font_size = infestation_button_font_size * 1.25

	# Optional: description font (reuse body)
	end_panel.desc_font = infestation_body_font
	end_panel.desc_font_size = infestation_body_font_size

	add_child(end_panel)

	# --- Make "continue" act as RESTART on loss ---
	if not end_panel.continue_pressed.is_connected(_on_loss_restart_pressed):
		end_panel.continue_pressed.connect(_on_loss_restart_pressed)

	# --- Infestation HUD ---
	if show_infestation_hud:
		infestation_hud = InfestationHUD.new()
		infestation_hud.zombie_limit = zombie_limit
		infestation_hud.zombie_portrait = zombie_portrait_tex
		infestation_hud.portrait_size = infestation_portrait_size

		infestation_hud.title_font = infestation_title_font
		infestation_hud.body_font = infestation_body_font
		infestation_hud.button_font = infestation_button_font

		infestation_hud.title_font_size = infestation_title_font_size
		infestation_hud.body_font_size = infestation_body_font_size
		infestation_hud.button_font_size = infestation_button_font_size

		add_child(infestation_hud)

	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_pressed)
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
	else:
		push_warning("TurnManager: menu_button_path not set or not found.")

	if hellfire_button:
		hellfire_button.pressed.connect(_on_hellfire_pressed)
	if blade_button:
		blade_button.pressed.connect(_on_blade_pressed)
	if mines_button:
		mines_button.pressed.connect(_on_mines_pressed)
	if overwatch_button:
		overwatch_button.pressed.connect(_on_overwatch_pressed)
	if suppress_button:
		suppress_button.pressed.connect(_on_suppress_pressed)
	if stim_button:
		stim_button.pressed.connect(_on_stim_pressed)
	if sunder_button:
		sunder_button.pressed.connect(_on_sunder_pressed)
	if pounce_button:
		pounce_button.pressed.connect(_on_pounce_pressed)
	if volley_button:
		volley_button.pressed.connect(_on_volley_pressed)
	if cannon_button:
		cannon_button.pressed.connect(_on_cannon_pressed)
	if quake_button:
		quake_button.pressed.connect(_on_quake_pressed)
	if nova_button:
		nova_button.pressed.connect(_on_nova_pressed)
	if web_button:
		web_button.pressed.connect(_on_web_pressed)
	if slam_button:
		slam_button.pressed.connect(_on_slam_pressed)
	if laser_grid_button:                                            
		laser_grid_button.pressed.connect(_on_laser_grid_pressed)    
	if overcharge_button:                                            
		overcharge_button.pressed.connect(_on_overcharge_pressed) 
	if barrage_button:
		barrage_button.pressed.connect(_on_barrage_pressed)
	if railgun_button:
		railgun_button.pressed.connect(_on_railgun_pressed)
	if malfunction_button:
		malfunction_button.pressed.connect(_on_malfunction_pressed)
	if storm_button:
		storm_button.pressed.connect(_on_storm_pressed)
	if artillery_strike_button:
		artillery_strike_button.pressed.connect(_on_artillery_strike_pressed)
	if laser_sweep_button:
		laser_sweep_button.pressed.connect(_on_laser_sweep_pressed)
				
	start_player_phase()
	_update_end_turn_button()

	if M != null:
		if M.has_signal("selection_changed") and not M.selection_changed.is_connected(_on_selection_changed):
			M.selection_changed.connect(_on_selection_changed)

		if M.has_signal("aim_changed") and not M.aim_changed.is_connected(_on_aim_changed):
			M.aim_changed.connect(_on_aim_changed)

	# MapController tutorial events -> use them to refresh counts (enemy deaths)
	if M != null and M.has_signal("tutorial_event"):
		if not M.tutorial_event.is_connected(_on_map_tutorial_event):
			M.tutorial_event.connect(_on_map_tutorial_event)

	_update_special_buttons()

	# Initial refresh (after scene loads / units spawn)
	loss_checks_enabled = false
	_had_any_allies = false
	_spawn_wait_tries = 0
	call_deferred("_wait_for_units_then_enable_loss_checks")

	var rs := get_tree().root.get_node_or_null("RunStateNode")
	if rs != null:
		# boss latch
		if "boss_mode_enabled_next_mission" in rs:
			boss_mode_enabled = bool(rs.boss_mode_enabled_next_mission)
		else:
			boss_mode_enabled = false

		# EVENT latch (this is what overworld.gd sets)
		if "event_mode_enabled_next_mission" in rs:
			titan_event_enabled = bool(rs.event_mode_enabled_next_mission)
		else:
			titan_event_enabled = false

		# if event is enabled, run titan event
		if titan_event_enabled:
			_is_titan_event = true
			_titan_turns_left = titan_turns_to_survive

			# stable RNG per node seed
			if "mission_seed" in rs:
				_titan_rng.seed = int(rs.mission_seed) ^ 0xA51C0DE
			else:
				_titan_rng.randomize()

			# consume
			rs.event_mode_enabled_next_mission = false
			rs.event_id_next_mission = &""

			if titan_mech != null:
				titan_mech.visible = true

			call_deferred("_titan_event_setup")
		else:
			_is_titan_event = false

func _wait_until_allies_exist(max_frames := 1200) -> bool:
	# 1200 frames ≈ 20 seconds @ 60fps (deployment/fades can be long)
	var frames := 0
	while frames < max_frames:
		if M != null:
			for u in M.get_all_units():
				if u != null and is_instance_valid(u) and u.hp > 0 and u.team == Unit.Team.ALLY:
					return true
		frames += 1
		await get_tree().process_frame
	return false
		
func _on_map_tutorial_event(id: StringName, _payload: Dictionary) -> void:
	# enemy_died is guaranteed from MapController.on_unit_died()
	if id == &"enemy_died":
		call_deferred("_refresh_population_and_check")

	if id == &"pickup_collected":
		_refresh_population_and_check()
		return		

func _refresh_population_and_check() -> void:
	if _game_over_triggered:
		return
	if M == null:
		return
	if not loss_checks_enabled:
		return

	var units := M.get_all_units()
	if units == null or units.is_empty():
		return

	var zombies := 0
	var allies := 0

	for u in units:
		if u == null or not is_instance_valid(u):
			continue
		if u.hp <= 0:
			continue

		if u.team == Unit.Team.ENEMY:
			zombies += 1
		elif u.team == Unit.Team.ALLY:
			allies += 1

	# Track: have we ever had allies alive?
	if allies > 0:
		_had_any_allies = true

	# Update HUD
	if infestation_hud != null and is_instance_valid(infestation_hud):
		infestation_hud.set_counts(zombies, zombie_limit)

		if M != null and "beacon_parts_collected" in M and "beacon_parts_needed" in M:
			infestation_hud.set_floppy_count(int(M.beacon_parts_collected), int(M.beacon_parts_needed))
		
		if M != null and M.has_method("get_kills_until_next_floppy"):
			infestation_hud.set_floppy_progress(int(M.call("get_kills_until_next_floppy")))
			
	# Loss #1: too many zombies (allowed as soon as checks are enabled)
	if zombies > zombie_limit:
		_loss_mode = LossMode.RESTART_MISSION
		game_over("SYSTEM OVERRUN\n\nInfestation exceeded containment limits.\nZombies: %d / %d" % [zombies, zombie_limit])
		return

	# Loss #2: no allies (ONLY if we have had allies at least once)
	if _had_any_allies and allies <= 0:
		_loss_mode = LossMode.TO_MENU
		game_over("LAST LIGHT EXTINGUISHED\n\nNo allied units remain operational.")
		return


func _on_loss_restart_pressed() -> void:
	if not _game_over_triggered:
		return

	var tree := get_tree()
	if tree == null:
		return

	var rs := tree.root.get_node_or_null("RunStateNode")

	# ---- Always clear local event state BEFORE reload ----
	_clear_titan_markers()
	_event_turn = 0
	_titan_turns_left = 0

	# ---- If we died during Titan event, re-arm it for next mission ----
	if _is_titan_event:
		_is_titan_event = false

		if rs != null:
			rs.event_mode_enabled_next_mission = true
			# keep mission_seed if you want deterministic restarts

		tree.paused = false
		tree.reload_current_scene()
		return

	# ---- Normal restart run ----
	_is_titan_event = false

	if rs != null:
		rs.boss_mode_enabled_next_mission = boss_mode_enabled
		rs.event_mode_enabled_next_mission = false
		rs.event_id_next_mission = &""
		rs.save_to_disk()

	tree.paused = false
	tree.reload_current_scene()



# -----------------------
# Phase control
# -----------------------
func start_player_phase() -> void:
	M.reset_turn_flags_for_allies()
	
	phase = Phase.PLAYER
	_moved.clear()
	_attacked.clear()

	for u in M.get_all_units():
		if u.team == Unit.Team.ALLY:
			_moved[u] = false
			_attacked[u] = false
			M.set_unit_exhausted(u, false) # reset tint each new player phase

	_update_end_turn_button()

func start_enemy_phase() -> void:
	phase = Phase.ENEMY
	M.reset_turn_flags_for_enemies()

	# ✅ Tick chill/ice AFTER player turn so chill affects player movement this turn
	IceZombie.ice_tick_global(M)
	
	# EVENT: Titan Overwatch
	if _is_titan_event:
		# Event is cinematic; no enemy phase logic.
		#await _titan_overwatch_enemy_phase()
		return
		
	if boss_mode_enabled and boss != null and is_instance_valid(boss):
		await boss.resolve_planned_attacks()
		_refresh_population_and_check()
		if _game_over_triggered:
			return

	_tick_buffs_enemy_phase_start()

	for u in M.get_all_units():
		if u != null and is_instance_valid(u) and (u is IceZombie):
			(u as IceZombie).ice_tick(M)

	# Fire zombies tick
	for u in M.get_all_units():
		if u != null and is_instance_valid(u) and (u is FireZombie):
			(u as FireZombie).fire_tick(M)

	# Burning tiles tick
	FireZombie.fire_tiles_tick(M)

	# ✅ Radiation phase-start tick (aura + contam + standing damage)
	if M != null and is_instance_valid(M):
		# 1) Each radioactive zombie pulses + leaves/refreshes contam
		if M.has_method("get_all_units"):
			for u in M.get_all_units():
				if u != null and is_instance_valid(u) and (u is RadioactiveZombie):
					(u as RadioactiveZombie).rad_tick(M)

		# 2) Contamination timers tick + damage allies standing on contaminated tiles
		RadioactiveZombie.contam_tick(M)

	_update_end_turn_button()
	_update_special_buttons()

	await _run_enemy_turns()

	# overwatch tick
	if M != null:
		M.tick_overwatch_turn()

	call_deferred("_refresh_population_and_check")
	if _game_over_triggered:
		return

	# spawn wave for next round (standard curve)
	if M != null and M.has_method("spawn_edge_road_zombie"):
		var to_spawn := _calc_spawn_count_for_round(round_index)
		var spawned := 0

		for i in range(to_spawn):
			# Make spawn_edge_road_zombie() return bool if it can; otherwise assume it worked.
			var ok := true
			if M.has_method("spawn_edge_road_zombie"):
				ok = M.call("spawn_edge_road_zombie")
			if ok:
				spawned += 1
			else:
				break # no more valid edge cells

		print("Spawned %d/%d enemies for Round %d" % [spawned, to_spawn, round_index])

		call_deferred("_refresh_population_and_check")
		if _game_over_triggered:
			return

	# Advance round counter NOW (enemy phase finished)
	round_index += 1

	# deadline check (tune for 6 parts)
	if M != null and M.has_meta("beacon_ready"):
		if round_index > beacon_deadline_round and (not M.beacon_ready):
			game_over("Beacon not completed by end of Round %d!" % beacon_deadline_round)
			return

	if boss_mode_enabled and boss != null and is_instance_valid(boss):
		boss.plan_next_attacks()

	start_player_phase()

func _calc_spawn_count_for_round(r: int) -> int:
	# r is the round that just finished / or current round_index before increment (your current usage)
	# Example curve:
	# Round 1: spawn_base
	# Round 2: spawn_base + 1
	# Round 3: spawn_base + 2 (+bonus if divisible)
	var n = spawn_base + (max(0, r - 1) * spawn_per_round)

	if spawn_bonus_every > 0 and r > 0 and (r % spawn_bonus_every == 0):
		n += spawn_bonus_amount

	n = clamp(n, 0, spawn_cap)
	return n

func _on_end_turn_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	
	# --- Clear Overlays ---	
	M._clear_overlay()

	# ✅ stop enemy pulses for next phase (they'll restart when threat overlay is redrawn)
	if M != null and M.has_method("stop_all_enemy_red_pulse"):
		M.call("stop_all_enemy_red_pulse")


	# --- Tutorial hook ---
	emit_signal("tutorial_event", &"end_turn_pressed", {"round": round_index})

	phase = Phase.BUSY
	_update_end_turn_button()

	# Auto-finish allies
	for u in _moved.keys():
		if u == null or not is_instance_valid(u):
			continue
		if not _moved.get(u, false):
			_moved[u] = true
		if not _attacked.get(u, false):
			_attacked[u] = true
			M.set_unit_exhausted(u, true)

	# NEW: support bots act here (before enemies)
	await _run_support_bots_phase()

	# then enemies
	await start_enemy_phase()


func _on_selection_changed(_u: Unit) -> void:
	_update_special_buttons()

func _on_aim_changed(_mode: int, _sid: StringName) -> void:
	_update_special_buttons()

func _update_end_turn_button() -> void:
	if end_turn_button == null:
		return
	# Always enabled during player phase (ITB style)
	end_turn_button.disabled = (phase != Phase.PLAYER)

func on_units_spawned() -> void:
	_update_special_buttons()
	snapshot_mission_start_squad()
	
	if _is_titan_event and not _titan_autorun_started:
		_titan_autorun_started = true
		phase = Phase.BUSY
		_update_end_turn_button()
		_update_special_buttons()
		call_deferred("_start_event_cinematic_autorun")

func _all_allies_done() -> bool:
	for u in _moved.keys():
		if u == null or not is_instance_valid(u):
			continue
		# Require: move used AND attack decision made (attack or skip)
		if not _moved.get(u, false):
			return false
		if not _attacked.get(u, false):
			return false
	return true

# -----------------------
# Gating (called by MapController)
# -----------------------
func can_select(u: Unit) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	if phase != Phase.PLAYER:
		return false
	# Only allies selectable on player turn
	if u.team != Unit.Team.ALLY:
		return false
	# Don't let player re-select units that finished both decisions
	if _moved.get(u, false) and _attacked.get(u, false):
		return false
	return true

func can_move(u: Unit) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	if phase != Phase.PLAYER:
		return false
	if u.team != Unit.Team.ALLY:
		return false
	return not _moved.get(u, false)

func can_attack(u: Unit) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	if phase != Phase.PLAYER:
		return false
	if u.team != Unit.Team.ALLY:
		return false
	# Attack decision only becomes available AFTER move (move-first rules)
	if not _moved.get(u, false):
		return false
	return not _attacked.get(u, false)

# MapController notifies us:
func notify_player_moved(u: Unit) -> void:
	if u != null and is_instance_valid(u):
		_moved[u] = true

		# If no enemies are in range, auto-skip the attack decision
		var any_target := false
		for e in M.get_all_units():
			if e.team == Unit.Team.ENEMY and M.can_attack_cell(u, e.cell):
				any_target = true
				break
		if not any_target:
			_attacked[u] = true
			M.set_unit_exhausted(u, true) # moved + no targets = done

	_update_end_turn_button()
	_update_special_buttons()


func notify_player_attacked(u: Unit) -> void:
	if u != null and is_instance_valid(u):
		_attacked[u] = true
		_moved[u] = true # attacking ends the whole unit turn
		M.set_unit_exhausted(u, true)
		
	_update_end_turn_button()
	_update_special_buttons()
	call_deferred("_refresh_population_and_check")

# If you want "skip attack" as a button later:
func skip_attack_for_selected(u: Unit) -> void:
	if phase != Phase.PLAYER:
		return
	if u == null or not is_instance_valid(u):
		return
	if not _moved.get(u, false):
		return
	_attacked[u] = true
	_update_end_turn_button()

# -----------------------
# Enemy AI
# -----------------------
func _run_enemy_turns() -> void:
	var enemies: Array[Unit] = []
	var allies: Array[Unit] = []

	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.hp <= 0:
			continue
		if u.team == Unit.Team.ENEMY:
			enemies.append(u)
		elif u.team == Unit.Team.ALLY:
			allies.append(u)

	if enemies.is_empty() or allies.is_empty():
		return

	for z in enemies:
		if z == null or not is_instance_valid(z) or z.hp <= 0:
			continue

		# Enemy acts only if IT can see an ally
		if not _enemy_can_see_any_ally(z, allies):
			continue

		await _enemy_take_turn(z)

func _enemy_in_ally_vision(z: Unit, allies: Array[Unit]) -> bool:
	var zc := z.cell

	for a in allies:
		if a == null or not is_instance_valid(a):
			continue

		# vision distance = ally movement + 3
		var vis := 0
		if "move_range" in a:
			vis = int(a.move_range) + zombie_vision
		else:
			vis = 3

		# Manhattan distance on your grid
		var d = abs(zc.x - a.cell.x) + abs(zc.y - a.cell.y)
		if d <= vis:
			return true

	return false

func _enemy_take_turn(z: Unit) -> void:
	# hard dead gate
	if z == null or not is_instance_valid(z) or z.hp <= 0:
		return

	# SUPPRESSION...
	if z.has_meta("suppress_turns") and int(z.get_meta("suppress_turns")) > 0:
		# (your existing suppression code)
		await get_tree().create_timer(0.12).timeout
		return

	# 1) Try special first (EliteMech artillery)
	if z is EliteMech:
		var did := await (z as EliteMech).ai_try_special(M)
		if did:
			return

	# 2) Otherwise do normal attack
	var target := _pick_best_attack_target(z)
	if target != null:
		await M.ai_attack(z, target)
		return


	# after awaits / damage events, check again
	if z == null or not is_instance_valid(z) or z.hp <= 0:
		return

	var move_cell := _best_move_toward_nearest_ally(z)

	# check again before moving
	if z == null or not is_instance_valid(z) or z.hp <= 0:
		return

	if move_cell != z.cell:
		await M.ai_move(z, move_cell)

	# mine could have killed it
	if z == null or not is_instance_valid(z) or z.hp <= 0:
		return

	target = _pick_best_attack_target(z)
	if target != null:
		await M.ai_attack(z, target)
		
func _pick_best_attack_target(z: Unit) -> Unit:
	var best: Unit = null
	var best_score := -999999

	for a in M.get_all_units():
		if a.team != Unit.Team.ALLY:
			continue
		if not M.can_attack_cell(z, a.cell):
			continue

		# Prefer finishing kills (lowest HP)
		var score := 100 - int(a.hp)
		if score > best_score:
			best_score = score
			best = a

	return best

func _best_move_toward_nearest_ally(z: Unit) -> Vector2i:
	var origin := z.cell
	var reachable = M.ai_reachable_cells(z)
	if reachable.is_empty():
		return origin

	var best_cell := origin
	var best_dist := 999999

	# Precompute ally cells
	var allies: Array[Vector2i] = []
	for a in M.get_all_units():
		if a.team == Unit.Team.ALLY:
			allies.append(a.cell)

	for c in reachable:
		var dmin := 999999
		for ac in allies:
			var d = abs(c.x - ac.x) + abs(c.y - ac.y)
			if d < dmin:
				dmin = d
		if dmin < best_dist:
			best_dist = dmin
			best_cell = c

	return best_cell

func player_input_allowed() -> bool:
	return phase == Phase.PLAYER

func _on_hellfire_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "hellfire"})
	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_hellfire"):
		return

	M.activate_special("hellfire")
	_update_special_buttons()

func _on_blade_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "blade"})
	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_blade"):
		return

	M.activate_special("blade")
	_update_special_buttons()

func _on_mines_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "mines"})
	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_place_mine"):
		return

	M.activate_special("mines")
	_update_special_buttons()

func _on_nova_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "nova"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return

	if not u.has_method("perform_nova"):
		return

	M.activate_special("nova")
	_update_special_buttons()

func _on_web_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "web"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return

	if not u.has_method("perform_web"):
		return

	M.activate_special("web")
	_update_special_buttons()

func _on_slam_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "slam"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return

	if not u.has_method("perform_slam"):
		return

	M.activate_special("slam")
	_update_special_buttons()

func _on_barrage_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "barrage"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_barrage"):
		return

	M.activate_special("barrage")
	_update_special_buttons()

func _on_railgun_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "railgun"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_railgun"):
		return

	M.activate_special("railgun")
	_update_special_buttons()

func _on_malfunction_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "malfunction"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_malfunction"):
		return

	M.activate_special("malfunction")
	_update_special_buttons()

func _on_storm_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "storm"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_storm"):
		return

	M.activate_special("storm")
	_update_special_buttons()

func _on_artillery_strike_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "artillery_strike"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_artillery_strike"):
		return

	M.activate_special("artillery_strike")
	_update_special_buttons()

func _on_laser_sweep_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "laser_sweep"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_laser_sweep"):
		return

	M.activate_special("laser_sweep")
	_update_special_buttons()

func _update_special_buttons() -> void:
	# Toggle visuals (pressed highlight)
	if hellfire_button: hellfire_button.toggle_mode = true
	if blade_button: blade_button.toggle_mode = true
	if mines_button: mines_button.toggle_mode = true
	if overwatch_button: overwatch_button.toggle_mode = true
	if suppress_button: suppress_button.toggle_mode = true
	if stim_button: stim_button.toggle_mode = true
	if sunder_button: sunder_button.toggle_mode = true
	if pounce_button: pounce_button.toggle_mode = true
	if volley_button: volley_button.toggle_mode = true
	if cannon_button: cannon_button.toggle_mode = true
	if quake_button: quake_button.toggle_mode = true
	if nova_button: nova_button.toggle_mode = true
	if web_button: web_button.toggle_mode = true
	if slam_button: slam_button.toggle_mode = true
	if laser_grid_button: laser_grid_button.toggle_mode = true     
	if overcharge_button: overcharge_button.toggle_mode = true  	
	if barrage_button: barrage_button.toggle_mode = true
	if railgun_button: railgun_button.toggle_mode = true
	if malfunction_button: malfunction_button.toggle_mode = true
	if storm_button: storm_button.toggle_mode = true
	if artillery_strike_button: artillery_strike_button.toggle_mode = true
	if laser_sweep_button: laser_sweep_button.toggle_mode = true
						
	# Reset
	if hellfire_button:
		hellfire_button.disabled = true
		hellfire_button.button_pressed = false
		hellfire_button.visible = false
	if blade_button:
		blade_button.disabled = true
		blade_button.button_pressed = false
		blade_button.visible = false
	if mines_button:
		mines_button.disabled = true
		mines_button.button_pressed = false
		mines_button.visible = false
	if overwatch_button:
		overwatch_button.disabled = true
		overwatch_button.button_pressed = false
		overwatch_button.visible = false
	if suppress_button:
		suppress_button.disabled = true
		suppress_button.button_pressed = false
		suppress_button.visible = false
	if stim_button:
		stim_button.disabled = true
		stim_button.button_pressed = false
		stim_button.visible = false
	if sunder_button:
		sunder_button.disabled = true
		sunder_button.button_pressed = false
		sunder_button.visible = false
	if pounce_button:
		pounce_button.disabled = true
		pounce_button.button_pressed = false
		pounce_button.visible = false
	if volley_button:
		volley_button.disabled = true
		volley_button.button_pressed = false
		volley_button.visible = false
	if cannon_button:
		cannon_button.disabled = true
		cannon_button.button_pressed = false
		cannon_button.visible = false
	if quake_button:
		quake_button.disabled = true
		quake_button.button_pressed = false
		quake_button.visible = false
	if nova_button:
		nova_button.disabled = true
		nova_button.button_pressed = false
		nova_button.visible = false
	if web_button:
		web_button.disabled = true
		web_button.button_pressed = false
		web_button.visible = false
	if slam_button:
		slam_button.disabled = true
		slam_button.button_pressed = false
		slam_button.visible = false
	if laser_grid_button:                      
		laser_grid_button.disabled = true       
		laser_grid_button.button_pressed = false 
		laser_grid_button.visible = false        
	if overcharge_button:                      
		overcharge_button.disabled = true       
		overcharge_button.button_pressed = false 
		overcharge_button.visible = false   
	if barrage_button:
		barrage_button.disabled = true
		barrage_button.button_pressed = false
		barrage_button.visible = false
	if railgun_button:
		railgun_button.disabled = true
		railgun_button.button_pressed = false
		railgun_button.visible = false			     
	if malfunction_button:
		malfunction_button.disabled = true
		malfunction_button.button_pressed = false
		malfunction_button.visible = false
	if storm_button:
		storm_button.disabled = true
		storm_button.button_pressed = false
		storm_button.visible = false		
	if artillery_strike_button:
		artillery_strike_button.disabled = true
		artillery_strike_button.button_pressed = false
		artillery_strike_button.visible = false
	if laser_sweep_button:
		laser_sweep_button.disabled = true
		laser_sweep_button.button_pressed = false
		laser_sweep_button.visible = false
									
	# Only during player phase
	if phase != Phase.PLAYER:
		return

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if u.team != Unit.Team.ALLY:
		return

	_ensure_unit_tracked(u)

	var spent_attack := bool(_attacked.get(u, false))

	# Determine what this unit has
	var has_hellfire := u.has_method("perform_hellfire")
	var has_blade := u.has_method("perform_blade")
	var has_mines := u.has_method("perform_place_mine")
	var has_overwatch := u.has_method("perform_overwatch")
	var has_suppress := u.has_method("perform_suppress")
	var has_stim := u.has_method("perform_stim")
	var has_sunder := u.has_method("perform_sunder")
	var has_pounce := u.has_method("perform_pounce")
	var has_volley := u.has_method("perform_volley")
	var has_cannon := u.has_method("perform_cannon")
	var has_quake := u.has_method("perform_quake")
	var has_nova := u.has_method("perform_nova")
	var has_web := u.has_method("perform_web")
	var has_slam := u.has_method("perform_slam") 
	var has_laser_grid := u.has_method("perform_laser_grid")         
	var has_overcharge := u.has_method("perform_overcharge") 
	var has_barrage := u.has_method("perform_barrage")
	var has_railgun := u.has_method("perform_railgun")
	var has_malfunction := u.has_method("perform_malfunction")
	var has_storm := u.has_method("perform_storm")
	var has_artillery_strike := u.has_method("perform_artillery_strike")
	var has_laser_sweep := u.has_method("perform_laser_sweep")
					
	# Optional filter list
	if u.has_method("get_available_specials"):
		var specials: Array[String] = u.get_available_specials()
		
		for i in range(specials.size()):
			specials[i] = String(specials[i]).to_lower().replace(" ", "_")
			
		has_hellfire = has_hellfire and specials.has("hellfire")
		has_blade = has_blade and specials.has("blade")
		has_mines = has_mines and specials.has("mines")
		has_overwatch = has_overwatch and specials.has("overwatch")
		has_suppress = has_suppress and specials.has("suppress")
		has_stim = has_stim and specials.has("stim")
		has_sunder = has_sunder and specials.has("sunder")
		has_pounce = has_pounce and specials.has("pounce")
		has_volley = has_volley and specials.has("volley") 
		has_cannon = has_cannon and specials.has("cannon") 
		has_quake = has_quake and specials.has("quake") 
		has_nova = has_nova and specials.has("nova")
		has_web = has_web and specials.has("web")
		has_slam = has_slam and specials.has("slam")
		has_laser_grid = has_laser_grid and specials.has("laser_grid")          
		has_overcharge = has_overcharge and specials.has("overcharge") 		
		has_barrage = has_barrage and specials.has("barrage")
		has_railgun = has_railgun and specials.has("railgun")
		has_malfunction = has_malfunction and specials.has("malfunction")
		has_storm = has_storm and specials.has("storm")
		has_artillery_strike = has_artillery_strike and specials.has("artillery_strike")
		has_laser_sweep = has_laser_sweep and specials.has("laser_sweep")
									
	# Show ONLY if unit still has an attack action available
	var show_specials := (not spent_attack)

	if hellfire_button: hellfire_button.visible = show_specials and has_hellfire
	if blade_button: blade_button.visible = show_specials and has_blade
	if mines_button: mines_button.visible = show_specials and has_mines
	if overwatch_button: overwatch_button.visible = show_specials and has_overwatch
	if suppress_button: suppress_button.visible = show_specials and has_suppress
	if stim_button: stim_button.visible = show_specials and has_stim
	if sunder_button: sunder_button.visible = show_specials and has_sunder
	if pounce_button: pounce_button.visible = show_specials and has_pounce
	if volley_button: volley_button.visible = show_specials and has_volley
	if cannon_button: cannon_button.visible = show_specials and has_cannon
	if quake_button: quake_button.visible = show_specials and has_quake
	if nova_button: nova_button.visible = show_specials and has_nova
	if web_button: web_button.visible = show_specials and has_web
	if slam_button: slam_button.visible = show_specials and has_slam
	if laser_grid_button: laser_grid_button.visible = show_specials and has_laser_grid     
	if overcharge_button: overcharge_button.visible = show_specials and has_overcharge     
	if barrage_button: barrage_button.visible = show_specials and has_barrage
	if railgun_button: railgun_button.visible = show_specials and has_railgun
	if malfunction_button: malfunction_button.visible = show_specials and has_malfunction
	if storm_button: storm_button.visible = show_specials and has_storm
	if artillery_strike_button: artillery_strike_button.visible = show_specials and has_artillery_strike
	if laser_sweep_button: laser_sweep_button.visible = show_specials and has_laser_sweep
	
	# Cooldowns
	var ok_hellfire := true
	var ok_blade := true
	var ok_mines := true
	var ok_overwatch := true
	var ok_suppress := true
	var ok_stim := true
	var ok_sunder := true
	var ok_pounce := true
	var ok_volley := true
	var ok_cannon := true
	var ok_quake := true
	var ok_nova := true
	var ok_web := true
	var ok_slam := true
	var ok_laser_grid := true          
	var ok_overcharge := true  
	var ok_barrage := true
	var ok_railgun := true
	var ok_malfunction := true
	var ok_storm := true
	var ok_artillery_strike := true
	var ok_laser_sweep := true
		
	if u.has_method("can_use_special"):
		ok_hellfire = u.can_use_special("hellfire")
		ok_blade = u.can_use_special("blade")
		ok_mines = u.can_use_special("mines")
		ok_overwatch = u.can_use_special("overwatch")
		ok_suppress = u.can_use_special("suppress")
		ok_stim = u.can_use_special("stim")
		ok_sunder = u.can_use_special("sunder")
		ok_pounce = u.can_use_special("pounce")
		ok_volley = u.can_use_special("volley")
		ok_cannon = u.can_use_special("cannon")
		ok_quake = u.can_use_special("quake")
		ok_nova = u.can_use_special("nova")
		ok_web = u.can_use_special("web")
		ok_slam = u.can_use_special("slam")
		ok_laser_grid = u.can_use_special("laser_grid")          
		ok_overcharge = u.can_use_special("overcharge")
		ok_barrage = u.can_use_special("barrage")
		ok_railgun = u.can_use_special("railgun")
		ok_malfunction = u.can_use_special("malfunction")
		ok_storm = u.can_use_special("storm")
		ok_artillery_strike = u.can_use_special("artillery_strike")
		ok_laser_sweep = u.can_use_special("laser_sweep")
		
	# Enable
	if hellfire_button: hellfire_button.disabled = spent_attack or (not has_hellfire) or (not ok_hellfire)
	if blade_button: blade_button.disabled = spent_attack or (not has_blade) or (not ok_blade)
	if mines_button: mines_button.disabled = spent_attack or (not has_mines) or (not ok_mines)
	if overwatch_button: overwatch_button.disabled = spent_attack or (not has_overwatch) or (not ok_overwatch)
	if suppress_button: suppress_button.disabled = spent_attack or (not has_suppress) or (not ok_suppress)
	if stim_button: stim_button.disabled = spent_attack or (not has_stim) or (not ok_stim)
	if sunder_button: sunder_button.disabled = spent_attack or (not has_sunder) or (not ok_sunder)
	if pounce_button: pounce_button.disabled = spent_attack or (not has_pounce) or (not ok_pounce)
	if volley_button: volley_button.disabled = spent_attack or (not has_volley) or (not ok_volley)
	if cannon_button: cannon_button.disabled = spent_attack or (not has_cannon) or (not ok_cannon)
	if quake_button: quake_button.disabled = spent_attack or (not has_quake) or (not ok_quake)
	if nova_button: nova_button.disabled = spent_attack or (not has_nova) or (not ok_nova)
	if web_button: web_button.disabled = spent_attack or (not has_web) or (not ok_web)
	if slam_button: slam_button.disabled = spent_attack or (not has_slam) or (not ok_slam)
	if laser_grid_button: laser_grid_button.disabled = spent_attack or (not has_laser_grid) or (not ok_laser_grid)     
	if overcharge_button: overcharge_button.disabled = spent_attack or (not has_overcharge) or (not ok_overcharge)
	if barrage_button: barrage_button.disabled = spent_attack or (not has_barrage) or (not ok_barrage)
	if railgun_button: railgun_button.disabled = spent_attack or (not has_railgun) or (not ok_railgun)
	if malfunction_button: malfunction_button.disabled = spent_attack or (not has_malfunction) or (not ok_malfunction)
	if storm_button: storm_button.disabled = spent_attack or (not has_storm) or (not ok_storm)
	if artillery_strike_button: artillery_strike_button.disabled = spent_attack or (not has_artillery_strike) or (not ok_artillery_strike)
	if laser_sweep_button: laser_sweep_button.disabled = spent_attack or (not has_laser_sweep) or (not ok_laser_sweep)

	# Note: need to handle underscores in special_id comparison
	var active := ""
	if M.aim_mode == MapController.AimMode.SPECIAL:
		active = String(M.special_id).to_lower().replace(" ", "_")     # MODIFY THIS LINE

	if hellfire_button and not hellfire_button.disabled:
		hellfire_button.button_pressed = (active == "hellfire")
	if blade_button and not blade_button.disabled:
		blade_button.button_pressed = (active == "blade")
	if mines_button and not mines_button.disabled:
		mines_button.button_pressed = (active == "mines")
	if suppress_button and not suppress_button.disabled:
		suppress_button.button_pressed = (active == "suppress")
	if sunder_button and not sunder_button.disabled:
		sunder_button.button_pressed = (active == "sunder")
	if pounce_button and not pounce_button.disabled:
		pounce_button.button_pressed = (active == "pounce")
	if volley_button and not volley_button.disabled:
		volley_button.button_pressed = (active == "volley")
	if cannon_button and not cannon_button.disabled:
		cannon_button.button_pressed = (active == "cannon")
	if quake_button and not quake_button.disabled:
		quake_button.button_pressed = (active == "quake")
	if nova_button and not nova_button.disabled:
		nova_button.button_pressed = (active == "nova")
	if web_button and not web_button.disabled:
		web_button.button_pressed = (active == "web")
	if slam_button and not slam_button.disabled:
		slam_button.button_pressed = (active == "slam")
	if laser_grid_button and not laser_grid_button.disabled:                      
		laser_grid_button.button_pressed = (active == "laser_grid")                
	if overcharge_button and not overcharge_button.disabled:                      
		overcharge_button.button_pressed = (active == "overcharge") 
	if barrage_button and not barrage_button.disabled:
		barrage_button.button_pressed = (active == "barrage")
	if railgun_button and not railgun_button.disabled:
		railgun_button.button_pressed = (active == "railgun")
	if malfunction_button and not malfunction_button.disabled:
		malfunction_button.button_pressed = (active == "malfunction")
	if storm_button and not storm_button.disabled:
		storm_button.button_pressed = (active == "storm")
	if artillery_strike_button and not artillery_strike_button.disabled:
		artillery_strike_button.button_pressed = (active == "artillery_strike")
	if laser_sweep_button and not laser_sweep_button.disabled:
		laser_sweep_button.button_pressed = (active == "laser_sweep")

	# --- Apply colors based on pressed state ---
	_skin_special_button(hellfire_button, hellfire_button.button_pressed if hellfire_button else false)
	_skin_special_button(blade_button, blade_button.button_pressed if blade_button else false)
	_skin_special_button(mines_button, mines_button.button_pressed if mines_button else false)
	_skin_special_button(overwatch_button, overwatch_button.button_pressed if overwatch_button else false)
	_skin_special_button(suppress_button, suppress_button.button_pressed if suppress_button else false)
	_skin_special_button(stim_button, stim_button.button_pressed if stim_button else false)
	_skin_special_button(sunder_button, sunder_button.button_pressed if sunder_button else false)
	_skin_special_button(pounce_button, pounce_button.button_pressed if pounce_button else false)
	_skin_special_button(volley_button, volley_button.button_pressed if volley_button else false)
	_skin_special_button(cannon_button, cannon_button.button_pressed if cannon_button else false)
	_skin_special_button(quake_button, quake_button.button_pressed if quake_button else false)
	_skin_special_button(nova_button, nova_button.button_pressed if nova_button else false)
	_skin_special_button(web_button, web_button.button_pressed if web_button else false)
	_skin_special_button(slam_button, slam_button.button_pressed if slam_button else false)
	_skin_special_button(laser_grid_button, laser_grid_button.button_pressed if laser_grid_button else false)          
	_skin_special_button(overcharge_button, overcharge_button.button_pressed if overcharge_button else false)   
	_skin_special_button(barrage_button, barrage_button.button_pressed if barrage_button else false)
	_skin_special_button(railgun_button, railgun_button.button_pressed if railgun_button else false)
	_skin_special_button(malfunction_button, malfunction_button.button_pressed if malfunction_button else false)
	_skin_special_button(storm_button,storm_button.button_pressed if storm_button else false)	
	_skin_special_button(artillery_strike_button, artillery_strike_button.button_pressed if artillery_strike_button else false)
	_skin_special_button(laser_sweep_button, laser_sweep_button.button_pressed if laser_sweep_button else false)
						
	# Overwatch + Stim are instant toggles
	if overwatch_button and not overwatch_button.disabled:
		if M != null and M.has_method("is_overwatching"):
			overwatch_button.button_pressed = bool(M.call("is_overwatching", u))
		else:
			overwatch_button.button_pressed = false

	# --- Stim button pressed state ---
	if stim_button and not stim_button.disabled:
		stim_button.button_pressed = (
			u.has_meta("stim_turns")
			and int(u.get_meta("stim_turns")) > 0
		)

func _skin_special_button(btn: BaseButton, selected: bool) -> void:
	if btn == null:
		return

	btn.toggle_mode = true # needed for button_pressed visuals

	var normal_bg := Color(0.10, 0.10, 0.12, 0.85)
	var selected_bg := Color(0.20, 0.85, 0.35, 0.95)
	var normal_text := Color(0.90, 0.90, 0.92, 1.0)
	var selected_text := Color(0.05, 0.05, 0.05, 1.0)

	var sb := StyleBoxFlat.new()
	sb.bg_color = selected_bg if selected else normal_bg
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6

	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)

	btn.add_theme_color_override("font_color", selected_text if selected else normal_text)
	btn.add_theme_color_override("font_hover_color", selected_text if selected else normal_text)
	btn.add_theme_color_override("font_pressed_color", selected_text if selected else normal_text)

func _auto_select_first_ally() -> void:
	# Keep current selection if it's valid + selectable
	if M.selected != null and is_instance_valid(M.selected) and can_select(M.selected):
		return

	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team != Unit.Team.ALLY:
			continue
		if can_select(u):
			M.select_unit(u) # your MapController select method
			return

func _ensure_unit_tracked(u: Unit) -> void:
	if u == null or not is_instance_valid(u):
		return
	if u.team != Unit.Team.ALLY:
		return
	if not _moved.has(u):
		_moved[u] = false
	if not _attacked.has(u):
		_attacked[u] = false

func _on_overwatch_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "overwatch"})
	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_overwatch"):
		return

	M.activate_special("overwatch") # instant special (your MapController handles instant)
	_update_special_buttons()

func _on_suppress_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "suppress"})
	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_suppress"):
		return

	M.activate_special("suppress")
	_update_special_buttons()

func _on_stim_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "stim"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_stim"):
		return

	# Fire instantly
	M.activate_special("stim")

	_update_special_buttons()


func _on_sunder_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "sunder"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_sunder"):
		return

	M.activate_special("sunder")
	_update_special_buttons()

func _tick_buffs_enemy_phase_start() -> void:
	var changed := false

	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue

		# tick elite special cooldowns
		if u is EliteMech:
			(u as EliteMech).tick_cooldowns()
			
		# Stim ticks down on ENEMY phase start
		if u.has_meta("stim_turns"):
			var t := int(u.get_meta("stim_turns"))
			if t > 0:
				t -= 1
				u.set_meta("stim_turns", t)
				changed = true

			# When it hits 0, fully clear (so UI + logic read clean)
			if t <= 0:
				# --- revert stats ---
				var mb := int(u.get_meta(&"stim_move_bonus")) if u.has_meta(&"stim_move_bonus") else 0
				if mb != 0 and "move_range" in u:
					u.move_range = int(u.move_range) - mb

				var adb := int(u.get_meta(&"stim_attack_damage_bonus")) if u.has_meta(&"stim_attack_damage_bonus") else 0
				if adb != 0 and "attack_damage" in u:
					u.attack_damage = int(u.attack_damage) - adb

				# --- clear shader / material ---
				var ci: CanvasItem = null
				if u.has_method("_get_unit_render_node"):
					ci = u.call("_get_unit_render_node")
				if ci != null and is_instance_valid(ci):
					ci.material = null

				# --- clear metas ---
				u.set_meta(&"stim_turns", 0)
				u.set_meta(&"stim_move_bonus", 0)
				u.set_meta(&"stim_attack_damage_bonus", 0)
				u.set_meta(&"stim_damage_bonus", 0) # keep if you still reference it elsewhere
				changed = true


	# If any buff state changed, refresh special buttons now
	if changed:
		_update_special_buttons()

func _try_end_player_phase_if_done() -> void:
	if M == null:
		return
	if _all_allies_done():
		await _run_support_bots_phase()
		await start_enemy_phase()

func _run_support_bots_phase() -> void:
	var prev := phase
	phase = Phase.BUSY
	_update_end_turn_button()
	_update_special_buttons()

	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team != Unit.Team.ALLY:
			continue

		# If you want cars to still “idle rumble” even with no enemies,
		# do NOT break here. Otherwise keep this.
		if M.get_all_enemies().is_empty():
			break

		if u.has_method("auto_support_action"):
			await u.call("auto_support_action", M)   # RecruitBot
		elif u.has_method("auto_roll_action"):
			await u.call("auto_roll_action", M)      # Rollerbot
		elif u.has_method("auto_drive_action"):
			await u.call("auto_drive_action", M)     # CarBot

	phase = prev
	_update_end_turn_button()
	_update_special_buttons()

func _on_pounce_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "pounce"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_pounce"):
		return

	M.activate_special("pounce")
	_update_special_buttons()

func _on_volley_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "volley"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return

	# R1 uses perform_volley (or whatever you named it)
	if not u.has_method("perform_volley"):
		return

	M.activate_special("volley")
	_update_special_buttons()

func _on_cannon_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "cannon"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return

	# R1 uses perform_volley (or whatever you named it)
	if not u.has_method("perform_cannon"):
		return

	M.activate_special("cannon")
	_update_special_buttons()

func _on_quake_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "quake"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return

	# R1 uses perform_volley (or whatever you named it)
	if not u.has_method("perform_quake"):
		return

	M.activate_special("quake")
	_update_special_buttons()

func _on_laser_grid_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "laser_grid"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return

	if not u.has_method("perform_laser_grid"):
		return

	M.activate_special("laser_grid")
	_update_special_buttons()

func _on_overcharge_pressed() -> void:
	if phase != Phase.PLAYER:
		return
	emit_signal("tutorial_event", &"special_button_pressed", {"id": "overcharge"})

	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return

	if not u.has_method("perform_overcharge"):
		return

	M.activate_special("overcharge")
	_update_special_buttons()

func _on_menu_pressed() -> void:
	print("MENU PRESSED -> changing scene to: ", title_scene_path)
	print("exists? ", ResourceLoader.exists(title_scene_path))

	if title_scene_path == "" or not ResourceLoader.exists(title_scene_path):
		push_error("TurnManager: title_scene_path missing or invalid: %s" % title_scene_path)
		return

	get_tree().paused = false
	get_tree().change_scene_to_file(title_scene_path)


enum LossMode { TO_MENU, RESTART_MISSION }
var _loss_mode: LossMode = LossMode.TO_MENU
var _mission_start_squad_paths: Array[String] = []

func snapshot_mission_start_squad() -> void:
	_mission_start_squad_paths.clear()

	var tree := get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return

	var rs := tree.root.get_node_or_null("RunState")
	if rs == null:
		rs = tree.root.get_node_or_null("RunStateNode")
	if rs == null:
		return

	if "squad_scene_paths" in rs:
		for p in rs.squad_scene_paths:
			_mission_start_squad_paths.append(str(p))

func game_over(msg: String) -> void:
	if _game_over_triggered:
		return
	_game_over_triggered = true

	print(msg)
	phase = Phase.BUSY
	_update_end_turn_button()
	_update_special_buttons()
	_set_hud_visible(false)

	if end_panel != null and is_instance_valid(end_panel):
		end_panel.show_loss(msg)

		if end_panel.continue_button != null:
			if _loss_mode == LossMode.RESTART_MISSION:
				end_panel.continue_button.text = "RETRY"
			else:
				end_panel.continue_button.text = "MAIN MENU"
			end_panel.continue_button.disabled = false

		end_panel._picked = true

		# Disconnect old (prevents stacking)
		if end_panel.continue_pressed.is_connected(_on_game_over_main_menu):
			end_panel.continue_pressed.disconnect(_on_game_over_main_menu)
		if end_panel.continue_pressed.is_connected(_on_game_over_retry):
			end_panel.continue_pressed.disconnect(_on_game_over_retry)

		# Connect correct
		if _loss_mode == LossMode.RESTART_MISSION:
			end_panel.continue_pressed.connect(_on_game_over_retry)
		else:
			end_panel.continue_pressed.connect(_on_game_over_main_menu)

func _on_game_over_retry() -> void:
	var tree := get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("No SceneTree available.")
		return

	# Restore squad to what it was at mission start
	var rs := tree.root.get_node_or_null("RunState")
	if rs == null:
		rs = tree.root.get_node_or_null("RunStateNode")

	if rs != null and "squad_scene_paths" in rs:
		rs.squad_scene_paths.clear()
		rs.squad_scene_paths.append_array(_mission_start_squad_paths)

		# Optional: undo any deaths that occurred during the failed mission
		# (only if you want infestation loss to NOT cause permadeath)
		if "dead_scene_paths" in rs:
			for p in _mission_start_squad_paths:
				rs.dead_scene_paths.erase(p)

		if rs.has_method("save_to_disk"):
			rs.call("save_to_disk")

	# Reload the current mission scene
	tree.reload_current_scene()

func _on_game_over_main_menu() -> void:
	# Always get a valid SceneTree first (your node might not be in-tree)
	var tree := get_tree()
	if tree == null:
		tree = Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("No SceneTree available.")
		return

	# 1) Reset runstate so a new run starts fresh (all units usable again)
	var rs := tree.root.get_node_or_null("RunState")
	if rs == null:
		rs = tree.root.get_node_or_null("RunStateNode")

	if rs != null:
		if rs.has_method("reset_run"):
			rs.call("reset_run")
		if rs.has_method("save_to_disk"):
			rs.call("save_to_disk")
	else:
		push_warning("GameOver: RunState not found; run may not fully reset.")

	# 2) Go to title screen
	tree.change_scene_to_file("res://scenes/title_screen.tscn")

func _wait_for_units_then_enable_loss_checks() -> void:
	if _game_over_triggered:
		return
	if M == null:
		return

	var units := M.get_all_units()
	if units != null and not units.is_empty():
		# We have units in the scene — safe to start evaluating.
		loss_checks_enabled = true

		# Start boss ONLY once, only if enabled
		if boss_mode_enabled and (boss == null or not is_instance_valid(boss)):
			start_boss_battle()

		call_deferred("_refresh_population_and_check")
		return

	_spawn_wait_tries += 1
	if _spawn_wait_tries >= _SPAWN_WAIT_MAX_TRIES:
		# Give up quietly; we'll re-enable later when something happens (kills/spawns/end turn)
		return

	# Try again next frame
	call_deferred("_wait_for_units_then_enable_loss_checks")


func start_boss_battle() -> void:
	if M == null or boss_controller_scene == null:
		return

	if boss != null and is_instance_valid(boss):
		boss.queue_free()

	boss = boss_controller_scene.instantiate() as BossController

	# Put boss behind grid visually
	# (Add as child of something behind the grid if you have a specific node for it)
	add_child(boss)
	boss.z_index = -1000

	boss.setup(M)

	if not boss.boss_defeated.is_connected(_on_boss_defeated):
		boss.boss_defeated.connect(_on_boss_defeated)

func _on_boss_defeated() -> void:
	phase = Phase.BUSY
	_update_end_turn_button()
	_update_special_buttons()

	# Save runstate flags now (fine)
	var rs := get_tree().root.get_node_or_null("RunStateNode")
	if rs != null:
		rs.boss_defeated_this_run = true
		rs.bomber_unlocked_this_run = true
		rs.boss_mode_enabled_next_mission = false
		if "overworld_cleared" in rs:
			rs.overworld_cleared[str(int(rs.overworld_current_node_id))] = true

	# Wait for boss outro tween to finish BEFORE changing scenes
	if boss != null and is_instance_valid(boss):
		if boss.has_signal("boss_outro_finished"):
			# If not already connected, connect once
			var done := false
			var cb := func(): done = true
			var callable := Callable(cb)
			if not boss.boss_outro_finished.is_connected(callable):
				boss.boss_outro_finished.connect(callable)

			# Frame-based wait (no timers)
			while not done:
				if boss == null or not is_instance_valid(boss):
					break
				var st := boss.get_tree()
				if st == null:
					break
				await st.process_frame

			if boss != null and is_instance_valid(boss) and boss.boss_outro_finished.is_connected(callable):
				boss.boss_outro_finished.disconnect(callable)

	# NOW go back to overworld
	await M._extract_allies_with_bomber()
	get_tree().change_scene_to_file("res://scenes/overworld.tscn")

func _get_vision(u: Unit) -> int:
	if u != null and is_instance_valid(u) and u.has_meta("vision"):
		return int(u.get_meta("vision"))
	# fallback: your old rule of thumb
	return int(u.move_range) + zombie_vision

func _enemy_can_see_any_ally(z: Unit, allies: Array[Unit]) -> bool:
	var vis := _get_vision(z)
	var zc := z.cell

	for a in allies:
		if a == null or not is_instance_valid(a) or a.hp <= 0:
			continue
		var d = abs(zc.x - a.cell.x) + abs(zc.y - a.cell.y)
		if d <= vis:
			return true

	return false

func _titan_event_setup() -> void:
	if M == null:
		return

	# despawn enemies silently (no death => no drops)
	var to_remove: Array = []
	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team == Unit.Team.ENEMY:
			to_remove.append(u)

	# if an enemy was selected, clear selection first
	if M.selected != null and is_instance_valid(M.selected) and M.selected.team == Unit.Team.ENEMY:
		M.selected = null

	for u in to_remove:
		# remove from grid registry so MapController doesn't keep a dead reference
		if "units_by_cell" in M:
			var c: Vector2i = u.cell
			if M.units_by_cell.has(c) and M.units_by_cell[c] == u:
				M.units_by_cell.erase(c)

		# free without triggering death logic
		u.queue_free()


	# Disable normal pacing
	beacon_deadline_round = 999999
	spawn_base = 0
	spawn_per_round = 0
	spawn_bonus_every = 0
	spawn_bonus_amount = 0

	# Spawn Titan mech
	if titan_mech_scene != null:
		titan_mech = titan_mech_scene.instantiate() as Node2D
		if titan_mech != null:
			# Add ABOVE terrain but BELOW UI
			var tm := M.terrain
			if tm != null and is_instance_valid(tm):
				var parent := tm.get_parent()
				if parent != null:
					parent.add_child(titan_mech)
				else:
					add_child(titan_mech) # fallback
			else:
				add_child(titan_mech) # fallback

			# Put it behind the terrain tilemap
			titan_mech.z_index = tm.z_index - 10 if tm != null else -99999

			# Position it just off-map (top-right isometric corner)
			_position_titan_off_map()
	
	_clear_titan_markers()

func _position_titan_off_map() -> void:
	if titan_mech == null:
		return

	var apex := _map_top_apex_world()
	var center_local := _titan_visual_center_local()

	# Put the Titan so its visual center sits on the map apex
	titan_mech.global_position = apex - center_local

func _clear_titan_markers() -> void:
	for m in _titan_markers:
		if m != null and is_instance_valid(m):
			m.queue_free()
	_titan_markers.clear()

func _titan_cell_to_world(cell: Vector2i) -> Vector2:
	if M == null or M.terrain == null:
		return Vector2.ZERO
	return M.terrain.to_global(M.terrain.map_to_local(cell))

func _titan_spawn_marker(cell: Vector2i) -> void:
	if M == null or M.terrain == null:
		return
	if M.attack_tile_scene == null:
		return

	var marker := M.attack_tile_scene.instantiate() as Node2D
	if marker == null:
		return

	# iso depth: same rule as units / overlays
	marker.z_index = cell.x + cell.y

	# position on grid
	marker.global_position = M.terrain.to_global(
		M.terrain.map_to_local(cell)
	)

	# put it with other overlays if possible
	if M.overlay_root != null:
		M.overlay_root.add_child(marker)
	else:
		add_child(marker)

	_titan_markers.append(marker)

func _titan_apply_strike(cell: Vector2i) -> void:
	# Explosion visual (optional)
	if titan_explosion_scene != null:
		var e := titan_explosion_scene.instantiate() as Node2D
		if e != null:
			e.global_position = _titan_cell_to_world(cell)
			e.global_position.y -= 16
			add_child(e)

	# Damage any unit in that cell
	if M == null:
		return

	for u in M.get_all_units():
		if u == null or not is_instance_valid(u) or u.hp <= 0:
			continue
		if u.cell == cell:
			u.take_damage(titan_strike_damage)

func _titan_overwatch_enemy_phase() -> void:
	# PATTERN + DOUBLING strikes per turn: 1,2,4,8,16...
	_clear_titan_markers()

	# Gather allies (fail-safe)
	var allies: Array[Unit] = []
	for u in M.get_all_units():
		if u == null or not is_instance_valid(u) or u.hp <= 0:
			continue
		if u.team == Unit.Team.ALLY:
			allies.append(u)

	if allies.is_empty():
		# bomber deploy can cause a brief window where no allies are placed yet
		var ok := await _wait_until_allies_placed(60) # ~1 sec @60fps
		
		allies.clear()
		for u in M.get_all_units():
			if u != null and is_instance_valid(u) and u.hp > 0 and u.team == Unit.Team.ALLY:
				allies.append(u)
		
		if not ok:
			game_over("No allies remaining.")
			return


	# -----------------------------
	# Pick strike cells (patterned)
	# -----------------------------
	_event_turn += 1  # drives doubling curve

	var n := _event_cells_this_turn()              # 1,2,4,8,16 (clamped)
	var pattern := _pick_pattern()
	var cands := _pattern_candidates(pattern)

	# Optional: bias candidates toward ally region a bit (keeps it tense)
	# If you DON'T want bias, delete this whole block.
	var pad := 4
	var minx := 999
	var miny := 999
	var maxx := -999
	var maxy := -999
	for a in allies:
		minx = min(minx, a.cell.x)
		miny = min(miny, a.cell.y)
		maxx = max(maxx, a.cell.x)
		maxy = max(maxy, a.cell.y)

	var x0 := minx - pad
	var x1 := maxx + pad
	var y0 := miny - pad
	var y1 := maxy + pad

	var w := int(M.grid.w)
	var h := int(M.grid.h)

	# Filter candidates to a padded ally box, but keep a fallback if it becomes empty.
	var boxed: Array[Vector2i] = []
	for c in cands:
		if c.x < 0 or c.y < 0 or c.x >= w or c.y >= h:
			continue
		if c.x < x0 or c.x > x1 or c.y < y0 or c.y > y1:
			continue
		boxed.append(c)

	var pool := boxed if not boxed.is_empty() else cands
	var cells := _choose_cells(pool, n)

	# --------------------------------
	# Preview (your existing markers)
	# --------------------------------
	for c in cells:
		_titan_spawn_marker(c)

	# SFX fire (optional)
	if M != null and M.has_method("_sfx"):
		M.call("_sfx", titan_sfx_fire, 1.0, 1.0, Vector2.ZERO)

	# wait briefly before impact
	var t := 0.0
	while t < titan_warn_time:
		await get_tree().process_frame
		t += get_process_delta_time()

	# -------------------
	# Impact (damage)
	# -------------------
	for c in cells:
		_titan_apply_strike(c)

	if M != null and M.has_method("_sfx"):
		M.call("_sfx", titan_sfx_explode, 1.0, 1.0, Vector2.ZERO)

	call_deferred("_refresh_population_and_check")
	if _game_over_triggered:
		return

	# advance event counter
	_titan_turns_left -= 1

	# still advance rounds so your UI keeps moving
	round_index += 1

	# success!
	if _titan_turns_left <= 0:
		await _titan_event_success()
		return

	# auto-continue (no player phase)
	if not _game_over_triggered:
		call_deferred("_start_titan_event_autorun")
		
func _wait_until_allies_placed(max_frames := 60) -> bool:
	var frames := 0
	while frames < max_frames:
		if M != null and "units_by_cell" in M:
			for u in M.get_all_units():
				if u == null or not is_instance_valid(u) or u.hp <= 0:
					continue
				if u.team != Unit.Team.ALLY:
					continue
				# "placed" means registered on the grid
				if M.units_by_cell.has(u.cell) and M.units_by_cell[u.cell] == u:
					return true
		frames += 1
		await get_tree().process_frame
	return false

func _titan_event_success() -> void:
	phase = Phase.BUSY
	_update_end_turn_button()
	_update_special_buttons()

	_clear_titan_markers()

	# despawn Titan
	if titan_mech != null and is_instance_valid(titan_mech):
		await _fade_and_free(titan_mech, 1.5)
		titan_mech = null

	# mark overworld node cleared
	var rs := get_tree().root.get_node_or_null("RunStateNode")
	if rs != null and ("overworld_cleared" in rs):
		rs.overworld_cleared[str(int(rs.overworld_current_node_id))] = true

	if M != null and M.has_method("_extract_allies_with_bomber"):
		await M._extract_allies_with_bomber()
		emit_signal("tutorial_event", &"extraction_finished", {})
			
	#get_tree().change_scene_to_file("res://scenes/overworld.tscn")

func _map_top_apex_world() -> Vector2:
	if M == null or M.terrain == null:
		return Vector2.ZERO
	var tm := M.terrain
	# cell (0,0) is the top corner in your generated maps
	var p := tm.to_global(tm.map_to_local(Vector2i(0, 0)))
	# small nudge upward to hit the "point" of the diamond
	return p + Vector2(0, -16)

func _titan_visual_center_local() -> Vector2:
	if titan_mech == null or not is_instance_valid(titan_mech):
		return Vector2.ZERO

	# 1) Prefer AnimatedSprite2D if present (your case)
	var a := titan_mech.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if a != null and a.sprite_frames != null:
		var tex := a.sprite_frames.get_frame_texture(a.animation, a.frame)
		if tex != null:
			# AnimatedSprite2D is typically drawn centered on its position
			# (there is no "centered" toggle like Sprite2D)
			return a.position

	# 2) Fallback: Sprite2D
	var s := titan_mech.get_node_or_null("Sprite2D") as Sprite2D
	if s != null and s.texture != null:
		if s.centered:
			return s.position
		else:
			return s.position + s.texture.get_size() * 0.5

	# 3) Generic fallback: use CanvasItem bounding boxes *only for types that support it*
	# (Control has get_rect; Node2D sprites don't)
	var rect := Rect2()
	var first := true

	for ch in titan_mech.get_children():
		if ch is Control:
			var c := ch as Control
			var r := c.get_rect()
			r.position += c.position
			if first:
				rect = r
				first = false
			else:
				rect = rect.merge(r)

	if not first:
		return rect.position + rect.size * 0.5

	# 4) Last fallback
	return Vector2.ZERO

func _fade_and_free(node: CanvasItem, time := 0.35) -> void:
	if node == null or not is_instance_valid(node):
		return

	var tw := create_tween()
	tw.tween_property(node, "modulate:a", 0.0, time)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

	await tw.finished
	if node != null and is_instance_valid(node):
		node.queue_free()

func _clear_titan_markers_fade() -> void:
	for m in _titan_markers:
		if m != null and is_instance_valid(m):
			_fade_and_free(m, 0.25)
	_titan_markers.clear()

func _event_cells_this_turn() -> int:
	var n := event_base_cells * int(pow(2.0, float(_event_turn)))
	return clampi(n, 1, event_max_cells)

func _start_titan_event_autorun() -> void:
	if _game_over_triggered:
		return
	if not _is_titan_event:
		return

	# lock input
	phase = Phase.BUSY
	_update_end_turn_button()
	_update_special_buttons()

	# wait for allies to actually exist
	var ok := await _wait_until_allies_exist()
	if not ok:
		game_over("No allies remaining.")
		return

	await get_tree().create_timer(0.1).timeout
	
	# now run the first titan phase
	await _titan_overwatch_enemy_phase()

func _start_event_cinematic_autorun() -> void:
	if _game_over_triggered:
		return
	if not _is_titan_event:
		return
	if M == null:
		return

	# lock input
	phase = Phase.BUSY
	_update_end_turn_button()
	_update_special_buttons()

	# Make sure allies exist (deployment/fade windows)
	var ok := await _wait_until_allies_exist()
	if not ok:
		game_over("No allies remaining.")
		return

	# Remove enemies + stop spawns for the cinematic
	_event_cinematic_setup_no_enemies()

	# Run the dialogue + movement beats
	await _run_event_cinematic_sequence()

	# Fade out + evac (your existing flow)
	await _titan_event_success()

func _event_cinematic_setup_no_enemies() -> void:
	if M == null:
		return

	# despawn enemies silently (no drops)
	var to_remove: Array[Unit] = []
	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.team == Unit.Team.ENEMY:
			to_remove.append(u)

	# clear selection if it was an enemy
	if M.selected != null and is_instance_valid(M.selected) and M.selected.team == Unit.Team.ENEMY:
		M.selected = null

	for u in to_remove:
		if u == null or not is_instance_valid(u):
			continue

		# remove from grid registry so we don't leave dead references
		if "units_by_cell" in M:
			var c: Vector2i = u.cell
			if M.units_by_cell.has(c) and M.units_by_cell[c] == u:
				M.units_by_cell.erase(c)

		u.queue_free()

	# disable normal pacing / spawns during event
	beacon_deadline_round = 999999
	spawn_base = 0
	spawn_per_round = 0
	spawn_bonus_every = 0
	spawn_bonus_amount = 0

func _event_beat(sec: float) -> void:
	if M == null:
		return
	var tree := M.get_tree()
	if tree == null:
		return
	await tree.create_timer(sec).timeout

func _run_event_cinematic_sequence() -> void:
	if M == null:
		return
	
	await get_tree().create_timer(5).timeout
	
	# -------- pacing knobs (TUNE THESE) --------
	var beat_short := 0.65
	var beat_med   := 0.95
	var beat_long  := 1.30
	var run_step_beat := 0.08   # pause between each step (movement speed)
	# -------------------------------------------

	# Gather allies (stable order)
	var allies: Array[Unit] = []
	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue
		if u.hp <= 0:
			continue
		if u.team == Unit.Team.ALLY:
			allies.append(u)

	if allies.is_empty():
		return

	# Pick speakers
	var a0: Unit = allies[0]
	var a1: Unit = allies[1] if allies.size() > 1 else a0
	var a2: Unit = allies[2] if allies.size() > 2 else a0

	# -------------------------------------------------------
	# 1) LONG MOVEMENT FIRST: run toward the TOP of the map
	# -------------------------------------------------------
	# pick a "top lane" target y (keep a little padding)
	var top_y := 1

	# decide how many steps to try (big run)
	# This is intentionally a lot; steps that fail will just do nothing if _cinematic_step blocks.
	var steps := 2

	# Move them in a staggered "column" feel: a0 then a1 then a2, repeat
	for i in range(steps):
		await _cinematic_step(a0, Vector2i(0, -1))
		await _event_beat(run_step_beat)

		await _cinematic_step(a1, Vector2i(0, -1))
		await _event_beat(run_step_beat)

		await _cinematic_step(a2, Vector2i(0, -1))
		await _event_beat(run_step_beat)

		# little breath pauses mid-run so it reads as "distance"
		if i == 2:
			await _event_beat(0.35)
		if i == 5:
			await _event_beat(0.45)

		# optional: stop early if lead unit reached top band
		if a0 != null and is_instance_valid(a0) and a0.cell.y <= top_y:
			break

	# small settle pause at destination
	await _event_beat(0.60)

# -------------------
	# 2) Dialogue beats
	# -------------------
	await M._say(a0, "...do you feel that vibration?")
	await _event_beat(beat_med)
	await M._say(a1, "Yeah. Not thunder.")
	await _event_beat(beat_short)
	await M._say(a2, "Something big is moving out there.")
	await _event_beat(beat_long)
	# --- Cinematic movement (your original) ---
	await _cinematic_step(a0, Vector2i(1, 0))
	await _event_beat(0.25)
	await _cinematic_step(a1, Vector2i(1, 0))
	await _event_beat(0.35)
	await M._say(a0, "Keep it tight... and your eyes up.")
	await _event_beat(beat_med)
	await M._say(a1, "That silhouette... a giant mecha?")
	await _event_beat(beat_long)
	await M._say(a2, "We are not equipped for that.")
	await _event_beat(beat_med)
	# Step back like they're backing off
	await _cinematic_step(a0, Vector2i(-1, 0))
	await _event_beat(0.25)
	await _cinematic_step(a1, Vector2i(-1, 0))
	await _event_beat(0.35)
	await M._say(a0, "No fight. Get ready to leave now.")
	await _event_beat(beat_med)
	await M._say(a2, "Bomber, get us out of here!")
	await _event_beat(beat_long)

func _cinematic_step(u: Unit, _delta_unused: Vector2i = Vector2i.ZERO) -> void:
	if M == null:
		return
	if u == null or not is_instance_valid(u):
		return
	if u.hp <= 0:
		return

	# -------- get move range (same pattern you use elsewhere) --------
	var r := 0
	if u.has_method("get_move_range"):
		r = int(u.call("get_move_range"))
	elif "move_range" in u:
		r = int(u.move_range)
	if r <= 0:
		return

	# -------- collect candidate destination tiles --------
	var origin := u.cell
	var candidates: Array[Vector2i] = []

	# Optional: structure blocking (same pattern as MapController)
	var structure_blocked: Dictionary = {}
	if "game_ref" in M and M.game_ref != null and "structure_blocked" in M.game_ref:
		structure_blocked = M.game_ref.structure_blocked

	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var dist = abs(dx) + abs(dy)
			if dist == 0 or dist > r:
				continue

			var dst := origin + Vector2i(dx, dy)

			# bounds
			if M.grid != null and M.grid.has_method("in_bounds"):
				if not bool(M.grid.in_bounds(dst)):
					continue

			# walkable
			if M.has_method("_is_walkable"):
				if not bool(M.call("_is_walkable", dst)):
					continue

			# blocked by structures (if you track this)
			if structure_blocked.has(dst):
				continue

			# occupied (avoid clipping)
			if "units_by_cell" in M and M.units_by_cell.has(dst):
				continue

			candidates.append(dst)

	if candidates.is_empty():
		return

	# randomize + pick one
	candidates.shuffle()
	var picked := candidates[0]

	# Prefer your real movement pipeline
	if M.has_method("ai_move_free"):
		await M.ai_move_free(u, picked)
		return

	# Fallback: tiny tween nudge (visual only)
	var start := u.global_position
	var end := start + Vector2(16, 8)
	var tw := create_tween()
	tw.tween_property(u, "global_position", end, 0.18)
	await tw.finished

func _set_hud_visible(v: bool) -> void:
	# ✅ Hide ALL special buttons (group-based)
	for n in get_tree().get_nodes_in_group("SpecialButton"):
		if n == null or not is_instance_valid(n):
			continue
		if n is CanvasItem:
			(n as CanvasItem).visible = false
		elif n is Node:
			# fallback if it's not a CanvasItem for some reason
			if "visible" in n:
				n.visible = false
					
	# End turn + menu buttons
	if end_turn_button != null:
		end_turn_button.visible = v
	if menu_button != null:
		menu_button.visible = v

	# Infestation HUD created by TurnManager
	if infestation_hud != null and is_instance_valid(infestation_hud):
		infestation_hud.visible = v

	# Main HUD CanvasLayer (your UnitCard HUD)
	# (Find by class_name HUD)
	for n in get_tree().get_nodes_in_group(""):
		pass # no-op; groups not used here

	var root := get_tree().root
	if root != null:
		# safest: scan for any node that is a HUD (class_name HUD)
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			if cur is HUD:
				(cur as CanvasLayer).visible = v
			for ch in cur.get_children():
				if ch is Node:
					stack.append(ch)
