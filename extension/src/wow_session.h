#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <array>
#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace wowee {
namespace auth {
class AuthHandler;
struct Realm;
} // namespace auth
namespace network {
class Packet;
class WorldSocket;
} // namespace network
namespace game {
class PacketParsers;
struct UpdateObjectData;
} // namespace game
} // namespace wowee

namespace godot {

// A 1.12.1 session against vMaNGOS in WoW wire coordinates; poll() drives it and emits every signal.
class WowSession : public RefCounted {
	GDCLASS(WowSession, RefCounted)

public:
	enum State {
		STATE_DISCONNECTED,
		STATE_AUTHENTICATING,
		STATE_REALM_LIST,
		STATE_CONNECTING_WORLD,
		STATE_CHARACTER_LIST,
		STATE_ENTERING_WORLD,
		STATE_IN_WORLD,
		STATE_FAILED,
	};

	// The five SMSG_ATTACKSWING_* refusals.
	enum AttackError {
		ATTACK_ERROR_NOT_IN_RANGE,
		ATTACK_ERROR_BAD_FACING,
		ATTACK_ERROR_NOT_STANDING,
		ATTACK_ERROR_DEAD_TARGET,
		ATTACK_ERROR_CANT_ATTACK,
	};

	// Vanilla numbering, which differs from the later expansions.
	enum ChatType {
		CHAT_SAY = 0x00,
		CHAT_PARTY = 0x01,
		CHAT_RAID = 0x02,
		CHAT_GUILD = 0x03,
		CHAT_OFFICER = 0x04,
		CHAT_YELL = 0x05,
		CHAT_WHISPER = 0x06,
		CHAT_WHISPER_INFORM = 0x07,
		CHAT_EMOTE = 0x08,
		CHAT_TEXT_EMOTE = 0x09,
		CHAT_SYSTEM = 0x0A,
		CHAT_MONSTER_SAY = 0x0B,
		CHAT_MONSTER_YELL = 0x0C,
		CHAT_MONSTER_EMOTE = 0x0D,
		CHAT_CHANNEL = 0x0E,
		CHAT_MONSTER_WHISPER = 0x1A,
		CHAT_RAID_BOSS_WHISPER = 0x59,
		CHAT_RAID_BOSS_EMOTE = 0x5A,
	};

private:
	struct WorldObject {
		uint8_t type_id = 0;
		std::unordered_map<uint16_t, uint32_t> fields;
		Vector3 position;
		float orientation = 0.0f;
		// Walk, run, run back, swim, swim back and turn rate, from the stock defaults until told otherwise.
		std::array<float, 6> speeds = { 2.5f, 7.0f, 4.5f, 4.722222f, 2.5f, 3.141594f };
	};

	std::unique_ptr<wowee::auth::AuthHandler> auth;
	std::unique_ptr<wowee::network::WorldSocket> world;
	std::unique_ptr<wowee::game::PacketParsers> parsers;
	// Sockets replaced from inside their own callbacks are parked here until poll() unwinds.
	std::unique_ptr<wowee::auth::AuthHandler> retired_auth;
	std::unique_ptr<wowee::network::WorldSocket> retired_world;
	bool polling = false;

	State state = STATE_DISCONNECTED;
	std::string username;
	std::string password;
	std::string auth_host;
	uint16_t auth_port = 3724;
	int auth_attempt = 0;
	bool retry_auth = false;
	std::vector<uint8_t> session_key;
	std::vector<wowee::auth::Realm> realms;
	uint32_t realm_id = 1;
	uint64_t player_guid = 0;
	std::unordered_map<uint64_t, WorldObject> objects;
	uint32_t ping_sequence = 0;
	uint64_t last_ping_msec = 0;
	std::unordered_map<uint64_t, std::string> player_names;
	std::unordered_map<uint32_t, Dictionary> creature_info;
	std::unordered_set<uint64_t> player_queries;
	std::unordered_map<uint32_t, std::vector<uint64_t>> creature_queries;
	// Player chat carries only the sender guid, so lines wait here for the name query.
	std::unordered_map<uint64_t, Array> chat_waiting;
	std::unordered_map<uint32_t, Dictionary> item_info;
	std::unordered_set<uint32_t> item_queries;
	std::unordered_set<uint32_t> creature_entry_queries;
	std::unordered_map<uint32_t, Dictionary> game_object_info;
	std::unordered_set<uint32_t> game_object_queries;
	std::unordered_map<uint32_t, Dictionary> quest_info;
	std::unordered_set<uint32_t> quest_queries;
	std::unordered_map<uint32_t, Array> npc_texts;
	std::unordered_set<uint32_t> npc_text_queries;
	PackedInt32Array known_spells;
	// Reputation list order: SMSG_INITIALIZE_FACTIONS flags and standings on top of Faction.dbc's base.
	PackedByteArray faction_flags;
	// The spline the server is moving the player along, as on a flight, and when it came in.
	Dictionary player_path;
	uint64_t player_path_msec = 0;
	PackedInt32Array faction_standings;
	// SMSG_ACTION_BUTTONS order: action id in the low 24 bits, the type in the high byte.
	PackedInt32Array action_buttons;

	void set_state(State p_state, const String &p_message = String());
	void retire_sockets();
	void release_retired();
	void begin_auth();
	void handle_world_packet(wowee::network::Packet &packet);
	void handle_update(wowee::game::UpdateObjectData &data);
	void handle_movement_relay(wowee::network::Packet &packet);
	void handle_compressed_moves(wowee::network::Packet &packet);
	void handle_chat(wowee::network::Packet &packet);
	void handle_quest_query(wowee::network::Packet &packet);
	bool handle_npc_packet(uint16_t op, wowee::network::Packet &packet);
	bool handle_combat_packet(uint16_t op, wowee::network::Packet &packet);
	void query_player_name(uint64_t guid);
	bool inflate(wowee::network::Packet &packet, std::vector<uint8_t> &r_data);
	const WorldObject *find(int64_t guid) const;

protected:
	static void _bind_methods();

public:
	WowSession();
	~WowSession() override;

	void login(const String &host, int port, const String &p_username, const String &p_password);
	void request_realms();
	void select_realm(int index);
	void request_characters();
	void create_character(const Dictionary &character);
	void delete_character(int64_t guid);
	void enter_world(int64_t guid);
	void logout();
	void send_movement(const String &opcode, const Vector3 &position, double orientation, int64_t flags, int64_t fall_time_msec = 0, const Vector3 &jump_velocity = Vector3(), double pitch = 0.0, int64_t ack_counter = -1, const PackedByteArray &ack_tail = PackedByteArray());
	void send_packet(const String &opcode, const PackedByteArray &payload);
	void send_chat(ChatType type, const String &message, const String &target = String());
	void cast_spell(int spell_id, int64_t target_guid = 0);
	void cancel_cast(int spell_id);
	void attack(int64_t target_guid);
	void stop_attack();
	void cancel_aura(int spell_id);
	PackedInt32Array get_known_spells() const { return known_spells; }
	PackedInt32Array get_action_buttons() const { return action_buttons; }
	PackedByteArray get_faction_flags() const { return faction_flags; }
	PackedInt32Array get_faction_standings() const { return faction_standings; }
	void set_action_button(int slot, int packed);
	void set_selection(int64_t guid);
	String get_object_name(int64_t guid);
	Dictionary get_item_info(int entry);
	Dictionary get_creature_info(int64_t guid);
	Dictionary get_creature_template(int entry);
	Dictionary get_game_object_info(int entry);
	Dictionary get_quest_info(int quest_id);
	Array get_npc_text(int text_id, int64_t guid);
	Dictionary get_player_path() const;
	void disconnect();
	void poll();

	State get_state() const { return state; }
	int64_t get_player_guid() const { return static_cast<int64_t>(player_guid); }
	PackedInt64Array get_object_guids() const;
	bool has_object(int64_t guid) const { return find(guid) != nullptr; }
	int get_object_type(int64_t guid) const;
	Vector3 get_object_position(int64_t guid) const;
	double get_object_orientation(int64_t guid) const;
	// Walk, run, run back, swim, swim back and turn rate.
	PackedFloat32Array get_object_speeds(int64_t guid) const;
	int64_t get_field(int64_t guid, const Variant &field) const;
	double get_field_float(int64_t guid, const Variant &field) const;
	int64_t get_field_guid(int64_t guid, const Variant &field) const;
	int field_index(const String &name) const;
};

} // namespace godot

VARIANT_ENUM_CAST(WowSession::State);
VARIANT_ENUM_CAST(WowSession::ChatType);
VARIANT_ENUM_CAST(WowSession::AttackError);
