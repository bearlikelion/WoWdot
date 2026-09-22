class_name LFGArt
extends RefCounted

const ICON_SIZE: float = 67.0
const BACKGROUND_SIZE: float = 75.0
# EyeTemplate's first frame on LFG-Eye.
const EYE_FRAME: Rect2 = Rect2(0, 0, 64, 64)
const COVER_ALPHA: float = 0.7
const DESATURATE: Shader = preload("res://ui/desaturate.gdshader")
# GetTexCoordsForRole's cell on UI-LFG-ICON-ROLES.
const ICON_CELLS: Dictionary[DungeonFinder.Role, Vector2] = {
	DungeonFinder.Role.TANK: Vector2(0, 1),
	DungeonFinder.Role.HEALER: Vector2(1, 0),
	DungeonFinder.Role.DAMAGE: Vector2(1, 1),
	DungeonFinder.Role.LEADER: Vector2(0, 0),
}
# GetBackgroundTexCoordsForRole's cell on UI-LFG-ROLE-BACKGROUNDS.
const BACKGROUND_CELLS: Dictionary[DungeonFinder.Role, Vector2] = {
	DungeonFinder.Role.TANK: Vector2(1, 0),
	DungeonFinder.Role.HEALER: Vector2(0, 0),
	DungeonFinder.Role.DAMAGE: Vector2(2, 0),
}
const NAMES: Dictionary[DungeonFinder.Role, String] = {
	DungeonFinder.Role.TANK: "TANK",
	DungeonFinder.Role.HEALER: "HEALER",
	DungeonFinder.Role.DAMAGE: "DAMAGER",
}


# The role a mask shows as, tank before healer before damage.
static func main_role(roles: int) -> DungeonFinder.Role:
	for role: DungeonFinder.Role in NAMES:
		if roles & role:
			return role
	return DungeonFinder.Role.DAMAGE


static func icon(rect: TextureRect, role: DungeonFinder.Role) -> void:
	_crop(rect, Rect2(ICON_CELLS[role] * ICON_SIZE, Vector2.ONE * ICON_SIZE))


static func background(rect: TextureRect, role: DungeonFinder.Role) -> void:
	_crop(rect, Rect2(BACKGROUND_CELLS[role] * BACKGROUND_SIZE, Vector2.ONE * BACKGROUND_SIZE))


# LFG_EnableRoleButton and LFG_PermanentlyDisableRoleButton for a class that cannot take the role.
static func set_role_available(button: BaseButton, available: bool) -> void:
	var check: BaseButton = button.get_node("CheckButton")
	var icon_rect: CanvasItem = button.get_node("NormalTexture")
	button.disabled = not available
	check.visible = available
	check.disabled = not available
	icon_rect.material = null if available else _desaturated()
	var cover: CanvasItem = button.get_node("Texture")
	cover.visible = not available
	cover.modulate.a = COVER_ALPHA
	var background: CanvasItem = button.get_node_or_null("%" + button.name + "Background")
	if background:
		background.visible = available


static func eye(rect: TextureRect) -> void:
	_crop(rect, EYE_FRAME)


static func _desaturated() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = DESATURATE
	return material


static func _crop(rect: TextureRect, region: Rect2) -> void:
	var atlas: AtlasTexture = rect.texture as AtlasTexture
	if atlas == null:
		atlas = AtlasTexture.new()
		atlas.atlas = rect.texture
		rect.texture = atlas
	atlas.region = region
