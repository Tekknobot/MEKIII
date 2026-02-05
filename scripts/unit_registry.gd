# res://scenes/units/unit_registry.gd
extends Node
class_name UnitRegistry

# These preloads FORCE Godot to include the .tscn in exports
const FORCE_EXPORT := [
	preload("res://scenes/units/allies/human.tscn"),
	preload("res://scenes/units/allies/humantwo.tscn"),
	preload("res://scenes/units/allies/M1.tscn"),
	preload("res://scenes/units/allies/M2.tscn"),
	preload("res://scenes/units/allies/mech.tscn"),
	preload("res://scenes/units/allies/mechtwo.tscn"),
	preload("res://scenes/units/allies/R1.tscn"),
	preload("res://scenes/units/allies/R2.tscn"),
	preload("res://scenes/units/allies/S2.tscn"),
	preload("res://scenes/units/allies/S3.tscn"),
	preload("res://scenes/units/allies/car.tscn"),
]

# These strings are what RunState should use to build roster_scene_paths
const ALLY_PATHS: Array[String] = [
	"res://scenes/units/allies/human.tscn",
	"res://scenes/units/allies/humantwo.tscn",
	"res://scenes/units/allies/M1.tscn",
	"res://scenes/units/allies/M2.tscn",
	"res://scenes/units/allies/mech.tscn",
	"res://scenes/units/allies/mechtwo.tscn",
	"res://scenes/units/allies/R1.tscn",
	"res://scenes/units/allies/R2.tscn",
	"res://scenes/units/allies/S2.tscn",
	"res://scenes/units/allies/S3.tscn",
	"res://scenes/units/allies/car.tscn",
]
