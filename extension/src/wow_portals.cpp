#include "wow_portals.h"

#include <godot_cpp/classes/viewport.hpp>

#include <limits>

namespace godot {

namespace {

// The client's own limits on how deep and how long one frame's portal walk may run.
constexpr int MAX_DEPTH = 10;
constexpr int MAX_STEPS = 1 << 16;
// A camera in a doorway sits on the edge of the room's box.
constexpr float BOUNDS_MARGIN = 1.0f;

} // namespace

void WowPortals::_notification(int p_what) {
	if (p_what == NOTIFICATION_READY) {
		set_process(root != nullptr && !portals.empty());
	} else if (p_what == NOTIFICATION_PROCESS) {
		update();
	}
}

void WowPortals::update() {
	Viewport *viewport = get_viewport();
	Camera3D *camera = viewport ? viewport->get_camera_3d() : nullptr;
	if (camera == nullptr) {
		return;
	}
	const Transform3D to_world = root->get_global_transform();
	eye = to_world.affine_inverse().xform(camera->get_global_position());
	const Projection to_clip = camera->get_camera_projection() * Projection(camera->get_camera_transform().affine_inverse() * to_world);
	const Rect2 screen(-1.0f, -1.0f, 2.0f, 2.0f);
	reached.assign(groups.size(), Rect2());
	seen.assign(groups.size(), false);

	// The camera is in a room when the nearest surface below it, across every group, is that room's floor.
	int below = -1;
	float nearest = std::numeric_limits<float>::infinity();
	float rise = 0.0f;
	for (size_t g = 0; g < groups.size(); g++) {
		if (!groups[g].bounds.grow(BOUNDS_MARGIN).has_point(eye)) {
			continue;
		}
		float group_rise = 0.0f;
		const float distance = floor_below(groups[g], eye, group_rise);
		if (distance < nearest) {
			nearest = distance;
			rise = group_rise;
			below = static_cast<int>(g);
		}
	}
	std::vector<int> start;
	if (below >= 0 && groups[below].interior && rise > 0.0f) {
		start.push_back(below);
	} else {
		for (size_t g = 0; g < groups.size(); g++) {
			if (!groups[g].interior || groups[g].bounds.grow(BOUNDS_MARGIN).has_point(eye)) {
				start.push_back(static_cast<int>(g));
			}
		}
	}
	// A dungeon seen from outside all of its rooms has nowhere to start, so it draws whole.
	if (start.empty()) {
		seen.assign(groups.size(), true);
	}
	steps = 0;
	for (int g : start) {
		visit(g, -1, screen, to_clip, 0);
	}
	// A walk that ran out of steps may have missed rooms, so everything draws instead.
	if (steps > MAX_STEPS) {
		seen.assign(groups.size(), true);
	}
	drawn.resize(groups.size(), true);
	for (size_t g = 0; g < groups.size(); g++) {
		const bool shown = !groups[g].interior || seen[g];
		if (drawn[g] == shown) {
			continue;
		}
		drawn[g] = shown;
		// A culled room still casts shadows, or sunlight would fall through the ceilings of rooms out of view.
		for (GeometryInstance3D *part : groups[g].parts) {
			part->set_cast_shadows_setting(shown ? GeometryInstance3D::SHADOW_CASTING_SETTING_ON : GeometryInstance3D::SHADOW_CASTING_SETTING_SHADOWS_ONLY);
		}
	}
}

// How far below the point the group's nearest surface lies, and how much that surface faces up.
float WowPortals::floor_below(const Group &group, const Vector3 &point, float &rise) const {
	float nearest = std::numeric_limits<float>::infinity();
	for (size_t t = 0; t + 2 < group.triangles.size(); t += 3) {
		const Vector3 &a = group.triangles[t];
		const Vector3 &b = group.triangles[t + 1];
		const Vector3 &c = group.triangles[t + 2];
		const float d = (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z);
		if (Math::is_zero_approx(d)) {
			continue;
		}
		const float u = ((point.x - a.x) * (c.z - a.z) - (c.x - a.x) * (point.z - a.z)) / d;
		const float v = ((b.x - a.x) * (point.z - a.z) - (point.x - a.x) * (b.z - a.z)) / d;
		if (u < 0.0f || v < 0.0f || u + v > 1.0f) {
			continue;
		}
		const float below = point.y - (a.y + u * (b.y - a.y) + v * (c.y - a.y));
		if (below >= 0.0f && below < nearest) {
			nearest = below;
			rise = group.rise[t / 3];
		}
	}
	return nearest;
}

// A portal's screen box narrows the view carried into the group behind it.
void WowPortals::visit(int group, int came, const Rect2 &view, const Projection &to_clip, int depth) {
	if (seen[group] && reached[group].encloses(view)) {
		return;
	}
	reached[group] = seen[group] ? reached[group].merge(view) : view;
	seen[group] = true;
	if (depth >= MAX_DEPTH || ++steps > MAX_STEPS) {
		return;
	}
	const Group &from = groups[group];
	for (int r = from.first_ref; r < from.first_ref + from.ref_count && r < static_cast<int>(refs.size()); r++) {
		const PortalRef &ref = refs[r];
		if (ref.group == came || ref.group >= static_cast<int>(groups.size()) || ref.portal >= static_cast<int>(portals.size())) {
			continue;
		}
		const float facing = planes[ref.portal].distance_to(eye);
		if ((ref.side < 0 ? -facing : facing) < 0.0f) {
			continue;
		}
		Rect2 box;
		bool in_front = false;
		bool behind = false;
		for (const Vector3 &corner : portals[ref.portal]) {
			const Vector4 clip = to_clip.xform(Vector4(corner.x, corner.y, corner.z, 1.0f));
			if (clip.w <= 0.0f) {
				behind = true;
				continue;
			}
			const Vector2 point(clip.x / clip.w, clip.y / clip.w);
			box = in_front ? box.expand(point) : Rect2(point, Vector2());
			in_front = true;
		}
		if (!in_front) {
			continue;
		}
		// A portal the camera stands in keeps the whole view, since its corners behind cannot be placed.
		Rect2 through = view;
		if (!behind) {
			if (!box.intersects(view, true)) {
				continue;
			}
			through = box.intersection(view);
		}
		visit(ref.group, group, through, to_clip, depth + 1);
	}
}

} // namespace godot
