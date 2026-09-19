class_name SpellButton
extends WowButton

# The spell this button shows, which a drag carries to an action button; 0 for an empty slot.
var spell_id: int = 0


func _get_drag_data(_at_position: Vector2) -> Variant:
	if spell_id == 0 or WowAssets.spells.is_passive(spell_id):
		return null
	var preview: TextureRect = TextureRect.new()
	preview.texture = WowAssets.spells.icon(spell_id)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.size = size
	set_drag_preview(preview)
	return {"spell": spell_id}
