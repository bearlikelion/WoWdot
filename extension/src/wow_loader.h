#pragma once

#include "wow_archive.h"

#include "pipeline/m2_loader.hpp"

namespace wowee::pipeline {
struct WMOGroup;
}

#include <godot_cpp/classes/animation_library.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/texture2d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace godot {

class WowLoader : public RefCounted {
	GDCLASS(WowLoader, RefCounted)

	struct M2Data {
		wowee::pipeline::M2Model model;
		std::vector<int> bone_parents;
		std::vector<Vector3> bone_rests;
	};

	Ref<WowArchive> archive;
	Ref<Shader> terrain_shader;
	TypedArray<Material> liquid_materials;

	std::mutex cache_mutex;
	std::unordered_map<std::string, Ref<ImageTexture>> textures;
	std::unordered_map<std::string, Ref<StandardMaterial3D>> materials;
	std::unordered_map<std::string, std::shared_ptr<const M2Data>> m2_data;
	std::unordered_map<std::string, Ref<ArrayMesh>> m2_meshes;
	std::unordered_map<std::string, Ref<AnimationLibrary>> m2_animations;
	std::unordered_map<uint32_t, String> animation_names;

	std::shared_ptr<const M2Data> get_m2_data(const String &path);
	Ref<ArrayMesh> get_m2_mesh(const String &path, const M2Data &data, const Dictionary &skins, const PackedInt32Array &geosets);
	Ref<AnimationLibrary> get_m2_animations(const String &path, const M2Data &data);
	Ref<AnimationLibrary> get_m2_global_animations(const String &path, const M2Data &data);
	Ref<StandardMaterial3D> get_material(const Variant &texture, uint32_t blend_mode, uint32_t flags, bool vertex_color, bool wmo, const Color &tint, const Variant &second = Variant(), int second_unit = -2);
	String animation_name(uint32_t id, uint32_t variation);
	void add_texture_animation(Node3D *root, MeshInstance3D *mesh, const wowee::pipeline::M2Model &model, const PackedInt32Array &geosets);
	void add_particles(Node3D *root, Skeleton3D *skeleton, const wowee::pipeline::M2Model &model);
	void add_m2_collision(Node3D *root, const wowee::pipeline::M2Model &model);
	void add_wmo_liquid(Node3D *root, const wowee::pipeline::WMOGroup &group, size_t index);

protected:
	static void _bind_methods();

public:
	// One loader on the project's client data, shared by WowTexture, the editor and the game.
	static Ref<WowLoader> get_shared();
	static void release_shared();
	static String client_data_dir();
	static Dictionary data_table(const String &name);
	static Dictionary profile();
	static void report_missing_data(const String &data_dir);

	void set_archive(const Ref<WowArchive> &p_archive) { archive = p_archive; }
	Ref<WowArchive> get_archive() const { return archive; }
	void set_terrain_shader(const Ref<Shader> &p_shader) { terrain_shader = p_shader; }
	Ref<Shader> get_terrain_shader() const { return terrain_shader; }
	void set_liquid_materials(const TypedArray<Material> &p_materials) { liquid_materials = p_materials; }
	TypedArray<Material> get_liquid_materials() const { return liquid_materials; }

	Ref<Image> load_image(const String &path);
	Ref<ImageTexture> load_texture(const String &path);
	Node3D *load_m2(const String &path, const Dictionary &skins = Dictionary(), const PackedInt32Array &geosets = PackedInt32Array());
	void add_collision(Node3D *node);
	Node3D *load_wmo(const String &path, int doodad_set = 0);
	Node3D *build_static_models(const Array &placements);
	Dictionary get_m2_info(const String &path);

	Dictionary get_map_info(const String &map_name);
	Node3D *load_adt(const String &map_name, int tile_x, int tile_y);
};

} // namespace godot
