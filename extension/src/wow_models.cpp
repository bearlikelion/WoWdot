#include "wow_coords.h"
#include "wow_dbc.h"
#include "wow_loader.h"

#include "pipeline/m2_loader.hpp"
#include "pipeline/wmo_loader.hpp"

#include <godot_cpp/classes/animation.hpp>
#include <godot_cpp/classes/animation_player.hpp>
#include <godot_cpp/classes/bone_attachment3d.hpp>
#include <godot_cpp/classes/curve.hpp>
#include <godot_cpp/classes/curve_texture.hpp>
#include <godot_cpp/classes/gpu_particles3d.hpp>
#include <godot_cpp/classes/gradient.hpp>
#include <godot_cpp/classes/gradient_texture1_d.hpp>
#include <godot_cpp/classes/particle_process_material.hpp>
#include <godot_cpp/classes/quad_mesh.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <optional>
#include <utility>
#include <vector>

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

// One batch per tile would vanish whole, since a batch is culled by the middle of its bounds.
constexpr float DOODAD_CELL_YARDS = 133.333f;
constexpr float DOODAD_RANGE_PER_YARD = 24.0f;
constexpr float DOODAD_NEAREST_RANGE = 120.0f;
constexpr float DOODAD_FURTHEST_RANGE = 600.0f;

// The first M2 version that keeps its geometry in .skin files.
constexpr uint32_t M2_SKIN_VERSION = 264;

constexpr uint32_t WMO_GROUP_HAS_VERTEX_COLORS = 0x4;
constexpr uint32_t WMO_GROUP_OCEAN = 0x80000;
// MLIQ tiles are the same size as the terrain's, and 0x08 marks one that does not draw.
constexpr float WMO_LIQUID_TILE = 1600.0f / 3.0f / 16.0f / 8.0f;
constexpr uint8_t WMO_LIQUID_TILE_HIDDEN = 0x08;
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

// With no sequence, returns the global-sequence keys, repeated on each track's own period up to length.
template <typename T>
std::vector<std::pair<uint32_t, T>> track_keys(const M2Model &model, const M2AnimationTrack &track, std::optional<size_t> sequence, uint32_t length, const std::vector<T> M2AnimationTrack::SequenceKeys::*values) {
	std::vector<std::pair<uint32_t, T>> result;
	const bool global = track.globalSequence >= 0;
	const size_t slot = sequence.value_or(0);
	if (global == sequence.has_value() || slot >= track.sequences.size()) {
		return result;
	}
	const M2AnimationTrack::SequenceKeys &keys = track.sequences[slot];
	const size_t count = std::min(keys.timestamps.size(), (keys.*values).size());
	uint32_t period = 0;
	if (global && static_cast<size_t>(track.globalSequence) < model.globalSequenceDurations.size()) {
		period = model.globalSequenceDurations[static_cast<size_t>(track.globalSequence)];
	}
	for (uint32_t offset = 0; count > 0 && offset < length; offset += period) {
		for (size_t k = 0; k < count; k++) {
			const uint32_t msec = offset + keys.timestamps[k];
			if (global && msec > length) {
				break;
			}
			result.emplace_back(msec, (keys.*values)[k]);
		}
		if (period == 0) {
			break;
		}
	}
	return result;
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

// Emitter tracks hold one value per sequence; the first is what the model rests at.
float track_value(const M2AnimationTrack &track, float fallback) {
	for (const M2AnimationTrack::SequenceKeys &keys : track.sequences) {
		if (!keys.floatValues.empty()) {
			return keys.floatValues[0];
		}
	}
	return fallback;
}

// The colour form of the same, for tracks whose keys are RGB triples.
Color track_color(const M2AnimationTrack &track, const Color &fallback) {
	for (const M2AnimationTrack::SequenceKeys &keys : track.sequences) {
		if (!keys.vec3Values.empty()) {
			const glm::vec3 &rgb = keys.vec3Values[0];
			return Color(rgb.r, rgb.g, rgb.b, 1.0f);
		}
	}
	return fallback;
}

// ponytail: additive emitters stack to white at rest; matching the stock client's blend is the fix.
constexpr float ADDITIVE_DAMPING = 0.35f;

// An FBlock is a small curve over a particle's life, which Godot takes as a ramp texture.
Ref<GradientTexture1D> particle_colors(const M2ParticleEmitter &emitter) {
	const bool additive = emitter.blendingType == M2_ADD || emitter.blendingType == M2_NO_ALPHA_ADD;
	const float damping = additive ? ADDITIVE_DAMPING : 1.0f;
	Ref<Gradient> gradient;
	gradient.instantiate();
	PackedFloat32Array offsets;
	PackedColorArray colors;
	const size_t count = std::min(emitter.particleColor.vec3Values.size(), emitter.particleAlpha.floatValues.size());
	for (size_t i = 0; i < count; i++) {
		const glm::vec3 rgb = emitter.particleColor.vec3Values[i];
		offsets.push_back(i < emitter.particleColor.timestamps.size() ? emitter.particleColor.timestamps[i] : float(i) / count);
		colors.push_back(Color(rgb.r, rgb.g, rgb.b, emitter.particleAlpha.floatValues[i] * damping));
	}
	if (colors.is_empty()) {
		return Ref<GradientTexture1D>();
	}
	gradient->set_offsets(offsets);
	gradient->set_colors(colors);
	Ref<GradientTexture1D> ramp;
	ramp.instantiate();
	ramp->set_gradient(gradient);
	return ramp;
}

Ref<CurveTexture> particle_sizes(const M2ParticleEmitter &emitter, float &largest) {
	Ref<Curve> curve;
	curve.instantiate();
	const std::vector<float> &sizes = emitter.particleScale.floatValues;
	largest = 0.0f;
	for (const float size : sizes) {
		largest = std::max(largest, size);
	}
	if (sizes.empty() || largest <= 0.0f) {
		return Ref<CurveTexture>();
	}
	for (size_t i = 0; i < sizes.size(); i++) {
		const float at = i < emitter.particleScale.timestamps.size() ? emitter.particleScale.timestamps[i] : float(i) / sizes.size();
		curve->add_point(Vector2(std::clamp(at, 0.0f, 1.0f), sizes[i] / largest));
	}
	Ref<CurveTexture> texture;
	texture.instantiate();
	texture->set_curve(curve);
	return texture;
}

// The batches a mesh keeps, in surface order, so animation can find the material of each one.
std::vector<uint32_t> visible_batches(const M2Model &model, const PackedInt32Array &geosets) {
	std::vector<uint32_t> kept;
	for (uint32_t b = 0; b < model.batches.size(); b++) {
		const M2Batch &batch = model.batches[b];
		if (batch.indexStart + batch.indexCount > model.indices.size() || batch.indexCount == 0) {
			continue;
		}
		if (!geosets.is_empty() && !geosets.has(batch.submeshId)) {
			continue;
		}
		if (batch_tint(model, batch).a < 0.01f) {
			continue;
		}
		kept.push_back(b);
	}
	return kept;
}

Animation::InterpolationType interpolation(const M2AnimationTrack &track) {
	// ponytail: hermite and bezier keys play back as linear.
	return track.interpolationType == 0 ? Animation::INTERPOLATION_NEAREST : Animation::INTERPOLATION_LINEAR;
}

// Texture transforms scroll and spin a batch's UVs, which is how water, fire and portals move.
Ref<Animation> build_uv_animation(const M2Model &model, const std::vector<uint32_t> &batches, const String &mesh_path) {
	Ref<Animation> anim;
	anim.instantiate();
	anim->set_loop_mode(Animation::LOOP_LINEAR);
	double length = 0.0;
	for (size_t surface = 0; surface < batches.size(); surface++) {
		const M2Batch &batch = model.batches[batches[surface]];
		if (batch.textureAnimIndex >= model.textureTransformLookup.size()) {
			continue;
		}
		const uint16_t slot = model.textureTransformLookup[batch.textureAnimIndex];
		if (slot >= model.textureTransforms.size()) {
			continue;
		}
		const M2AnimationTrack &track = model.textureTransforms[slot].translation;
		const bool global = track.globalSequence >= 0;
		const uint32_t period = global
				&& static_cast<size_t>(track.globalSequence) < model.globalSequenceDurations.size()
				? model.globalSequenceDurations[static_cast<size_t>(track.globalSequence)]
				: 0;
		uint32_t span = 0;
		if (!track.sequences.empty()) {
			for (const uint32_t stamp : track.sequences[0].timestamps) {
				span = std::max(span, stamp);
			}
		}
		const auto keys = track_keys(model, track, global ? std::nullopt : std::optional<size_t>(0), std::max({ period, span, 1u }), &M2AnimationTrack::SequenceKeys::vec3Values);
		if (keys.size() < 2) {
			continue;
		}
		const int t = anim->add_track(Animation::TYPE_VALUE);
		const String property = String(":surface_material_override/") + String::num_int64(surface) + String(":uv1_offset");
		anim->track_set_path(t, NodePath(mesh_path + property));
		anim->track_set_interpolation_type(t, interpolation(track));
		for (const auto &[msec, value] : keys) {
			anim->track_insert_key(t, msec / 1000.0, Vector3(value.x, value.y, 0.0f));
			length = std::max(length, msec / 1000.0);
		}
	}
	anim->set_length(std::max(length, 0.001));
	return anim;
}

Ref<Animation> build_animation(const M2Model &model, std::optional<size_t> sequence, uint32_t length, const std::vector<Vector3> &rests) {
	Ref<Animation> anim;
	anim.instantiate();
	anim->set_length(length / 1000.0);
	anim->set_loop_mode(Animation::LOOP_LINEAR);
	for (size_t b = 0; b < model.bones.size(); b++) {
		const M2Bone &bone = model.bones[b];
		const NodePath path("Skeleton:bone_" + String::num_int64(b));
		if (const auto keys = track_keys(model, bone.translation, sequence, length, &M2AnimationTrack::SequenceKeys::vec3Values); !keys.empty()) {
			const int t = anim->add_track(Animation::TYPE_POSITION_3D);
			anim->track_set_path(t, path);
			anim->track_set_interpolation_type(t, interpolation(bone.translation));
			for (const auto &[msec, value] : keys) {
				anim->position_track_insert_key(t, msec / 1000.0, rests[b] + wow_to_godot(value));
			}
		}
		if (const auto keys = track_keys(model, bone.rotation, sequence, length, &M2AnimationTrack::SequenceKeys::quatValues); !keys.empty()) {
			const int t = anim->add_track(Animation::TYPE_ROTATION_3D);
			anim->track_set_path(t, path);
			anim->track_set_interpolation_type(t, interpolation(bone.rotation));
			for (const auto &[msec, value] : keys) {
				anim->rotation_track_insert_key(t, msec / 1000.0, wow_to_godot(value).normalized());
			}
		}
		if (const auto keys = track_keys(model, bone.scale, sequence, length, &M2AnimationTrack::SequenceKeys::vec3Values); !keys.empty()) {
			const int t = anim->add_track(Animation::TYPE_SCALE_3D);
			anim->track_set_path(t, path);
			anim->track_set_interpolation_type(t, interpolation(bone.scale));
			for (const auto &[msec, value] : keys) {
				anim->scale_track_insert_key(t, msec / 1000.0, wow_scale_to_godot(value));
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
			// A blend mode only reaches the pipeline from the transparent pass, else the glow draws as a solid card.
			mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
			mat->set_blend_mode(wmo ? BaseMaterial3D::BLEND_MODE_MIX : BaseMaterial3D::BLEND_MODE_ADD);
			mat->set_depth_draw_mode(BaseMaterial3D::DEPTH_DRAW_DISABLED);
			break;
		case M2_MOD:
		case M2_MOD2X:
			mat->set_transparency(BaseMaterial3D::TRANSPARENCY_ALPHA);
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
	// From version 264 the batches and indices live in a .skin file beside the model.
	if (data->model.version >= M2_SKIN_VERSION && data->model.indices.empty()) {
		std::vector<uint8_t> skin;
		if (archive->read_bytes(WowArchive::normalize(path.get_basename() + "00.skin"), skin)) {
			M2Loader::loadSkin(skin, data->model);
		} else {
			UtilityFunctions::push_warning("WowLoader: missing skin for ", path);
		}
	}
	// A spell effect is often nothing but emitters, so geometry alone does not decide.
	if (!data->model.isValid() && data->model.particleEmitters.empty() && data->model.ribbonEmitters.empty()) {
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
	for (const uint32_t index : visible_batches(model, geosets)) {
		const M2Batch &batch = model.batches[index];
		const Color tint = batch_tint(model, batch);
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
			const uint32_t length = std::max<uint32_t>(data.model.sequences[i].duration, 1);
			animations->add_animation(name, build_animation(data.model, i, length, data.bone_rests));
		}
	}
	std::lock_guard<std::mutex> lock(cache_mutex);
	return m2_animations.emplace(key, animations).first->second;
}

// Kept out of the main library, or the main player's deterministic blend would reset these bones.
Ref<AnimationLibrary> WowLoader::get_m2_global_animations(const String &path, const M2Data &data) {
	const std::string key = std::string(path.to_lower().replace("/", "\\").utf8().get_data()) + "|global";
	{
		std::lock_guard<std::mutex> lock(cache_mutex);
		auto cached = m2_animations.find(key);
		if (cached != m2_animations.end()) {
			return cached->second;
		}
	}
	Ref<AnimationLibrary> animations;
	animations.instantiate();
	const std::vector<uint32_t> &durations = data.model.globalSequenceDurations;
	if (const auto longest = std::max_element(durations.begin(), durations.end()); longest != durations.end() && *longest > 0) {
		const Ref<Animation> anim = build_animation(data.model, std::nullopt, *longest, data.bone_rests);
		if (anim->get_track_count() > 0) {
			animations->add_animation("Global", anim);
		}
	}
	std::lock_guard<std::mutex> lock(cache_mutex);
	return m2_animations.emplace(key, animations).first->second;
}

// Asked for after loading, because a shape per streamed model costs far more than it is worth.
void WowLoader::add_collision(Node3D *node) {
	ERR_FAIL_NULL(node);
	if (node->find_child("Collision", false, false) != nullptr) {
		return;
	}
	const String path = node->get_meta("m2_path", String());
	if (path.is_empty()) {
		return;
	}
	if (const std::shared_ptr<const M2Data> data = get_m2_data(path)) {
		add_m2_collision(node, data->model);
	}
}

void WowLoader::add_m2_collision(Node3D *root, const M2Model &model) {
	PackedVector3Array faces;
	for (size_t t = 0; t + 2 < model.collisionIndices.size(); t += 3) {
		for (int k : { 0, 2, 1 }) {
			const uint16_t index = model.collisionIndices[t + k];
			if (index >= model.collisionVertices.size()) {
				return;
			}
			faces.push_back(wow_to_godot(model.collisionVertices[index]));
		}
	}
	if (faces.is_empty()) {
		return;
	}
	Ref<ConcavePolygonShape3D> shape;
	shape.instantiate();
	shape->set_faces(faces);
	// Both sides collide, so a ray finds the deck whichever way the collision mesh was wound.
	shape->set_backface_collision_enabled(true);
	CollisionShape3D *collision = memnew(CollisionShape3D);
	collision->set_shape(shape);
	StaticBody3D *body = memnew(StaticBody3D);
	body->set_name("Collision");
	body->add_child(collision);
	root->add_child(body);
}

Node3D *WowLoader::load_m2(const String &path, const Dictionary &skins, const PackedInt32Array &geosets) {
	ERR_FAIL_COND_V(archive.is_null(), nullptr);
	const std::shared_ptr<const M2Data> data = get_m2_data(path);
	if (!data) {
		return nullptr;
	}
	Node3D *root = memnew(Node3D);
	root->set_name(file_stem(path));
	// Anything hung on the model later finds its attachment points through this.
	root->set_meta("m2_path", path);
	MeshInstance3D *mesh = memnew(MeshInstance3D);
	mesh->set_name("Mesh");
	mesh->set_mesh(get_m2_mesh(path, *data, skins, geosets));
	if (data->bone_rests.empty()) {
		root->add_child(mesh);
		add_texture_animation(root, mesh, data->model, geosets);
		add_particles(root, nullptr, data->model);
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
	add_texture_animation(root, mesh, data->model, geosets);

	const Ref<AnimationLibrary> animations = get_m2_animations(path, *data);
	AnimationPlayer *player = memnew(AnimationPlayer);
	player->set_name("AnimationPlayer");
	player->add_animation_library("", animations);
	root->add_child(player);
	if (const Ref<AnimationLibrary> global = get_m2_global_animations(path, *data); global->has_animation("Global")) {
		AnimationPlayer *clock = memnew(AnimationPlayer);
		clock->set_name("GlobalSequences");
		clock->add_animation_library("", global);
		root->add_child(clock);
		clock->set_autoplay("Global");
	}
	if (animations->has_animation("Stand")) {
		player->set_autoplay("Stand");
	}
	add_particles(root, skeleton, data->model);
	return root;
}

// The scrolling UVs animate a copy of the material, so other models with the same one stay put.
void WowLoader::add_texture_animation(Node3D *root, MeshInstance3D *mesh, const M2Model &model, const PackedInt32Array &geosets) {
	const std::vector<uint32_t> batches = visible_batches(model, geosets);
	// The mesh sits under the skeleton on a skinned model, and straight under the root otherwise.
	const Ref<Animation> anim = build_uv_animation(model, batches, String(root->get_path_to(mesh)));
	if (anim->get_track_count() == 0) {
		return;
	}
	for (int t = 0; t < anim->get_track_count(); t++) {
		const int surface = String(anim->track_get_path(t).get_subname(0)).get_slice("/", 1).to_int();
		const Ref<Material> material = mesh->get_mesh()->surface_get_material(surface);
		if (material.is_valid()) {
			mesh->set_surface_override_material(surface, material->duplicate());
		}
	}
	Ref<AnimationLibrary> library;
	library.instantiate();
	library->add_animation("Textures", anim);
	AnimationPlayer *player = memnew(AnimationPlayer);
	player->set_name("TextureAnimation");
	player->add_animation_library("", library);
	root->add_child(player);
	player->set_autoplay("Textures");
}

// M2 emitters become GPUParticles3D, driven by the values the model rests at.
void WowLoader::add_particles(Node3D *root, Skeleton3D *skeleton, const M2Model &model) {
	for (size_t i = 0; i < model.particleEmitters.size(); i++) {
		const M2ParticleEmitter &emitter = model.particleEmitters[i];
		if (!emitter.enabled || track_value(emitter.emissionRate, 0.0f) <= 0.0f) {
			continue;
		}
		String texture;
		if (emitter.texture < model.textures.size()) {
			texture = String(model.textures[emitter.texture].filename.c_str());
		}
		if (texture.is_empty()) {
			continue;
		}
		const float lifespan = std::max(track_value(emitter.lifespan, 1.0f), 0.05f);
		const float rate = track_value(emitter.emissionRate, 0.0f);
		float largest = 1.0f;
		const Ref<CurveTexture> sizes = particle_sizes(emitter, largest);
		Ref<ParticleProcessMaterial> process;
		process.instantiate();
		process->set_direction(Vector3(0.0f, 1.0f, 0.0f));
		process->set_spread(Math::rad_to_deg(track_value(emitter.verticalRange, 0.0f)));
		const float speed = track_value(emitter.emissionSpeed, 0.0f);
		const float spread = track_value(emitter.speedVariation, 0.0f) * speed;
		process->set_param_min(ParticleProcessMaterial::PARAM_INITIAL_LINEAR_VELOCITY, std::max(speed - spread, 0.0f));
		process->set_param_max(ParticleProcessMaterial::PARAM_INITIAL_LINEAR_VELOCITY, speed + spread);
		process->set_gravity(Vector3(0.0f, -track_value(emitter.gravity, 0.0f), 0.0f));
		process->set_param_min(ParticleProcessMaterial::PARAM_SCALE, largest);
		process->set_param_max(ParticleProcessMaterial::PARAM_SCALE, largest);
		if (sizes.is_valid()) {
			process->set_param_texture(ParticleProcessMaterial::PARAM_SCALE, sizes);
		}
		if (emitter.textureRows * emitter.textureCols > 1) {
			process->set_param_min(ParticleProcessMaterial::PARAM_ANIM_SPEED, 1.0f);
			process->set_param_max(ParticleProcessMaterial::PARAM_ANIM_SPEED, 1.0f);
		}
		if (const Ref<GradientTexture1D> ramp = particle_colors(emitter); ramp.is_valid()) {
			process->set_color_ramp(ramp);
		}
		const float length = track_value(emitter.emissionAreaLength, 0.0f);
		const float width = track_value(emitter.emissionAreaWidth, 0.0f);
		if (emitter.emitterType == 2 && length > 0.0f) {
			process->set_emission_shape(ParticleProcessMaterial::EMISSION_SHAPE_SPHERE);
			process->set_emission_sphere_radius(length);
		} else if (length > 0.0f || width > 0.0f) {
			process->set_emission_shape(ParticleProcessMaterial::EMISSION_SHAPE_BOX);
			process->set_emission_box_extents(Vector3(width * 0.5f, 0.0f, length * 0.5f));
		}
		GPUParticles3D *particles = memnew(GPUParticles3D);
		particles->set_name("Particles" + String::num_int64(i));
		particles->set_process_material(process);
		particles->set_lifetime(lifespan);
		particles->set_amount(std::clamp(static_cast<int>(rate * lifespan) + 1, 1, 512));
		Ref<QuadMesh> quad;
		quad.instantiate();
		quad->set_size(Vector2(1.0f, 1.0f));
		Ref<StandardMaterial3D> material;
		material.instantiate();
		material->set_texture(StandardMaterial3D::TEXTURE_ALBEDO, load_texture(texture));
		material->set_shading_mode(StandardMaterial3D::SHADING_MODE_UNSHADED);
		material->set_transparency(StandardMaterial3D::TRANSPARENCY_ALPHA);
		material->set_depth_draw_mode(StandardMaterial3D::DEPTH_DRAW_DISABLED);
		material->set_specular(0.0f);
		// The emitter's colour and alpha arrive as the particle's vertex colour.
		material->set_flag(StandardMaterial3D::FLAG_ALBEDO_FROM_VERTEX_COLOR, true);
		// Only BILLBOARD_PARTICLES keeps the particle's scale and walks the texture's tiles.
		material->set_billboard_mode(StandardMaterial3D::BILLBOARD_PARTICLES);
		material->set_particles_anim_h_frames(emitter.textureCols);
		material->set_particles_anim_v_frames(emitter.textureRows);
		material->set_particles_anim_loop(false);
		if (emitter.blendingType == M2_ADD || emitter.blendingType == M2_NO_ALPHA_ADD) {
			material->set_blend_mode(StandardMaterial3D::BLEND_MODE_ADD);
		} else if (emitter.blendingType == M2_MOD || emitter.blendingType == M2_MOD2X) {
			material->set_blend_mode(StandardMaterial3D::BLEND_MODE_MUL);
		}
		quad->set_material(material);
		particles->set_draw_pass_mesh(0, quad);
		Node3D *holder = root;
		Vector3 offset = wow_to_godot(emitter.position);
		if (skeleton && emitter.bone < static_cast<uint16_t>(skeleton->get_bone_count())) {
			BoneAttachment3D *attachment = memnew(BoneAttachment3D);
			attachment->set_name("ParticleBone" + String::num_int64(i));
			skeleton->add_child(attachment);
			attachment->set_bone_idx(emitter.bone);
			holder = attachment;
			// The bone already stands at its pivot, and the emitter position is model space too.
			offset -= wow_to_godot(model.bones[emitter.bone].pivot);
		}
		holder->add_child(particles);
		particles->set_position(offset);
	}
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
		b["tint"] = batch_tint(model, batch);
		b["flags"] = batch.materialIndex < model.materials.size() ? static_cast<int64_t>(model.materials[batch.materialIndex].flags) : static_cast<int64_t>(0);
		b["texture_animation"] = static_cast<int64_t>(batch.textureAnimIndex);
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
	Array transforms;
	for (const M2TextureTransform &transform : model.textureTransforms) {
		Dictionary t;
		t["global_sequence"] = transform.translation.globalSequence;
		t["sequences"] = static_cast<int64_t>(transform.translation.sequences.size());
		int64_t keys = 0;
		for (const M2AnimationTrack::SequenceKeys &sequence : transform.translation.sequences) {
			keys += static_cast<int64_t>(sequence.timestamps.size());
		}
		t["translation_keys"] = keys;
		int64_t spins = 0;
		for (const M2AnimationTrack::SequenceKeys &sequence : transform.rotation.sequences) {
			spins += static_cast<int64_t>(sequence.timestamps.size());
		}
		t["rotation_keys"] = spins;
		int64_t zooms = 0;
		for (const M2AnimationTrack::SequenceKeys &sequence : transform.scale.sequences) {
			zooms += static_cast<int64_t>(sequence.timestamps.size());
		}
		t["scale_keys"] = zooms;
		transforms.push_back(t);
	}
	info["texture_transforms"] = transforms;
	PackedInt32Array transform_lookup;
	for (const uint16_t index : model.textureTransformLookup) {
		transform_lookup.push_back(index);
	}
	info["texture_transform_lookup"] = transform_lookup;
	Array emitters;
	for (const M2ParticleEmitter &emitter : model.particleEmitters) {
		Dictionary e;
		e["texture"] = emitter.texture < model.textures.size()
				? String(model.textures[emitter.texture].filename.c_str())
				: String("?");
		e["blend"] = emitter.blendingType;
		e["type"] = emitter.emitterType;
		e["flags"] = emitter.flags;
		e["rows"] = emitter.textureRows;
		e["cols"] = emitter.textureCols;
		e["rate"] = track_value(emitter.emissionRate, 0.0f);
		e["speed"] = track_value(emitter.emissionSpeed, 0.0f);
		e["lifespan"] = track_value(emitter.lifespan, 0.0f);
		PackedFloat32Array scales;
		for (const float size : emitter.particleScale.floatValues) {
			scales.push_back(size);
		}
		e["scales"] = scales;
		PackedColorArray tints;
		for (const glm::vec3 rgb : emitter.particleColor.vec3Values) {
			tints.push_back(Color(rgb.r, rgb.g, rgb.b, 1.0f));
		}
		e["colors"] = tints;
		PackedFloat32Array alphas;
		for (const float alpha : emitter.particleAlpha.floatValues) {
			alphas.push_back(alpha);
		}
		e["alphas"] = alphas;
		emitters.push_back(e);
	}
	info["particles"] = emitters;
	Array ribbons;
	for (const M2RibbonEmitter &ribbon : model.ribbonEmitters) {
		Dictionary r;
		r["bone"] = ribbon.bone;
		r["position"] = wow_to_godot(ribbon.position);
		r["texture"] = ribbon.textureIndex < model.textures.size()
				? String(model.textures[ribbon.textureIndex].filename.c_str())
				: String("?");
		r["edges_per_second"] = ribbon.edgesPerSecond;
		r["lifetime"] = ribbon.edgeLifetime;
		r["gravity"] = ribbon.gravity;
		r["above"] = track_value(ribbon.heightAboveTrack, 1.0f);
		r["below"] = track_value(ribbon.heightBelowTrack, 1.0f);
		ribbons.push_back(r);
	}
	info["ribbons"] = ribbons;
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
// A batch is culled by its middle, so the reach it covers is added to the range.
static float doodad_range(const M2Model &model, const std::vector<Transform3D> &instances) {
	AABB bounds;
	for (size_t i = 0; i < instances.size(); i++) {
		const float reach = std::max(model.boundRadius * static_cast<float>(instances[i].basis.get_scale().x), 1.0f);
		const AABB box(instances[i].origin - Vector3(reach, reach, reach), Vector3(reach, reach, reach) * 2.0f);
		bounds = i == 0 ? box : bounds.merge(box);
	}
	const float own = std::clamp(model.boundRadius * DOODAD_RANGE_PER_YARD, DOODAD_NEAREST_RANGE, DOODAD_FURTHEST_RANGE);
	return own + bounds.size.length() * 0.5f;
}

Node3D *WowLoader::build_static_models(const Array &placements) {
	std::unordered_map<std::string, std::pair<String, std::vector<Transform3D>>> groups;
	for (int i = 0; i < placements.size(); i++) {
		const Dictionary placement = placements[i];
		const String path = placement["path"];
		const Transform3D transform = placement["transform"];
		const std::string cell = std::to_string(static_cast<int>(std::floor(transform.origin.x / DOODAD_CELL_YARDS)))
				+ "," + std::to_string(static_cast<int>(std::floor(transform.origin.z / DOODAD_CELL_YARDS)));
		auto &group = groups[std::string(path.to_lower().utf8().get_data()) + "|" + cell];
		group.first = path;
		group.second.push_back(transform);
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
		instance->set_visibility_range_end(doodad_range(model, group.second));
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

// Vanilla WMOs carry no LiquidType.dbc id, so the low bits of the group's type pick the material.
int wmo_liquid_material(const WMOGroup &group) {
	const uint32_t basic = group.liquidType & 3;
	if (basic == 0) {
		return group.flags & WMO_GROUP_OCEAN ? 1 : 0;
	}
	return static_cast<int>(basic);
}

// MLIQ: a grid of heights over the group, laid out like the terrain's own liquid tiles.
void WowLoader::add_wmo_liquid(Node3D *root, const WMOGroup &group, size_t index) {
	const WMOLiquid &liquid = group.liquid;
	if (!liquid.hasLiquid() || liquid.heights.size() < liquid.xVerts * liquid.yVerts) {
		return;
	}
	const int material = wmo_liquid_material(group);
	if (material >= liquid_materials.size()) {
		return;
	}
	auto corner = [&](uint32_t col, uint32_t row) {
		return wow_to_godot(glm::vec3(
				liquid.basePosition.x + col * WMO_LIQUID_TILE,
				liquid.basePosition.y + row * WMO_LIQUID_TILE,
				liquid.heights[row * liquid.xVerts + col]));
	};
	PackedVector3Array faces;
	AABB volume;
	bool started = false;
	for (uint32_t row = 0; row < liquid.yTiles; row++) {
		for (uint32_t col = 0; col < liquid.xTiles; col++) {
			const size_t tile = row * liquid.xTiles + col;
			if (tile < liquid.flags.size() && (liquid.flags[tile] & WMO_LIQUID_TILE_HIDDEN)) {
				continue;
			}
			const Vector3 a = corner(col, row), b = corner(col + 1, row);
			const Vector3 d = corner(col, row + 1), e = corner(col + 1, row + 1);
			faces.append_array(PackedVector3Array({ a, b, e, a, e, d }));
			for (const Vector3 &corner_point : { a, b, d, e }) {
				volume = started ? volume.expand(corner_point) : AABB(corner_point, Vector3());
				started = true;
			}
		}
	}
	if (faces.is_empty()) {
		return;
	}
	Ref<ArrayMesh> mesh;
	mesh.instantiate();
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = faces;
	mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	mesh->surface_set_material(0, liquid_materials[material]);
	MeshInstance3D *instance = memnew(MeshInstance3D);
	instance->set_name("Liquid" + String::num_int64(index));
	instance->set_mesh(mesh);
	// Model space, so the placement transform still has to be applied; the top is the surface.
	const float floor_y = std::min(wow_to_godot(group.boundingBoxMin).y, volume.position.y);
	volume.size.y += volume.position.y - floor_y;
	volume.position.y = floor_y;
	instance->set_meta("liquid_volume", volume);
	root->add_child(instance);
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
		add_wmo_liquid(root, group, g);

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
