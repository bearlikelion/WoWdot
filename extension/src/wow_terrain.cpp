#include "wow_coords.h"
#include "wow_loader.h"

#include "core/coordinates.hpp"
#include "pipeline/adt_loader.hpp"
#include "pipeline/terrain_mesh.hpp"
#include "pipeline/wdt_loader.hpp"

#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/height_map_shape3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cstring>

using namespace wowee;

namespace godot {

namespace {

constexpr uint32_t CHUNK_MAIN = 0x4D41494E;
constexpr uint32_t MAIN_HAS_ADT = 0x1;
constexpr int GRID = 64;
constexpr float CHUNK_SIZE = core::coords::TILE_SIZE / 16.0f;
constexpr float UNIT_SIZE = CHUNK_SIZE / 8.0f;
constexpr int HEIGHT_GRID = 257;
constexpr float HEIGHT_STEP = core::coords::TILE_SIZE / (HEIGHT_GRID - 1);

String map_dir(const String &map_name) {
	return "World\\Maps\\" + map_name + "\\" + map_name;
}

// ADT placements store position in placement space and Euler degrees; heading is offset by 180.
Transform3D placement_transform(const float position[3], const float rotation[3], float scale) {
	const glm::vec3 wow = core::coords::adtToWorld(position[0], position[1], position[2]);
	const float to_rad = Math_PI / 180.0f;
	const glm::quat q = glm::angleAxis((rotation[1] + 180.0f) * to_rad, glm::vec3(0, 0, 1)) *
			glm::angleAxis(-rotation[0] * to_rad, glm::vec3(0, 1, 0)) *
			glm::angleAxis(-rotation[2] * to_rad, glm::vec3(1, 0, 0));
	return Transform3D(Basis(wow_to_godot(q)).scaled(Vector3(scale, scale, scale)), wow_to_godot(wow));
}

// Texture repeats once per quad, eight times across a chunk, using the same half-step inner vertices as MCVT.
Vector2 vertex_offset(int index) {
	const int row = index / 17;
	const int col = index % 17;
	return col > 8 ? Vector2(col - 8.5f, row + 0.5f) : Vector2(col, row);
}

Ref<ImageTexture> alpha_texture(const pipeline::ChunkMesh &chunk) {
	PackedByteArray pixels;
	pixels.resize(64 * 64 * 4);
	uint8_t *out = pixels.ptrw();
	std::memset(out, 0, pixels.size());
	for (size_t layer = 1; layer < chunk.layers.size() && layer < 4; layer++) {
		const std::vector<uint8_t> &alpha = chunk.layers[layer].alphaData;
		for (size_t i = 0; i < alpha.size() && i < 64 * 64; i++) {
			out[i * 4 + layer - 1] = alpha[i];
		}
	}
	return ImageTexture::create_from_image(Image::create_from_data(64, 64, false, Image::FORMAT_RGBA8, pixels));
}

// A half-quad grid hits every MCVT vertex, and edge midpoints of the fan triangulation are corner averages.
PackedFloat32Array collision_heights(const pipeline::ADTTerrain &terrain) {
	PackedFloat32Array heights;
	heights.resize(HEIGHT_GRID * HEIGHT_GRID);
	float *out = heights.ptrw();
	for (int j = 0; j < HEIGHT_GRID; j++) {
		const int cy = std::min(j / 16, 15);
		const int row2 = j - cy * 16;
		for (int i = 0; i < HEIGHT_GRID; i++) {
			const int cx = std::min(i / 16, 15);
			const int col2 = i - cx * 16;
			const pipeline::MapChunk &chunk = terrain.chunks[cy * 16 + cx];
			float h = 0.0f;
			if (chunk.hasHeightMap()) {
				const auto &mcvt = chunk.heightMap.heights;
				auto outer = [&](int row, int col) { return mcvt[row * 17 + col]; };
				if (row2 % 2 == 1 && col2 % 2 == 1) {
					h = mcvt[(row2 / 2) * 17 + 9 + col2 / 2];
				} else if (row2 % 2 == 1) {
					h = 0.5f * (outer(row2 / 2, col2 / 2) + outer(row2 / 2 + 1, col2 / 2));
				} else if (col2 % 2 == 1) {
					h = 0.5f * (outer(row2 / 2, col2 / 2) + outer(row2 / 2, col2 / 2 + 1));
				} else {
					h = outer(row2 / 2, col2 / 2);
				}
				h += chunk.position[2];
			}
			// HeightMapShape3D rows run along Godot +Z (WoW -X), columns along Godot +X (WoW -Y).
			out[j * HEIGHT_GRID + i] = h / HEIGHT_STEP;
		}
	}
	return heights;
}

} // namespace

Dictionary WowLoader::get_map_info(const String &map_name) {
	ERR_FAIL_COND_V(archive.is_null(), Dictionary());
	std::vector<uint8_t> data;
	if (!archive->read_bytes(WowArchive::normalize(map_dir(map_name) + ".wdt"), data)) {
		UtilityFunctions::push_warning("WowLoader: missing WDT for ", map_name);
		return Dictionary();
	}
	Array tiles;
	for (size_t offset = 0; offset + 8 <= data.size();) {
		uint32_t magic = 0;
		uint32_t size = 0;
		std::memcpy(&magic, &data[offset], 4);
		std::memcpy(&size, &data[offset + 4], 4);
		if (magic == CHUNK_MAIN && offset + 8 + size <= data.size() && size >= GRID * GRID * 8) {
			for (int i = 0; i < GRID * GRID; i++) {
				uint32_t flags = 0;
				std::memcpy(&flags, &data[offset + 8 + i * 8], 4);
				if (flags & MAIN_HAS_ADT) {
					tiles.push_back(Vector2i(i % GRID, i / GRID));
				}
			}
		}
		offset += 8 + size;
	}
	Dictionary info;
	info["tiles"] = tiles;
	const pipeline::WDTInfo wdt = pipeline::parseWDT(data);
	if (!wdt.rootWMOPath.empty()) {
		info["wmo"] = String(wdt.rootWMOPath.c_str());
		Transform3D transform = placement_transform(wdt.position, wdt.rotation, 1.0f);
		// A zero MODF position means server coordinates are the WMO's own, so it sits at the origin.
		if (wdt.position[0] == 0.0f && wdt.position[1] == 0.0f && wdt.position[2] == 0.0f) {
			transform.origin = Vector3();
		}
		info["wmo_transform"] = transform;
		info["wmo_doodad_set"] = wdt.doodadSet;
	}
	return info;
}

Node3D *WowLoader::load_adt(const String &map_name, int tile_x, int tile_y) {
	ERR_FAIL_COND_V(archive.is_null(), nullptr);
	const String path = map_dir(map_name) + "_" + String::num_int64(tile_x) + "_" + String::num_int64(tile_y) + ".adt";
	std::vector<uint8_t> data;
	if (!archive->read_bytes(WowArchive::normalize(path), data)) {
		return nullptr;
	}
	pipeline::ADTTerrain terrain = pipeline::ADTLoader::load(data);
	if (!terrain.isLoaded()) {
		UtilityFunctions::push_warning("WowLoader: bad ADT ", path);
		return nullptr;
	}
	terrain.coord.x = tile_x;
	terrain.coord.y = tile_y;
	const pipeline::TerrainMesh mesh = pipeline::TerrainMeshGenerator::generate(terrain);

	Node3D *root = memnew(Node3D);
	root->set_name("Tile_" + String::num_int64(tile_x) + "_" + String::num_int64(tile_y));
	// One mesh with a surface per chunk keeps a tile to a single node; 256 is Godot's surface limit.
	Ref<ArrayMesh> terrain_mesh;
	terrain_mesh.instantiate();

	for (int c = 0; c < 256; c++) {
		const pipeline::ChunkMesh &chunk = mesh.chunks[c];
		if (!chunk.isValid()) {
			continue;
		}
		PackedVector3Array vertices;
		PackedVector3Array normals;
		PackedVector2Array uvs;
		PackedVector2Array alpha_uvs;
		for (size_t i = 0; i < chunk.vertices.size(); i++) {
			const pipeline::TerrainVertex &v = chunk.vertices[i];
			vertices.push_back(wow_to_godot(glm::vec3(v.position[0], v.position[1], v.position[2])));
			normals.push_back(wow_to_godot(glm::vec3(v.normal[0], v.normal[1], v.normal[2])).normalized());
			uvs.push_back(vertex_offset(i));
			alpha_uvs.push_back(Vector2(v.layerUV[0], v.layerUV[1]));
		}
		PackedInt32Array indices;
		for (uint32_t index : chunk.indices) {
			indices.push_back(index);
		}
		Array arrays;
		arrays.resize(Mesh::ARRAY_MAX);
		arrays[Mesh::ARRAY_VERTEX] = vertices;
		arrays[Mesh::ARRAY_NORMAL] = normals;
		arrays[Mesh::ARRAY_TEX_UV] = uvs;
		arrays[Mesh::ARRAY_TEX_UV2] = alpha_uvs;
		arrays[Mesh::ARRAY_INDEX] = indices;
		const int surface = terrain_mesh->get_surface_count();
		terrain_mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
		terrain_mesh->surface_set_name(surface, "Chunk_" + String::num_int64(c % 16) + "_" + String::num_int64(c / 16));

		if (terrain_shader.is_valid()) {
			Ref<ShaderMaterial> material;
			material.instantiate();
			material->set_shader(terrain_shader);
			material->set_shader_parameter("layer_count", int64_t(chunk.layers.size()));
			for (size_t layer = 0; layer < chunk.layers.size() && layer < 4; layer++) {
				const uint32_t texture_id = chunk.layers[layer].textureId;
				if (texture_id < mesh.textures.size()) {
					material->set_shader_parameter("layer" + String::num_int64(layer), load_texture(mesh.textures[texture_id].c_str()));
				}
			}
			material->set_shader_parameter("alpha_map", alpha_texture(chunk));
			terrain_mesh->surface_set_material(surface, material);
		}
	}
	MeshInstance3D *terrain_instance = memnew(MeshInstance3D);
	terrain_instance->set_name("Terrain");
	terrain_instance->set_mesh(terrain_mesh);
	root->add_child(terrain_instance);

	// MCLQ water: 9x9 absolute heights per chunk with an 8x8 tile mask, laid out like the outer MCVT grid.
	std::vector<PackedVector3Array> liquid_vertices(4);
	for (int c = 0; c < 256; c++) {
		const float base_x = (32.0f - tile_y) * core::coords::TILE_SIZE - (c / 16) * CHUNK_SIZE;
		const float base_y = (32.0f - tile_x) * core::coords::TILE_SIZE - (c % 16) * CHUNK_SIZE;
		for (const pipeline::ADTTerrain::WaterLayer &layer : terrain.waterData[c].layers) {
			const int stride = layer.width + 1;
			if (layer.heights.size() < size_t(stride * (layer.height + 1)) || layer.liquidType > 3) {
				continue;
			}
			auto corner = [&](int col, int row) {
				const int x = layer.x + col;
				const int y = layer.y + row;
				return wow_to_godot(glm::vec3(base_x - y * UNIT_SIZE, base_y - x * UNIT_SIZE, layer.heights[row * stride + col]));
			};
			for (int row = 0; row < layer.height; row++) {
				for (int col = 0; col < layer.width; col++) {
					if (row < int(layer.mask.size()) && !(layer.mask[row] & (1 << col))) {
						continue;
					}
					const Vector3 a = corner(col, row), b = corner(col + 1, row), d = corner(col, row + 1), e = corner(col + 1, row + 1);
					liquid_vertices[layer.liquidType].append_array(PackedVector3Array({ a, b, e, a, e, d }));
				}
			}
		}
	}
	Ref<ArrayMesh> water;
	water.instantiate();
	for (int type = 0; type < 4; type++) {
		if (liquid_vertices[type].is_empty()) {
			continue;
		}
		Array arrays;
		arrays.resize(Mesh::ARRAY_MAX);
		arrays[Mesh::ARRAY_VERTEX] = liquid_vertices[type];
		const int surface = water->get_surface_count();
		water->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
		if (type < liquid_materials.size()) {
			water->surface_set_material(surface, liquid_materials[type]);
		}
	}
	if (water->get_surface_count() > 0) {
		MeshInstance3D *instance = memnew(MeshInstance3D);
		instance->set_name("Liquid");
		instance->set_mesh(water);
		root->add_child(instance);
	}

	// ponytail: heightmap collision ignores MCNK holes (cave mouths); add hole-aware triangles when a cave needs walking into.
	Ref<HeightMapShape3D> shape;
	shape.instantiate();
	shape->set_map_width(HEIGHT_GRID);
	shape->set_map_depth(HEIGHT_GRID);
	shape->set_map_data(collision_heights(terrain));
	const float tile_north = (32.0f - tile_y) * core::coords::TILE_SIZE;
	const float tile_west = (32.0f - tile_x) * core::coords::TILE_SIZE;
	CollisionShape3D *collision = memnew(CollisionShape3D);
	collision->set_shape(shape);
	collision->set_transform(Transform3D(Basis().scaled(Vector3(HEIGHT_STEP, HEIGHT_STEP, HEIGHT_STEP)),
			Vector3(-tile_west + core::coords::TILE_SIZE / 2.0f, 0.0f, -tile_north + core::coords::TILE_SIZE / 2.0f)));
	StaticBody3D *body = memnew(StaticBody3D);
	body->set_name("Collision");
	body->add_child(collision);
	root->add_child(body);

	Array placements;
	for (const auto &p : terrain.doodadPlacements) {
		if (p.nameId >= terrain.doodadNames.size()) {
			continue;
		}
		Dictionary d;
		d["kind"] = "m2";
		d["path"] = String(terrain.doodadNames[p.nameId].c_str());
		d["unique_id"] = p.uniqueId;
		d["transform"] = placement_transform(p.position, p.rotation, p.scale / 1024.0f);
		placements.push_back(d);
	}
	for (const auto &p : terrain.wmoPlacements) {
		if (p.nameId >= terrain.wmoNames.size()) {
			continue;
		}
		Dictionary d;
		d["kind"] = "wmo";
		d["path"] = String(terrain.wmoNames[p.nameId].c_str());
		d["unique_id"] = p.uniqueId;
		d["transform"] = placement_transform(p.position, p.rotation, 1.0f);
		d["doodad_set"] = p.doodadSet;
		placements.push_back(d);
	}
	root->set_meta("placements", placements);
	return root;
}

} // namespace godot
