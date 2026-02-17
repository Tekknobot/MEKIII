extends Zombie
class_name FireZombie

# -----------------------------------
# Fire tuning
# -----------------------------------
@export var fire_aura_radius := 1                 # adjacent tiles
@export var fire_aura_damage := 1                 # dmg per tick to adjacent allies
@export var fire_tick_every_enemy_turn := true    # tick at start of each enemy phase

@export var fire_tile_duration := 2               # turns a tile stays burning
@export var fire_tile_damage := 1                 # dmg when ally enters/starts on burning tile

@export var fire_spread_on_hit := true            # ignite the attacked cell
@export var fire_trail := true                    # ignite the tile this zombie stands on
@export var fire_glow_strength := 0.25            # visual tint (optional)

# internal
var _fire_active := true

func _ready() -> void:
	super._ready()

	set_meta("display_name", "Fire Zombie")
	set_meta("portrait_tex", preload("res://sprites/Portraits/zombie_port.png"))

	# Slightly different stats (optional)
	move_range = 3
	attack_range = 1
	attack_damage = 1

	# Optional: tanky-ish but not crazy
	max_hp = int(round(max_hp * 1.10))
	hp = clamp(hp, 0, max_hp)

	# Optional visual tint
	var ci := _get_render_item()
	if ci != null:
		ci.modulate = ci.modulate.lerp(Color(1.0, 0.55, 0.15, 1.0), fire_glow_strength)

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
# Call once per enemy phase (recommended: start of enemy phase)
func fire_tick(M: Node) -> void:
	if not _fire_active:
		return
	if hp <= 0:
		return
	if M == null or not is_instance_valid(M):
		return

	# 1) Aura damage
	_apply_aura_damage(M)

	# 2) Burning trail
	if fire_trail:
		_mark_burning(M, cell, fire_tile_duration)

func on_hit_cell(M: Node, target_cell: Vector2i) -> void:
	if not fire_spread_on_hit:
		return
	if M == null or not is_instance_valid(M):
		return
	_mark_burning(M, target_cell, fire_tile_duration)

# ---------------------------------------------------------
# Implementation
# ---------------------------------------------------------

func _apply_aura_damage(M: Node) -> void:
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
		if d <= fire_aura_radius:
			_deal_damage_safely(M, u, fire_aura_damage)

func _deal_damage_safely(M: Node, u: Unit, dmg: int) -> void:
	if dmg <= 0:
		return

	if M.has_method("_flash_unit_white"):
		M.call("_flash_unit_white", u, 0.10)

	if u.has_method("apply_damage"):
		u.call("apply_damage", dmg)
	elif u.has_method("take_damage"):
		u.call("take_damage", dmg)
	else:
		u.hp = max(0, u.hp - dmg)

func _mark_burning(M: Node, c: Vector2i, turns: int) -> void:
	# Store in MapController metadata: cell -> remaining turns
	var key := &"fire_tiles"
	var tiles := {}

	if M.has_meta(key):
		tiles = M.get_meta(key)
	if not (tiles is Dictionary):
		tiles = {}

	var cur := int(tiles.get(c, 0))
	tiles[c] = max(cur, turns)

	M.set_meta(key, tiles)

	# Optional: refresh visuals if you add them later
	if M.has_method("_fire_refresh_visuals"):
		M.call("_fire_refresh_visuals")

# ---------------------------------------------------------
# Static tick: damage allies standing on burning tiles,
# then decrement & expire. Call this at phase start.
# ---------------------------------------------------------
static func _round_stamp_from_map(M: Node) -> int:
	# best-effort: uses MapController.TM.round_index if present
	var stamp := 0
	var tm = M.get("TM") if M != null and M.has_method("get") else null
	if tm != null and is_instance_valid(tm) and ("round_index" in tm):
		stamp = int(tm.round_index)
	return stamp

static func _pulse_quirk(u: Unit, qid: StringName) -> void:
	# HUD listens to quirk_triggered and you already removed floating text there
	if u != null and is_instance_valid(u) and u.has_signal("quirk_triggered"):
		u.emit_signal("quirk_triggered", qid, "", Color.WHITE)

static func fire_tiles_tick(M: Node) -> void:
	if M == null or not is_instance_valid(M):
		return

	var key := &"fire_tiles"
	if not M.has_meta(key):
		return

	var tiles = M.get_meta(key)
	if not (tiles is Dictionary):
		return

	var stamp := _round_stamp_from_map(M)

	# 1) Damage allies standing on burning tiles
	if M.has_method("get_all_units"):
		for u in M.call("get_all_units"):
			if u == null or not is_instance_valid(u):
				continue
			if u.hp <= 0:
				continue
			if u.team != Unit.Team.ALLY:
				continue
			if not tiles.has(u.cell):
				continue

			# -------------------------
			# QUIRKS: FIRE tile handling
			# -------------------------

			# ANOM: ignore fire tile damage
			if _u_has_quirk(u, &"hazard_nullifier"):
				_pulse_quirk(u, &"hazard_nullifier")
				continue

			# First fire tile damage each round is 0
			if _u_has_quirk(u, &"fireproof_coating"):
				var last_stamp := int(u.get_meta(&"q_fireproof_stamp", -999))
				if last_stamp != stamp:
					u.set_meta(&"q_fireproof_stamp", stamp)
					u.set_meta(&"q_fireproof_used", false)

				if not bool(u.get_meta(&"q_fireproof_used", false)):
					u.set_meta(&"q_fireproof_used", true)
					_pulse_quirk(u, &"fireproof_coating")
					continue

			# If we got here, FIRE damage is actually happening this tick
			# Thermal Vents: when fire damages you, clear chilled + +1 dmg next turn
			if _u_has_quirk(u, &"thermal_vents"):
				if int(u.get_meta(&"chilled_turns", 0)) > 0:
					u.set_meta(&"chilled_turns", 0)

				var st := int(u.get_meta(&"stim_turns", 0))
				var cur := int(u.get_meta(&"stim_damage_bonus", 0))
				u.set_meta(&"stim_turns", max(st, 1))
				u.set_meta(&"stim_damage_bonus", cur + 1)

				_pulse_quirk(u, &"thermal_vents")

			# ANOM: Melt Systems — fire clears chilled + heal 1 (still takes damage unless you want otherwise)
			if _u_has_quirk(u, &"melt_systems"):
				if int(u.get_meta(&"chilled_turns", 0)) > 0:
					u.set_meta(&"chilled_turns", 0)

				# Heal 1 (up to max)
				if "hp" in u and "max_hp" in u:
					u.hp = clampi(int(u.hp) + 1, 0, int(u.max_hp))

				_pulse_quirk(u, &"melt_systems")

			# Apply fire tile damage
			if M.has_method("_flash_unit_white"):
				M.call("_flash_unit_white", u, 0.10)

			var dmg := 1
			if u.has_method("apply_damage"):
				u.call("apply_damage", dmg)
			elif u.has_method("take_damage"):
				u.call("take_damage", dmg)
			else:
				u.hp = max(0, u.hp - dmg)

	# 2) Decrement & expire tiles
	var to_erase: Array[Vector2i] = []
	for c in tiles.keys():
		tiles[c] = int(tiles[c]) - 1
		if int(tiles[c]) <= 0:
			to_erase.append(c)
	for c in to_erase:
		tiles.erase(c)

	M.set_meta(key, tiles)

	if M.has_method("_fire_refresh_visuals"):
		M.call("_fire_refresh_visuals")
