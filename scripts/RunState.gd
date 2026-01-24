# res://scripts/RunState.gd
extends Node
class_name RunState

# Flat list (optional, useful for UI/history)
var run_upgrades: Array[StringName] = []

# Counted storage (this is what stacking uses)
var run_upgrade_counts: Dictionary = {} # StringName -> int


func clear() -> void:
	run_upgrades.clear()
	run_upgrade_counts.clear()


func add_upgrade(id: StringName) -> void:
	# Always append to history list
	run_upgrades.append(id)

	# Increment count (stacking)
	run_upgrade_counts[id] = int(run_upgrade_counts.get(id, 0)) + 1


func has_upgrade(id: StringName) -> bool:
	return run_upgrade_counts.has(id)


func get_upgrade_count(id: StringName) -> int:
	return int(run_upgrade_counts.get(id, 0))
