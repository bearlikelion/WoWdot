class_name QuestBlob
extends Control

# QuestPOIFrame's objective area: a shaded patch with a lit edge, drawn under the POI icons.
const FILL: Color = Color(1.0, 0.82, 0.0, 0.18)
const EDGE: Color = Color(1.0, 0.82, 0.0, 0.7)
const EDGE_WIDTH: float = 2.0

# The area's outline in this control's pixels.
var outline: PackedVector2Array = []:
	set(value):
		outline = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


func _draw() -> void:
	if outline.size() < 3:
		return
	var hull: PackedVector2Array = Geometry2D.convex_hull(outline)
	draw_colored_polygon(hull, FILL)
	draw_polyline(hull, EDGE, EDGE_WIDTH, true)
