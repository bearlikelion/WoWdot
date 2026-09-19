#include "wow_coords.h"
#include "wow_dbc.h"
#include "wow_loader.h"

#include "pipeline/m2_loader.hpp"
#include "pipeline/wmo_loader.hpp"

#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/classes/animation_player.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cstdio>

using namespace wowee::pipeline;

namespace godot {

namespace {

enum M2Blend : uint32_t {
	M2_OPAQUE = 0,
	M2_ALPHA_KEY = 1,
	M2_ALPHA = 2,
	M2_NO_ALPHA_ADD = 3,
	M2_ADD = 4,
	M2_MOD = 5,
	M2_MOD2X = 6,
};

enum MaterialFlag : uint32_t {
	UNLIT = 0x1,
	UNFOGGED = 0x2,
	TWO_SIDED = 0x4,
};

constexpr uint32_t WMO_GROUP_HAS_VERTEX_COLORS = 0x4;
constexpr uint8_t WMO_TRIANGLE_NO_COLLIDE = 0x4;

String file_stem(const String &path) {
	return path.replace("\\", "/").get_file().get_basename();
}

// A surface gathers only the vertices its triangles use, remapped to local indices.
struct SurfaceBuilder {
	std::unordered_map<uint32_t, int32_t> remap;
	PackedVector3Array vertices;
	PackedVector3Array normals;
	PackedVector2Array uvs;
	PackedVector2Array uvs2;
	PackedColorArray colors;
	PackedInt32Array bones;
	PackedFloat32Array weights;
	PackedInt32Array indices;

	Array arrays() const {
		Array a;
		a.resize(Mesh::ARRAY_MAX);
		a[Mesh::ARRAY_VERTEX] = vertices;
		a[Mesh::ARRAY_NORMAL] = normals;
		a[Mesh::ARRAY_TEX_UV] = uvs;
		if (!uvs2.is_empty()) {
			a[Mesh::ARRAY_TEX_UV2] = uvs2;
		}
		if (!colors.is_empty()) {
			a[Mesh::ARRAY_COLOR] = colors;
		}
		if (!bones.is_empty()) {
			a[Mesh::ARRAY_BONES] = bones;
			a[Mesh::ARRAY_WEIGHTS] = weights;
		}
		a[Mesh::ARRAY_INDEX] = indices;
		return a;
	}
};

void add_m2_vertex(SurfaceBuilder &s, const M2Model &model, uint32_t index, bool skinned) {
	auto it = s.remap.find(index);
	if (it != s.remap.end()) {
		s.indices.push_back(it->second);
		return;
	}
	const M2Vertex &v = model.vertices[index];
	const int32_t local = s.vertices.size();
	s.remap[index] = local;
	s.indices.push_back(local);
	s.vertices.push_back(wow_to_godot(v.position));
	s.normals.push_back(wow_to_godot(v.normal).normalized());
	s.uvs.push_back(Vector2(v.texCoords[0].x, v.texCoords[0].y));
	s.uvs2.push_back(Vector2(v.texCoords[1].x, v.texCoords[1].y));
	if (!skinned) {
		return;
	}
	float total = 0.0f;
	for (int k = 0; k < 4; k++) {
		total += v.boneWeights[k];
	}
	for (int k = 0; k < 4; k++) {
		s.bones.push_back(v.boneIndices[k]);
		s.weights.push_back(total > 0.0f ? v.boneWeights[k] / total : (k == 0 ? 1.0f : 0.0f));
	}
}

template <typename T>
bool sequence_keys(const M2AnimationTrack &track, size_t sequence, const std::vector<T> M2AnimationTrack::SequenceKeys::*values, size_t &r_count) {
	// ponytail: global-sequence tracks (looping independently of the animation) are skipped.
	if (track.globalSequence >= 0 || sequence >= track.sequences.size()) {
		return false;
	}
	const M2AnimationTrack::SequenceKeys &keys = track.sequences[sequence];
	r_count = std::min(keys.timestamps.size(), (keys.*values).size());
	return r_count > 0;
}

// Rest colour and opacity of a batch; particle emitter models hide their helper geometry with the alpha.
Color batch_tint(const M2Model &model, const M2Batch &batch) {
	float alpha = 1.0f;
	if (batch.transparencyIndex < model.textureWeightLookup.size()) {
		const uint16_t weight = model.textureWeightLookup[batch.transparencyIndex];
		if (weight < model.textureWeights.size()) {
			alpha *= model.textureWeights[weight];
		}
	}
	glm::vec3 rgb(1.0f);
	if (batch.colorIndex < model.colorAlphas.size()) {
		alpha *= model.colorAlphas[batch.colorIndex];
	}
	if (batch.colorIndex < model.colorRGBs.size()) {
		rgb = model.colorRGBs[batch.colorIndex];
	}
	return Color(rgb.r, rgb.g, rgb.b, alpha);
}

Animation::InterpolationType interpolation(const M2AnimationTrack &track) {
	// ponytail: hermite and bezier keys play back as linear.
	return track.interpolationType == 0 ? Animation::INTERPOLATION_NEAREST : Animation::INTERPOLATION_LINEAR;
}

Ref<Animation> build_animation(const M2Model &model, size_t sequence, const std::vector<Vector3> &rests) {
	Ref<Animation> anim;
	anim.instantiate();
	anim->set_length(std::max<uint32_t>(model.sequences[sequence].duration, 1) / 1000.0);
	anim->set_loop_mode(Animation::LOOP_LINEAR);
	for (size_t b = 0; b < model.bones.size(); b++) {
		const M2Bone &bone = model.bones[b];
		const NodePath path("Skeleton:bone_" + String::num_int64(b));
		size_t count = 0;
		if (sequence_keys(bone.translation, sequence, &M2AnimationTrack::SequenceKeys::vec3Values, count)) {
			const auto &keys = bone.translation.sequences[sequence];
			const int t = anim->add_track(Animation::TYPE_POSITION_3D);
			anim->track_set_path(t, path);
			anim->track_set_interpolation_type(t, interpolation(bone.translation));
			for (size_t k = 0; k < count; k++) {
				anim->position_track_insert_key(t, keys.timestamps[k] / 1000.0, rests[b] + wow_to_godot(keys.vec3Values[k]));
			}
		}
		if (sequence_keys(bone.rotation, sequence, &M2AnimationTrack::SequenceKeys::quatValues, count)) {
			const auto &keys = bone.rotation.sequences[sequence];
			const int t = anim->add_track(Animation::TYPE_ROTATION_3D);
			anim->track_set_path(t, path);
			anim->track_set_interpolation_type(t, interpolation(bone.rotation));
			for (size_t k = 0; k < count; k++) {
				anim->rotation_track_insert_key(t, keys.timestamps[k] / 1000.0, wow_to_godot(keys.quatValues[k]).normalized());
			}
		}
		if (sequence_keys(bone.scale, sequence, &M2AnimationTrack::SequenceKeys::vec3Values, count)) {
			const auto &keys = bone.scale.sequences[sequence];
			const int t = anim->add_track(Animation::TYPE_SCALE_3D);
			anim->track_set_path(t, path);
			anim->track_set_interpolation_type(t, interpolation(bone.scale));
			for (size_t k = 0; k < count; k++) {
				anim->scale_track_insert_key(t, keys.timestamps[k] / 1000.0, wow_scale_to_godot(keys.vec3Values[k]));
			}
		}
	}
	return anim;
}

} // namespace

String WowLoader::animation_name(uint32_t id, uint32_t variation) {
	std::lock_guard<std::mutex> lock(cache_mutex);
	if (animation_names.empty()) {
		const Ref<WowDBC> dbc = WowDBC::open(archive, "AnimationData");
		for (int row = 0; dbc.is_valid() && row < dbc->row_count(); row++) {
			animation_names[dbc->get_uint(row, 0)] = dbc->get_string(row, 1);
		}
	}
	auto it = animation_names.find(id);
	String name = it != animation_names.end() ? it->second : "Anim" + String::num_int64(id);
	return variation > 0 ? name + "_" + String::num_int64(variation) : name;
}

// The texture is an archive path or a ready Texture2D, such as a composited character skin.
Ref<StandardMaterial3D> WowLoader::get_material(const Variant &texture, uint32_t blend_mode, uint32_t flags, bool vertex_color, bool wmo, const Color &tint) {
	const Ref<Texture2D> ready = texture;
	const String texture_key = ready.is_valid() ? "#" + String::num_int64(ready->get_instance_id()) : String(texture).to_lower();
	const std::string key = std::string(texture_key.utf8().get_data()) + "|" + std::to_string(blend_mode) + "|" + std::to_string(flags) + "|" + std::to_string(vertex_color) + "|" + std::to_string(wmo) + "|" + std::to_string(tint.to_rgba32());
	{
		std::lock_guard<std::mutex> lock(cache_mutex);
		auto it = materials.find(key);
		if (it != materials.end()) {
			return it->second;
		}
	}
	Ref<StandardMaterial3D> mat;
	mat.instantiate();
	// The 1.12 client lights models with plain diffuse, so specular only adds a sheen to foliage cards.
	mat->set_specular(0.0);
	if (ready.is_valid()) {
		mat->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, ready);
	} else if (!String(texture).is_empty()) {
		mat->set_texture(BaseMaterial3D::TEXTURE_ALBEDO, load_texture(texture));
	}
	// WMO blend modes 0 and 1 match M2's opaque and alpha key; higher WMO modes are rare enough to treat as alpha.
	switch (blend_mode) {
		case M2_OPAQUE:
			break;
		case M2_ALPHA_KEY:
			mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA_SCISSOR);
			mat->set_alpha_scissor_threshold(0.5);
			break;
		case M2_NO_ALPHA_ADD:
		case M2_ADD:
			mat->set_transparency(wmo ? BaseMaterial3D::TRANSPARENCY_ALPHA : BaseMaterial3D::TRANSPARENCY_DISABLED);
			mat->set_blend_mode(wmo ? BaseMaterial3D::BLEND_MODE_MIX : BaseMaterial3D::BLEND_MODE_ADD);
			break;
		case M2_MOD:
		case M2_MOD2X:
			mat->set_blend_mode(wmo ? BaseMaterial3D::BLEND_MODE_MIX : BaseMaterial3D::BLEND_MODE_MUL);
			break;
		default:
			mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
			break;
	}
	if (flags & UNLIT) {
		mat->set_shading_mode(BaseMaterial3D::SHADING_MODE_UNSHADED);
	}
	if (flags & UNFOGGED) {
		mat->set_flag(BaseMaterial3D::FLAG_DISABLE_FOG, true);
	}
	if (flags & TWO_SIDED) {
		mat->set_cull_mode(BaseMaterial3D::CULL_DISABLED);
	}
	if (vertex_color) {
		mat->set_flag(BaseMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
	}
	if (tint != Color(1.0f, 1.0f, 1.0f, 1.0f)) {
		mat->set_albedo(tint);
	}
	if (tint.a < 1.0f) {
		if (mat->get_transparency() == BaseMaterial3D::TRANSPARENCY_DISABLED && mat->get_blend_mode() == BaseMaterial3D::BLEND_MODE_MIX) {
			mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
		}
	}
	std::lock_guard<std::mutex> lock(cache_mutex);
	return materials.emplace(key, mat).first->second;
}

std::shared_ptr<const WowLoader::M2Data> WowLoader::get_m2_data(const String &path) {
	const std::string key = path.to_lower().replace("/", "\\").utf8().get_data();
	{
		std::lock_guard<std::mutex> lock(cache_mutex);
		auto cached = m2_data.find(key);
		if (cached != m2_data.end()) {
			return cached->second;
		}
	}
	std::vector<uint8_t> bytes;
	if (!archive->read_bytes(WowArchive::normalize(path), bytes)) {
		UtilityFunctions::push_warning("WowLoader: missing model ", path);
		return nullptr;
	}
	auto data = std::make_shared<M2Data>();
	data->model = M2Loader::load(bytes);
	if (!data->model.isValid()) {
		// Particle-only emitter models carry no geometry, so only warn about ones that should have some.
		if (!data->model.vertices.empty()) {
			UtilityFunctions::push_warning("WowLoader: bad model ", path);
		}
		std::lock_guard<std::mutex> lock(cache_mutex);
		return m2_data.emplace(key, nullptr).first->second;
	}
	for (const M2Bone &bone : data->model.bones) {
		const glm::vec3 parent_pivot = bone.parentBone >= 0 ? data->model.bones[bone.parentBone].pivot : glm::vec3(0.0f);
		data->bone_parents.push_back(bone.parentBone);
		data->bone_rests.push_back(wow_to_godot(bone.pivot - parent_pivot));
	}
	std::lock_guard<std::mutex> lock(cache_mutex);
	return m2_data.emplace(key, data).first->second;
}

// Skins map a texture type to a path or a ready texture; geosets, when given, keep only those submeshes.
Ref<ArrayMesh> WowLoader::get_m2_mesh(const String &path, const M2Data &data, const Dictionary &skins, const PackedInt32Array &geosets) {
	const std::string key = std::string(path.to_lower().utf8().get_data()) + "|" + String(Variant(skins)).utf8().get_data() + "|" + String(Variant(geosets)).utf8().get_data();
	{
		std::lock_guard<std::mutex> lock(cache_mutex);
		auto cached = m2_meshes.find(key);
		if (cached != m2_meshes.end()) {
			return cached->second;
		}
	}
	const M2Model &model = data.model;
	const bool skinned = !model.bones.empty();
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	for (const M2Batch &batch : model.batches) {
		if (batch.indexStart + batch.indexCount > model.indices.size() || batch.indexCount == 0) {
			continue;
		}
		if (!geosets.is_empty() && !geosets.has(batch.submeshId)) {
			continue;
		}
		const Color tint = batch_tint(model, batch);
		if (tint.a < 0.01f) {
			continue;
		}
		SurfaceBuilder s;
		for (uint32_t t = batch.indexStart; t + 2 < batch.indexStart + batch.indexCount; t += 3) {
			for (int k : { 0, 2, 1 }) {
				add_m2_vertex(s, model, model.indices[t + k], skinned);
			}
		}
		Variant texture = String();
		if (batch.textureIndex < model.textureLookup.size() && model.textureLookup[batch.textureIndex] < model.textures.size()) {
			const M2Texture &tex = model.textures[model.textureLookup[batch.textureIndex]];
			texture = tex.type == 0 ? Variant(String(tex.filename.c_str())) : skins.get(static_cast<int64_t>(tex.type), String());
		}
		const M2Material material = batch.materialIndex < model.materials.size() ? model.materials[batch.materialIndex] : M2Material{ 0, 0 };
		const int surface = mesh->get_surface_count();
		mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, s.arrays());
		mesh->surface_set_name(surface, "geoset_" + String::num_int64(batch.submeshId));
		Ref<StandardMaterial3D> mat = get_material(texture, material.blendMode, material.flags, false, false, tint);
		if (batch.materialLayer > 0) {
			mat = mat->duplicate();
			mat->set_render_priority(batch.materialLayer);
		}
		mesh->surface_set_material(surface, mat);
	}
	std::lock_guard<std::mutex> lock(cache_mutex);
	return m2_meshes.emplace(key, mesh).first->second;
}

Ref<AnimationLibrary> WowLoader::get_m2_animations(const String &path, const M2Data &data) {
	const std::string key = path.to_lower().replace("/", "\\").utf8().get_data();
	{
		std::lock_guard<std::mutex> lock(cache_mutex);
		auto cached = m2_animations.find(key);
		if (cached != m2_animations.end()) {
			return cached->second;
		}
	}
	Ref<AnimationLibrary> animations;
	animations.instantiate();
	for (size_t i = 0; i < data.model.sequences.size(); i++) {
		const String name = animation_name(data.model.sequences[i].id, data.model.sequences[i].variationIndex);
		if (!animations->has_animation(name)) {
			animations->add_animation(name, build_animation(data.model, i, data.bone_rests));
		}
	}
	std::lock_guard<std::mutex> lock(cache_mutex);
	return m2_animations.emplace(key, animations).first->second;
}

Node3D *WowLoader::load_m2(const String &path, const Dictionary &skins, const PackedInt32Array &geosets) {
	ERR_FAIL_COND_V(archive.is_null(), nullptr);
	const std::shared_ptr<const M2Data> data = get_m2_data(path);
	if (!data) {
		return nullptr;
	}
	Node3D *root = memnew(Node3D);
	root->set_name(file_stem(path));
	MeshInstance3D *mesh = memnew(MeshInstance3D);
	mesh->set_name("Mesh");
	mesh->set_mesh(get_m2_mesh(path, *data, skins, geosets));
	if (data->bone_rests.empty()) {
		root->add_child(mesh);
		return root;
	}
	Skeleton3D *skeleton = memnew(Skeleton3D);
	skeleton->set_name("Skeleton");
	for (size_t b = 0; b < data->bone_rests.size(); b++) {
		skeleton->add_bone("bone_" + String::num_int64(b));
	}
	for (size_t b = 0; b < data->bone_rests.size(); b++) {
		skeleton->set_bone_parent(b, data->bone_parents[b]);
		skeleton->set_bone_rest(b, Transform3D(Basis(), data->bone_rests[b]));
	}
	skeleton->reset_bone_poses();
	root->add_child(skeleton);
	skeleton->add_child(mesh);
	mesh->set_skeleton_path(NodePath(".."));

	const Ref<AnimationLibrary> animations = get_m2_animations(path, *data);
	AnimationPlayer *player = memnew(AnimationPlayer);
	player->set_name("AnimationPlayer");
	player->add_animation_library("", animations);
	root->add_child(player);
	if (animations->has_animation("Stand")) {
		player->set_autoplay("Stand");
	}
	return root;
}

Dictionary WowLoader::get_m2_info(const String &path) {
	ERR_FAIL_COND_V(archive.is_null(), Dictionary());
	const std::shared_ptr<const M2Data> data = get_m2_data(path);
	if (!data) {
		return Dictionary();
	}
	const M2Model &model = data->model;
	Array texture_list;
	for (const M2Texture &tex : model.textures) {
		Dictionary t;
		t["type"] = tex.type;
		t["file"] = String(tex.filename.c_str());
		texture_list.push_back(t);
	}
	Array batches;
	for (const M2Batch &batch : model.batches) {
		Dictionary b;
		b["geoset"] = batch.submeshId;
		b["texture_count"] = batch.textureCount;
		b["texture"] = batch.textureIndex < model.textureLookup.size() ? static_cast<int64_t>(model.textureLookup[batch.textureIndex]) : static_cast<int64_t>(-1);
		b["blend"] = batch.materialIndex < model.materials.size() ? static_cast<int64_t>(model.materials[batch.materialIndex].blendMode) : static_cast<int64_t>(-1);
		batches.push_back(b);
	}
	PackedStringArray animations;
	for (const M2Sequence &seq : model.sequences) {
		animations.push_back(animation_name(seq.id, seq.variationIndex));
	}
	Dictionary info;
	info["version"] = model.version;
	info["bones"] = static_cast<int64_t>(model.bones.size());
	PackedInt32Array bone_flags;
	for (const M2Bone &bone : model.bones) {
		bone_flags.push_back(bone.flags);
	}
	info["bone_flags"] = bone_flags;
	info["textures"] = texture_list;
	info["batches"] = batches;
	info["animations"] = animations;
	Array cameras;
	for (const M2Camera &camera : model.cameras) {
		Dictionary c;
		c["position"] = wow_to_godot(camera.positionBase);
		c["target"] = wow_to_godot(camera.targetBase);
		c["fov"] = camera.fov;
		cameras.push_back(c);
	}
	info["cameras"] = cameras;
	Array attachments;
	for (const M2Attachment &attachment : model.attachments) {
		Dictionary a;
		a["id"] = attachment.id;
		a["bone"] = attachment.bone;
		a["position"] = wow_to_godot(attachment.position);
		attachments.push_back(a);
	}
	info["attachments"] = attachments;
	return info;
}

// Static props draw in their rest pose as one MultiMesh per model, which skips per-instance skeletons.
Node3D *WowLoader::build_static_models(const Array &placements) {
	std::unordered_map<std::string, std::pair<String, std::vector<Transform3D>>> groups;
	for (int i = 0; i < placements.size(); i++) {
		const Dictionary placement = placements[i];
		const String path = placement["path"];
		auto &group = groups[path.to_lower().utf8().get_data()];
		group.first = path;
		group.second.push_back(placement["transform"]);
	}
	Node3D *root = memnew(Node3D);
	root->set_name("Doodads");
	PackedVector3Array faces;
	for (const auto &[key, group] : groups) {
		const std::shared_ptr<const M2Data> data = get_m2_data(group.first);
		if (!data) {
			continue;
		}
		const M2Model &model = data->model;
		for (const Transform3D &transform : group.second) {
			for (size_t t = 0; t + 2 < model.collisionIndices.size(); t += 3) {
				for (int k : { 0, 2, 1 }) {
					const uint16_t index = model.collisionIndices[t + k];
					faces.push_back(index < model.collisionVertices.size() ? transform.xform(wow_to_godot(model.collisionVertices[index])) : transform.origin);
				}
			}
		}
		Ref<MultiMesh> multimesh;
		multimesh.instantiate();
		multimesh->set_transform_format(MultiMesh::TRANSFORM_3D);
		multimesh->set_mesh(get_m2_mesh(group.first, *data, Dictionary(), PackedInt32Array()));
		multimesh->set_instance_count(group.second.size());
		for (size_t i = 0; i < group.second.size(); i++) {
			multimesh->set_instance_transform(i, group.second[i]);
		}
		MultiMeshInstance3D *instance = memnew(MultiMeshInstance3D);
		instance->set_name(file_stem(group.first));
		instance->set_multimesh(multimesh);
		root->add_child(instance);
	}
	if (!faces.is_empty()) {
		Ref<ConcavePolygonShape3D> shape;
		shape.instantiate();
		shape->set_faces(faces);
		CollisionShape3D *collision = memnew(CollisionShape3D);
		collision->set_shape(shape);
		StaticBody3D *body = memnew(StaticBody3D);
		body->set_name("Collision");
		body->add_child(collision);
		root->add_child(body);
	}
	return root;
}

Node3D *WowLoader::load_wmo(const String &path, int doodad_set) {
	ERR_FAIL_COND_V(archive.is_null(), nullptr);
	std::vector<uint8_t> data;
	if (!archive->read_bytes(WowArchive::normalize(path), data)) {
		UtilityFunctions::push_warning("WowLoader: missing WMO ", path);
		return nullptr;
	}
	WMOModel model = WMOLoader::load(data);
	const String base = path.get_basename();
	for (uint32_t g = 0; g < model.nGroups; g++) {
		char suffix[16];
		std::snprintf(suffix, sizeof(suffix), "_%03u.wmo", g);
		std::vector<uint8_t> group_data;
		if (archive->read_bytes(WowArchive::normalize(base + String(suffix)), group_data)) {
			WMOLoader::loadGroup(group_data, model, g);
		}
	}

	Node3D *root = memnew(Node3D);
	root->set_name(file_stem(path));
	for (size_t g = 0; g < model.groups.size(); g++) {
		const WMOGroup &group = model.groups[g];
		if (group.vertices.empty()) {
			continue;
		}
		const bool vertex_colors = group.flags & WMO_GROUP_HAS_VERTEX_COLORS;
		Ref<ArrayMesh> mesh;
		mesh.instantiate();
		for (const WMOBatch &batch : group.batches) {
			if (batch.startIndex + batch.indexCount > group.indices.size() || batch.indexCount == 0) {
				continue;
			}
			SurfaceBuilder s;
			for (uint32_t i = batch.startIndex; i < batch.startIndex + batch.indexCount; i++) {
				const uint32_t index = group.indices[i];
				auto it = s.remap.find(index);
				if (it != s.remap.end()) {
					s.indices.push_back(it->second);
					continue;
				}
				const WMOVertex &v = group.vertices[index];
				s.remap[index] = s.vertices.size();
				s.indices.push_back(s.vertices.size());
				s.vertices.push_back(wow_to_godot(v.position));
				s.normals.push_back(wow_to_godot(v.normal).normalized());
				s.uvs.push_back(Vector2(v.texCoord.x, v.texCoord.y));
				if (vertex_colors) {
					s.colors.push_back(Color(v.color.r, v.color.g, v.color.b, 1.0f));
				}
			}
			// WoW triangles wind the opposite way to Godot's front faces.
			int32_t *tri = s.indices.ptrw();
			for (int64_t t = 0; t + 2 < s.indices.size(); t += 3) {
				std::swap(tri[t + 1], tri[t + 2]);
			}
			String texture;
			uint32_t blend = 0;
			uint32_t flags = 0;
			if (batch.materialId < model.materials.size()) {
				const WMOMaterial &m = model.materials[batch.materialId];
				auto tex = model.textureOffsetToIndex.find(m.texture1);
				if (tex != model.textureOffsetToIndex.end() && tex->second < model.textures.size()) {
					texture = String(model.textures[tex->second].c_str());
				}
				blend = m.blendMode;
				flags = m.flags;
			}
			const int surface = mesh->get_surface_count();
			mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, s.arrays());
			mesh->surface_set_material(surface, get_material(texture, blend, flags, vertex_colors, true, Color(1.0f, 1.0f, 1.0f, 1.0f)));
		}
		MeshInstance3D *instance = memnew(MeshInstance3D);
		instance->set_name(group.name.empty() ? "Group" + String::num_int64(g) : String(group.name.c_str()));
		instance->set_mesh(mesh);
		root->add_child(instance);

		PackedVector3Array faces;
		for (size_t t = 0; t + 2 < group.indices.size(); t += 3) {
			if (t / 3 < group.triFlags.size() && (group.triFlags[t / 3] & WMO_TRIANGLE_NO_COLLIDE)) {
				continue;
			}
			for (int k : { 0, 2, 1 }) {
				faces.push_back(wow_to_godot(group.vertices[group.indices[t + k]].position));
			}
		}
		if (!faces.is_empty()) {
			Ref<ConcavePolygonShape3D> shape;
			shape.instantiate();
			shape->set_faces(faces);
			StaticBody3D *body = memnew(StaticBody3D);
			body->set_name("Collision");
			CollisionShape3D *collision = memnew(CollisionShape3D);
			collision->set_shape(shape);
			body->add_child(collision);
			instance->add_child(body);
		}
	}

	// Set 0 holds the doodads every placement shows; a placement may add one more set.
	std::vector<int> sets = { 0 };
	if (doodad_set > 0) {
		sets.push_back(doodad_set);
	}
	Array doodads;
	for (int set_index : sets) {
		if (static_cast<size_t>(set_index) >= model.doodadSets.size()) {
			continue;
		}
		const WMODoodadSet &set = model.doodadSets[set_index];
		for (uint32_t d = set.startIndex; d < set.startIndex + set.count && d < model.doodads.size(); d++) {
			const WMODoodad &doodad = model.doodads[d];
			auto name = model.doodadNames.find(doodad.nameIndex);
			if (name == model.doodadNames.end()) {
				continue;
			}
			Dictionary placement;
			placement["path"] = String(name->second.c_str());
			placement["transform"] = Transform3D(Basis(wow_to_godot(doodad.rotation)).scaled(Vector3(1, 1, 1) * doodad.scale), wow_to_godot(doodad.position));
			doodads.push_back(placement);
		}
	}
	if (!doodads.is_empty()) {
		root->add_child(build_static_models(doodads));
	}
	return root;
}

} // namespace godot
