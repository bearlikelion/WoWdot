#include "wow_ribbon.h"

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <algorithm>

namespace godot {

void WowRibbon::_bind_methods() {
	ClassDB::bind_method(D_METHOD("get_edge_count"), &WowRibbon::get_edge_count);
}

void WowRibbon::_ready() {
	if (Engine::get_singleton()->is_editor_hint()) {
		return;
	}
	strip.instantiate();
	set_mesh(strip);
	// Node3D drops its transform parent when a node goes top level, so the anchor is kept by hand.
	anchor = Object::cast_to<Node3D>(get_parent());
	set_as_top_level(true);
	set_global_transform(Transform3D());
	set_process(true);
}

// The trail hangs where the bone has been, so each frame drops the oldest edge and adds the newest.
void WowRibbon::_process(double delta) {
	if (strip.is_null()) {
		return;
	}
	if (anchor == nullptr) {
		return;
	}
	const Vector3 origin = anchor->get_global_position();
	const float step = delta;
	for (Edge &edge : edges) {
		edge.age += step;
		edge.origin.y -= gravity * step * step;
	}
	while (!edges.empty() && edges.front().age > lifetime) {
		edges.pop_front();
	}
	since_edge += step;
	if (since_edge >= 1.0f / std::max(edges_per_second, 1.0f)) {
		since_edge = 0.0f;
		record(origin);
	}
	strip->clear_surfaces();
	if (edges.size() < 2) {
		return;
	}
	strip->surface_begin(Mesh::PRIMITIVE_TRIANGLE_STRIP, get_material_override());
	for (size_t i = 0; i < edges.size(); i++) {
		const Edge &edge = edges[i];
		const float fade = 1.0f - edge.age / std::max(lifetime, 0.001f);
		const float along = static_cast<float>(i) / static_cast<float>(edges.size() - 1);
		strip->surface_set_color(Color(tint.r, tint.g, tint.b, tint.a * fade));
		strip->surface_set_uv(Vector2(0.0f, 1.0f - along));
		strip->surface_add_vertex(edge.origin + edge.side * above);
		strip->surface_set_color(Color(tint.r, tint.g, tint.b, tint.a * fade));
		strip->surface_set_uv(Vector2(1.0f, 1.0f - along));
		strip->surface_add_vertex(edge.origin - edge.side * below);
	}
	strip->surface_end();
}

// The strip is widened across the direction of travel, which keeps it facing the way it moves.
void WowRibbon::record(const Vector3 &origin) {
	Vector3 travel = started ? origin - last_origin : Vector3();
	last_origin = origin;
	started = true;
	if (travel.length_squared() < 0.000001f) {
		travel = edges.empty() ? Vector3(0.0f, 0.0f, 1.0f) : origin - edges.back().origin;
	}
	Vector3 side = travel.cross(Vector3(0.0f, 1.0f, 0.0f));
	if (side.length_squared() < 0.000001f) {
		side = Vector3(1.0f, 0.0f, 0.0f);
	}
	edges.push_back({ origin, side.normalized(), 0.0f });
}

} // namespace godot
