#include "wow_session.h"

#include "auth/auth_handler.hpp"
#include "auth/auth_packets.hpp"
#include "game/character.hpp"
#include "game/entity.hpp"
#include "game/opcode_table.hpp"
#include "game/packet_parsers.hpp"
#include "game/update_field_table.hpp"
#include "game/world_packets.hpp"
#include "network/packet.hpp"
#include "network/world_socket.hpp"

#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>

#include <zlib.h>

#include <algorithm>
#include <cctype>
#include <cstring>
#include <random>

using namespace wowee;

namespace godot {

namespace {

constexpr uint16_t CLIENT_BUILD = 5875;
constexpr uint8_t AUTH_PROTOCOL = 8;
constexpr uint8_t AUTH_PROTOCOL_LEGACY = 3;
constexpr uint8_t CHAR_CREATE_SUCCESS = 46;
constexpr uint64_t PING_INTERVAL_MSEC = 30000;
constexpr uint32_t LANG_ORCISH = 1;
constexpr uint32_t LANG_COMMON = 7;
constexpr uint8_t TYPEID_UNIT = 3;
constexpr uint8_t TYPEID_PLAYER = 4;

bool is_player_guid(uint64_t guid) {
	return guid != 0 && (guid >> 48) == 0;
}

bool is_horde(uint8_t race) {
	return race == 2 || race == 5 || race == 6 || race == 8;
}

std::unordered_map<std::string, int> &field_indices() {
	static std::unordered_map<std::string, int> indices;
	return indices;
}

// The vendored parsers read the opcode and update field tables through process-wide pointers.
void load_protocol_tables() {
	static game::OpcodeTable opcodes;
	static game::UpdateFieldTable fields;
	static bool loaded = false;
	if (loaded) {
		return;
	}
	ProjectSettings *settings = ProjectSettings::get_singleton();
	opcodes.loadFromJson(settings->globalize_path("res://data/classic/opcodes.json").utf8().get_data());
	fields.loadFromJson(settings->globalize_path("res://data/classic/update_fields.json").utf8().get_data());
	game::setActiveOpcodeTable(&opcodes);
	game::setActiveUpdateFieldTable(&fields);
	const Dictionary names = JSON::parse_string(FileAccess::get_file_as_string("res://data/classic/update_fields.json"));
	const Array keys = names.keys();
	for (int i = 0; i < keys.size(); i++) {
		field_indices()[String(keys[i]).utf8().get_data()] = int(names[keys[i]]);
	}
	loaded = true;
}

std::optional<game::LogicalOpcode> logical(network::Packet &packet) {
	return game::getActiveOpcodeTable()->fromWire(packet.getOpcode());
}

Vector3 wow_vector(float x, float y, float z) {
	return Vector3(x, y, z);
}

} // namespace

WowSession::WowSession() {
	load_protocol_tables();
	// The classic login proof can carry a hash of the stock client's executables when they are around.
	OS *os = OS::get_singleton();
	const String data_dir = ProjectSettings::get_singleton()->get_setting("wowgd/client_data_dir", "");
	if (!os->has_environment("WOWEE_INTEGRITY_DIR") && !data_dir.is_empty()) {
		os->set_environment("WOWEE_INTEGRITY_DIR", data_dir.get_base_dir());
	}
	parsers = game::createPacketParsers("classic");
}

WowSession::~WowSession() {
	disconnect();
}

void WowSession::set_state(State p_state, const String &p_message) {
	state = p_state;
	emit_signal("state_changed", p_state, p_message);
}

void WowSession::login(const String &host, int port, const String &p_username, const String &p_password) {
	disconnect();
	username = p_username.to_upper().utf8().get_data();
	password = p_password.utf8().get_data();
	auth_host = host.utf8().get_data();
	auth_port = uint16_t(port);
	auth_attempt = 0;
	begin_auth();
}

void WowSession::begin_auth() {
	retire_sockets();
	auth = std::make_unique<auth::AuthHandler>();
	auth::ClientInfo info;
	info.majorVersion = 1;
	info.minorVersion = 12;
	info.patchVersion = 1;
	info.build = CLIENT_BUILD;
	// vMaNGOS answers protocol 8 while older MaNGOS cores only take 3, so a protocol failure retries once.
	info.protocolVersion = auth_attempt == 0 ? AUTH_PROTOCOL : AUTH_PROTOCOL_LEGACY;
	info.legacyVanillaRealmList = true;
	auth->setClientInfo(info);
	// Callbacks keep their own handler, since a handler replaced mid-callback may still report.
	auth::AuthHandler *handler = auth.get();
	auth->setOnSuccess([this, handler](const std::vector<uint8_t> &key) {
		if (handler != auth.get()) {
			return;
		}
		session_key = key;
		handler->requestRealmList();
	});
	auth->setOnRealmList([this, handler](const std::vector<auth::Realm> &list) {
		if (handler != auth.get()) {
			return;
		}
		realms = list;
		Array out;
		for (const auth::Realm &realm : realms) {
			Dictionary r;
			r["id"] = realm.id;
			r["name"] = String::utf8(realm.name.c_str());
			r["address"] = String(realm.address.c_str());
			r["characters"] = realm.characters;
			r["population"] = realm.population;
			r["flags"] = realm.flags;
			out.push_back(r);
		}
		set_state(STATE_REALM_LIST);
		emit_signal("realms_received", out);
	});
	auth->setOnFailure([this, handler](const std::string &reason) {
		if (handler != auth.get()) {
			return;
		}
		if (handler->lastFailureWasProtocol() && auth_attempt == 0) {
			retry_auth = true;
			return;
		}
		set_state(STATE_FAILED, String::utf8(reason.c_str()));
	});
	set_state(STATE_AUTHENTICATING);
	if (!auth->connect(auth_host, auth_port)) {
		set_state(STATE_FAILED, "Cannot reach the login server");
		return;
	}
	auth->authenticate(username, password);
}

void WowSession::select_realm(int index) {
	ERR_FAIL_INDEX(index, int(realms.size()));
	const std::string address = realms[index].address;
	const size_t colon = address.rfind(':');
	const std::string host = address.substr(0, colon);
	const uint16_t port = colon == std::string::npos ? 8085 : uint16_t(std::stoi(address.substr(colon + 1)));
	realm_id = realms[index].id;
	retire_sockets();
	world = std::make_unique<network::WorldSocket>();
	network::WorldSocket *socket = world.get();
	world->setPacketCallback([this, socket](const network::Packet &packet) {
		if (socket != world.get()) {
			return;
		}
		network::Packet copy = packet;
		handle_world_packet(copy);
	});
	set_state(STATE_CONNECTING_WORLD);
	if (!world->connect(host, port)) {
		set_state(STATE_FAILED, "Cannot reach the world server");
	}
}

void WowSession::request_characters() {
	ERR_FAIL_COND(!world);
	world->send(game::CharEnumPacket::build());
}

void WowSession::create_character(const Dictionary &character) {
	ERR_FAIL_COND(!world);
	game::CharCreateData data;
	data.name = String(character.get("name", "")).utf8().get_data();
	data.race = game::Race(int(character.get("race", 1)));
	data.characterClass = game::Class(int(character.get("class", 1)));
	data.gender = game::Gender(int(character.get("gender", 0)));
	data.skin = int(character.get("skin", 0));
	data.face = int(character.get("face", 0));
	data.hairStyle = int(character.get("hair_style", 0));
	data.hairColor = int(character.get("hair_color", 0));
	data.facialHair = int(character.get("facial_hair", 0));
	world->send(game::CharCreatePacket::build(data));
}

void WowSession::enter_world(int64_t guid) {
	ERR_FAIL_COND(!world);
	player_guid = uint64_t(guid);
	objects.clear();
	world->send(game::PlayerLoginPacket::build(player_guid));
	set_state(STATE_ENTERING_WORLD);
}

void WowSession::logout() {
	ERR_FAIL_COND(!world);
	world->send(network::Packet(game::wireOpcode(game::LogicalOpcode::CMSG_LOGOUT_REQUEST)));
}

void WowSession::send_movement(const String &opcode, const Vector3 &position, double orientation, int64_t flags) {
	ERR_FAIL_COND(!world || state != STATE_IN_WORLD);
	const auto op = game::OpcodeTable::nameToLogical(opcode.utf8().get_data());
	ERR_FAIL_COND_MSG(!op, "WowSession: unknown opcode " + opcode);
	game::MovementInfo info;
	info.flags = uint32_t(flags);
	info.time = uint32_t(Time::get_singleton()->get_ticks_msec());
	info.x = position.x;
	info.y = position.y;
	info.z = position.z;
	info.orientation = float(orientation);
	world->send(parsers->buildMovementPacket(*op, info, player_guid));
	auto it = objects.find(player_guid);
	if (it != objects.end()) {
		it->second.position = position;
		it->second.orientation = float(orientation);
	}
}

void WowSession::send_packet(const String &opcode, const PackedByteArray &payload) {
	ERR_FAIL_COND(!world);
	const auto op = game::OpcodeTable::nameToLogical(opcode.utf8().get_data());
	ERR_FAIL_COND_MSG(!op, "WowSession: unknown opcode " + opcode);
	std::vector<uint8_t> data(payload.ptr(), payload.ptr() + payload.size());
	world->send(network::Packet(game::wireOpcode(*op), std::move(data)));
}

void WowSession::send_chat(ChatType type, const String &message, const String &target) {
	ERR_FAIL_COND(!world || state != STATE_IN_WORLD);
	const uint8_t race = uint8_t(get_field(int64_t(player_guid), "UNIT_FIELD_BYTES_0") & 0xFF);
	network::Packet packet(game::wireOpcode(game::LogicalOpcode::CMSG_MESSAGECHAT));
	packet.writeUInt32(type);
	packet.writeUInt32(is_horde(race) ? LANG_ORCISH : LANG_COMMON);
	if (type == CHAT_WHISPER || type == CHAT_CHANNEL) {
		packet.writeString(target.utf8().get_data());
	}
	packet.writeString(message.utf8().get_data());
	world->send(packet);
}

void WowSession::set_selection(int64_t guid) {
	ERR_FAIL_COND(!world);
	world->send(game::SetSelectionPacket::build(uint64_t(guid)));
}

// Empty until the server answers the query this sends; name_received follows.
String WowSession::get_object_name(int64_t guid) {
	const WorldObject *object = find(guid);
	if (!object || !world) {
		return String();
	}
	if (object->type_id == TYPEID_PLAYER) {
		auto it = player_names.find(uint64_t(guid));
		if (it != player_names.end()) {
			return String::utf8(it->second.c_str());
		}
		query_player_name(uint64_t(guid));
	} else if (object->type_id == TYPEID_UNIT) {
		const uint32_t entry = uint32_t(get_field(guid, "OBJECT_FIELD_ENTRY"));
		auto it = creature_names.find(entry);
		if (it != creature_names.end()) {
			return String::utf8(it->second.c_str());
		}
		std::vector<uint64_t> &waiting = creature_queries[entry];
		if (waiting.empty()) {
			world->send(game::CreatureQueryPacket::build(entry, uint64_t(guid)));
		}
		if (std::find(waiting.begin(), waiting.end(), uint64_t(guid)) == waiting.end()) {
			waiting.push_back(uint64_t(guid));
		}
	}
	return String();
}

void WowSession::query_player_name(uint64_t guid) {
	if (world && player_queries.insert(guid).second) {
		world->send(game::NameQueryPacket::build(guid));
	}
}

void WowSession::handle_chat(network::Packet &packet) {
	const uint8_t type = packet.readUInt8();
	Dictionary line;
	line["type"] = type;
	line["language"] = packet.readUInt32();
	uint64_t sender = 0;
	std::string name;
	switch (type) {
		case CHAT_MONSTER_EMOTE:
		case CHAT_MONSTER_WHISPER:
		case CHAT_RAID_BOSS_WHISPER:
		case CHAT_RAID_BOSS_EMOTE:
			packet.readUInt32();
			name = packet.readString();
			packet.readUInt64();
			break;
		case CHAT_SAY:
		case CHAT_PARTY:
		case CHAT_YELL:
			sender = packet.readUInt64();
			packet.readUInt64();
			break;
		case CHAT_MONSTER_SAY:
		case CHAT_MONSTER_YELL:
			sender = packet.readUInt64();
			packet.readUInt32();
			name = packet.readString();
			packet.readUInt64();
			break;
		case CHAT_CHANNEL:
			line["channel"] = String::utf8(packet.readString().c_str());
			packet.readUInt32();
			sender = packet.readUInt64();
			break;
		default:
			sender = packet.readUInt64();
			break;
	}
	packet.readUInt32();
	line["text"] = String::utf8(packet.readString().c_str());
	line["sender_guid"] = int64_t(sender);
	if (name.empty() && is_player_guid(sender)) {
		auto it = player_names.find(sender);
		if (it == player_names.end()) {
			chat_waiting[sender].push_back(line);
			query_player_name(sender);
			return;
		}
		name = it->second;
	}
	line["sender_name"] = String::utf8(name.c_str());
	emit_signal("chat_received", line);
}

void WowSession::retire_sockets() {
	if (auth) {
		retired_auth = std::move(auth);
	}
	if (world) {
		retired_world = std::move(world);
	}
	if (!polling) {
		release_retired();
	}
}

void WowSession::release_retired() {
	if (retired_auth) {
		retired_auth->disconnect();
		retired_auth.reset();
	}
	if (retired_world) {
		retired_world->disconnect();
		retired_world.reset();
	}
}

void WowSession::disconnect() {
	retire_sockets();
	objects.clear();
	player_queries.clear();
	creature_queries.clear();
	chat_waiting.clear();
	player_guid = 0;
	state = STATE_DISCONNECTED;
}

void WowSession::poll() {
	polling = true;
	if (auth) {
		auth->update(0.0f);
		if (retry_auth) {
			retry_auth = false;
			auth_attempt++;
			begin_auth();
		}
	}
	if (world) {
		world->update();
	}
	if (world) {
		const uint64_t now = Time::get_singleton()->get_ticks_msec();
		if (state == STATE_IN_WORLD && now - last_ping_msec > PING_INTERVAL_MSEC) {
			last_ping_msec = now;
			world->send(game::PingPacket::build(++ping_sequence, 0));
		}
		if (world && state != STATE_FAILED && state != STATE_CONNECTING_WORLD && !world->isConnected()) {
			set_state(STATE_FAILED, "Disconnected from the world server");
		}
	}
	polling = false;
	release_retired();
}

void WowSession::handle_world_packet(network::Packet &packet) {
	using game::LogicalOpcode;
	const auto op = logical(packet);
	if (!op) {
		return;
	}
	switch (*op) {
		case LogicalOpcode::SMSG_AUTH_CHALLENGE: {
			game::AuthChallengeData challenge;
			if (!game::AuthChallengeParser::parse(packet, challenge)) {
				set_state(STATE_FAILED, "Bad SMSG_AUTH_CHALLENGE");
				return;
			}
			const uint32_t client_seed = std::random_device()();
			world->send(game::AuthSessionPacket::build(CLIENT_BUILD, username, client_seed, session_key, challenge.serverSeed, realm_id));
			// The server encrypts from its next packet on, so the cipher starts right after AUTH_SESSION.
			world->initEncryption(session_key, CLIENT_BUILD);
			return;
		}
		case LogicalOpcode::SMSG_AUTH_RESPONSE: {
			game::AuthResponseData response;
			if (!game::AuthResponseParser::parse(packet, response) || !response.isSuccess()) {
				set_state(STATE_FAILED, "World server refused the session");
				return;
			}
			set_state(STATE_CHARACTER_LIST);
			request_characters();
			return;
		}
		case LogicalOpcode::SMSG_CHAR_ENUM: {
			game::CharEnumResponse response;
			if (!parsers->parseCharEnum(packet, response)) {
				set_state(STATE_FAILED, "Bad SMSG_CHAR_ENUM");
				return;
			}
			Array out;
			for (const game::Character &c : response.characters) {
				Dictionary d;
				d["guid"] = int64_t(c.guid);
				d["name"] = String::utf8(c.name.c_str());
				d["race"] = int(c.race);
				d["class"] = int(c.characterClass);
				d["gender"] = int(c.gender);
				d["level"] = c.level;
				d["skin"] = c.appearanceBytes & 0xFF;
				d["face"] = (c.appearanceBytes >> 8) & 0xFF;
				d["hair_style"] = (c.appearanceBytes >> 16) & 0xFF;
				d["hair_color"] = (c.appearanceBytes >> 24) & 0xFF;
				d["facial_hair"] = c.facialFeatures;
				d["zone"] = c.zoneId;
				d["map"] = c.mapId;
				d["position"] = wow_vector(c.x, c.y, c.z);
				out.push_back(d);
			}
			emit_signal("characters_received", out);
			return;
		}
		case LogicalOpcode::SMSG_CHAR_CREATE: {
			const uint8_t code = packet.getSize() > 0 ? packet.readUInt8() : 0;
			emit_signal("character_created", code == CHAR_CREATE_SUCCESS, code);
			return;
		}
		case LogicalOpcode::SMSG_LOGIN_VERIFY_WORLD: {
			game::LoginVerifyWorldData data;
			if (!game::LoginVerifyWorldParser::parse(packet, data) || !data.isValid()) {
				set_state(STATE_FAILED, "Bad SMSG_LOGIN_VERIFY_WORLD");
				return;
			}
			last_ping_msec = Time::get_singleton()->get_ticks_msec();
			// vMaNGOS ignores movement until the client names the unit it controls, as the stock client does here.
			network::Packet mover(game::wireOpcode(LogicalOpcode::CMSG_SET_ACTIVE_MOVER));
			mover.writeUInt64(player_guid);
			world->send(mover);
			set_state(STATE_IN_WORLD);
			emit_signal("world_entered", data.mapId, wow_vector(data.x, data.y, data.z), data.orientation);
			return;
		}
		case LogicalOpcode::SMSG_UPDATE_OBJECT: {
			game::UpdateObjectData data;
			if (parsers->parseUpdateObject(packet, data)) {
				handle_update(data);
			}
			return;
		}
		case LogicalOpcode::SMSG_COMPRESSED_UPDATE_OBJECT: {
			std::vector<uint8_t> raw;
			if (!inflate(packet, raw)) {
				return;
			}
			network::Packet unpacked(game::wireOpcode(LogicalOpcode::SMSG_UPDATE_OBJECT), std::move(raw));
			game::UpdateObjectData data;
			if (parsers->parseUpdateObject(unpacked, data)) {
				handle_update(data);
			}
			return;
		}
		case LogicalOpcode::SMSG_DESTROY_OBJECT: {
			const uint64_t guid = packet.readUInt64();
			objects.erase(guid);
			PackedInt64Array guids;
			guids.push_back(int64_t(guid));
			emit_signal("objects_destroyed", guids);
			return;
		}
		case LogicalOpcode::SMSG_MONSTER_MOVE: {
			game::MonsterMoveData data;
			if (!parsers->parseMonsterMove(packet, data)) {
				return;
			}
			Dictionary move;
			move["position"] = wow_vector(data.x, data.y, data.z);
			if (data.hasDest) {
				move["destination"] = wow_vector(data.destX, data.destY, data.destZ);
				move["duration_msec"] = data.duration;
			}
			auto it = objects.find(data.guid);
			if (it != objects.end()) {
				it->second.position = data.hasDest ? wow_vector(data.destX, data.destY, data.destZ) : wow_vector(data.x, data.y, data.z);
			}
			emit_signal("object_moved", int64_t(data.guid), move);
			return;
		}
		case LogicalOpcode::SMSG_COMPRESSED_MOVES:
			handle_compressed_moves(packet);
			return;
		case LogicalOpcode::SMSG_PONG:
			return;
		case LogicalOpcode::SMSG_MESSAGECHAT:
			handle_chat(packet);
			return;
		case LogicalOpcode::SMSG_NAME_QUERY_RESPONSE: {
			game::NameQueryResponseData data;
			if (!parsers->parseNameQueryResponse(packet, data) || !data.isValid()) {
				return;
			}
			const String name = String::utf8(data.name.c_str());
			player_names[data.guid] = data.name;
			player_queries.erase(data.guid);
			emit_signal("name_received", int64_t(data.guid), name);
			auto waiting = chat_waiting.find(data.guid);
			if (waiting != chat_waiting.end()) {
				const Array lines = waiting->second;
				chat_waiting.erase(waiting);
				for (int i = 0; i < lines.size(); i++) {
					Dictionary line = lines[i];
					line["sender_name"] = name;
					emit_signal("chat_received", line);
				}
			}
			return;
		}
		case LogicalOpcode::SMSG_CREATURE_QUERY_RESPONSE: {
			game::CreatureQueryResponseData data;
			if (!parsers->parseCreatureQueryResponse(packet, data) || !data.isValid()) {
				return;
			}
			creature_names[data.entry] = data.name;
			auto waiting = creature_queries.find(data.entry);
			if (waiting != creature_queries.end()) {
				const std::vector<uint64_t> guids = std::move(waiting->second);
				creature_queries.erase(waiting);
				for (uint64_t guid : guids) {
					emit_signal("name_received", int64_t(guid), String::utf8(data.name.c_str()));
				}
			}
			return;
		}
		case LogicalOpcode::SMSG_LOGOUT_COMPLETE:
			objects.clear();
			player_guid = 0;
			set_state(STATE_CHARACTER_LIST);
			request_characters();
			return;
		default:
			break;
	}
	const char *name = game::OpcodeTable::logicalToName(*op);
	if (std::strncmp(name, "MSG_MOVE_", 9) == 0 && std::strstr(name, "TELEPORT") == nullptr && std::strstr(name, "WORLDPORT") == nullptr) {
		handle_movement_relay(packet);
		return;
	}
	PackedByteArray payload;
	payload.resize(packet.getSize());
	std::copy(packet.getData().begin(), packet.getData().end(), payload.ptrw());
	emit_signal("packet_received", String(name), payload);
}

void WowSession::handle_update(game::UpdateObjectData &data) {
	PackedInt64Array destroyed;
	for (uint64_t guid : data.outOfRangeGuids) {
		objects.erase(guid);
		destroyed.push_back(int64_t(guid));
	}
	for (game::UpdateBlock &block : data.blocks) {
		const bool created = block.updateType == game::UpdateType::CREATE_OBJECT || block.updateType == game::UpdateType::CREATE_OBJECT2;
		if (block.updateType == game::UpdateType::OUT_OF_RANGE_OBJECTS) {
			continue;
		}
		if (!created && objects.find(block.guid) == objects.end()) {
			continue;
		}
		WorldObject &object = objects[block.guid];
		if (created) {
			object.type_id = uint8_t(block.objectType);
		}
		for (const auto &[index, value] : block.fields) {
			object.fields[index] = value;
		}
		if (block.hasMovement) {
			object.position = wow_vector(block.x, block.y, block.z);
			object.orientation = block.orientation;
		}
		if (created) {
			emit_signal("object_created", int64_t(block.guid), object.type_id);
		} else if (block.updateType == game::UpdateType::MOVEMENT) {
			Dictionary move;
			move["position"] = object.position;
			move["orientation"] = object.orientation;
			emit_signal("object_moved", int64_t(block.guid), move);
		} else {
			emit_signal("object_updated", int64_t(block.guid));
		}
	}
	if (!destroyed.is_empty()) {
		emit_signal("objects_destroyed", destroyed);
	}
}

// Vanilla relays carry a packed GUID, then flags, time, position and facing with no second flags field.
void WowSession::handle_movement_relay(network::Packet &packet) {
	const uint64_t guid = packet.readPackedGuid();
	const uint32_t flags = packet.readUInt32();
	packet.readUInt32();
	const float x = packet.readFloat();
	const float y = packet.readFloat();
	const float z = packet.readFloat();
	const float orientation = packet.readFloat();
	auto it = objects.find(guid);
	if (it != objects.end()) {
		it->second.position = wow_vector(x, y, z);
		it->second.orientation = orientation;
	}
	Dictionary move;
	move["position"] = wow_vector(x, y, z);
	move["orientation"] = orientation;
	move["flags"] = flags;
	move["opcode"] = String(game::OpcodeTable::logicalToName(*logical(packet)));
	emit_signal("object_moved", int64_t(guid), move);
}

// SMSG_COMPRESSED_MOVES inflates to a run of [u8 size][u16 opcode][payload] monster move packets.
void WowSession::handle_compressed_moves(network::Packet &packet) {
	std::vector<uint8_t> raw;
	if (!inflate(packet, raw)) {
		return;
	}
	size_t offset = 0;
	while (offset + 3 <= raw.size()) {
		const uint8_t size = raw[offset];
		const uint16_t opcode = uint16_t(raw[offset + 1] | (raw[offset + 2] << 8));
		if (size < 2 || offset + 1 + size > raw.size()) {
			break;
		}
		network::Packet inner(opcode, std::vector<uint8_t>(raw.begin() + offset + 3, raw.begin() + offset + 1 + size));
		handle_world_packet(inner);
		offset += 1 + size;
	}
}

bool WowSession::inflate(network::Packet &packet, std::vector<uint8_t> &r_data) {
	if (packet.getSize() < 4) {
		return false;
	}
	uLongf size = packet.readUInt32();
	r_data.resize(size);
	const std::vector<uint8_t> &data = packet.getData();
	return uncompress(r_data.data(), &size, data.data() + 4, data.size() - 4) == Z_OK && size == r_data.size();
}

const WowSession::WorldObject *WowSession::find(int64_t guid) const {
	auto it = objects.find(uint64_t(guid));
	return it == objects.end() ? nullptr : &it->second;
}

PackedInt64Array WowSession::get_object_guids() const {
	PackedInt64Array guids;
	for (const auto &[guid, object] : objects) {
		guids.push_back(int64_t(guid));
	}
	return guids;
}

int WowSession::get_object_type(int64_t guid) const {
	const WorldObject *object = find(guid);
	return object ? object->type_id : -1;
}

Vector3 WowSession::get_object_position(int64_t guid) const {
	const WorldObject *object = find(guid);
	return object ? object->position : Vector3();
}

double WowSession::get_object_orientation(int64_t guid) const {
	const WorldObject *object = find(guid);
	return object ? object->orientation : 0.0;
}

int WowSession::field_index(const String &name) const {
	auto it = field_indices().find(name.utf8().get_data());
	return it == field_indices().end() ? -1 : it->second;
}

int64_t WowSession::get_field(int64_t guid, const Variant &field) const {
	const WorldObject *object = find(guid);
	const int index = field.get_type() == Variant::INT ? int(field) : field_index(field);
	if (!object || index < 0) {
		return 0;
	}
	auto it = object->fields.find(uint16_t(index));
	return it == object->fields.end() ? 0 : it->second;
}

double WowSession::get_field_float(int64_t guid, const Variant &field) const {
	const uint32_t bits = uint32_t(get_field(guid, field));
	float value = 0.0f;
	std::memcpy(&value, &bits, sizeof(value));
	return value;
}

void WowSession::_bind_methods() {
	ClassDB::bind_method(D_METHOD("login", "host", "port", "username", "password"), &WowSession::login);
	ClassDB::bind_method(D_METHOD("select_realm", "index"), &WowSession::select_realm);
	ClassDB::bind_method(D_METHOD("request_characters"), &WowSession::request_characters);
	ClassDB::bind_method(D_METHOD("create_character", "character"), &WowSession::create_character);
	ClassDB::bind_method(D_METHOD("enter_world", "guid"), &WowSession::enter_world);
	ClassDB::bind_method(D_METHOD("logout"), &WowSession::logout);
	ClassDB::bind_method(D_METHOD("send_movement", "opcode", "position", "orientation", "flags"), &WowSession::send_movement);
	ClassDB::bind_method(D_METHOD("send_packet", "opcode", "payload"), &WowSession::send_packet);
	ClassDB::bind_method(D_METHOD("send_chat", "type", "message", "target"), &WowSession::send_chat, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("set_selection", "guid"), &WowSession::set_selection);
	ClassDB::bind_method(D_METHOD("get_object_name", "guid"), &WowSession::get_object_name);
	ClassDB::bind_method(D_METHOD("disconnect"), &WowSession::disconnect);
	ClassDB::bind_method(D_METHOD("poll"), &WowSession::poll);
	ClassDB::bind_method(D_METHOD("get_state"), &WowSession::get_state);
	ClassDB::bind_method(D_METHOD("get_player_guid"), &WowSession::get_player_guid);
	ClassDB::bind_method(D_METHOD("get_object_guids"), &WowSession::get_object_guids);
	ClassDB::bind_method(D_METHOD("has_object", "guid"), &WowSession::has_object);
	ClassDB::bind_method(D_METHOD("get_object_type", "guid"), &WowSession::get_object_type);
	ClassDB::bind_method(D_METHOD("get_object_position", "guid"), &WowSession::get_object_position);
	ClassDB::bind_method(D_METHOD("get_object_orientation", "guid"), &WowSession::get_object_orientation);
	ClassDB::bind_method(D_METHOD("get_field", "guid", "field"), &WowSession::get_field);
	ClassDB::bind_method(D_METHOD("get_field_float", "guid", "field"), &WowSession::get_field_float);
	ClassDB::bind_method(D_METHOD("field_index", "name"), &WowSession::field_index);

	ADD_SIGNAL(MethodInfo("state_changed", PropertyInfo(Variant::INT, "state"), PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("realms_received", PropertyInfo(Variant::ARRAY, "realms")));
	ADD_SIGNAL(MethodInfo("characters_received", PropertyInfo(Variant::ARRAY, "characters")));
	ADD_SIGNAL(MethodInfo("character_created", PropertyInfo(Variant::BOOL, "success"), PropertyInfo(Variant::INT, "code")));
	ADD_SIGNAL(MethodInfo("world_entered", PropertyInfo(Variant::INT, "map_id"), PropertyInfo(Variant::VECTOR3, "position"), PropertyInfo(Variant::FLOAT, "orientation")));
	ADD_SIGNAL(MethodInfo("object_created", PropertyInfo(Variant::INT, "guid"), PropertyInfo(Variant::INT, "type_id")));
	ADD_SIGNAL(MethodInfo("object_updated", PropertyInfo(Variant::INT, "guid")));
	ADD_SIGNAL(MethodInfo("object_moved", PropertyInfo(Variant::INT, "guid"), PropertyInfo(Variant::DICTIONARY, "movement")));
	ADD_SIGNAL(MethodInfo("objects_destroyed", PropertyInfo(Variant::PACKED_INT64_ARRAY, "guids")));
	ADD_SIGNAL(MethodInfo("chat_received", PropertyInfo(Variant::DICTIONARY, "line")));
	ADD_SIGNAL(MethodInfo("name_received", PropertyInfo(Variant::INT, "guid"), PropertyInfo(Variant::STRING, "name")));
	ADD_SIGNAL(MethodInfo("packet_received", PropertyInfo(Variant::STRING, "opcode"), PropertyInfo(Variant::PACKED_BYTE_ARRAY, "payload")));

	BIND_ENUM_CONSTANT(STATE_DISCONNECTED);
	BIND_ENUM_CONSTANT(STATE_AUTHENTICATING);
	BIND_ENUM_CONSTANT(STATE_REALM_LIST);
	BIND_ENUM_CONSTANT(STATE_CONNECTING_WORLD);
	BIND_ENUM_CONSTANT(STATE_CHARACTER_LIST);
	BIND_ENUM_CONSTANT(STATE_ENTERING_WORLD);
	BIND_ENUM_CONSTANT(STATE_IN_WORLD);
	BIND_ENUM_CONSTANT(STATE_FAILED);

	BIND_ENUM_CONSTANT(CHAT_SAY);
	BIND_ENUM_CONSTANT(CHAT_PARTY);
	BIND_ENUM_CONSTANT(CHAT_RAID);
	BIND_ENUM_CONSTANT(CHAT_GUILD);
	BIND_ENUM_CONSTANT(CHAT_OFFICER);
	BIND_ENUM_CONSTANT(CHAT_YELL);
	BIND_ENUM_CONSTANT(CHAT_WHISPER);
	BIND_ENUM_CONSTANT(CHAT_WHISPER_INFORM);
	BIND_ENUM_CONSTANT(CHAT_EMOTE);
	BIND_ENUM_CONSTANT(CHAT_TEXT_EMOTE);
	BIND_ENUM_CONSTANT(CHAT_SYSTEM);
	BIND_ENUM_CONSTANT(CHAT_MONSTER_SAY);
	BIND_ENUM_CONSTANT(CHAT_MONSTER_YELL);
	BIND_ENUM_CONSTANT(CHAT_MONSTER_EMOTE);
	BIND_ENUM_CONSTANT(CHAT_CHANNEL);
	BIND_ENUM_CONSTANT(CHAT_MONSTER_WHISPER);
	BIND_ENUM_CONSTANT(CHAT_RAID_BOSS_WHISPER);
	BIND_ENUM_CONSTANT(CHAT_RAID_BOSS_EMOTE);
}

} // namespace godot
