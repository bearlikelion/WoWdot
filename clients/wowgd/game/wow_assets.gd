@tool
extends Node

const TERRAIN_SHADER: Shader = preload("res://game/world/terrain.gdshader")
const AUDIO: PackedScene = preload("res://game/wow_audio.tscn")
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
var spells: SpellInfo:
	get:
		if _spells == null:
			_spells = SpellInfo.new(archive)
		return _spells
var spell_visuals: SpellVisuals:
	get:
		if _spell_visuals == null:
			_spell_visuals = SpellVisuals.new(archive)
		return _spell_visuals
var audio: WowAudio:
	get:
		if _audio == null:
			_audio = AUDIO.instantiate()
			add_child(_audio)
		return _audio
var video: VideoSettings:
	get:
		if _video == null:
			_video = VideoSettings.new()
		return _video

var _archive: WowArchive
var _loader: WowLoader
var _characters: CharacterModels
var _creatures: CreatureModels
var _spells: SpellInfo
var _spell_visuals: SpellVisuals
var _audio: WowAudio
var _video: VideoSettings


# One shared loader, so WowTexture resources and the world use the same archive and caches.
func _open() -> void:
	_loader = WowLoader.get_shared()
	_archive = _loader.archive
	_loader.terrain_shader = TERRAIN_SHADER
	_loader.liquid_materials = LIQUID_MATERIALS
