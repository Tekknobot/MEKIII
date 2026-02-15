extends Zombie
class_name IceZombie

# -----------------------------------
# Ice tuning
# -----------------------------------
@export var ice_aura_radius := 1                 # adjacent tiles
@export var chill_duration := 1                  # turns slowed

@export var ice_tile_duration := 2               # turns a tile stays icy
@export var ice_tile_chill_duration := 1         # chill applied when stepping on ice

@export var ice_tick_every_enemy_turn := true    # tick at start of each enemy phase
@export var ice_trail := true                    # leaves ice on its tile each tick
@export var ice_spread_on_hit := true            # leaves ice on attacked cell

# Optional: visual tint strength (if you have render node)
@export var ice_tint_strength := 0.25

# internal
var _ice_active := true

func _ready() -> void:
	super._ready()

	set_meta("display_name", "Ice Zombie")
	set_meta("portrait_tex", preload("res://sprites/Portraits/crusher_zombie_port.png"))
	
	# Optional stat flavor
	move_range = 3
	attack_range = 1
	attack_damage = 1

	# Optional visual tint (safe)
	var ci := _get_render_item()
	if ci != null:
		ci.modulate = ci.modulate.lerp(Color(0.55, 0.85, 1.0, 1.0), ice_tint_strength)

# ---------------------------------------------------------
# Hooks you call from TurnManager / MapController
# ---------------------------------------------------------

# Call once per enemy phase (recommended: at start of ENEMY phase)
func ice_tick(M: Node) -> void:
	if not _ice_active or hp <= 0:
		return
	if M == null or not is_instance_valid(M):
		return

	# 1) Chill aura (slow nearby allies)
	_apply_chill_aura(M)

	# 2) Ice trail under self
	if ice_trail:
		_mark_ice_tile(M, cell, ice_tile_duration)

func on_hit_cell(M: Node, target_cell: Vector2i) -> void:
	if not ice_spread_on_hit:
		return
	if M == null or not is_instance_valid(M):
		return
	_mark_ice_tile(M, target_cell, ice_tile_duration)

# ---------------------------------------------------------
# Implementation
# ---------------------------------------------------------

func _apply_chill_aura(M: Node) -> void:
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
		if d <= ice_aura_radius:
			_apply_chill(u, chill_duration)
			
			# ✅ apply chill visual on allies
			if M.has_method("_refresh_chill_visuals_for_unit"):
				M.call("_refresh_chill_visuals_for_unit", u)


func _apply_chill(u: Unit, turns: int) -> void:
	# Store a simple debuff in metadata.
	# Your movement/turn code should read this and reduce move_range accordingly.
	var cur := int(u.get_meta(&"chilled_turns", 0))
	u.set_meta(&"chilled_turns", max(cur, turns))

	# ✅ Achievement: Get Chilled (first time only)
	if cur <= 0 and u.team == Unit.Team.ALLY:
		var rs := get_node_or_null("/root/RunStateNode")
		if rs == null:
			rs = get_node_or_null("/root/RunState")
		if rs != null and rs.has_method("unlock_achievement"):
			rs.unlock_achievement("ice_cold")
			
func _mark_ice_tile(M: Node, c: Vector2i, turns: int) -> void:
	# MapController meta: cell -> remaining turns
	var key := &"ice_tiles"
	var tiles := {}

	if M.has_meta(key):
		tiles = M.get_meta(key)
	if not (tiles is Dictionary):
		tiles = {}

	var cur := int(tiles.get(c, 0))
	tiles[c] = max(cur, turns)

	M.set_meta(key, tiles)

	# Optional: refresh visuals if you implement it like rad/fire
	if M.has_method("_ice_refresh_visuals"):
		M.call("_ice_refresh_visuals")

# ---------------------------------------------------------
# Static tick: decrement ice tiles + decrement chill timers.
# Call this at phase start (enemy and/or player).
# ---------------------------------------------------------
static func ice_tick_global(M: Node) -> void:
	if M == null or not is_instance_valid(M):
		return

	# 1) decrement chill timers on allies (or all units)
	if M.has_method("get_all_units"):
		for u in M.call("get_all_units"):
			if u == null or not is_instance_valid(u):
				continue
			var t := int(u.get_meta(&"chilled_turns", 0))
			if t > 0:
				u.set_meta(&"chilled_turns", t - 1)

	# 2) decrement ice tile timers
	var key := &"ice_tiles"
	if M.has_meta(key):
		var tiles = M.get_meta(key)
		if tiles is Dictionary:
			var to_erase: Array[Vector2i] = []
			for c in tiles.keys():
				tiles[c] = int(tiles[c]) - 1
				if int(tiles[c]) <= 0:
					to_erase.append(c)
			for c in to_erase:
				tiles.erase(c)

			M.set_meta(key, tiles)

			if M.has_method("_ice_refresh_visuals"):
				M.call("_ice_refresh_visuals")

	# ✅ ADD THIS RIGHT HERE (very bottom of function)
	if M.has_method("_refresh_chill_visuals"):
		M.call("_refresh_chill_visuals")
