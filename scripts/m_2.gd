extends Unit
class_name M2

# -------------------------
# Visual / identity
# -------------------------
@export var portrait_tex: Texture2D = preload("res://sprites/Portraits/dog_port.png") # swap to panther portrait
@export var display_name := "M2 Panther"
@export var thumbnail: Texture2D

@export var attack_anim_name: StringName = &"attack"
@export var attack_fx_scene: PackedScene = null

# -------------------------
# Base stats
# -------------------------
@export var base_move_range := 6
@export var base_attack_range := 1
@export var base_max_hp := 6

# -------------------------
# ONLY SPECIAL: POUNCE
# - choose enemy within pounce_range
# - deal damage
# - knockback 1 tile away from M2
# - if off-map: ringout death
# - if knocked into another unit: slam (both take damage) + optional "both die"
# -------------------------
@export var pounce_range := 4
@export var pounce_damage := 2
@export var pounce_knockback := 1
@export var pounce_cooldown := 3

@export var slam_damage := 2
@export var slam_kills_both := true  # set false if you only want damage

func _ready() -> void:
	set_meta("portrait_tex", portrait_tex)
	set_meta("display_name", display_name)

	footprint_size = Vector2i(1, 1)
	move_range = base_move_range
	attack_range = base_attack_range

	max_hp = max(max_hp, base_max_hp)
	hp = clamp(hp, 0, max_hp)

	super._ready()

# -------------------------
# Specials list (for UI)
# -------------------------
func get_available_specials() -> Array[String]:
	return ["Pounce"]

func can_use_special(id: String) -> bool:
	id = id.to_lower()
	if id != "pounce":
		return false
	return int(special_cd.get(id, 0)) <= 0

func get_special_range(id: String) -> int:
	id = id.to_lower()
	if id == "pounce":
		return pounce_range
	return 0

# -------------------------------------------------------
# Special: POUNCE (CHAIN) — hits ALL enemy units in range
# - Finds enemies in pounce_range (Manhattan) and attacks them
#   one-by-one: damage -> knockback -> next target.
# - Cooldown applied ONCE at the end.
# -------------------------------------------------------
func perform_pounce(M: MapController, _target_cell: Vector2i) -> void:
	if not can_use_special("pounce"):
		return
	if M == null:
		return
	if pounce_range <= 0:
		return

	var visited: Dictionary = {} # instance_id -> true
	const HIT_DELAY := 0.55

	while true:
		var targets: Array[Unit] = []

		# snapshot keys so unit_at_cell can erase safely
		var keys := M.units_by_cell.keys()
		for k in keys:
			var u := M.unit_at_cell(k)
			if u == null:
				continue
			if u.team == team:
				continue
			var d = abs(u.cell.x - cell.x) + abs(u.cell.y - cell.y)
			if d > 0 and d <= pounce_range:
				targets.append(u)

		# closest first (simple bubble sort)
		for i in range(targets.size()):
			for j in range(i + 1, targets.size()):
				var a := targets[i]
				var b := targets[j]
				if a == null or b == null:
					continue
				var da = abs(a.cell.x - cell.x) + abs(a.cell.y - cell.y)
				var db = abs(b.cell.x - cell.x) + abs(b.cell.y - cell.y)
				if da > db:
					targets[i] = b
					targets[j] = a

		var tgt: Unit = null
		var tgt_cell_for_fx := Vector2i.ZERO

		for u in targets:
			if u == null or not is_instance_valid(u):
				continue
			var id := u.get_instance_id()
			if visited.has(id):
				continue
			tgt = u
			visited[id] = true
			# ✅ cache while valid (safe to use after awaits)
			tgt_cell_for_fx = u.cell
			break

		if tgt == null:
			break

		# ✅ pause between hits
		await get_tree().create_timer(HIT_DELAY).timeout

		# ✅ IMPORTANT: re-check BEFORE touching tgt properties
		if tgt == null or not is_instance_valid(tgt):
			continue

		# ✅ use cached cell for facing/fx (won’t crash if tgt dies mid-frame)
		_face_toward_cell(tgt_cell_for_fx)
		_play_attack_fx(M, tgt_cell_for_fx)
		_play_attack_anim_once()

		_apply_damage_safely(tgt, pounce_damage)

		# ✅ wait anim
		await _wait_attack_anim()

		# ✅ re-check again after await
		if tgt == null or not is_instance_valid(tgt):
			continue

		# knockback
		var dir := _dir_away_from_self(tgt.cell) # safe now because tgt valid
		if dir == Vector2i.ZERO:
			continue

		for i in range(pounce_knockback):
			if tgt == null or not is_instance_valid(tgt):
				break

			var next_cell := tgt.cell + dir

			if not _cell_in_bounds(M, next_cell):
				if M.has_method("_ringout_push_and_die"):
					await M.call("_ringout_push_and_die", self, tgt)
				else:
					_apply_damage_safely(tgt, 999)
				break

			var structure_blocked := _get_structure_blocked(M)
			if _cell_blocked(structure_blocked, next_cell):
				break

			var occ := M.unit_at_cell(next_cell)
			if occ != null and is_instance_valid(occ):
				_apply_damage_safely(tgt, slam_damage)
				_apply_damage_safely(occ, slam_damage)
				if slam_kills_both:
					_apply_damage_safely(tgt, 999)
					_apply_damage_safely(occ, 999)
				break

			if M.has_method("_push_unit_to_cell"):
				await M.call("_push_unit_to_cell", tgt, next_cell)
			else:
				_basic_push_fallback(M, tgt, next_cell)

			# ✅ if push killed tgt somehow, don’t loop into tgt.cell again
			if tgt == null or not is_instance_valid(tgt):
				break

	mark_special_used("pounce", pounce_cooldown)

# -------------------------
# Helpers
# -------------------------

func _dir_away_from_self(target_cell: Vector2i) -> Vector2i:
	var dx := target_cell.x - cell.x
	var dy := target_cell.y - cell.y
	# push away from M2 (sign of delta)
	return Vector2i(signi(dx), signi(dy))

func signi(v: int) -> int:
	if v > 0: return 1
	if v < 0: return -1
	return 0

func _cell_in_bounds(M: MapController, c: Vector2i) -> bool:
	if M.grid != null and M.grid.has_method("in_bounds"):
		return bool(M.grid.in_bounds(c))
	if M.grid != null and ("w" in M.grid) and ("h" in M.grid):
		return c.x >= 0 and c.y >= 0 and c.x < int(M.grid.w) and c.y < int(M.grid.h)
	return true

func _get_structure_blocked(M: MapController) -> Dictionary:
	if M.game_ref != null and ("structure_blocked" in M.game_ref):
		return M.game_ref.structure_blocked
	return {}

func _cell_blocked(structure_blocked: Dictionary, c: Vector2i) -> bool:
	return structure_blocked.has(c) and bool(structure_blocked[c]) == true

func _basic_push_fallback(M: MapController, u: Unit, to_cell: Vector2i) -> void:
	if u == null or not is_instance_valid(u):
		return
	var from := u.cell
	if M.units_by_cell.has(from) and M.units_by_cell[from] == u:
		M.units_by_cell.erase(from)
	M.units_by_cell[to_cell] = u
	u.set_cell(to_cell, M.terrain)

func _apply_damage_safely(tgt: Object, dmg: int) -> void:
	if tgt == null:
		return

	if tgt.has_method("take_damage"):
		var m := tgt.get_method_list().filter(func(x): return x.name == "take_damage")
		if m.size() > 0 and m[0].args.size() >= 2:
			tgt.call("take_damage", dmg, self)
		else:
			tgt.call("take_damage", dmg)
		return

	if tgt.has_method("apply_damage"):
		var m2 := tgt.get_method_list().filter(func(x): return x.name == "apply_damage")
		if m2.size() > 0 and m2[0].args.size() >= 2:
			tgt.call("apply_damage", dmg, self)
		else:
			tgt.call("apply_damage", dmg)
		return

	if "hp" in tgt:
		tgt.hp -= dmg
		if tgt.hp <= 0:
			if tgt.has_method("die"):
				tgt.call("die")
			else:
				tgt.queue_free()

func _play_attack_fx(M: MapController, target_cell: Vector2i) -> void:
	if M == null:
		return

	var global_pos := Vector2.ZERO
	if M.terrain != null:
		var map_local = M.terrain.map_to_local(target_cell)
		global_pos = M.terrain.to_global(map_local)
	else:
		global_pos = Vector2(target_cell.x * 32, target_cell.y * 32)

	if M.has_method("_sfx"):
		M.call("_sfx", &"pounce", 1.0, randf_range(0.95, 1.05), global_pos)

	var ap := get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		ap = get_node_or_null("Anim") as AnimationPlayer

	if ap != null and ap.has_animation(String(attack_anim_name)):
		ap.play(String(attack_anim_name))
		return

	if attack_fx_scene != null:
		var fx := attack_fx_scene.instantiate()
		var parent: Node = M
		parent.add_child(fx)
		if fx is Node2D:
			(fx as Node2D).global_position = global_pos

func _face_toward_cell(target_cell: Vector2i) -> void:
	var spr2 := get_node_or_null("Sprite2D") as Sprite2D
	if spr2 == null:
		spr2 = get_node_or_null("Visual/Sprite2D") as Sprite2D
	if spr2 == null:
		return
	if target_cell.x < cell.x:
		spr2.flip_h = true
	elif target_cell.x > cell.x:
		spr2.flip_h = false

func _play_attack_anim_once() -> void:
	var sprA := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		sprA = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		return

	var anim := String(attack_anim_name)
	if sprA.sprite_frames == null:
		return
	if not sprA.sprite_frames.has_animation(anim):
		return

	sprA.stop()
	sprA.play(anim)

func _wait_attack_anim() -> void:
	var sprA := get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		sprA = get_node_or_null("Visual/AnimatedSprite2D") as AnimatedSprite2D
	if sprA == null:
		return

	var anim := String(attack_anim_name)
	if sprA.sprite_frames == null:
		return
	if not sprA.sprite_frames.has_animation(anim):
		return

	await sprA.animation_finished

	# ✅ snap back to idle automatically
	if sprA.sprite_frames.has_animation("idle"):
		sprA.play("idle")
