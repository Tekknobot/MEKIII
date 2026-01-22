extends Node
class_name TurnManager

@export var map_controller_path: NodePath
@export var end_turn_button_path: NodePath

@onready var M: MapController = get_node(map_controller_path)
@onready var end_turn_button := get_node_or_null(end_turn_button_path)

@export var hellfire_button_path: NodePath
@export var blade_button_path: NodePath
@export var mines_button_path: NodePath
@export var overwatch_button_path: NodePath
@export var suppress_button_path: NodePath
@export var stim_button_path: NodePath

@onready var suppress_button := get_node_or_null(suppress_button_path)
@onready var stim_button := get_node_or_null(stim_button_path)

@onready var overwatch_button := get_node_or_null(overwatch_button_path)
@onready var hellfire_button := get_node_or_null(hellfire_button_path)
@onready var blade_button := get_node_or_null(blade_button_path)
@onready var mines_button := get_node_or_null(mines_button_path)

enum Phase { PLAYER, ENEMY, BUSY }
var phase: Phase = Phase.PLAYER

# Per-ally action state
var _moved: Dictionary = {}   # Unit -> bool
var _attacked: Dictionary = {}# Unit -> bool

var enemy_spawn_count := 2   # how many edge zombies to spawn per round
var round_index := 1  # Round 1 at game start

# --- Beacon pacing ---
@export var beacon_parts_required := 6
@export var beacon_deadline_round := 12  # "must be done by end of Round 12" (tune this)

# --- Enemy wave spawning ---
@export var spawn_base := 3              # Round 1 adds +3 (tune)
@export var spawn_per_round := 1         # +1 per round
@export var spawn_bonus_every := 3       # every 3 rounds add extra
@export var spawn_bonus_amount := 2      # how many extra on bonus rounds
@export var spawn_cap := 32              # hard safety cap

func _ready() -> void:
	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_pressed)

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

	start_player_phase()
	_update_end_turn_button()

	if M != null:
		if M.has_signal("selection_changed") and not M.selection_changed.is_connected(_on_selection_changed):
			M.selection_changed.connect(_on_selection_changed)

		if M.has_signal("aim_changed") and not M.aim_changed.is_connected(_on_aim_changed):
			M.aim_changed.connect(_on_aim_changed)

	_update_special_buttons()
	
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
			M.set_unit_exhausted(u, false) # ✅ reset tint each new player phase

	_update_end_turn_button()

func start_enemy_phase() -> void:
	phase = Phase.ENEMY
	M.reset_turn_flags_for_enemies()

	_tick_buffs_enemy_phase_start()

	_update_end_turn_button()
	_update_special_buttons()

	await _run_enemy_turns()

	# overwatch tick
	if M != null:
		M.tick_overwatch_turn()

	# ✅ spawn wave for next round (standard curve)
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

	# ✅ Advance round counter NOW (enemy phase finished)
	round_index += 1

	# ✅ deadline check (tune for 6 parts)
	if M != null and M.has_meta("beacon_ready"):
		if round_index > beacon_deadline_round and (not M.beacon_ready):
			game_over("Beacon not completed by end of Round %d!" % beacon_deadline_round)
			return

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

	# ✅ NEW: support bots act here (before enemies)
	await _run_support_bots_phase()

	# ✅ then enemies
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
	# Don’t let player re-select units that finished both decisions
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
			M.set_unit_exhausted(u, true) # ✅ moved + no targets = done

	_update_end_turn_button()
	_update_end_turn_button()
	_update_special_buttons()


func notify_player_attacked(u: Unit) -> void:
	if u != null and is_instance_valid(u):
		_attacked[u] = true
		_moved[u] = true # ✅ attacking ends the whole unit turn
		M.set_unit_exhausted(u, true)
		
	_update_end_turn_button()
	_update_end_turn_button()
	_update_special_buttons()

# If you want “skip attack” as a button later:
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
		# ✅ re-check every time (support missiles could have killed it)
		if z == null or not is_instance_valid(z) or z.hp <= 0:
			continue

		if not _enemy_in_ally_vision(z, allies):
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
			vis = int(a.move_range) + 3
		else:
			vis = 3

		# Manhattan distance on your grid
		var d = abs(zc.x - a.cell.x) + abs(zc.y - a.cell.y)
		if d <= vis:
			return true

	return false

func _enemy_take_turn(z: Unit) -> void:
	# ✅ hard dead gate
	if z == null or not is_instance_valid(z) or z.hp <= 0:
		return

	# SUPPRESSION...
	if z.has_meta("suppress_turns") and int(z.get_meta("suppress_turns")) > 0:
		# (your existing suppression code)
		await get_tree().create_timer(0.12).timeout
		return

	var target := _pick_best_attack_target(z)
	if target != null:
		await M.ai_attack(z, target)
		return

	# ✅ after awaits / damage events, check again
	if z == null or not is_instance_valid(z) or z.hp <= 0:
		return

	var move_cell := _best_move_toward_nearest_ally(z)

	# ✅ check again before moving
	if z == null or not is_instance_valid(z) or z.hp <= 0:
		return

	if move_cell != z.cell:
		await M.ai_move(z, move_cell)

	# ✅ mine could have killed it
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
	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_place_mine"):
		return

	M.activate_special("mines")
	_update_special_buttons()

func _update_special_buttons() -> void:
	# Toggle visuals (pressed highlight)
	if hellfire_button: hellfire_button.toggle_mode = true
	if blade_button: blade_button.toggle_mode = true
	if mines_button: mines_button.toggle_mode = true
	if overwatch_button: overwatch_button.toggle_mode = true
	if suppress_button: suppress_button.toggle_mode = true
	if stim_button: stim_button.toggle_mode = true

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

	# Optional filter list
	if u.has_method("get_available_specials"):
		var specials: Array[String] = u.get_available_specials()
		for i in range(specials.size()):
			specials[i] = String(specials[i]).to_lower()
		has_hellfire = has_hellfire and specials.has("hellfire")
		has_blade = has_blade and specials.has("blade")
		has_mines = has_mines and specials.has("mines")
		has_overwatch = has_overwatch and specials.has("overwatch")
		has_suppress = has_suppress and specials.has("suppress")
		has_stim = has_stim and specials.has("stim")

	# ✅ Show ONLY if unit still has an attack action available
	var show_specials := (not spent_attack)

	if hellfire_button: hellfire_button.visible = show_specials and has_hellfire
	if blade_button: blade_button.visible = show_specials and has_blade
	if mines_button: mines_button.visible = show_specials and has_mines
	if overwatch_button: overwatch_button.visible = show_specials and has_overwatch
	if suppress_button: suppress_button.visible = show_specials and has_suppress
	if stim_button: stim_button.visible = show_specials and has_stim


	# Cooldowns
	var ok_hellfire := true
	var ok_blade := true
	var ok_mines := true
	var ok_overwatch := true
	var ok_suppress := true
	var ok_stim := true
	if u.has_method("can_use_special"):
		ok_hellfire = u.can_use_special("hellfire")
		ok_blade = u.can_use_special("blade")
		ok_mines = u.can_use_special("mines")
		ok_overwatch = u.can_use_special("overwatch")
		ok_suppress = u.can_use_special("suppress")
		ok_stim = u.can_use_special("stim")

	# Enable
	if hellfire_button: hellfire_button.disabled = spent_attack or (not has_hellfire) or (not ok_hellfire)
	if blade_button: blade_button.disabled = spent_attack or (not has_blade) or (not ok_blade)
	if mines_button: mines_button.disabled = spent_attack or (not has_mines) or (not ok_mines)
	if overwatch_button: overwatch_button.disabled = spent_attack or (not has_overwatch) or (not ok_overwatch)
	if suppress_button: suppress_button.disabled = spent_attack or (not has_suppress) or (not ok_suppress)
	if stim_button: stim_button.disabled = spent_attack or (not has_stim) or (not ok_stim)

	# Pressed visuals
	var active := ""
	if M.aim_mode == MapController.AimMode.SPECIAL:
		active = String(M.special_id).to_lower()

	if hellfire_button and not hellfire_button.disabled:
		hellfire_button.button_pressed = (active == "hellfire")
	if blade_button and not blade_button.disabled:
		blade_button.button_pressed = (active == "blade")
	if mines_button and not mines_button.disabled:
		mines_button.button_pressed = (active == "mines")
	if suppress_button and not suppress_button.disabled:
		suppress_button.button_pressed = (active == "suppress")

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
	var u := M.selected
	if u == null or not is_instance_valid(u):
		return
	if _attacked.get(u, false):
		return
	if not u.has_method("perform_stim"):
		return

	M.activate_special("stim") # make it instant in MapController like overwatch, OR targeted if you prefer
	_update_special_buttons()

func _tick_buffs_enemy_phase_start() -> void:
	var changed := false

	for u in M.get_all_units():
		if u == null or not is_instance_valid(u):
			continue

		# Stim ticks down on ENEMY phase start
		if u.has_meta("stim_turns"):
			var t := int(u.get_meta("stim_turns"))
			if t > 0:
				t -= 1
				u.set_meta("stim_turns", t)
				changed = true

			# When it hits 0, fully clear (so UI + logic read clean)
			if t <= 0:
				u.set_meta("stim_turns", 0)
				u.set_meta("stim_move_bonus", 0)
				u.set_meta("stim_damage_bonus", 0)
				changed = true

	# ✅ If any buff state changed, refresh special buttons now
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
		if not (u is RecruitBot):
			continue
		if M.get_all_enemies().is_empty():
			break

		await (u as RecruitBot).auto_support_action(M)

	# leave it BUSY if we're transitioning to enemy anyway,
	# but restore if caller wasn’t doing a transition
	phase = prev
	_update_end_turn_button()
	_update_special_buttons()

func game_over(msg: String) -> void:
	print(msg)
	phase = Phase.BUSY
	_update_end_turn_button()
	_update_special_buttons()
	# Optional: if you have a Game node, call it:
	# var G := get_tree().get_first_node_in_group("Game")
	# if G and G.has_method("game_over"): G.call("game_over", msg)
