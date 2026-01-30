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

@export var boss_anchor_y := 1              # how close to top edge (0 is very top row)
@export var boss_top_x_bias := 0.50         # 0.50 = exact top center, 0.66 = between center & right, 0.75 = more right
@export var boss_pixel_offset := Vector2.ZERO  # fine tune in pixels if needed

@export var boss_flash_node_path: NodePath   # optional: set to your Sprite2D (or boss art root)
@export var boss_flash_time := 0.10

@export var boss_exit_rise_px := 260.0       # how far up it flies
@export var boss_exit_time := 2.55
@export var boss_exit_ease := Tween.EASE_IN
@export var boss_exit_trans := Tween.TRANS_QUAD

var _boss_flash_tw: Tween = null
var _exiting := false

# -------------------------
# Public setup
# -------------------------
func setup(map_controller: MapController) -> void:
	M = map_controller
	boss_hp = boss_max_hp
	phase = 1
	planned_attacks.clear()

	_pick_valid_weakpoint_cells_top_right()

	_position_big_sprite()

	_spawn_weakpoints()
	_plan_next_turn()

func _pick_valid_weakpoint_cells_top_right() -> void:
	if M == null:
		return

	var w := _get_map_w()
	var h := _get_map_h()

	# Bias: top edge + between center and right corner
	var base_x := clampi(int(round((w - 1) * 0.66)), 0, w - 1)
	var base_y := clampi(2, 0, h - 1)

	# Offsets for your 4 parts relative to an anchor
	# (tweak these if you want a wider boss)
	var rel := {
		&"LEFT_ARM":  Vector2i(-2, 0),
		&"RIGHT_ARM": Vector2i( 2, 0),
		&"CORE":      Vector2i( 0, 1),
		&"LEGS":      Vector2i( 0, 2),
	}

	# Try nearby anchors (spiral-ish search)
	var tries: Array[Vector2i] = []
	for r in range(0, 6):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue
				tries.append(Vector2i(dx, dy))

	for off in tries:
		var anchor := Vector2i(
			clampi(base_x + off.x, 0, w - 1),
			clampi(base_y + off.y, 0, h - 1)
		)

		var cells := {
			&"LEFT_ARM":  anchor + rel[&"LEFT_ARM"],
			&"RIGHT_ARM": anchor + rel[&"RIGHT_ARM"],
			&"CORE":      anchor + rel[&"CORE"],
			&"LEGS":      anchor + rel[&"LEGS"],
		}

		if _all_cells_valid_for_spawn(cells.values()):
			left_arm_cell  = cells[&"LEFT_ARM"]
			right_arm_cell = cells[&"RIGHT_ARM"]
			core_cell      = cells[&"CORE"]
			legs_cell      = cells[&"LEGS"]
			return

	# Fallback (if everything fails): keep existing exports
	# but at least clamp them
	left_arm_cell  = Vector2i(clampi(left_arm_cell.x, 0, w-1),  clampi(left_arm_cell.y, 0, h-1))
	right_arm_cell = Vector2i(clampi(right_arm_cell.x, 0, w-1), clampi(right_arm_cell.y, 0, h-1))
	core_cell      = Vector2i(clampi(core_cell.x, 0, w-1),      clampi(core_cell.y, 0, h-1))
	legs_cell      = Vector2i(clampi(legs_cell.x, 0, w-1),      clampi(legs_cell.y, 0, h-1))

func _all_cells_valid_for_spawn(cells: Array) -> bool:
	if M == null:
		return false

	var game := M.game_ref
	var structure_blocked: Dictionary = {}
	if game != null and ("structure_blocked" in game):
		structure_blocked = game.structure_blocked

	var seen := {}
	for cc in cells:
		if not (cc is Vector2i):
			return false
		var c := cc as Vector2i

		# in-bounds
		if not _in_bounds(c):
			return false

		# no duplicates
		if seen.has(c):
			return false
		seen[c] = true

		# must be walkable
		if M.has_method("_is_walkable"):
			if not M._is_walkable(c):
				return false
		else:
			# fallback: if you don't have _is_walkable accessible, at least require terrain exists
			pass

		# must not already have a unit (robust)
		if _cell_has_any_unit(c):
			return false

		# must not be blocked by structures
		if structure_blocked.has(c):
			return false

	return true
	
func _position_big_sprite() -> void:
	if M == null or M.terrain == null:
		return

	var w := _get_map_w()
	var h := _get_map_h()

	var ax := clampi(int(round((w - 1) * boss_top_x_bias)), 0, w - 1)
	var ay := clampi(boss_anchor_y, 0, h - 1)

	var anchor_cell := Vector2i(ax, ay)

	# Convert cell -> GLOBAL position on your map
	var world := M.terrain.to_global(M.terrain.map_to_local(anchor_cell))

	global_position = world + boss_pixel_offset

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
	# don't overwrite an occupied cell (robust)
	if _cell_has_any_unit(cell):
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
	if _exiting:
		return

	if parts_alive.has(part_id):
		parts_alive[part_id] = false

	# ✅ flash boss immediately
	_flash_boss_white(0.12)

	# Apply boss HP damage (your existing behavior)
	_apply_boss_damage(boss_damage)

	# ✅ if all weakpoints are gone, fly up and free
	if _all_parts_dead():
		_clear_intents()
		emit_signal("boss_defeated")
		_exit_and_free()
		return

	# Otherwise: re-plan so intents change next turn
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

	# delay before anything happens
	if impact_delay_sec > 0.0:
		await get_tree().create_timer(impact_delay_sec).timeout

	var hit_set: Dictionary = {}              # splash+core damage targets
	var max_dmg_for_cell: Dictionary = {}     # Vector2i -> int
	var intent_fx_set: Dictionary = {}        # ONLY core intent tiles for VFX

	# -------------------------
	# Collect targets
	# -------------------------
	for a in planned_attacks:
		var core_cells: Array = a.get("cells", [])
		var dmg: int = int(a.get("dmg", 1))

		# VFX only on core intent tiles
		for cc in core_cells:
			if cc is Vector2i and _in_bounds(cc):
				intent_fx_set[cc] = true

		# Damage applies to splash area (includes core)
		var hit_cells: Array[Vector2i] = _cells_with_splash(core_cells, splash_radius)
		for c in hit_cells:
			hit_set[c] = true
			var prev := int(max_dmg_for_cell.get(c, 0))
			if dmg > prev:
				max_dmg_for_cell[c] = dmg

	# -------------------------
	# Build ordered lists
	# -------------------------
	var fx_cells_ordered: Array[Vector2i] = []
	for k in intent_fx_set.keys():
		fx_cells_ordered.append(k as Vector2i)
	fx_cells_ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x + a.y) < (b.x + b.y)
	)

	var hit_cells_ordered: Array[Vector2i] = []
	for k in hit_set.keys():
		hit_cells_ordered.append(k as Vector2i)
	hit_cells_ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a.x + a.y) < (b.x + b.y)
	)

	# -------------------------
	# VFX pass (intent tiles only) with stagger
	# -------------------------
	for c in fx_cells_ordered:
		_spawn_explosion_at_cell(c)
		if between_impacts_sec > 0.0:
			await get_tree().create_timer(between_impacts_sec).timeout

	# Optional tiny beat between VFX and damage (feel free to remove)
	# await get_tree().create_timer(0.05).timeout

	# -------------------------
	# Damage pass (splash+core) with stagger
	# -------------------------
	for c in hit_cells_ordered:
		var dmg := int(max_dmg_for_cell.get(c, 1))

		var u = M.units_by_cell.get(c, null)
		if u != null and is_instance_valid(u) and u.hp > 0:
			u.take_damage(dmg)
			M._flash_unit_white(u, 0.88)
		else:
			_hit_structures_at_cell(c, dmg)

		if between_impacts_sec > 0.0:
			await get_tree().create_timer(between_impacts_sec).timeout

	_clear_intents()

func _hit_structures_at_cell(c: Vector2i, dmg: int) -> void:
	for s in get_tree().get_nodes_in_group("Structures"):
		if s == null or not is_instance_valid(s):
			continue
		if not (s is Structure):
			continue

		var st := s as Structure
		if st.is_destroyed():
			continue

		if st.occupies_cell(c):
			st.apply_damage(dmg)
			M._flash_structure_white(st, 0.88)

func plan_next_attacks() -> void:
	_plan_next_turn()

func _flash_structures_hit_at_cell(c: Vector2i, dur := 0.12) -> void:
	if M == null or M.terrain == null:
		return

	# Use terrain local coords so it matches how structures were positioned
	var cell_pos := M.terrain.map_to_local(c)

	for s in get_tree().get_nodes_in_group("Structures"):
		if s == null or not is_instance_valid(s):
			continue
		if not (s is Node2D):
			continue

		# --- determine footprint (default 1x1) ---
		var origin: Vector2i = Vector2i(-999, -999)
		var size: Vector2i = Vector2i(1, 1)

		# Prefer meta if you set it (recommended)
		if s.has_meta("origin_cell"):
			origin = s.get_meta("origin_cell") as Vector2i
		if s.has_meta("footprint"):
			size = s.get_meta("footprint") as Vector2i

		# If no meta, fallback: approximate origin from position
		if origin.x < -900:
			origin = M.terrain.local_to_map((s as Node2D).position)

		# Check if hit cell is within structure footprint
		if c.x >= origin.x and c.y >= origin.y and c.x < origin.x + size.x and c.y < origin.y + size.y:
			M._flash_unit_white(s, dur) # ✅ "just use _flash_unit"

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

		fx.global_position = M.terrain.to_global(M.terrain.map_to_local(c))
		fx.global_position.y -= 16

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

func _get_flash_target() -> CanvasItem:
	# Prefer explicit node
	if boss_flash_node_path != NodePath(""):
		var n := get_node_or_null(boss_flash_node_path)
		if n != null and n is CanvasItem:
			return n as CanvasItem

	# Fallback: a child named "Sprite"
	var spr := get_node_or_null("Sprite")
	if spr != null and spr is CanvasItem:
		return spr as CanvasItem

	# Fallback: this node if it can modulate
	if self is CanvasItem:
		return self as CanvasItem

	return null


func _flash_boss_white(dur := -1.0) -> void:
	if dur <= 0.0:
		dur = boss_flash_time

	var target := _get_flash_target()
	if target == null:
		return

	if _boss_flash_tw != null and is_instance_valid(_boss_flash_tw):
		_boss_flash_tw.kill()

	# Store original modulation
	var orig := target.modulate

	# Flash to white and back
	_boss_flash_tw = create_tween()
	_boss_flash_tw.tween_property(target, "modulate", Color(1.0, 0.0, 0.0, 1.0), dur * 0.5)
	_boss_flash_tw.tween_property(target, "modulate", orig, dur * 0.5)


func _all_parts_dead() -> bool:
	for k in parts_alive.keys():
		if bool(parts_alive[k]) == true:
			return false
	return true


func _exit_and_free() -> void:
	if _exiting:
		return
	_exiting = true

	# stop planning/telegraphing
	_clear_intents()

	# Optional: disable processing if you use it
	set_process(false)
	set_physics_process(false)

	# Tween up and fade out a bit
	var start_pos := global_position
	var end_pos := start_pos + Vector2(0, -boss_exit_rise_px)

	# If you want it to go fully off-screen relative to the camera/viewport, you can
	# increase boss_exit_rise_px or compute from viewport size. Keeping it simple here.

	var tw := create_tween()
	tw.set_trans(boss_exit_trans)
	tw.set_ease(boss_exit_ease)

	tw.tween_property(self, "global_position", end_pos, boss_exit_time)

	# Fade if possible (boss art node)
	var target := _get_flash_target()
	if target != null:
		tw.parallel().tween_property(target, "modulate:a", 0.0, boss_exit_time)

	tw.finished.connect(func():
		if is_instance_valid(self):
			queue_free()
	)

func _cell_has_any_unit(c: Vector2i) -> bool:
	if M == null:
		return false

	# Primary truth in your game
	if M.units_by_cell != null and M.units_by_cell.has(c):
		var u = M.units_by_cell.get(c, null)
		if u != null and is_instance_valid(u):
			return true

	# Extra safety: scan Units under units_root (covers cases where dict wasn't updated)
	if M.units_root != null:
		for ch in M.units_root.get_children():
			if ch == null or not is_instance_valid(ch):
				continue
			if ch is Unit:
				var uu := ch as Unit
				if uu.cell == c and uu.hp > 0:
					return true

	return false
