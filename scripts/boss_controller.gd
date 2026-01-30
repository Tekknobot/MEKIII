extends Node2D
class_name BossController

signal boss_defeated

@export var boss_max_hp: int = 12
var boss_hp: int = 12

# 3 phases: 1 -> 2 -> 3
var phase: int = 1

# One weakpoint scene (instantiate 4x)
@export var weakpoint_scene: PackedScene

# Optional textures for each weakpoint instance (if your weakpoint scene has a Sprite2D named "Sprite")
@export var wp_left_arm_tex: Texture2D
@export var wp_right_arm_tex: Texture2D
@export var wp_legs_tex: Texture2D
@export var wp_core_tex: Texture2D

# Where weakpoints spawn on the grid
@export var left_arm_cell: Vector2i = Vector2i(5, 2)
@export var right_arm_cell: Vector2i = Vector2i(10, 2)
@export var legs_cell: Vector2i = Vector2i(7, 4)
@export var core_cell: Vector2i = Vector2i(8, 3)

# Map hookup
var M: MapController = null

# Tracks which weakpoints still exist
var parts_alive := {
	&"LEFT_ARM": true,
	&"RIGHT_ARM": true,
	&"LEGS": true,
	&"CORE": true,
}

# Planned attacks for next resolve:
# each entry: { "cells": Array[Vector2i], "dmg": int }
var planned_attacks: Array = []

@export var impact_delay_sec: float = 0.30         # delay before damage resolves
@export var between_impacts_sec: float = 0.05      # stagger per cell (optional)
@export var splash_radius: int = 1                 # 1 = adjacent Manhattan
@export var explosion_fx_scene: PackedScene        # a Node2D/VFX scene
@export var explosion_sfx: AudioStream             # boom sound
@export var explosion_sfx_bus: StringName = &"SFX" # your SFX bus name

# -------------------------
# Public setup
# -------------------------
func setup(map_controller: MapController) -> void:
	M = map_controller
	boss_hp = boss_max_hp
	phase = 1
	planned_attacks.clear()

	_spawn_weakpoints()
	_plan_next_turn() # telegraph immediately


# -------------------------
# Weakpoints (single scene, 4 instances)
# -------------------------
func _spawn_weakpoints() -> void:
	if M == null:
		return

	_spawn_wp(weakpoint_scene, left_arm_cell, &"LEFT_ARM", 3, 3, wp_left_arm_tex)
	_spawn_wp(weakpoint_scene, right_arm_cell, &"RIGHT_ARM", 3, 3, wp_right_arm_tex)
	_spawn_wp(weakpoint_scene, legs_cell, &"LEGS", 4, 3, wp_legs_tex)
	_spawn_wp(weakpoint_scene, core_cell, &"CORE", 5, 6, wp_core_tex)

func _spawn_wp(scene: PackedScene, cell: Vector2i, id: StringName, hp_val: int, boss_damage_on_destroy: int, tex: Texture2D) -> void:
	if scene == null:
		return
	if not parts_alive.has(id) or parts_alive[id] == false:
		return
	if M == null or M.terrain == null or M.units_root == null:
		return
	if not _in_bounds(cell):
		return
	# don't overwrite an occupied cell
	if M.units_by_cell.has(cell):
		return

	var u := scene.instantiate() as Unit
	if u == null:
		return

	# --- place & register (TileMap-required) ---
	M.units_root.add_child(u)
	u.cell = cell
	u.z_index = _z_from_cell(cell)
	u.position = M.terrain.map_to_local(cell)

	M.units_by_cell[cell] = u

	# --- configure as boss part ---
	u.team = Unit.Team.ENEMY
	u.move_range = 0
	u.attack_range = 0
	u.max_hp = hp_val
	u.hp = hp_val

	u.set_meta("boss_part_id", id)
	u.set_meta("boss_damage_on_destroy", boss_damage_on_destroy)
	u.set_meta("is_boss_part", true)

	# Optional: set a texture if your weakpoint scene has Sprite2D child named "Sprite"
	if tex != null:
		var spr := u.get_node_or_null("Sprite") as Sprite2D
		if spr != null:
			spr.texture = tex

func _z_from_cell(c: Vector2i) -> int:
	# Lower = behind, higher = in front
	# You can tweak base if your project uses a different z band for units.
	var base := 0
	return base + (c.x + c.y)

func on_weakpoint_destroyed(part_id: StringName, boss_damage: int) -> void:
	if parts_alive.has(part_id):
		parts_alive[part_id] = false

	_apply_boss_damage(boss_damage)

	# Re-plan immediately so player sees the change next turn
	_plan_next_turn()


# -------------------------
# Boss HP / phases
# -------------------------
func _apply_boss_damage(amount: int) -> void:
	var dmg = max(0, amount)
	boss_hp = max(0, boss_hp - dmg)
	_update_phase()

	if boss_hp <= 0:
		_clear_intents()
		emit_signal("boss_defeated")

func _update_phase() -> void:
	# Phase 2 at <= 66%, phase 3 at <= 33%
	var t1 := int(ceil(float(boss_max_hp) * 0.66))
	var t2 := int(ceil(float(boss_max_hp) * 0.33))

	var new_phase := 1
	if boss_hp <= t2:
		new_phase = 3
	elif boss_hp <= t1:
		new_phase = 2

	phase = new_phase


# -------------------------
# Turn flow
# -------------------------
# Called at start of enemy phase (or right before enemies act): apply attacks from last plan
func resolve_planned_attacks() -> void:
	# keep this wrapper so existing callers don’t crash
	await resolve_planned_attacks_async()

func resolve_planned_attacks_async() -> void:
	if M == null:
		return
	if planned_attacks.is_empty():
		return

	# Small readable delay before impacts start
	if impact_delay_sec > 0.0:
		await get_tree().create_timer(impact_delay_sec).timeout

	# ✅ Collect all impacted cells (with splash) once, so a cell only gets hit once per resolve
	var hit_set: Dictionary = {} # Vector2i -> true
	var max_dmg_for_cell: Dictionary = {} # Vector2i -> int

	for a in planned_attacks:
		var core_cells: Array = a.get("cells", [])
		var dmg: int = int(a.get("dmg", 1))

		var hit_cells: Array[Vector2i] = _cells_with_splash(core_cells, splash_radius)
		for c in hit_cells:
			hit_set[c] = true
			# if two attacks overlap, keep the higher damage (fair + simple)
			var prev := int(max_dmg_for_cell.get(c, 0))
			if dmg > prev:
				max_dmg_for_cell[c] = dmg

	# ✅ Stagger impacts for juice
	var hit_cells_ordered: Array[Vector2i] = []
	for c in hit_set.keys():
		hit_cells_ordered.append(c)

	# optional: consistent-ish order (front to back)
	hit_cells_ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x + a.y) < (b.x + b.y)
	)

	for c in hit_cells_ordered:
		_spawn_explosion_at_cell(c)

		var dmg := int(max_dmg_for_cell.get(c, 1))

		var u = M.units_by_cell.get(c, null)
		if u != null and is_instance_valid(u) and u.hp > 0:
			# ✅ Splash hurts ANY unit (allies + zombies + weakpoints, etc.)
			u.take_damage(dmg)

		if between_impacts_sec > 0.0:
			await get_tree().create_timer(between_impacts_sec).timeout

	_clear_intents()

func plan_next_attacks() -> void:
	_plan_next_turn()

# -------------------------
# Plan + telegraph
# -------------------------
func _plan_next_turn() -> void:
	if M == null:
		return

	planned_attacks.clear()
	_clear_intents()

	# attacks per phase
	var attacks_to_plan := 1
	if phase == 2:
		attacks_to_plan = 2
	elif phase == 3:
		attacks_to_plan = 3

	var patterns: Array[Callable] = []

	# Arms enable slam + row sweep
	if parts_alive.get(&"LEFT_ARM", false) or parts_alive.get(&"RIGHT_ARM", false):
		patterns.append(Callable(self, "_pat_slam_3x3"))
		patterns.append(Callable(self, "_pat_sweep_row"))

	# Legs enable shockwave ring
	if parts_alive.get(&"LEGS", false):
		patterns.append(Callable(self, "_pat_shockwave_ring"))

	# Core enables plus burst
	if parts_alive.get(&"CORE", false):
		patterns.append(Callable(self, "_pat_core_burst_plus"))

	if patterns.is_empty():
		patterns.append(Callable(self, "_pat_slam_3x3"))

	for i in range(attacks_to_plan):
		var pick := patterns[randi() % patterns.size()]
		var attack = pick.call()
		if attack is Dictionary:
			planned_attacks.append(attack)

	# Telegraph cells
	var all_cells: Array[Vector2i] = []
	for a in planned_attacks:
		var arr = a.get("cells", [])
		for c in arr:
			if c is Vector2i:
				all_cells.append(c)

	if "boss_show_intents" in M:
		M.boss_show_intents(all_cells)

func _clear_intents() -> void:
	if M != null and "boss_clear_intents" in M:
		M.boss_clear_intents()
	planned_attacks.clear()


# -----------------------------------------
# Patterns (return Dictionary {cells:Array[Vector2i], dmg:int})
# -----------------------------------------
func _pat_slam_3x3() -> Dictionary:
	var center := _pick_target_cell_prefer_allies()
	var cells: Array[Vector2i] = []

	var dmg := 1
	if phase == 3:
		dmg = 2

	var dxs := [-1, 0, 1]
	var dys := [-1, 0, 1]
	for dx in dxs:
		for dy in dys:
			var c := center + Vector2i(dx, dy)
			if _in_bounds(c):
				cells.append(c)

	return {"cells": cells, "dmg": dmg}

func _pat_sweep_row() -> Dictionary:
	var target := _pick_target_cell_prefer_allies()
	var y := target.y

	var w := _get_map_w()
	var cells: Array[Vector2i] = []
	for x in range(w):
		var cc := Vector2i(x, y)
		if _in_bounds(cc):
			cells.append(cc)

	return {"cells": cells, "dmg": 1}

func _pat_shockwave_ring() -> Dictionary:
	var center := _pick_target_cell_prefer_allies()

	var r := 2
	if phase == 2:
		r = 3
	elif phase == 3:
		r = 4

	var cells: Array[Vector2i] = []
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var dist = abs(dx) + abs(dy)
			if dist == r:
				var c := center + Vector2i(dx, dy)
				if _in_bounds(c):
					cells.append(c)

	return {"cells": cells, "dmg": 1}

func _pat_core_burst_plus() -> Dictionary:
	var center := _pick_target_cell_prefer_allies()

	var length := 3
	if phase == 2:
		length = 4
	elif phase == 3:
		length = 5

	var dmg := 1
	if phase == 3:
		dmg = 2

	var cells: Array[Vector2i] = []
	if _in_bounds(center):
		cells.append(center)

	var dirs := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for i in range(1, length + 1):
		for dir in dirs:
			var c = center + dir * i
			if _in_bounds(c):
				cells.append(c)

	return {"cells": cells, "dmg": dmg}


# -----------------------------------------
# Apply damage to units in cells (robust)
# -----------------------------------------
func _apply_attack(cells: Array, dmg: int) -> void:
	if M == null:
		return

	for c in cells:
		if not (c is Vector2i):
			continue
		var u = M.units_by_cell.get(c, null)
		if u == null or not is_instance_valid(u):
			continue
		if u.hp <= 0:
			continue

		# Boss mainly hits allies
		if u.team != Unit.Team.ALLY:
			continue

		# Try common damage APIs without crashing
		if "take_damage" in u:
			u.take_damage(dmg)
		elif "apply_damage" in u:
			u.apply_damage(dmg)
		elif "hit" in u:
			u.hit(dmg)
		else:
			# last resort: subtract hp
			u.hp = max(0, int(u.hp) - dmg)


# -----------------------------------------
# Target selection helpers
# -----------------------------------------
func _pick_target_cell_prefer_allies() -> Vector2i:
	# Prefer ally cells
	var ally_cells: Array[Vector2i] = []
	for u in _get_all_units_safe():
		if u == null or not is_instance_valid(u):
			continue
		if u.hp <= 0:
			continue
		if u.team == Unit.Team.ALLY:
			ally_cells.append(u.cell)

	if not ally_cells.is_empty():
		return ally_cells[randi() % ally_cells.size()]

	# fallback: center-ish
	return Vector2i(_get_map_w() / 2, _get_map_h() / 2)

func _get_all_units_safe() -> Array:
	# Prefer MapController helper if you have it
	if M != null and ("get_all_units" in M):
		return M.get_all_units()

	# Fallback: iterate dictionary values
	var out: Array = []
	if M != null and M.units_by_cell != null:
		for k in M.units_by_cell.keys():
			out.append(M.units_by_cell[k])
	return out


# -----------------------------------------
# Bounds helpers (no M.grid dependency)
# -----------------------------------------
func _get_map_w() -> int:
	if M != null and ("map_width" in M):
		return int(M.map_width)
	if M != null and M.grid != null and ("w" in M.grid):
		return int(M.grid.w)
	# default (your game is often 16x16)
	return 16

func _get_map_h() -> int:
	if M != null and ("map_height" in M):
		return int(M.map_height)
	if M != null and M.grid != null and ("h" in M.grid):
		return int(M.grid.h)
	return 16

func _in_bounds(c: Vector2i) -> bool:
	var w := _get_map_w()
	var h := _get_map_h()
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h

func _cells_with_splash(core_cells: Array, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen: Dictionary = {}

	for cc in core_cells:
		var c := cc as Vector2i
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				var md = abs(dx) + abs(dy)
				if md > radius:
					continue
				var p := c + Vector2i(dx, dy)
				if _in_bounds(p) and not seen.has(p):
					seen[p] = true
					out.append(p)
	return out

func _spawn_explosion_at_cell(c: Vector2i) -> void:
	if M == null or M.terrain == null:
		return

	# VFX
	if explosion_fx_scene != null:
		var fx := explosion_fx_scene.instantiate()
		# Prefer overlay_root if you have it, otherwise just add to MapController
		if "overlay_root" in M and M.overlay_root != null:
			M.overlay_root.add_child(fx)
		else:
			M.add_child(fx)

		fx.global_position = M.terrain.map_to_local(c)

		# Layer by grid sum so it sits correctly
		if fx is CanvasItem:
			(fx as CanvasItem).z_index = (c.x + c.y) + 150

		# Auto cleanup if it doesn’t already
		if fx.has_method("play"):
			fx.call("play")
		else:
			# safety cleanup after a moment
			get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(fx): fx.queue_free())

	# SFX
	if explosion_sfx != null:
		var p := AudioStreamPlayer.new()
		p.bus = String(explosion_sfx_bus)
		p.stream = explosion_sfx
		add_child(p)
		p.play()
		p.finished.connect(func():
			if is_instance_valid(p):
				p.queue_free()
		)
