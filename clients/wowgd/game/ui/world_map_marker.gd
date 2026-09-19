class_name WorldMapMarker
extends Control

enum Kind { POI, MAJOR_POI, FLIGHT_KNOWN, FLIGHT_UNKNOWN, QUEST }

# mWoW's map markers: gold landmarks, flight point diamonds, quest givers cyan ringed in gold.
const POI_COLOR: Color = Color("#FFD700")
const FLIGHT_UNKNOWN_COLOR: Color = Color("#46C85A")
const QUEST_COLOR: Color = Color("#00D2FF")
const OUTLINE: Color = Color(0.1, 0.08, 0.02)
const SIZES: Dictionary[Kind, float] = {
	Kind.POI: 8.0, Kind.MAJOR_POI: 16.0, Kind.FLIGHT_KNOWN: 12.0, Kind.FLIGHT_UNKNOWN: 12.0,
	Kind.QUEST: 10.0,
}

var kind: Kind = Kind.POI:
	set(value):
		kind = value
		custom_minimum_size = Vector2.ONE * SIZES[kind]
		size = custom_minimum_size
		queue_redraw()
var title: String = ""
var description: String = ""


func _draw() -> void:
	var radius: float = SIZES[kind] / 2.0
	var center: Vector2 = size / 2.0
	match kind:
		Kind.FLIGHT_KNOWN, Kind.FLIGHT_UNKNOWN:
			var diamond: PackedVector2Array = [
				center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
				center + Vector2(0.0, radius), center + Vector2(-radius, 0.0),
			]
			var fill: Color = POI_COLOR if kind == Kind.FLIGHT_KNOWN else FLIGHT_UNKNOWN_COLOR
			draw_colored_polygon(diamond, fill)
			diamond.append(diamond[0])
			draw_polyline(diamond, OUTLINE, 1.5, true)
		Kind.QUEST:
			draw_circle(center, radius, POI_COLOR)
			draw_circle(center, radius - 2.0, QUEST_COLOR)
		_:
			draw_circle(center, radius, OUTLINE)
			draw_circle(center, radius - 1.5, POI_COLOR)
