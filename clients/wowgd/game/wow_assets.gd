@tool
extends Node

const TERRAIN_SHADER: Shader = preload("res://game/world/terrain.gdshader")
# Indexed by liquid type: water, ocean, magma, slime.
const LIQUID_MATERIALS: Array[Material] = [
	preload("res://game/world/liquid_water.tres"),
	preload("res://game/world/liquid_ocean.tres"),
	preload("res://game/world/liquid_magma.tres"),
	preload("res://game/world/liquid_slime.tres"),
]

var archive: WowArchive:
	get:
		if _archive == null:
			_open()
		return _archive
var loader: WowLoader:
	get:
		if _loader == null:
			_open()
		return _loader
var characters: CharacterModels:
	get:
		if _characters == null:
			_characters = CharacterModels.new(loader)
		return _characters
var creatures: CreatureModels:
	get:
		if _creatures == null:
			_creatures = CreatureModels.new(loader, characters)
		return _creatures

var _archive: WowArchive
var _loader: WowLoader
var _characters: CharacterModels
var _creatures: CreatureModels


func _open() -> void:
	_archive = WowArchive.new()
	var data_dir: String = ProjectSettings.get_setting("wowgd/client_data_dir", "")
	if _archive.open(data_dir) != OK:
		push_error("WowAssets: cannot open client data at '%s'" % data_dir)
	_loader = WowLoader.new()
	_loader.archive = _archive
	_loader.terrain_shader = TERRAIN_SHADER
	_loader.liquid_materials = LIQUID_MATERIALS
