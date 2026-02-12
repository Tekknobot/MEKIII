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
static func fire_tiles_tick(M: Node) -> void:
	if M == null or not is_instance_valid(M):
		return

	var key := &"fire_tiles"
	if not M.has_meta(key):
		return

	var tiles = M.get_meta(key)
	if not (tiles is Dictionary):
		return

	# 1) Damage allies standing on burning tiles
	if M.has_method("get_all_units"):
		for u in M.call("get_all_units"):
			if u == null or not is_instance_valid(u):
				continue
			if u.hp <= 0:
				continue
			if u.team != Unit.Team.ALLY:
				continue
			if tiles.has(u.cell):
				if M.has_method("_flash_unit_white"):
					M.call("_flash_unit_white", u, 0.10)

				var dmg := 1
				if u.has_method("apply_damage"):
					u.call("apply_damage", dmg)
				elif u.has_method("take_damage"):
					u.call("take_damage", dmg)
				else:
					u.hp = max(0, u.hp - dmg)

	# 2) Decrement & expire
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
