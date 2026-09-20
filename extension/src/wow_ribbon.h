#pragma once

#include <godot_cpp/classes/immediate_mesh.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/variant/color.hpp>

#include <deque>

namespace godot {

// An M2 ribbon emitter: a strip that trails the bone it hangs from, rebuilt every frame.
class WowRibbon : public MeshInstance3D {
	GDCLASS(WowRibbon, MeshInstance3D)

protected:
	static void _bind_methods();

public:
	void _ready() override;
	void _process(double delta) override;

	void set_above(float value) { above = value; }
	void set_below(float value) { below = value; }
	void set_lifetime(float value) { lifetime = value; }
	void set_edges_per_second(float value) { edges_per_second = value; }
	void set_gravity(float value) { gravity = value; }
	void set_tint(const Color &value) { tint = value; }
	int get_edge_count() const { return static_cast<int>(edges.size()); }

private:
	struct Edge {
		Vector3 origin;
		Vector3 side;
		float age;
	};

	void record(const Vector3 &origin);

	Node3D *anchor = nullptr;
	Ref<ImmediateMesh> strip;
	std::deque<Edge> edges;
	Vector3 last_origin;
	float above = 0.5f;
	float below = 0.5f;
	float lifetime = 0.5f;
	float edges_per_second = 20.0f;
	float gravity = 0.0f;
	float since_edge = 0.0f;
	bool started = false;
	Color tint = Color(1.0f, 1.0f, 1.0f, 1.0f);
};

} // namespace godot
