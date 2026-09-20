#pragma once

#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <cstring>

namespace godot {

// The MSG_MOVE_* payload: which flags gate the optional blocks, and what rides with them.
struct MovementLayout {
	uint32_t on_transport;
	uint32_t falling;
	uint32_t pitch_mask;
	uint8_t flags2_size;
	// A packed transport guid followed by a transport time and seat byte.
	bool wide_transport;
	// Every payload opens with the mover's packed guid, which the server checks.
	bool names_mover;
};

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
	// The chat types are numbered differently and SMSG_MESSAGECHAT names its sender up front.
	bool renumbered_chat;
	MovementLayout movement;
};

inline const WowProfile &wow_profile() {
	static const WowProfile classic = { "classic", "1.12.1", 5875, 1, 12, 1, true, 46, 57, false,
		{ 0x2000000, 0x2000, 0x200000, 0, false, false } };
	static const WowProfile wotlk = { "wotlk", "3.3.5a", 12340, 3, 3, 5, false, 47, 71, true,
		{ 0x200, 0x1000, 0x200000 | 0x2000000, 2, true, true } };
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
