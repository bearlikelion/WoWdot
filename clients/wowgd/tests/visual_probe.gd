class_name VisualProbe
extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var archive: WowArchive = WowAssets.archive
	var spells: WowDBC = WowDBC.open(archive, "Spell")
	var visuals: WowDBC = WowDBC.open(archive, "SpellVisual")
	var kits: WowDBC = WowDBC.open(archive, "SpellVisualKit")
	var anims: WowDBC = WowDBC.open(archive, "AnimationData")
	for spell: int in [133, 116, 168, 5185, 2098, 78]:
		var visual_row: int = visuals.find(spells.get_uint(spells.find(spell), "SpellVisualID"))
		if visual_row < 0:
			continue
		var line: PackedStringArray = []
		for kit_name: String in ["PrecastKit", "CastKit", "ImpactKit"]:
			var kit_row: int = kits.find(visuals.get_uint(visual_row, kit_name))
			if kit_row < 0:
				continue
			var names: PackedStringArray = []
			for column: int in [1, 2]:
				var id: int = kits.get_int(kit_row, column)
				var anim_row: int = anims.find(id) if id >= 0 else -1
				names.append("%d=%s" % [id, anims.get_string(anim_row, 1) if anim_row >= 0 else "-"])
			line.append("%s[%s]" % [kit_name, ", ".join(names)])
		print("spell %d: %s" % [spell, "  ".join(line)])
	get_tree().quit()
