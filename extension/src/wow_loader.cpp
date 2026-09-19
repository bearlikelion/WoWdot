#include "wow_loader.h"

#include "pipeline/blp_loader.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cctype>
#include <cstring>

namespace godot {

namespace {

constexpr size_t BLP2_HAS_MIPS = 11;
constexpr size_t BLP2_WIDTH = 12;
constexpr size_t BLP2_HEIGHT = 16;
constexpr size_t BLP2_MIP_OFFSETS = 20;
constexpr size_t BLP2_MIP_SIZES = 84;
constexpr size_t BLP2_HEADER_SIZE = 148;

// Decodes BLP2's authored mip chain by pointing a patched header at each level; false if incomplete.
bool decode_blp_mips(std::vector<uint8_t> data, int width, int height, PackedByteArray &r_pixels) {
	if (data.size() < BLP2_HEADER_SIZE || std::memcmp(data.data(), "BLP2", 4) != 0 || data[BLP2_HAS_MIPS] == 0) {
		return false;
	}
	uint32_t offsets[16];
	uint32_t sizes[16];
	std::memcpy(offsets, &data[BLP2_MIP_OFFSETS], sizeof(offsets));
	std::memcpy(sizes, &data[BLP2_MIP_SIZES], sizeof(sizes));
	uint32_t w = width;
	uint32_t h = height;
	for (int level = 0; level < 16; level++) {
		if (offsets[level] == 0 || sizes[level] == 0) {
			return false;
		}
		std::memcpy(&data[BLP2_WIDTH], &w, 4);
		std::memcpy(&data[BLP2_HEIGHT], &h, 4);
		std::memcpy(&data[BLP2_MIP_OFFSETS], &offsets[level], 4);
		std::memcpy(&data[BLP2_MIP_SIZES], &sizes[level], 4);
		const wowee::pipeline::BLPImage mip = wowee::pipeline::BLPLoader::load(data);
		if (!mip.isValid() || static_cast<uint32_t>(mip.width) != w || static_cast<uint32_t>(mip.height) != h) {
			return false;
		}
		const int64_t start = r_pixels.size();
		r_pixels.resize(start + mip.data.size());
		std::copy(mip.data.begin(), mip.data.end(), r_pixels.ptrw() + start);
		if (w == 1 && h == 1) {
			return true;
		}
		w = std::max<uint32_t>(1, w / 2);
		h = std::max<uint32_t>(1, h / 2);
	}
	return false;
}

} // namespace

namespace {
std::mutex shared_mutex;
// Reset by release_shared() at module teardown, before static destruction could outlive the engine.
Ref<WowLoader> shared_loader;
} // namespace

Ref<WowLoader> WowLoader::get_shared() {
	const std::lock_guard<std::mutex> lock(shared_mutex);
	if (shared_loader.is_null()) {
		Ref<WowArchive> archive;
		archive.instantiate();
		const String data_dir = ProjectSettings::get_singleton()->get_setting("wowgd/client_data_dir", "");
		if (archive->open(data_dir) != OK) {
			UtilityFunctions::push_error("WowLoader: cannot open client data at '", data_dir, "'");
		}
		shared_loader.instantiate();
		shared_loader->set_archive(archive);
	}
	return shared_loader;
}

void WowLoader::release_shared() {
	const std::lock_guard<std::mutex> lock(shared_mutex);
	shared_loader.unref();
}

Ref<Image> WowLoader::load_image(const String &path) {
	ERR_FAIL_COND_V(archive.is_null(), Ref<Image>());
	std::vector<uint8_t> data;
	if (!archive->read_bytes(WowArchive::normalize(path), data)) {
		UtilityFunctions::push_warning("WowLoader: missing texture ", path);
		return Ref<Image>();
	}
	const wowee::pipeline::BLPImage blp = wowee::pipeline::BLPLoader::load(data);
	if (!blp.isValid()) {
		UtilityFunctions::push_warning("WowLoader: bad BLP ", path);
		return Ref<Image>();
	}
	// ponytail: DXT is decoded to RGBA8 on the CPU; pass DXT blocks through to Image if VRAM or load time matters.
	PackedByteArray mips;
	if (decode_blp_mips(data, blp.width, blp.height, mips)) {
		return Image::create_from_data(blp.width, blp.height, true, Image::FORMAT_RGBA8, mips);
	}
	PackedByteArray pixels;
	pixels.resize(blp.data.size());
	std::copy(blp.data.begin(), blp.data.end(), pixels.ptrw());
	Ref<Image> image = Image::create_from_data(blp.width, blp.height, false, Image::FORMAT_RGBA8, pixels);
	image->generate_mipmaps();
	return image;
}

Ref<ImageTexture> WowLoader::load_texture(const String &path) {
	std::string key = WowArchive::normalize(path);
	std::transform(key.begin(), key.end(), key.begin(), [](unsigned char c) { return std::tolower(c); });
	{
		std::lock_guard<std::mutex> lock(cache_mutex);
		auto it = textures.find(key);
		if (it != textures.end()) {
			return it->second;
		}
	}
	const Ref<Image> image = load_image(path);
	if (image.is_null()) {
		return Ref<ImageTexture>();
	}
	Ref<ImageTexture> texture = ImageTexture::create_from_image(image);
	std::lock_guard<std::mutex> lock(cache_mutex);
	textures[key] = texture;
	return texture;
}

void WowLoader::_bind_methods() {
	ClassDB::bind_static_method("WowLoader", D_METHOD("get_shared"), &WowLoader::get_shared);
	ClassDB::bind_method(D_METHOD("set_archive", "archive"), &WowLoader::set_archive);
	ClassDB::bind_method(D_METHOD("get_archive"), &WowLoader::get_archive);
	ClassDB::bind_method(D_METHOD("set_terrain_shader", "shader"), &WowLoader::set_terrain_shader);
	ClassDB::bind_method(D_METHOD("get_terrain_shader"), &WowLoader::get_terrain_shader);
	ClassDB::bind_method(D_METHOD("set_liquid_materials", "materials"), &WowLoader::set_liquid_materials);
	ClassDB::bind_method(D_METHOD("get_liquid_materials"), &WowLoader::get_liquid_materials);
	ClassDB::bind_method(D_METHOD("load_image", "path"), &WowLoader::load_image);
	ClassDB::bind_method(D_METHOD("load_texture", "path"), &WowLoader::load_texture);
	ClassDB::bind_method(D_METHOD("load_m2", "path", "skins", "geosets"), &WowLoader::load_m2, DEFVAL(Dictionary()), DEFVAL(PackedInt32Array()));
	ClassDB::bind_method(D_METHOD("load_wmo", "path", "doodad_set"), &WowLoader::load_wmo, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_m2_info", "path"), &WowLoader::get_m2_info);
	ClassDB::bind_method(D_METHOD("build_static_models", "placements"), &WowLoader::build_static_models);
	ClassDB::bind_method(D_METHOD("get_map_info", "map_name"), &WowLoader::get_map_info);
	ClassDB::bind_method(D_METHOD("load_adt", "map_name", "tile_x", "tile_y"), &WowLoader::load_adt);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "archive", PROPERTY_HINT_RESOURCE_TYPE, "WowArchive"), "set_archive", "get_archive");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "terrain_shader", PROPERTY_HINT_RESOURCE_TYPE, "Shader"), "set_terrain_shader", "get_terrain_shader");
	ADD_PROPERTY(PropertyInfo(Variant::ARRAY, "liquid_materials", PROPERTY_HINT_ARRAY_TYPE, "Material"), "set_liquid_materials", "get_liquid_materials");
}

} // namespace godot
