#pragma once

#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/image_texture.hpp>
#include <godot_cpp/classes/texture2d.hpp>

namespace godot {

// A texture named by its archive path, so scenes and themes store the path and never the pixels.
class WowTexture : public Texture2D {
	GDCLASS(WowTexture, Texture2D)

	String file;
	Ref<ImageTexture> texture;

protected:
	static void _bind_methods();

public:
	void set_file(const String &p_file);
	String get_file() const { return file; }

	RID _get_rid() const override;
	int32_t _get_width() const override;
	int32_t _get_height() const override;
	bool _has_alpha() const override { return true; }
	Ref<Image> _get_image() const override;
};

} // namespace godot
