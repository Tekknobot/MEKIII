extends Zombie
class_name RadioactiveZombie

# -----------------------------------
# Radiation tuning
# -----------------------------------
@export var rad_aura_radius := 1               # 1 = adjacent tiles
@export var rad_aura_damage := 1               # damage per tick to adjacent allies
@export var rad_tick_every_enemy_turn := true  # tick at start of each enemy phase

@export var rad_contam_duration := 2           # turns a tile stays contaminated
@export var rad_contam_damage := 1             # damage when an ally starts/enters contaminated tile
@export var rad_spread_on_hit := true          # contaminate the attacked cell

@export var rad_glow_strength := 0.25          # purely visual (optional)

# internal
var _rad_active := true

func _ready() -> void:
	super._ready()
	# Identity
	set_meta("display_name", "Radioactive Zombie")
	set_meta("portrait_tex", preload("res://sprites/Portraits/radioactive_zombie_port.png"))

	# Slightly different stats (optional)
	# These make it feel distinct without being a boss.
	move_range = 3
	attack_range = 1
	attack_damage = 1

	# Optional: make it a bit tankier than normal zombie
	max_hp = int(round(max_hp * 1.15))
	hp = clamp(hp, 0, max_hp)

	# Optional visual tint/glow
	var ci := _get_render_item()
	if ci != null:
		ci.modulate = ci.modulate.lerp(Color(0.4, 1.0, 0.6, 1.0), rad_glow_strength)

static func _u_has_quirk(u: Unit, qid: StringName) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	if not u.has_meta(&"quirks"):
		return false
	var want := String(qid)
	var qs: Array = u.get_meta(&"quirks", [])
	for v in qs:
		if String(v) == want:
			return true
	return false

# ---------------------------------------------------------
# Hooks you call from TurnManager / MapController
# ---------------------------------------------------------

# Call this once per enemy phase (recommended: at the start of enemy turns)
func rad_tick(M: Node) -> void:
	if not _rad_active:
		return
	if hp <= 0:
		return
	if M == null or not is_instance_valid(M):
		return

	# 1) Aura damage to adjacent ALLIES
	_apply_aura_damage(M)

	# 2) Contaminate the tile we're standing on (optional "trail")
	_mark_contaminated(M, cell, rad_contam_duration)

func on_hit_cell(M: Node, target_cell: Vector2i) -> void:
	if not rad_spread_on_hit:
		return
	if M == null or not is_instance_valid(M):
		return
	_mark_contaminated(M, target_cell, rad_contam_duration)

# ---------------------------------------------------------
# Implementation
# ---------------------------------------------------------

func _apply_aura_damage(M: Node) -> void:
	# We rely on MapController helpers you already tend to have:
	# - get_all_units()
	# - _flash_unit_white(u, t)
	# - apply_damage(u, dmg) OR unit.take_damage()
	# We'll do a safe, minimal approach.

	if not M.has_method("get_all_units"):
		return

	for u in M.call("get_all_units"):
		if u == null or not is_instance_valid(u):
			continue
		if u.hp <= 0:
			continue
		if u.team != Unit.Team.ALLY:
			continue

		var d = abs(u.cell.x - cell.x) + abs(u.cell.y - cell.y)
		if d <= rad_aura_radius:
			# damage
			_deal_damage_safely(M, u, rad_aura_damage)

func _deal_damage_safely(M: Node, u: Unit, dmg: int) -> void:
	if dmg <= 0:
		return
	if M == null or not is_instance_valid(M):
		return

	# ✅ Preferred: MapController handles the delay + flash safely
	if M.has_method("apply_damage_delayed"):
		M.call_deferred("apply_damage_delayed", u, dmg, 0.06, 0.10)
		return

	# Fallback: old immediate behavior
	if M.has_method("_flash_unit_white"):
		M.call("_flash_unit_white", u, 0.10)

	if u.has_method("apply_damage"):
		u.call("apply_damage", dmg)
	elif u.has_method("take_damage"):
		u.call("take_damage", dmg)
	else:
		u.hp = max(0, u.hp - dmg)

func _mark_contaminated(M: Node, c: Vector2i, turns: int) -> void:
	# Host-authoritative hazard placement in co-op.
	if M == null:
		return
	if M.has_method("coop_hazard_set"):
		M.call("coop_hazard_set", &"rad_contam", c, turns)
		return

	var key := &"rad_contam"
	var contam := {}
	if M.has_meta(key):
		contam = M.get_meta(key)
	if not (contam is Dictionary):
		contam = {}

	var cur := int(contam.get(c, 0))
	contam[c] = max(cur, turns)
	if M.has_method("coop_hazard_set_state"):
		M.call("coop_hazard_set_state", key, contam)
	else:
		M.set_meta(key, contam)
		if M.has_method("_rad_refresh_visuals"):
			M.call("_rad_refresh_visuals")


# ---------------------------------------------------------
# Static helper you can call from TurnManager each round
# Decrements contamination and damages allies on contaminated tiles
# ---------------------------------------------------------
static func _round_stamp_from_map(M: Node) -> int:
	var stamp := 0
	var tm = M.get("TM") if M != null and M.has_method("get") else null
	if tm != null and is_instance_valid(tm) and ("round_index" in tm):
		stamp = int(tm.round_index)
	return stamp

static func _pulse_quirk(u: Unit, qid: StringName) -> void:
	if u != null and is_instance_valid(u) and u.has_signal("quirk_triggered"):
		u.emit_signal("quirk_triggered", qid, "", Color.WHITE)

static func contam_tick(M: Node) -> void:
	if M == null or not is_instance_valid(M):
		return

	var key := &"rad_contam"
	if not M.has_meta(key):
		return

	var contam = M.get_meta(key)
	if not (contam is Dictionary):
		return

	var stamp := _round_stamp_from_map(M)

	# 1) Damage allies standing on contaminated tiles
	if M.has_method("get_all_units"):
		for u in M.call("get_all_units"):
			if u == null or not is_instance_valid(u):
				continue
			if u.hp <= 0:
				continue
			if u.team != Unit.Team.ALLY:
				continue
			if not contam.has(u.cell):
				continue

			# -------------------------
			# QUIRKS: RAD tile handling
			# -------------------------

			# Rad Overdrive: first time you are on rad contam each round => +2 Move next turn
			# (Triggers even if damage is scrubbed/nullified)
			if _u_has_quirk(u, &"rad_overdrive"):
				var last := int(u.get_meta(&"q_rad_overdrive_stamp", -999))
				if last != stamp:
					u.set_meta(&"q_rad_overdrive_stamp", stamp)
					u.set_meta(&"q_rad_overdrive_used", false)

				if not bool(u.get_meta(&"q_rad_overdrive_used", false)):
					u.set_meta(&"q_rad_overdrive_used", true)

					# Uses your "quirk move bonus" meta (the one you patched into Unit.get_move_range)
					u.set_meta(&"q_move_turns", 1)
					u.set_meta(&"q_move_bonus", 2)

					_pulse_quirk(u, &"rad_overdrive")

			# ANOM: ignore rad tile damage
			if _u_has_quirk(u, &"hazard_nullifier"):
				_pulse_quirk(u, &"hazard_nullifier")
				continue

			# Rad Scrubber: ignore rad tile damage
			if _u_has_quirk(u, &"rad_scrubber"):
				_pulse_quirk(u, &"rad_scrubber")
				continue

			# Apply rad tile damage
			if M.has_method("_flash_unit_white"):
				M.call("_flash_unit_white", u, 0.10)

			var dmg := 1
			if u.has_method("apply_damage"):
				u.call("apply_damage", dmg)
			elif u.has_method("take_damage"):
				u.call("take_damage", dmg)
			else:
				u.hp = max(0, u.hp - dmg)

	# 2) Decrement timers + erase expired
	var to_erase: Array[Vector2i] = []
	for c in contam.keys():
		contam[c] = int(contam[c]) - 1
		if int(contam[c]) <= 0:
			to_erase.append(c)
	for c in to_erase:
		contam.erase(c)

	M.set_meta(key, contam)

	if M.has_method("_rad_refresh_visuals"):
		M.call("_rad_refresh_visuals")
