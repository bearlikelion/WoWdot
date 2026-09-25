#pragma once

#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/geometry_instance3d.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/projection.hpp>

#include <vector>

namespace godot {

// Draws only the interior groups of a WMO that a chain of portals from the camera can see into.
class WowPortals : public Node {
	GDCLASS(WowPortals, Node)

public:
	struct Group {
		bool interior = false;
		AABB bounds;
		int first_ref = 0;
		int ref_count = 0;
		// The group's mesh and its own doodads.
		std::vector<GeometryInstance3D *> parts;
		// Three corners per triangle, and how much each triangle faces up.
		std::vector<Vector3> triangles;
		std::vector<float> rise;
	};
	struct PortalRef {
		int portal = 0;
		int group = 0;
		// Which side of the portal's plane the camera must be on to look through it.
		int side = 0;
	};

	Node3D *root = nullptr;
	std::vector<Group> groups;
	std::vector<PackedVector3Array> portals;
	std::vector<Plane> planes;
	std::vector<PortalRef> refs;

protected:
	static void _bind_methods() {}
	void _notification(int p_what);

private:
	std::vector<Rect2> reached;
	std::vector<bool> seen;
	std::vector<bool> drawn;
	Vector3 eye;
	int steps = 0;

	void update();
	float floor_below(const Group &group, const Vector3 &point, float &rise) const;
	void visit(int group, int came, const Rect2 &view, const Projection &to_clip, int depth);
};

} // namespace godot
