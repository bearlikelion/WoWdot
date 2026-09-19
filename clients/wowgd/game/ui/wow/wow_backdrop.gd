@tool
class_name WowBackdrop
extends Control

# Edge files hold eight square pieces in a row: left, right, top, bottom, then the four corners.
enum Piece { LEFT, RIGHT, TOP, BOTTOM, TOP_LEFT, TOP_RIGHT, BOTTOM_LEFT, BOTTOM_RIGHT }

@export var background: Texture2D:
	set(value):
		background = value
		queue_redraw()
@export var edge: Texture2D:
	set(value):
		edge = value
		queue_redraw()
@export var tile: bool = false
@export var tile_size: float = 0.0
@export var edge_size: float = 0.0
# Background insets as left, right, top, bottom.
@export var insets: Vector4 = Vector4.ZERO
@export var background_color: Color = Color.WHITE:
	set(value):
		background_color = value
		queue_redraw()
@export var border_color: Color = Color.WHITE:
	set(value):
		border_color = value
		queue_redraw()


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if background:
		_draw_background()
	if edge:
		_draw_edge()


func _draw_background() -> void:
	var area: Rect2 = Rect2(
		insets.x, insets.z, size.x - insets.x - insets.y, size.y - insets.z - insets.w
	)
	if not tile or tile_size <= 0.0:
		draw_texture_rect(background, area, false, background_color)
		return
	var scale: float = tile_size / background.get_width()
	draw_set_transform(area.position, 0.0, Vector2(scale, scale))
	draw_texture_rect(background, Rect2(Vector2.ZERO, area.size / scale), true, background_color)
	draw_set_transform(Vector2.ZERO)


func _draw_edge() -> void:
	var piece: float = edge.get_width() / 8.0
	var thickness: float = edge_size if edge_size > 0.0 else piece
	var inner: Vector2 = size - Vector2(thickness, thickness) * 2.0
	_piece(Piece.TOP_LEFT, Vector2.ZERO, Vector2(thickness, thickness), 0.0)
	_piece(Piece.TOP_RIGHT, Vector2(size.x - thickness, 0.0), Vector2(thickness, thickness), 0.0)
	_piece(Piece.BOTTOM_LEFT, Vector2(0.0, size.y - thickness), Vector2(thickness, thickness), 0.0)
	_piece(
		Piece.BOTTOM_RIGHT, size - Vector2(thickness, thickness), Vector2(thickness, thickness), 0.0
	)
	_run(Piece.LEFT, Vector2(0.0, thickness), inner.y, thickness, false)
	_run(Piece.RIGHT, Vector2(size.x - thickness, thickness), inner.y, thickness, false)
	_run(Piece.TOP, Vector2(thickness, 0.0), inner.x, thickness, true)
	_run(Piece.BOTTOM, Vector2(thickness, size.y - thickness), inner.x, thickness, true)


# Repeats one edge piece along a side; top and bottom pieces are stored turned a quarter.
func _run(which: Piece, start: Vector2, length: float, thickness: float, horizontal: bool) -> void:
	var done: float = 0.0
	while done < length - 0.01:
		var step: float = minf(thickness, length - done)
		var fraction: float = step / thickness
		if horizontal:
			_piece(which, start + Vector2(done, 0.0), Vector2(step, thickness), fraction)
		else:
			_piece(which, start + Vector2(0.0, done), Vector2(thickness, step), fraction)
		done += step


func _piece(which: Piece, at: Vector2, extent: Vector2, fraction: float) -> void:
	var piece: float = edge.get_width() / 8.0
	var source: Rect2 = Rect2(piece * which, 0.0, piece, edge.get_height())
	if fraction > 0.0 and fraction < 1.0:
		source.size.y *= fraction
	if which == Piece.TOP or which == Piece.BOTTOM:
		# Stored as vertical strips; a clockwise quarter turn from the top-right lays them outer side out.
		draw_set_transform(at + Vector2(extent.x, 0.0), PI / 2.0)
		var turned: Rect2 = Rect2(Vector2.ZERO, Vector2(extent.y, extent.x))
		draw_texture_rect_region(edge, turned, source, border_color)
		draw_set_transform(Vector2.ZERO)
		return
	draw_texture_rect_region(edge, Rect2(at, extent), source, border_color)
