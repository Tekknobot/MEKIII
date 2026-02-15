# res://scripts/quirk_db.gd
extends Object
class_name QuirkDB

# "Mewgenics-like" genetic roll system, but in-universe for ZombieMECHA.
# We call them "Quirks" (chassis quirks / pilot quirks / hardware quirks), not mutations.
#
# Data-driven: add new quirks by appending to QUIRK_DEFS.
# Effects are intentionally simple (+/- stats, + overwatch range, + special cooldown tweaks).

const MAX_QUIRKS_PER_UNIT := 3

const QUIRK_DEFS: Array[Dictionary] = [
	{
		"id": &"reinforced_frame",
		"title": "Reinforced Frame",
		"desc": "+1 Max HP. Heavier plating.",
		"effects": {"max_hp": 1}
	},
	{
		"id": &"overclocked_servos",
		"title": "Overclocked Servos",
		"desc": "+1 Move. -1 Max HP (fragile actuators).",
		"effects": {"move_range": 1, "max_hp": -1}
	},
	{
		"id": &"precision_optics",
		"title": "Precision Optics",
		"desc": "+1 Attack Range.",
		"effects": {"attack_range": 1}
	},
	{
		"id": &"hot_load",
		"title": "Hot Load",
		"desc": "+1 Damage. +1 Move (reckless).",
		"effects": {"attack_damage": 1, "move_range": 1}
	},
	{
		"id": &"leaky_hydraulics",
		"title": "Leaky Hydraulics",
		"desc": "-1 Move. Sluggish response.",
		"effects": {"move_range": -1}
	},
	{
		"id": &"thin_armor",
		"title": "Thin Armor",
		"desc": "-1 Max HP."	,
		"effects": {"max_hp": -1}
	},
	{
		"id": &"sentinel_rig",
		"title": "Sentinel Rig",
		"desc": "+1 Overwatch range.",
		"effects": {"overwatch_range": 1}
	},
]


static func has_def(id: StringName) -> bool:
	for d in QUIRK_DEFS:
		if d.get("id", &"") == id:
			return true
	return false


static func get_def(id: StringName) -> Dictionary:
	for d in QUIRK_DEFS:
		if d.get("id", &"") == id:
			return d
	return {}


static func describe_list(ids: Array) -> String:
	# ids can be Array[StringName] or Array[String]
	var parts: Array[String] = []
	for v in ids:
		var id := StringName(str(v))
		var d := get_def(id)
		if d.is_empty():
			continue
		parts.append("%s" % str(d.get("title", id)))
	return ", ".join(parts)


static func roll_random_quirk(rng: RandomNumberGenerator, owned: Array) -> StringName:
	# Returns a quirk id not in owned. Empty if none available.
	var used: Dictionary = {}
	for q in owned:
		used[StringName(str(q))] = true

	var candidates: Array[StringName] = []
	for d in QUIRK_DEFS:
		var id = d.get("id", &"")
		if id == &"":
			continue
		if not used.has(id):
			candidates.append(id)

	if candidates.is_empty():
		return &""

	return candidates[rng.randi_range(0, candidates.size() - 1)]


static func apply_to_unit(u: Node, quirks: Array) -> void:
	if u == null or not is_instance_valid(u):
		return

	# Store on unit for UI/debug
	var norm: Array[StringName] = []
	for q in quirks:
		var id := StringName(str(q))
		if has_def(id):
			norm.append(id)
	u.set_meta(&"quirks", norm)

	# Apply simple stat deltas
	var d_hp := 0
	var d_mv := 0
	var d_rng := 0
	var d_dmg := 0
	var d_ow := 0

	for id in norm:
		var def := get_def(id)
		var fx: Dictionary = def.get("effects", {})
		d_hp += int(fx.get("max_hp", 0))
		d_mv += int(fx.get("move_range", 0))
		d_rng += int(fx.get("attack_range", 0))
		d_dmg += int(fx.get("attack_damage", 0))
		d_ow += int(fx.get("overwatch_range", 0))

	# Write back to common Unit fields if present
	if "max_hp" in u:
		u.max_hp = max(1, int(u.max_hp) + d_hp)
	if "move_range" in u:
		u.move_range = max(1, int(u.move_range) + d_mv)
	if "attack_range" in u:
		u.attack_range = max(1, int(u.attack_range) + d_rng)
	if "attack_damage" in u:
		u.attack_damage = max(0, int(u.attack_damage) + d_dmg)

	# Overwatch lives in MapController dictionaries, but many units just need a meta.
	if d_ow != 0:
		var cur := 0
		if u.has_meta(&"overwatch_bonus"):
			cur = int(u.get_meta(&"overwatch_bonus", 0))
		u.set_meta(&"overwatch_bonus", cur + d_ow)

	# Clamp current HP after max HP changes
	if "hp" in u and "max_hp" in u:
		u.hp = clamp(int(u.hp), 0, int(u.max_hp))

static func get_color(id: StringName) -> Color:
	var d := get_def(id)
	if d.has("color"):
		var s := str(d.get("color", ""))
		if s != "":
			return Color(s)

	# ✅ fallback: stable hashed color per id (still “unique per quirk”)
	var h = abs(hash(String(id))) % 360
	return Color.from_hsv(float(h) / 360.0, 0.55, 0.95)
