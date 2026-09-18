#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <glm/glm.hpp>
#include <glm/gtc/quaternion.hpp>

namespace godot {

inline Vector3 wow_to_godot(const glm::vec3 &v) {
	return Vector3(-v.y, v.z, -v.x);
}

inline Quaternion wow_to_godot(const glm::quat &q) {
	return Quaternion(-q.y, q.z, -q.x, q.w);
}

// Per-axis scale only permutes, since the mapping is a rotation.
inline Vector3 wow_scale_to_godot(const glm::vec3 &s) {
	return Vector3(s.y, s.z, s.x);
}

// The one conversion between WoW wire space (X north, Y west, Z up, yards) and Godot (Y up, -Z north, metres).
class WowCoords : public Object {
	GDCLASS(WowCoords, Object)

protected:
	static void _bind_methods();

public:
	static Vector3 to_godot(const Vector3 &wow) { return Vector3(-wow.y, wow.z, -wow.x); }
	static Vector3 from_godot(const Vector3 &godot) { return Vector3(-godot.z, -godot.x, godot.y); }
};

} // namespace godot
