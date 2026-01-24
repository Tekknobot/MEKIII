# res://scripts/RunState.gd
extends Node
class_name RunState

var run_upgrades: Array[StringName] = []

func clear():
	run_upgrades.clear()

func add_upgrade(id: StringName):
	if not run_upgrades.has(id):
		run_upgrades.append(id)

func has_upgrade(id: StringName) -> bool:
	return run_upgrades.has(id)
