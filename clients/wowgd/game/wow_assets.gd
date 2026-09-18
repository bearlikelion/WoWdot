@tool
extends Node

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
var creatures: CreatureModels:
	get:
		if _creatures == null:
			_creatures = CreatureModels.new(loader)
		return _creatures

var _archive: WowArchive
var _loader: WowLoader
var _creatures: CreatureModels


func _open() -> void:
	_archive = WowArchive.new()
	var data_dir: String = ProjectSettings.get_setting("wowgd/client_data_dir", "")
	if _archive.open(data_dir) != OK:
		push_error("WowAssets: cannot open client data at '%s'" % data_dir)
	_loader = WowLoader.new()
	_loader.archive = _archive
