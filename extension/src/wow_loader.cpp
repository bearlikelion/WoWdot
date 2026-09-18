#include "wow_loader.h"

#include "pipeline/blp_loader.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <cctype>

namespace godot {

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
	PackedByteArray pixels;
	pixels.resize(blp.data.size());
	std::copy(blp.data.begin(), blp.data.end(), pixels.ptrw());
	// ponytail: DXT is decoded to RGBA8 on the CPU; pass DXT blocks through to Image if VRAM or load time matters.
	Ref<Image> image = Image::create_from_data(blp.width, blp.height, false, Image::FORMAT_RGBA8, pixels);
	image->generate_mipmaps();
	return image;
}

Ref<ImageTexture> WowLoader::load_texture(const String &path) {
	std::string key = WowArchive::normalize(path);
	std::transform(key.begin(), key.end(), key.begin(), [](unsigned char c) { return std::tolower(c); });
	{
		std::lock_guard<std::mutex> lock(mutex);
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
	std::lock_guard<std::mutex> lock(mutex);
	textures[key] = texture;
	return texture;
}

void WowLoader::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_archive", "archive"), &WowLoader::set_archive);
	ClassDB::bind_method(D_METHOD("get_archive"), &WowLoader::get_archive);
	ClassDB::bind_method(D_METHOD("load_image", "path"), &WowLoader::load_image);
	ClassDB::bind_method(D_METHOD("load_texture", "path"), &WowLoader::load_texture);
	ClassDB::bind_method(D_METHOD("load_m2", "path", "skins"), &WowLoader::load_m2, DEFVAL(Dictionary()));
	ClassDB::bind_method(D_METHOD("load_wmo", "path"), &WowLoader::load_wmo);
	ClassDB::bind_method(D_METHOD("get_m2_info", "path"), &WowLoader::get_m2_info);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "archive", PROPERTY_HINT_RESOURCE_TYPE, "WowArchive"), "set_archive", "get_archive");
}

} // namespace godot
