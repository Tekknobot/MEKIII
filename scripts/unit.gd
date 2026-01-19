extends Node2D
class_name Unit

enum Team { ALLY, ENEMY }

# -------------------------
# Core stats (what Human expects)
# -------------------------
@export var team: Team = Team.ALLY

@export var footprint_size: Vector2i = Vector2i(1, 1)

@export var move_range: int = 3
@export var attack_range: int = 3
@export var attack_damage: int = 1

@export var tnt_throw_range: int = 0

@export var max_hp: int = 3
@export var hp: int = 3

# -------------------------
# Placement + layering
# -------------------------
var cell: Vector2i = Vector2i.ZERO

@export var z_base: int = 1
@export var z_per_cell: int = 1

@export var sprite_path: NodePath = NodePath("Sprite2D")
@onready var spr: Sprite2D = get_node_or_null(sprite_path) as Sprite2D

func _ready() -> void:
	# Base init so children can safely call super._ready()
	hp = clamp(hp, 0, max_hp)
	_update_depth()

func set_cell(c: Vector2i, terrain: TileMap) -> void:
	cell = c
	if terrain and is_instance_valid(terrain):
		global_position = terrain.to_global(terrain.map_to_local(c))
	_update_depth()

func _update_depth() -> void:
	z_as_relative = false
	# ✅ x+y sum layering (matches your practice)
	z_index = 1 + (cell.x + cell.y) * z_per_cell

func set_selected(on: bool) -> void:
	if spr:
		spr.modulate = (Color(1, 1, 1) if not on else Color(1.25, 1.25, 1.25))

func take_damage(dmg: int) -> void:
	hp = max(hp - dmg, 0)
