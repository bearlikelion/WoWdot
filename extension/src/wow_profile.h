#pragma once

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <cstring>

namespace godot {

// What a client speaks: the wire build, plus the few things the build alone does not decide.
struct WowProfile {
	const char *id;
	const char *version;
	uint16_t build;
	uint8_t major;
	uint8_t minor;
	uint8_t patch;
	bool legacy_realm_list;
	uint8_t char_create_success;
	uint8_t char_delete_success;
};

inline const WowProfile &wow_profile() {
	static const WowProfile classic = { "classic", "1.12.1", 5875, 1, 12, 1, true, 46, 57 };
	static const WowProfile wotlk = { "wotlk", "3.3.5a", 12340, 3, 3, 5, false, 47, 71 };
	static const WowProfile &active =
			String(ProjectSettings::get_singleton()->get_setting("wowgd/expansion", "classic")) == "wotlk"
			? wotlk
			: classic;
	return active;
}

// res://data/<id>/ holds the profile's opcode, update field and DBC layout tables.
inline String wow_data_path(const String &name) {
	return String("res://data/") + wow_profile().id + "/" + name;
}

} // namespace godot
