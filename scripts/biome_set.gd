extends Resource
class_name BiomeSet

@export var id: StringName = &"biome_default"
@export var display_name: String = "Default"

# Optional: only use if you want to lock/unlock later
@export var unlocked_by_default: bool = true

# Textures that override your existing TileSet source IDs
@export var dirt: Texture2D
@export var sandstone: Texture2D
@export var snow: Texture2D
@export var grass: Texture2D
@export var ice: Texture2D
@export var water: Texture2D # can be null to reuse global water
