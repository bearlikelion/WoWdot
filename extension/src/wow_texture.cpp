#include "wow_texture.h"

#include "wow_loader.h"

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void WowTexture::set_file(const String &p_file) {
	file = p_file;
	texture = file.is_empty() ? Ref<ImageTexture>() : WowLoader::get_shared()->load_texture(file);
	emit_changed();
}

RID WowTexture::_get_rid() const {
	return texture.is_valid() ? texture->get_rid() : RID();
}

int32_t WowTexture::_get_width() const {
	return texture.is_valid() ? texture->get_width() : 1;
}

int32_t WowTexture::_get_height() const {
	return texture.is_valid() ? texture->get_height() : 1;
}

Ref<Image> WowTexture::_get_image() const {
	return texture.is_valid() ? texture->get_image() : Ref<Image>();
}

void WowTexture::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_file", "file"), &WowTexture::set_file);
	ClassDB::bind_method(D_METHOD("get_file"), &WowTexture::get_file);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "file"), "set_file", "get_file");
}

} // namespace godot
