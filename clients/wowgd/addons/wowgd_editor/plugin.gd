@tool
extends EditorPlugin

const ASSET_DOCK: PackedScene = preload("res://addons/wowgd_editor/asset_dock.tscn")

var _dock: WowAssetDock


func _enter_tree() -> void:
	_dock = ASSET_DOCK.instantiate()
	_dock.asset_chosen.connect(_on_asset_chosen)
	add_control_to_dock(DOCK_SLOT_LEFT_UR, _dock)


func _exit_tree() -> void:
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _on_asset_chosen(path: String) -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		push_warning("Open a 3D scene before adding WoW models.")
		return
	var selected: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	var parent: Node = selected[0] if not selected.is_empty() else root
	var model: WowModel = WowModel.new()
	model.name = path.replace("\\", "/").get_file().get_basename()
	model.model_path = path
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Add WoW model")
	undo.add_do_method(parent, "add_child", model, true)
	undo.add_do_method(model, "set_owner", root)
	undo.add_do_reference(model)
	undo.add_undo_method(parent, "remove_child", model)
	undo.commit_action()
