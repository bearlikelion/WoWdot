class_name GDDocsCli
extends SceneTree

# godot --headless --path . --script res://addons/gddocs/gddocs_cli.gd


func _init() -> void:
	var error: Error = GDDocsBuilder.build()
	if error == OK:
		print("GDDocs: wrote %s" % GDDocsBuilder.output_path())
	quit(error)
