#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <cstdint>
#include <memory>
#include <string>
#include <unordered_map>
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

private:
	struct WorldObject {
		uint8_t type_id = 0;
		std::unordered_map<uint16_t, uint32_t> fields;
		Vector3 position;
		float orientation = 0.0f;
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

	void set_state(State p_state, const String &p_message = String());
	void retire_sockets();
	void begin_auth();
	void handle_world_packet(wowee::network::Packet &packet);
	void handle_update(wowee::game::UpdateObjectData &data);
	void handle_movement_relay(wowee::network::Packet &packet);
	void handle_compressed_moves(wowee::network::Packet &packet);
	bool inflate(wowee::network::Packet &packet, std::vector<uint8_t> &r_data);
	const WorldObject *find(int64_t guid) const;

protected:
	static void _bind_methods();

public:
	WowSession();
	~WowSession() override;

	void login(const String &host, int port, const String &p_username, const String &p_password);
	void select_realm(int index);
	void request_characters();
	void create_character(const Dictionary &character);
	void enter_world(int64_t guid);
	void logout();
	void send_movement(const String &opcode, const Vector3 &position, double orientation, int64_t flags);
	void send_packet(const String &opcode, const PackedByteArray &payload);
	void disconnect();
	void poll();

	State get_state() const { return state; }
	int64_t get_player_guid() const { return int64_t(player_guid); }
	PackedInt64Array get_object_guids() const;
	bool has_object(int64_t guid) const { return find(guid) != nullptr; }
	int get_object_type(int64_t guid) const;
	Vector3 get_object_position(int64_t guid) const;
	double get_object_orientation(int64_t guid) const;
	int64_t get_field(int64_t guid, const Variant &field) const;
	double get_field_float(int64_t guid, const Variant &field) const;
	int field_index(const String &name) const;
};

} // namespace godot

VARIANT_ENUM_CAST(WowSession::State);
