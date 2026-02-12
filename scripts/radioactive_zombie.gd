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

	# Prefer MapController methods if they exist (keeps FX consistent)
	if M.has_method("_flash_unit_white"):
		M.call("_flash_unit_white", u, 0.10)

	# Try common patterns
	if u.has_method("apply_damage"):
		u.call("apply_damage", dmg)
	elif u.has_method("take_damage"):
		u.call("take_damage", dmg)
	else:
		# fallback direct
		u.hp = max(0, u.hp - dmg)

func _mark_contaminated(M: Node, c: Vector2i, turns: int) -> void:
	var key := &"rad_contam"
	var contam := {}

	if M.has_meta(key):
		contam = M.get_meta(key)
	if not (contam is Dictionary):
		contam = {}

	var cur := int(contam.get(c, 0))
	contam[c] = max(cur, turns)

	M.set_meta(key, contam)

	# ✅ NEW: refresh contamination visuals
	if M.has_method("_rad_refresh_visuals"):
		M.call("_rad_refresh_visuals")

# ---------------------------------------------------------
# Static helper you can call from TurnManager each round
# Decrements contamination and damages allies on contaminated tiles
# ---------------------------------------------------------
static func contam_tick(M: Node) -> void:
	if M == null or not is_instance_valid(M):
		return

	var key := &"rad_contam"
	if not M.has_meta(key):
		return

	var contam = M.get_meta(key)
	if not (contam is Dictionary):
		return

	# -------------------------------------------------
	# 1) Damage allies standing on contaminated tiles
	# -------------------------------------------------
	if M.has_method("get_all_units"):
		for u in M.call("get_all_units"):
			if u == null or not is_instance_valid(u):
				continue
			if u.hp <= 0:
				continue
			if u.team != Unit.Team.ALLY:
				continue
			if contam.has(u.cell):
				if M.has_method("_flash_unit_white"):
					M.call("_flash_unit_white", u, 0.10)

				var dmg := 1
				if u.has_method("apply_damage"):
					u.call("apply_damage", dmg)
				elif u.has_method("take_damage"):
					u.call("take_damage", dmg)
				else:
					u.hp = max(0, u.hp - dmg)

	# -------------------------------------------------
	# 2) Decrement timers + erase expired
	# -------------------------------------------------
	var to_erase: Array[Vector2i] = []
	for c in contam.keys():
		contam[c] = int(contam[c]) - 1
		if int(contam[c]) <= 0:
			to_erase.append(c)

	for c in to_erase:
		contam.erase(c)

	M.set_meta(key, contam)

	# -------------------------------------------------
	# 3) Refresh visuals
	# -------------------------------------------------
	if M.has_method("_rad_refresh_visuals"):
		M.call("_rad_refresh_visuals")
