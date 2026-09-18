#pragma once

#include "wow_archive.h"

#include <godot_cpp/classes/animation_library.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace godot {

// Turns archive files into Godot resources and nodes, caching shared resources by path.
class WowLoader : public RefCounted {
	GDCLASS(WowLoader, RefCounted)

	struct M2Template {
		Ref<ArrayMesh> mesh;
		Ref<AnimationLibrary> animations;
		std::vector<int> bone_parents;
		std::vector<Vector3> bone_rests;
	};

	Ref<WowArchive> archive;
	std::unordered_map<std::string, Ref<ImageTexture>> textures;
	std::unordered_map<std::string, Ref<StandardMaterial3D>> materials;
	std::unordered_map<std::string, M2Template> m2_templates;
	std::unordered_map<uint32_t, String> animation_names;
	std::mutex mutex;
	std::recursive_mutex model_mutex;

	const M2Template *get_m2_template(const String &path, const Dictionary &skins);
	Ref<StandardMaterial3D> get_material(const String &texture, uint32_t blend_mode, uint32_t flags, bool vertex_color, bool wmo);
	String animation_name(uint32_t id, uint32_t variation);

protected:
	static void _bind_methods();

public:
	void set_archive(const Ref<WowArchive> &p_archive) { archive = p_archive; }
	Ref<WowArchive> get_archive() const { return archive; }

	Ref<Image> load_image(const String &path);
	Ref<ImageTexture> load_texture(const String &path);
	Node3D *load_m2(const String &path, const Dictionary &skins = Dictionary());
	Node3D *load_wmo(const String &path);
	Dictionary get_m2_info(const String &path);
};

} // namespace godot
