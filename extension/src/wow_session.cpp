#include "wow_session.h"
#include "wow_loader.h"

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
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

#include <zlib.h>

#include <algorithm>
#include <cmath>
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
constexpr uint8_t CHAR_DELETE_SUCCESS = 57;
constexpr uint64_t PING_INTERVAL_MSEC = 30000;
constexpr uint32_t LANG_ORCISH = 1;
constexpr uint32_t LANG_COMMON = 7;
constexpr uint8_t TYPEID_UNIT = 3;
constexpr uint8_t TYPEID_PLAYER = 4;
constexpr uint8_t MONSTER_MOVE_FACING_ANGLE = 4;
constexpr uint32_t MOVEFLAG_JUMPING = 0x2000;
constexpr uint32_t MOVEFLAG_SWIMMING = 0x200000;
constexpr uint32_t MOVEFLAG_ONTRANSPORT = 0x2000000;
constexpr uint32_t MOVEFLAG_SPLINE_ELEVATION = 0x4000000;

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

// The vendored loaders read from disk, and an exported build keeps res:// inside the PCK.
static std::string table_path(const String &name) {
	const String packed = "res://data/classic/" + name;
	ProjectSettings *settings = ProjectSettings::get_singleton();
	if (!OS::get_singleton()->has_feature("template")) {
		return settings->globalize_path(packed).utf8().get_data();
	}
	const String copy = "user://" + name;
	const Ref<FileAccess> out = FileAccess::open(copy, FileAccess::WRITE);
	if (out.is_valid()) {
		out->store_string(FileAccess::get_file_as_string(packed));
	}
	return settings->globalize_path(copy).utf8().get_data();
}

// The vendored parsers read the opcode and update field tables through process-wide pointers.
void load_protocol_tables() {
	static game::OpcodeTable opcodes;
	static game::UpdateFieldTable fields;
	static bool loaded = false;
	if (loaded) {
		return;
	}
	opcodes.loadFromJson(table_path("opcodes.json"));
	fields.loadFromJson(table_path("update_fields.json"));
	game::setActiveOpcodeTable(&opcodes);
	game::setActiveUpdateFieldTable(&fields);
	const Dictionary names = JSON::parse_string(FileAccess::get_file_as_string("res://data/classic/update_fields.json"));
	const Array keys = names.keys();
	for (int i = 0; i < keys.size(); i++) {
		field_indices()[String(keys[i]).utf8().get_data()] = static_cast<int>(names[keys[i]]);
	}
	loaded = true;
}

std::optional<game::LogicalOpcode> logical(network::Packet &packet) {
	return game::getActiveOpcodeTable()->fromWire(packet.getOpcode());
}

Vector3 wow_vector(float x, float y, float z) {
	return Vector3(x, y, z);
}

// Vanilla MovementInfo; the game code already uses vanilla flag bits, which the vendored writer would remap.
void write_movement_info(network::Packet &packet, uint32_t flags, const Vector3 &position, float orientation, float pitch, uint32_t fall_time, const Vector3 &jump_velocity) {
	packet.writeUInt32(flags);
	packet.writeUInt32(static_cast<uint32_t>(Time::get_singleton()->get_ticks_msec()));
	packet.writeFloat(position.x);
	packet.writeFloat(position.y);
	packet.writeFloat(position.z);
	packet.writeFloat(orientation);
	if (flags & MOVEFLAG_SWIMMING) {
		packet.writeFloat(pitch);
	}
	packet.writeUInt32(fall_time);
	if (flags & MOVEFLAG_JUMPING) {
		const float xy_speed = Vector2(jump_velocity.x, jump_velocity.y).length();
		// The stock client sends upward speed negated, which vMaNGOS's knockback check also expects.
		packet.writeFloat(-jump_velocity.z);
		packet.writeFloat(xy_speed > 0.0f ? jump_velocity.x / xy_speed : std::cos(orientation));
		packet.writeFloat(xy_speed > 0.0f ? jump_velocity.y / xy_speed : std::sin(orientation));
		packet.writeFloat(xy_speed);
	}
}

} // namespace

WowSession::WowSession() {
	load_protocol_tables();
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
	auth_port = static_cast<uint16_t>(port);
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
	// realmd's StrictVersionCheck wants a hash of WoW.exe and its DLLs, which sit beside Data.
	auth->setIntegrityDir(WowLoader::client_data_dir().get_base_dir().utf8().get_data());
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
			r["icon"] = realm.icon;
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

// The logon server drops the connection after the realm list, so a fresh list needs a new login.
void WowSession::request_realms() {
	ERR_FAIL_COND(username.empty());
	auth_attempt = 0;
	begin_auth();
}

void WowSession::select_realm(int index) {
	ERR_FAIL_INDEX(index, static_cast<int>(realms.size()));
	const std::string address = realms[index].address;
	const size_t colon = address.rfind(':');
	const std::string host = address.substr(0, colon);
	const uint16_t port = colon == std::string::npos ? 8085 : static_cast<uint16_t>(std::stoi(address.substr(colon + 1)));
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
	data.race = static_cast<game::Race>(static_cast<int>(character.get("race", 1)));
	data.characterClass = static_cast<game::Class>(static_cast<int>(character.get("class", 1)));
	data.gender = static_cast<game::Gender>(static_cast<int>(character.get("gender", 0)));
	data.skin = static_cast<int>(character.get("skin", 0));
	data.face = static_cast<int>(character.get("face", 0));
	data.hairStyle = static_cast<int>(character.get("hair_style", 0));
	data.hairColor = static_cast<int>(character.get("hair_color", 0));
	data.facialHair = static_cast<int>(character.get("facial_hair", 0));
	world->send(game::CharCreatePacket::build(data));
}

void WowSession::delete_character(int64_t guid) {
	ERR_FAIL_COND(!world);
	network::Packet packet(game::wireOpcode(game::LogicalOpcode::CMSG_CHAR_DELETE));
	packet.writeUInt64(static_cast<uint64_t>(guid));
	world->send(packet);
}

void WowSession::enter_world(int64_t guid) {
	ERR_FAIL_COND(!world);
	player_guid = static_cast<uint64_t>(guid);
	objects.clear();
	world->send(game::PlayerLoginPacket::build(player_guid));
	set_state(STATE_ENTERING_WORLD);
}

void WowSession::logout() {
	ERR_FAIL_COND(!world);
	world->send(network::Packet(game::wireOpcode(game::LogicalOpcode::CMSG_LOGOUT_REQUEST)));
}

// jump_velocity is in WoW space; its horizontal part gives the jump direction and speed.
// An ack_counter of 0 or more answers a server movement change: guid and counter first, ack_tail last.
void WowSession::send_movement(const String &opcode, const Vector3 &position, double orientation, int64_t flags, int64_t fall_time_msec, const Vector3 &jump_velocity, double pitch, int64_t ack_counter, const PackedByteArray &ack_tail) {
	ERR_FAIL_COND(!world || state != STATE_IN_WORLD);
	const auto op = game::OpcodeTable::nameToLogical(opcode.utf8().get_data());
	ERR_FAIL_COND_MSG(!op, "WowSession: unknown opcode " + opcode);
	network::Packet packet(game::wireOpcode(*op));
	if (ack_counter >= 0) {
		packet.writeUInt64(player_guid);
		packet.writeUInt32(static_cast<uint32_t>(ack_counter));
	}
	write_movement_info(packet, static_cast<uint32_t>(flags), position, static_cast<float>(orientation), static_cast<float>(pitch), static_cast<uint32_t>(fall_time_msec), jump_velocity);
	packet.writeBytes(ack_tail.ptr(), static_cast<size_t>(ack_tail.size()));
	world->send(packet);
	if (auto it = objects.find(player_guid); it != objects.end()) {
		it->second.position = position;
		it->second.orientation = static_cast<float>(orientation);
	}
}

void WowSession::send_packet(const String &opcode, const PackedByteArray &payload) {
	ERR_FAIL_COND(!world);
	const auto op = game::OpcodeTable::nameToLogical(opcode.utf8().get_data());
	ERR_FAIL_COND_MSG(!op, "WowSession: unknown opcode " + opcode);
	std::vector<uint8_t> data(payload.ptr(), payload.ptr() + payload.size());
	world->send(network::Packet(game::wireOpcode(*op), std::move(data)));
}

void WowSession::cast_spell(int spell_id, int64_t target_guid) {
	ERR_FAIL_COND(!world || state != STATE_IN_WORLD);
	world->send(parsers->buildCastSpell(static_cast<uint32_t>(spell_id), static_cast<uint64_t>(target_guid), 0));
}

void WowSession::cancel_cast(int spell_id) {
	ERR_FAIL_COND(!world);
	network::Packet packet(game::wireOpcode(game::LogicalOpcode::CMSG_CANCEL_CAST));
	packet.writeUInt32(static_cast<uint32_t>(spell_id));
	world->send(packet);
}

void WowSession::attack(int64_t target_guid) {
	ERR_FAIL_COND(!world || state != STATE_IN_WORLD);
	network::Packet packet(game::wireOpcode(game::LogicalOpcode::CMSG_ATTACKSWING));
	packet.writeUInt64(static_cast<uint64_t>(target_guid));
	world->send(packet);
}

void WowSession::stop_attack() {
	ERR_FAIL_COND(!world);
	world->send(network::Packet(game::wireOpcode(game::LogicalOpcode::CMSG_ATTACKSTOP)));
}

void WowSession::cancel_aura(int spell_id) {
	ERR_FAIL_COND(!world || state != STATE_IN_WORLD);
	network::Packet packet(game::wireOpcode(game::LogicalOpcode::CMSG_CANCEL_AURA));
	packet.writeUInt32(static_cast<uint32_t>(spell_id));
	world->send(packet);
}

void WowSession::set_action_button(int slot, int packed) {
	ERR_FAIL_COND(!world || slot < 0 || slot >= action_buttons.size());
	action_buttons.set(slot, packed);
	network::Packet packet(game::wireOpcode(game::LogicalOpcode::CMSG_SET_ACTION_BUTTON));
	packet.writeUInt8(static_cast<uint8_t>(slot));
	packet.writeUInt32(static_cast<uint32_t>(packed));
	world->send(packet);
	emit_signal("action_buttons_changed");
}

// Spell, cooldown and melee packets in their vanilla layouts; true when the opcode was one of them.
bool WowSession::handle_combat_packet(uint16_t op, network::Packet &packet) {
	using game::LogicalOpcode;
	switch (static_cast<LogicalOpcode>(op)) {
		case LogicalOpcode::SMSG_INITIAL_SPELLS: {
			game::InitialSpellsData data;
			if (parsers->parseInitialSpells(packet, data)) {
				known_spells.clear();
				for (uint32_t spell : data.spellIds) {
					known_spells.push_back(static_cast<int32_t>(spell));
				}
				emit_signal("spells_changed");
			}
			return true;
		}
		case LogicalOpcode::SMSG_LEARNED_SPELL: {
			known_spells.push_back(packet.readUInt16());
			emit_signal("spells_changed");
			return true;
		}
		case LogicalOpcode::SMSG_REMOVED_SPELL: {
			if (const int64_t at = known_spells.find(packet.readUInt16()); at >= 0) {
				known_spells.remove_at(at);
			}
			emit_signal("spells_changed");
			return true;
		}
		case LogicalOpcode::SMSG_SUPERCEDED_SPELL: {
			const int32_t old_spell = packet.readUInt16();
			const int32_t new_spell = packet.readUInt16();
			if (const int64_t at = known_spells.find(old_spell); at >= 0) {
				known_spells.set(at, new_spell);
			} else {
				known_spells.push_back(new_spell);
			}
			for (int64_t i = 0; i < action_buttons.size(); i++) {
				if (action_buttons[i] == old_spell) {
					action_buttons.set(i, new_spell);
				}
			}
			emit_signal("spells_changed");
			emit_signal("action_buttons_changed");
			return true;
		}
		case LogicalOpcode::SMSG_ACTION_BUTTONS: {
			action_buttons.resize(0);
			while (packet.hasRemaining(4)) {
				action_buttons.push_back(static_cast<int32_t>(packet.readUInt32()));
			}
			emit_signal("action_buttons_changed");
			return true;
		}
		case LogicalOpcode::SMSG_SPELL_START: {
			game::SpellStartData data;
			if (parsers->parseSpellStart(packet, data)) {
				emit_signal("spell_cast_started", static_cast<int64_t>(data.casterUnit ? data.casterUnit : data.casterGuid), static_cast<int>(data.spellId), static_cast<int>(data.castTime));
			}
			return true;
		}
		case LogicalOpcode::SMSG_SPELL_GO: {
			game::SpellGoData data;
			if (parsers->parseSpellGo(packet, data)) {
				emit_signal("spell_cast_finished", static_cast<int64_t>(data.casterUnit ? data.casterUnit : data.casterGuid), static_cast<int>(data.spellId));
			}
			return true;
		}
		case LogicalOpcode::SMSG_CAST_FAILED: {
			const int spell = static_cast<int>(packet.readUInt32());
			const uint8_t status = packet.readUInt8();
			if (status != 0) {
				emit_signal("spell_cast_failed", static_cast<int64_t>(player_guid), spell, packet.hasRemaining(1) ? static_cast<int>(packet.readUInt8()) : 0);
			}
			return true;
		}
		case LogicalOpcode::SMSG_SPELL_FAILED_OTHER: {
			// Reason -1 marks an interrupt; 0 is a real SpellCastResult (SPELL_FAILED_AFFECTING_COMBAT).
			const int64_t caster = static_cast<int64_t>(packet.readUInt64());
			emit_signal("spell_cast_failed", caster, static_cast<int>(packet.readUInt32()), -1);
			return true;
		}
		case LogicalOpcode::SMSG_ATTACKSWING_NOTINRANGE:
			emit_signal("attack_swing_error", ATTACK_ERROR_NOT_IN_RANGE);
			return true;
		case LogicalOpcode::SMSG_ATTACKSWING_BADFACING:
			emit_signal("attack_swing_error", ATTACK_ERROR_BAD_FACING);
			return true;
		case LogicalOpcode::SMSG_ATTACKSWING_NOTSTANDING:
			emit_signal("attack_swing_error", ATTACK_ERROR_NOT_STANDING);
			return true;
		case LogicalOpcode::SMSG_ATTACKSWING_DEADTARGET:
			emit_signal("attack_swing_error", ATTACK_ERROR_DEAD_TARGET);
			return true;
		case LogicalOpcode::SMSG_ATTACKSWING_CANT_ATTACK:
			emit_signal("attack_swing_error", ATTACK_ERROR_CANT_ATTACK);
			return true;
		case LogicalOpcode::SMSG_SPELL_DELAYED: {
			const int64_t caster = static_cast<int64_t>(packet.readUInt64());
			emit_signal("spell_cast_delayed", caster, static_cast<int>(packet.readUInt32()));
			return true;
		}
		case LogicalOpcode::MSG_CHANNEL_START: {
			const int spell = static_cast<int>(packet.readUInt32());
			emit_signal("spell_channel_started", spell, static_cast<int>(packet.readUInt32()));
			return true;
		}
		case LogicalOpcode::MSG_CHANNEL_UPDATE: {
			emit_signal("spell_channel_updated", static_cast<int>(packet.readUInt32()));
			return true;
		}
		case LogicalOpcode::SMSG_SPELL_COOLDOWN: {
			packet.readUInt64();
			while (packet.hasRemaining(8)) {
				const int spell = static_cast<int>(packet.readUInt32());
				emit_signal("spell_cooldown", spell, static_cast<int>(packet.readUInt32()));
			}
			return true;
		}
		case LogicalOpcode::SMSG_COOLDOWN_EVENT:
		case LogicalOpcode::SMSG_CLEAR_COOLDOWN: {
			emit_signal("spell_cooldown", static_cast<int>(packet.readUInt32()), 0);
			return true;
		}
		case LogicalOpcode::SMSG_UPDATE_AURA_DURATION: {
			const int slot = packet.readUInt8();
			emit_signal("aura_duration", slot, static_cast<int64_t>(packet.readUInt32()));
			return true;
		}
		case LogicalOpcode::SMSG_ATTACKERSTATEUPDATE: {
			game::AttackerStateUpdateData data;
			if (parsers->parseAttackerStateUpdate(packet, data)) {
				emit_signal("melee_swing", static_cast<int64_t>(data.attackerGuid), static_cast<int64_t>(data.targetGuid),
						data.totalDamage, static_cast<int64_t>(data.hitInfo), static_cast<int64_t>(data.victimState));
			}
			// Falls through to packet_received too, where CombatEvents reads the absorbs, resists and blocks.
			return false;
		}
		case LogicalOpcode::SMSG_ATTACKSTART: {
			const int64_t attacker = static_cast<int64_t>(packet.readUInt64());
			emit_signal("attack_started", attacker, static_cast<int64_t>(packet.readUInt64()));
			return true;
		}
		case LogicalOpcode::SMSG_ATTACKSTOP: {
			const int64_t attacker = static_cast<int64_t>(packet.readPackedGuid());
			emit_signal("attack_stopped", attacker, static_cast<int64_t>(packet.readPackedGuid()));
			return true;
		}
		default:
			return false;
	}
}

void WowSession::send_chat(ChatType type, const String &message, const String &target) {
	ERR_FAIL_COND(!world || state != STATE_IN_WORLD);
	const uint8_t race = static_cast<uint8_t>(get_field(int64_t(player_guid), "UNIT_FIELD_BYTES_0") & 0xFF);
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
	world->send(game::SetSelectionPacket::build(static_cast<uint64_t>(guid)));
}

// Empty until the server answers the query this sends; name_received follows.
String WowSession::get_object_name(int64_t guid) {
	const WorldObject *object = find(guid);
	if (!object || !world) {
		return String();
	}
	if (object->type_id == TYPEID_PLAYER) {
		if (const auto it = player_names.find(static_cast<uint64_t>(guid)); it != player_names.end()) {
			return String::utf8(it->second.c_str());
		}
		query_player_name(static_cast<uint64_t>(guid));
	} else if (object->type_id == TYPEID_UNIT) {
		const uint32_t entry = static_cast<uint32_t>(get_field(guid, "OBJECT_FIELD_ENTRY"));
		if (const auto it = creature_info.find(entry); it != creature_info.end()) {
			return it->second["name"];
		}
		std::vector<uint64_t> &waiting = creature_queries[entry];
		if (waiting.empty()) {
			world->send(game::CreatureQueryPacket::build(entry, static_cast<uint64_t>(guid)));
		}
		if (std::find(waiting.begin(), waiting.end(), static_cast<uint64_t>(guid)) == waiting.end()) {
			waiting.push_back(static_cast<uint64_t>(guid));
		}
	}
	return String();
}

// The creature query answer for a unit (name, subname, rank, type, family), or empty until it arrives.
Dictionary WowSession::get_creature_info(int64_t guid) {
	const WorldObject *object = find(guid);
	if (!object || object->type_id != TYPEID_UNIT) {
		return Dictionary();
	}
	const uint32_t entry = static_cast<uint32_t>(get_field(guid, "OBJECT_FIELD_ENTRY"));
	if (const auto it = creature_info.find(entry); it != creature_info.end()) {
		return it->second;
	}
	get_object_name(guid);
	return Dictionary();
}

// Empty until the server answers the query this sends; item_info_received follows.
Dictionary WowSession::get_item_info(int entry) {
	const uint32_t key = static_cast<uint32_t>(entry);
	if (const auto it = item_info.find(key); it != item_info.end()) {
		return it->second;
	}
	if (world && entry > 0 && item_queries.insert(key).second) {
		world->send(parsers->buildItemQuery(key, 0));
	}
	return Dictionary();
}

// By entry rather than by unit, for names a unit is not around to ask about; creature_info_received follows.
Dictionary WowSession::get_creature_template(int entry) {
	const uint32_t key = static_cast<uint32_t>(entry);
	if (const auto it = creature_info.find(key); it != creature_info.end()) {
		return it->second;
	}
	if (world && entry > 0 && creature_entry_queries.insert(key).second) {
		world->send(game::CreatureQueryPacket::build(key, 0));
	}
	return Dictionary();
}

// Empty until the server answers the query this sends; game_object_info_received follows.
Dictionary WowSession::get_game_object_info(int entry) {
	const uint32_t key = static_cast<uint32_t>(entry);
	if (const auto it = game_object_info.find(key); it != game_object_info.end()) {
		return it->second;
	}
	if (world && entry > 0 && game_object_queries.insert(key).second) {
		world->send(game::GameObjectQueryPacket::build(key, 0));
	}
	return Dictionary();
}

// Empty until the server answers the query this sends; quest_info_received follows.
Dictionary WowSession::get_quest_info(int quest_id) {
	const uint32_t key = static_cast<uint32_t>(quest_id);
	if (const auto it = quest_info.find(key); it != quest_info.end()) {
		return it->second;
	}
	if (world && quest_id > 0 && quest_queries.insert(key).second) {
		network::Packet packet(game::wireOpcode(game::LogicalOpcode::CMSG_QUEST_QUERY));
		packet.writeUInt32(key);
		world->send(packet);
	}
	return Dictionary();
}

// The 1.12 SMSG_QUEST_QUERY_RESPONSE: fixed fields, reward pairs, the four texts, then the objectives.
void WowSession::handle_quest_query(network::Packet &packet) {
	constexpr int REWARD_ITEMS = 4;
	constexpr int REWARD_CHOICES = 6;
	constexpr int OBJECTIVES = 4;
	const uint32_t id = packet.readUInt32();
	Dictionary quest;
	quest["id"] = static_cast<int64_t>(id);
	quest["method"] = static_cast<int64_t>(packet.readUInt32());
	quest["level"] = static_cast<int64_t>(packet.readUInt32());
	quest["zone_or_sort"] = static_cast<int64_t>(static_cast<int32_t>(packet.readUInt32()));
	quest["type"] = static_cast<int64_t>(packet.readUInt32());
	for (int i = 0; i < 4; ++i) {
		packet.readUInt32(); // Reputation objective and opposite faction requirements.
	}
	quest["next_quest"] = static_cast<int64_t>(packet.readUInt32());
	quest["money"] = static_cast<int64_t>(static_cast<int32_t>(packet.readUInt32()));
	quest["max_level_money"] = static_cast<int64_t>(packet.readUInt32());
	quest["reward_spell"] = static_cast<int64_t>(packet.readUInt32());
	quest["source_item"] = static_cast<int64_t>(packet.readUInt32());
	quest["flags"] = static_cast<int64_t>(packet.readUInt32());
	const auto read_pairs = [&packet](int count) {
		Array pairs;
		for (int i = 0; i < count; ++i) {
			const int64_t item = packet.readUInt32();
			const int64_t amount = packet.readUInt32();
			if (item != 0) {
				pairs.push_back(Vector2i(static_cast<int32_t>(item), static_cast<int32_t>(amount)));
			}
		}
		return pairs;
	};
	quest["rewards"] = read_pairs(REWARD_ITEMS);
	quest["choices"] = read_pairs(REWARD_CHOICES);
	quest["point_map"] = static_cast<int64_t>(packet.readUInt32());
	const float point_x = packet.readFloat();
	const float point_y = packet.readFloat();
	quest["point"] = Vector2(point_x, point_y);
	packet.readUInt32(); // Point option.
	quest["title"] = String::utf8(packet.readString().c_str());
	quest["objectives"] = String::utf8(packet.readString().c_str());
	quest["details"] = String::utf8(packet.readString().c_str());
	quest["end_text"] = String::utf8(packet.readString().c_str());
	Array objectives;
	for (int i = 0; i < OBJECTIVES; ++i) {
		Dictionary objective;
		// Game objects come as their entry with the sign bit set.
		objective["target"] = static_cast<int64_t>(static_cast<int32_t>(packet.readUInt32()));
		objective["target_count"] = static_cast<int64_t>(packet.readUInt32());
		objective["item"] = static_cast<int64_t>(packet.readUInt32());
		objective["item_count"] = static_cast<int64_t>(packet.readUInt32());
		objectives.push_back(objective);
	}
	for (int i = 0; i < OBJECTIVES; ++i) {
		Dictionary objective = objectives[i];
		objective["text"] = String::utf8(packet.readString().c_str());
	}
	quest["objective_list"] = objectives;
	quest_info[id] = quest;
	quest_queries.erase(id);
	emit_signal("quest_info_received", static_cast<int64_t>(id));
}

// The path the server is flying the player along, with its elapsed time brought up to now, or empty.
Dictionary WowSession::get_player_path() const {
	if (player_path.is_empty()) {
		return Dictionary();
	}
	Dictionary path = player_path.duplicate();
	const int64_t elapsed = static_cast<int64_t>(player_path["elapsed_msec"])
		+ static_cast<int64_t>(Time::get_singleton()->get_ticks_msec() - player_path_msec);
	if (elapsed >= static_cast<int64_t>(player_path["duration_msec"])) {
		return Dictionary();
	}
	path["elapsed_msec"] = elapsed;
	return path;
}

// NPC text options as [probability, male text, female text]; empty until the server answers.
Array WowSession::get_npc_text(int text_id, int64_t guid) {
	const uint32_t key = static_cast<uint32_t>(text_id);
	if (const auto it = npc_texts.find(key); it != npc_texts.end()) {
		return it->second;
	}
	if (world && npc_text_queries.insert(key).second) {
		network::Packet packet(game::wireOpcode(game::LogicalOpcode::CMSG_NPC_TEXT_QUERY));
		packet.writeUInt32(key);
		packet.writeUInt64(static_cast<uint64_t>(guid));
		world->send(packet);
	}
	return Array();
}

namespace {

// Quest dialog item lists: a count, then item, count and display id for each.
Array read_quest_items(network::Packet &packet) {
	Array items;
	const uint32_t count = packet.readUInt32();
	for (uint32_t i = 0; i < count && packet.hasRemaining(12); ++i) {
		const int32_t item = static_cast<int32_t>(packet.readUInt32());
		const int32_t amount = static_cast<int32_t>(packet.readUInt32());
		packet.readUInt32();
		items.push_back(Vector2i(item, amount));
	}
	return items;
}

String read_string(network::Packet &packet) {
	return String::utf8(packet.readString().c_str());
}

} // namespace

// Gossip, NPC text and the quest giver dialogs, each passed on as a Dictionary.
bool WowSession::handle_npc_packet(uint16_t op, network::Packet &packet) {
	using game::LogicalOpcode;
	switch (static_cast<LogicalOpcode>(op)) {
		case LogicalOpcode::SMSG_QUESTGIVER_STATUS: {
			const int64_t guid = static_cast<int64_t>(packet.readUInt64());
			emit_signal("quest_giver_status_received", guid, static_cast<int64_t>(packet.readUInt32()));
			return true;
		}
		case LogicalOpcode::SMSG_GOSSIP_MESSAGE: {
			Dictionary gossip;
			gossip["guid"] = static_cast<int64_t>(packet.readUInt64());
			gossip["text_id"] = static_cast<int64_t>(packet.readUInt32());
			Array options;
			const uint32_t option_count = packet.readUInt32();
			for (uint32_t i = 0; i < option_count && packet.hasRemaining(6); ++i) {
				Dictionary option;
				option["index"] = static_cast<int64_t>(packet.readUInt32());
				option["icon"] = static_cast<int64_t>(packet.readUInt8());
				option["coded"] = packet.readUInt8() != 0;
				option["text"] = read_string(packet);
				options.push_back(option);
			}
			gossip["options"] = options;
			Array quests;
			const uint32_t quest_count = packet.readUInt32();
			for (uint32_t i = 0; i < quest_count && packet.hasRemaining(12); ++i) {
				Dictionary quest;
				quest["id"] = static_cast<int64_t>(packet.readUInt32());
				quest["icon"] = static_cast<int64_t>(packet.readUInt32());
				quest["level"] = static_cast<int64_t>(packet.readUInt32());
				quest["title"] = read_string(packet);
				quests.push_back(quest);
			}
			gossip["quests"] = quests;
			emit_signal("gossip_received", gossip);
			return true;
		}
		case LogicalOpcode::SMSG_GOSSIP_COMPLETE:
			emit_signal("gossip_closed");
			return true;
		case LogicalOpcode::SMSG_NPC_TEXT_UPDATE: {
			constexpr int OPTIONS = 8;
			constexpr int EMOTES = 3;
			const uint32_t text_id = packet.readUInt32();
			Array options;
			for (int i = 0; i < OPTIONS && packet.hasRemaining(4); ++i) {
				const float probability = packet.readFloat();
				const String male = read_string(packet);
				const String female = read_string(packet);
				packet.readUInt32(); // Language.
				for (int e = 0; e < EMOTES * 2; ++e) {
					packet.readUInt32();
				}
				Array option;
				option.push_back(probability);
				option.push_back(male);
				option.push_back(female);
				options.push_back(option);
			}
			npc_texts[text_id] = options;
			npc_text_queries.erase(text_id);
			emit_signal("npc_text_received", static_cast<int64_t>(text_id));
			return true;
		}
		case LogicalOpcode::SMSG_QUESTGIVER_QUEST_LIST: {
			Dictionary greeting;
			greeting["guid"] = static_cast<int64_t>(packet.readUInt64());
			greeting["text"] = read_string(packet);
			packet.readUInt32(); // Emote delay.
			packet.readUInt32(); // Emote.
			Array quests;
			const uint8_t count = packet.readUInt8();
			for (uint8_t i = 0; i < count && packet.hasRemaining(12); ++i) {
				Dictionary quest;
				quest["id"] = static_cast<int64_t>(packet.readUInt32());
				quest["icon"] = static_cast<int64_t>(packet.readUInt32());
				quest["level"] = static_cast<int64_t>(packet.readUInt32());
				quest["title"] = read_string(packet);
				quests.push_back(quest);
			}
			greeting["quests"] = quests;
			emit_signal("quest_greeting_received", greeting);
			return true;
		}
		case LogicalOpcode::SMSG_QUESTGIVER_QUEST_DETAILS: {
			Dictionary details;
			details["guid"] = static_cast<int64_t>(packet.readUInt64());
			details["quest_id"] = static_cast<int64_t>(packet.readUInt32());
			details["title"] = read_string(packet);
			details["text"] = read_string(packet);
			details["objectives"] = read_string(packet);
			details["auto_accept"] = packet.readUInt32() != 0;
			details["choices"] = read_quest_items(packet);
			details["rewards"] = read_quest_items(packet);
			details["money"] = static_cast<int64_t>(static_cast<int32_t>(packet.readUInt32()));
			details["reward_spell"] = static_cast<int64_t>(packet.readUInt32());
			emit_signal("quest_details_received", details);
			return true;
		}
		case LogicalOpcode::SMSG_QUESTGIVER_REQUEST_ITEMS: {
			constexpr uint32_t COMPLETABLE = 0x03;
			Dictionary progress;
			progress["guid"] = static_cast<int64_t>(packet.readUInt64());
			progress["quest_id"] = static_cast<int64_t>(packet.readUInt32());
			progress["title"] = read_string(packet);
			progress["text"] = read_string(packet);
			packet.readUInt32(); // Emote delay.
			packet.readUInt32(); // Emote.
			progress["close_on_cancel"] = packet.readUInt32() != 0;
			progress["money"] = static_cast<int64_t>(packet.readUInt32());
			progress["items"] = read_quest_items(packet);
			packet.readUInt32();
			// The second of four flag words reads 3 once every objective is done.
			progress["completable"] = packet.readUInt32() == COMPLETABLE;
			emit_signal("quest_progress_received", progress);
			return true;
		}
		case LogicalOpcode::SMSG_QUESTGIVER_OFFER_REWARD: {
			Dictionary reward;
			reward["guid"] = static_cast<int64_t>(packet.readUInt64());
			reward["quest_id"] = static_cast<int64_t>(packet.readUInt32());
			reward["title"] = read_string(packet);
			reward["text"] = read_string(packet);
			reward["auto_finish"] = packet.readUInt32() != 0;
			const uint32_t emotes = packet.readUInt32();
			for (uint32_t i = 0; i < emotes * 2 && packet.hasRemaining(4); ++i) {
				packet.readUInt32();
			}
			reward["choices"] = read_quest_items(packet);
			reward["rewards"] = read_quest_items(packet);
			reward["money"] = static_cast<int64_t>(static_cast<int32_t>(packet.readUInt32()));
			reward["flags"] = static_cast<int64_t>(packet.readUInt32());
			reward["reward_spell"] = static_cast<int64_t>(packet.readUInt32());
			emit_signal("quest_reward_received", reward);
			return true;
		}
		case LogicalOpcode::SMSG_QUESTGIVER_QUEST_COMPLETE: {
			const int64_t quest_id = packet.readUInt32();
			packet.readUInt32();
			const int64_t xp = packet.readUInt32();
			const int64_t money = packet.readUInt32();
			emit_signal("quest_completed", quest_id, xp, money);
			return true;
		}
		case LogicalOpcode::SMSG_QUESTUPDATE_ADD_KILL: {
			const int64_t quest_id = packet.readUInt32();
			const int64_t entry = packet.readUInt32();
			const int64_t count = packet.readUInt32();
			const int64_t required = packet.readUInt32();
			emit_signal("quest_kill_added", quest_id, entry, count, required);
			return true;
		}
		case LogicalOpcode::SMSG_LIST_INVENTORY: {
			constexpr uint32_t UNLIMITED = 0xFFFFFFFF;
			Dictionary inventory;
			inventory["guid"] = static_cast<int64_t>(packet.readUInt64());
			Array items;
			const uint8_t count = packet.readUInt8();
			for (uint8_t i = 0; i < count && packet.hasRemaining(28); ++i) {
				Dictionary item;
				item["slot"] = static_cast<int64_t>(packet.readUInt32());
				item["entry"] = static_cast<int64_t>(packet.readUInt32());
				item["display"] = static_cast<int64_t>(packet.readUInt32());
				const uint32_t stock = packet.readUInt32();
				item["stock"] = stock == UNLIMITED ? static_cast<int64_t>(-1) : static_cast<int64_t>(stock);
				item["price"] = static_cast<int64_t>(packet.readUInt32());
				item["durability"] = static_cast<int64_t>(packet.readUInt32());
				item["count"] = static_cast<int64_t>(packet.readUInt32());
				items.push_back(item);
			}
			inventory["items"] = items;
			emit_signal("merchant_inventory_received", inventory);
			return true;
		}
		case LogicalOpcode::SMSG_BUY_ITEM: {
			constexpr uint32_t UNLIMITED = 0xFFFFFFFF;
			packet.readUInt64();
			const int64_t slot = packet.readUInt32();
			const uint32_t stock = packet.readUInt32();
			emit_signal("merchant_stock_changed", slot, stock == UNLIMITED ? static_cast<int64_t>(-1) : static_cast<int64_t>(stock));
			return true;
		}
		case LogicalOpcode::SMSG_BUY_FAILED: {
			packet.readUInt64();
			packet.readUInt32();
			emit_signal("merchant_buy_failed", static_cast<int64_t>(packet.readUInt8()));
			return true;
		}
		case LogicalOpcode::SMSG_SELL_ITEM: {
			packet.readUInt64();
			packet.readUInt64();
			emit_signal("merchant_sell_failed", static_cast<int64_t>(packet.readUInt8()));
			return true;
		}
		case LogicalOpcode::SMSG_TRAINER_LIST: {
			Dictionary trainer;
			trainer["guid"] = static_cast<int64_t>(packet.readUInt64());
			trainer["type"] = static_cast<int64_t>(packet.readUInt32());
			Array spells;
			const uint32_t count = packet.readUInt32();
			for (uint32_t i = 0; i < count && packet.hasRemaining(38); ++i) {
				Dictionary spell;
				spell["id"] = static_cast<int64_t>(packet.readUInt32());
				spell["state"] = static_cast<int64_t>(packet.readUInt8());
				spell["cost"] = static_cast<int64_t>(packet.readUInt32());
				const uint32_t can_learn_profession = packet.readUInt32();
				// Learnable only when both profession words agree.
				spell["profession_ok"] = can_learn_profession == packet.readUInt32();
				spell["level"] = static_cast<int64_t>(packet.readUInt8());
				spell["skill"] = static_cast<int64_t>(packet.readUInt32());
				spell["skill_value"] = static_cast<int64_t>(packet.readUInt32());
				PackedInt32Array prereqs;
				for (int p = 0; p < 2; ++p) {
					if (const uint32_t prereq = packet.readUInt32(); prereq != 0) {
						prereqs.push_back(static_cast<int32_t>(prereq));
					}
				}
				spell["prereqs"] = prereqs;
				packet.readUInt32();
				spells.push_back(spell);
			}
			trainer["spells"] = spells;
			trainer["greeting"] = read_string(packet);
			emit_signal("trainer_list_received", trainer);
			return true;
		}
		case LogicalOpcode::SMSG_TRAINER_BUY_SUCCEEDED: {
			packet.readUInt64();
			emit_signal("trainer_spell_bought", static_cast<int64_t>(packet.readUInt32()));
			return true;
		}
		case LogicalOpcode::SMSG_TRAINER_BUY_FAILED: {
			packet.readUInt64();
			const int64_t spell = packet.readUInt32();
			emit_signal("trainer_buy_failed", spell, static_cast<int64_t>(packet.readUInt32()));
			return true;
		}
		case LogicalOpcode::SMSG_SHOWTAXINODES: {
			constexpr int MASK_WORDS = 8;
			Dictionary taxi;
			packet.readUInt32();
			taxi["guid"] = static_cast<int64_t>(packet.readUInt64());
			taxi["current"] = static_cast<int64_t>(packet.readUInt32());
			PackedInt64Array mask;
			for (int i = 0; i < MASK_WORDS && packet.hasRemaining(4); ++i) {
				mask.push_back(packet.readUInt32());
			}
			taxi["mask"] = mask;
			emit_signal("taxi_nodes_received", taxi);
			return true;
		}
		case LogicalOpcode::SMSG_TAXINODE_STATUS: {
			const int64_t guid = static_cast<int64_t>(packet.readUInt64());
			emit_signal("taxi_node_status_received", guid, packet.readUInt8() != 0);
			return true;
		}
		case LogicalOpcode::SMSG_NEW_TAXI_PATH:
			emit_signal("taxi_path_discovered");
			return true;
		case LogicalOpcode::SMSG_ACTIVATETAXIREPLY:
			emit_signal("taxi_reply_received", static_cast<int64_t>(packet.readUInt32()));
			return true;
		case LogicalOpcode::SMSG_QUESTUPDATE_COMPLETE:
			emit_signal("quest_objectives_completed", static_cast<int64_t>(packet.readUInt32()));
			return true;
		default:
			return false;
	}
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
	line["sender_guid"] = static_cast<int64_t>(sender);
	if (name.empty() && is_player_guid(sender)) {
		const auto it = player_names.find(sender);
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
	item_queries.clear();
	creature_entry_queries.clear();
	game_object_queries.clear();
	quest_queries.clear();
	npc_text_queries.clear();
	chat_waiting.clear();
	player_guid = 0;
	player_path = Dictionary();
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
				d["guid"] = static_cast<int64_t>(c.guid);
				d["name"] = String::utf8(c.name.c_str());
				d["race"] = static_cast<int>(c.race);
				d["class"] = static_cast<int>(c.characterClass);
				d["gender"] = static_cast<int>(c.gender);
				d["level"] = c.level;
				d["skin"] = c.appearanceBytes & 0xFF;
				d["face"] = (c.appearanceBytes >> 8) & 0xFF;
				d["hair_style"] = (c.appearanceBytes >> 16) & 0xFF;
				d["hair_color"] = (c.appearanceBytes >> 24) & 0xFF;
				d["facial_hair"] = c.facialFeatures;
				d["zone"] = c.zoneId;
				d["map"] = c.mapId;
				d["position"] = wow_vector(c.x, c.y, c.z);
				d["flags"] = c.flags;
				d["guild"] = c.guildId;
				// Display ids by inventory slot, head (0) through tabard (18) and the first bag.
				PackedInt32Array equipment;
				for (const game::EquipmentItem &item : c.equipment) {
					equipment.push_back(static_cast<int32_t>(item.displayModel));
				}
				d["equipment"] = equipment;
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
		case LogicalOpcode::SMSG_CHAR_DELETE: {
			const uint8_t code = packet.getSize() > 0 ? packet.readUInt8() : 0;
			emit_signal("character_deleted", code == CHAR_DELETE_SUCCESS, code);
			return;
		}
		case LogicalOpcode::SMSG_CHARACTER_LOGIN_FAILED: {
			const uint8_t code = packet.getSize() > 0 ? packet.readUInt8() : 0;
			player_guid = 0;
			player_path = Dictionary();
			set_state(STATE_CHARACTER_LIST);
			emit_signal("character_login_failed", code);
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
			guids.push_back(static_cast<int64_t>(guid));
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
			if (data.moveType == MONSTER_MOVE_FACING_ANGLE) {
				move["orientation"] = data.facingAngle;
			}
			constexpr uint32_t SPLINE_FLYING = 0x200;
			if (data.splineFlags & SPLINE_FLYING) {
				PackedVector3Array points;
				for (const auto &point : data.waypoints) {
					points.push_back(wow_vector(point.x, point.y, point.z));
				}
				points.push_back(wow_vector(data.destX, data.destY, data.destZ));
				move["points"] = points;
				if (data.guid == player_guid) {
					player_path = move.duplicate();
					player_path["elapsed_msec"] = static_cast<int64_t>(0);
					player_path["from_start"] = false;
					player_path_msec = Time::get_singleton()->get_ticks_msec();
				}
			}
			if (auto it = objects.find(data.guid); it != objects.end()) {
				it->second.position = data.hasDest ? wow_vector(data.destX, data.destY, data.destZ) : wow_vector(data.x, data.y, data.z);
				if (data.moveType == MONSTER_MOVE_FACING_ANGLE) {
					it->second.orientation = data.facingAngle;
				}
			}
			emit_signal("object_moved", static_cast<int64_t>(data.guid), move);
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
			emit_signal("name_received", static_cast<int64_t>(data.guid), name);
			if (const auto waiting = chat_waiting.find(data.guid); waiting != chat_waiting.end()) {
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
		case LogicalOpcode::SMSG_ITEM_QUERY_SINGLE_RESPONSE: {
			game::ItemQueryResponseData data;
			if (!parsers->parseItemQueryResponse(packet, data) || data.entry == 0) {
				return;
			}
			Dictionary info;
			info["entry"] = static_cast<int64_t>(data.entry);
			info["name"] = String::utf8(data.name.c_str());
			info["class"] = static_cast<int64_t>(data.itemClass);
			info["subclass"] = static_cast<int64_t>(data.subClass);
			info["display_id"] = static_cast<int64_t>(data.displayInfoId);
			info["quality"] = static_cast<int64_t>(data.quality);
			info["inventory_type"] = static_cast<int64_t>(data.inventoryType);
			info["max_stack"] = data.maxStack;
			info["container_slots"] = static_cast<int64_t>(data.containerSlots);
			info["damage_min"] = data.damageMin;
			info["damage_max"] = data.damageMax;
			info["delay_msec"] = static_cast<int64_t>(data.delayMs);
			info["armor"] = data.armor;
			info["stamina"] = data.stamina;
			info["strength"] = data.strength;
			info["agility"] = data.agility;
			info["intellect"] = data.intellect;
			info["spirit"] = data.spirit;
			info["sell_price"] = static_cast<int64_t>(data.sellPrice);
			info["item_level"] = static_cast<int64_t>(data.itemLevel);
			info["required_level"] = static_cast<int64_t>(data.requiredLevel);
			info["sheath"] = static_cast<int64_t>(data.sheath);
			item_info[data.entry] = info;
			item_queries.erase(data.entry);
			emit_signal("item_info_received", static_cast<int64_t>(data.entry));
			return;
		}
		case LogicalOpcode::SMSG_CREATURE_QUERY_RESPONSE: {
			game::CreatureQueryResponseData data;
			if (!parsers->parseCreatureQueryResponse(packet, data) || !data.isValid()) {
				return;
			}
			Dictionary info;
			info["entry"] = static_cast<int64_t>(data.entry);
			info["name"] = String::utf8(data.name.c_str());
			info["subname"] = String::utf8(data.subName.c_str());
			info["rank"] = static_cast<int64_t>(data.rank);
			info["type"] = static_cast<int64_t>(data.creatureType);
			info["family"] = static_cast<int64_t>(data.family);
			creature_info[data.entry] = info;
			if (creature_entry_queries.erase(data.entry) > 0) {
				emit_signal("creature_info_received", static_cast<int64_t>(data.entry));
			}
			if (auto waiting = creature_queries.find(data.entry); waiting != creature_queries.end()) {
				const std::vector<uint64_t> guids = std::move(waiting->second);
				creature_queries.erase(waiting);
				for (uint64_t guid : guids) {
					emit_signal("name_received", static_cast<int64_t>(guid), String::utf8(data.name.c_str()));
				}
			}
			return;
		}
		case LogicalOpcode::SMSG_GAMEOBJECT_QUERY_RESPONSE: {
			game::GameObjectQueryResponseData data;
			if (!parsers->parseGameObjectQueryResponse(packet, data) || !data.isValid()) {
				return;
			}
			Dictionary info;
			info["entry"] = static_cast<int64_t>(data.entry);
			info["name"] = String::utf8(data.name.c_str());
			info["type"] = static_cast<int64_t>(data.type);
			game_object_info[data.entry] = info;
			game_object_queries.erase(data.entry);
			emit_signal("game_object_info_received", static_cast<int64_t>(data.entry));
			return;
		}
		case LogicalOpcode::SMSG_INITIALIZE_FACTIONS: {
			const uint32_t count = packet.readUInt32();
			faction_flags.resize(0);
			faction_standings.resize(0);
			for (uint32_t i = 0; i < count && packet.hasRemaining(5); ++i) {
				faction_flags.push_back(packet.readUInt8());
				faction_standings.push_back(static_cast<int32_t>(packet.readUInt32()));
			}
			emit_signal("factions_changed");
			return;
		}
		case LogicalOpcode::SMSG_SET_FACTION_STANDING: {
			const uint32_t count = packet.readUInt32();
			for (uint32_t i = 0; i < count && packet.hasRemaining(8); ++i) {
				const int64_t index = packet.readUInt32();
				const int32_t standing = static_cast<int32_t>(packet.readUInt32());
				if (index < faction_standings.size()) {
					faction_standings.set(index, standing);
					// A standing change makes the faction show in the list.
					faction_flags.set(index, faction_flags[index] | 0x01);
				}
			}
			emit_signal("factions_changed");
			return;
		}
		case LogicalOpcode::SMSG_SET_FACTION_VISIBLE: {
			if (const int64_t index = packet.readUInt32(); index < faction_flags.size()) {
				faction_flags.set(index, faction_flags[index] | 0x01);
				emit_signal("factions_changed");
			}
			return;
		}
		case LogicalOpcode::SMSG_QUEST_QUERY_RESPONSE:
			handle_quest_query(packet);
			return;
		case LogicalOpcode::MSG_MOVE_TELEPORT_ACK: {
			// A near teleport: the server holds the player until the counter comes back with the time.
			const uint64_t guid = packet.readPackedGuid();
			const uint32_t counter = packet.readUInt32();
			packet.readUInt32(); // Movement flags.
			packet.readUInt32(); // Server time.
			const float x = packet.readFloat();
			const float y = packet.readFloat();
			const float z = packet.readFloat();
			const float orientation = packet.readFloat();
			if (guid != player_guid) {
				return;
			}
			if (auto it = objects.find(guid); it != objects.end()) {
				it->second.position = wow_vector(x, y, z);
				it->second.orientation = orientation;
			}
			network::Packet ack(game::wireOpcode(LogicalOpcode::MSG_MOVE_TELEPORT_ACK));
			ack.writeUInt64(guid);
			ack.writeUInt32(counter);
			ack.writeUInt32(static_cast<uint32_t>(Time::get_singleton()->get_ticks_msec()));
			world->send(ack);
			emit_signal("player_teleported", wow_vector(x, y, z), orientation);
			return;
		}
		case LogicalOpcode::SMSG_LOGOUT_COMPLETE:
			objects.clear();
			player_guid = 0;
			player_path = Dictionary();
			set_state(STATE_CHARACTER_LIST);
			request_characters();
			return;
		default:
			if (handle_combat_packet(static_cast<uint16_t>(*op), packet)
				|| handle_npc_packet(static_cast<uint16_t>(*op), packet)) {
				return;
			}
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
		destroyed.push_back(static_cast<int64_t>(guid));
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
			object.type_id = static_cast<uint8_t>(block.objectType);
		}
		for (const auto &[index, value] : block.fields) {
			object.fields[index] = value;
		}
		if (block.hasMovement) {
			object.position = wow_vector(block.x, block.y, block.z);
			object.orientation = block.orientation;
			if (block.runSpeed > 0.0f) {
				object.speeds = { block.walkSpeed, block.runSpeed, block.runBackSpeed, block.swimSpeed, block.swimBackSpeed, block.turnRate };
			}
		}
		// Logging in mid-flight: the create block carries the whole path and how far along it is.
		if (block.hasSpline && block.guid == player_guid && block.splineDuration > 0) {
			PackedVector3Array points;
			for (const auto &point : block.splinePoints) {
				points.push_back(wow_vector(point.x, point.y, point.z));
			}
			player_path = Dictionary();
			player_path["points"] = points;
			player_path["duration_msec"] = static_cast<int64_t>(block.splineDuration);
			player_path["elapsed_msec"] = static_cast<int64_t>(block.splineTimePassed);
			player_path["from_start"] = true;
			player_path_msec = Time::get_singleton()->get_ticks_msec();
		}
		if (created) {
			emit_signal("object_created", static_cast<int64_t>(block.guid), object.type_id);
		} else if (block.updateType == game::UpdateType::MOVEMENT) {
			Dictionary move;
			move["position"] = object.position;
			move["orientation"] = object.orientation;
			emit_signal("object_moved", static_cast<int64_t>(block.guid), move);
		} else {
			emit_signal("object_updated", static_cast<int64_t>(block.guid));
		}
	}
	if (!destroyed.is_empty()) {
		emit_signal("objects_destroyed", destroyed);
	}
}

// Vanilla relays carry a packed GUID, then MovementInfo with no second flags field; speed changes append the speed.
void WowSession::handle_movement_relay(network::Packet &packet) {
	constexpr std::array<const char *, 6> SPEED_OPCODES = {
		"MSG_MOVE_SET_WALK_SPEED", "MSG_MOVE_SET_RUN_SPEED", "MSG_MOVE_SET_RUN_BACK_SPEED",
		"MSG_MOVE_SET_SWIM_SPEED", "MSG_MOVE_SET_SWIM_BACK_SPEED", "MSG_MOVE_SET_TURN_RATE",
	};
	constexpr std::array<const char *, 6> SPEED_KEYS = {
		"walk_speed", "run_speed", "run_back_speed", "swim_speed", "swim_back_speed", "turn_rate",
	};
	const char *name = game::OpcodeTable::logicalToName(*logical(packet));
	const uint64_t guid = packet.readPackedGuid();
	const uint32_t flags = packet.readUInt32();
	packet.readUInt32();
	const float x = packet.readFloat();
	const float y = packet.readFloat();
	const float z = packet.readFloat();
	const float orientation = packet.readFloat();
	if (flags & MOVEFLAG_ONTRANSPORT) {
		packet.readUInt64();
		for (int i = 0; i < 4; i++) {
			packet.readFloat();
		}
	}
	if (flags & MOVEFLAG_SWIMMING) {
		packet.readFloat();
	}
	const uint32_t fall_time = packet.hasRemaining(4) ? packet.readUInt32() : 0;
	Vector3 jump_velocity;
	if ((flags & MOVEFLAG_JUMPING) && packet.hasRemaining(16)) {
		const float z_speed = packet.readFloat();
		const float cos_angle = packet.readFloat();
		const float sin_angle = packet.readFloat();
		const float xy_speed = packet.readFloat();
		jump_velocity = Vector3(cos_angle * xy_speed, sin_angle * xy_speed, -z_speed);
	}
	if ((flags & MOVEFLAG_SPLINE_ELEVATION) && packet.hasRemaining(4)) {
		packet.readFloat();
	}
	Dictionary move;
	move["position"] = wow_vector(x, y, z);
	move["orientation"] = orientation;
	move["flags"] = flags;
	move["opcode"] = String(name);
	move["fall_time_msec"] = fall_time;
	move["jump_velocity"] = jump_velocity;
	auto it = objects.find(guid);
	if (it != objects.end()) {
		WorldObject &object = it->second;
		object.position = wow_vector(x, y, z);
		object.orientation = orientation;
		for (size_t i = 0; i < SPEED_OPCODES.size(); i++) {
			if (std::strcmp(name, SPEED_OPCODES[i]) == 0 && packet.hasRemaining(4)) {
				object.speeds[i] = packet.readFloat();
			}
		}
		for (size_t i = 0; i < SPEED_KEYS.size(); i++) {
			move[SPEED_KEYS[i]] = object.speeds[i];
		}
	}
	emit_signal("object_moved", static_cast<int64_t>(guid), move);
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
		const uint16_t opcode = static_cast<uint16_t>(raw[offset + 1] | (raw[offset + 2] << 8));
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
	auto it = objects.find(static_cast<uint64_t>(guid));
	return it == objects.end() ? nullptr : &it->second;
}

PackedInt64Array WowSession::get_object_guids() const {
	PackedInt64Array guids;
	for (const auto &[guid, object] : objects) {
		guids.push_back(static_cast<int64_t>(guid));
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

PackedFloat32Array WowSession::get_object_speeds(int64_t guid) const {
	PackedFloat32Array speeds;
	if (const WorldObject *object = find(guid)) {
		for (const float speed : object->speeds) {
			speeds.push_back(speed);
		}
	}
	return speeds;
}

int WowSession::field_index(const String &name) const {
	auto it = field_indices().find(name.utf8().get_data());
	return it == field_indices().end() ? -1 : it->second;
}

int64_t WowSession::get_field(int64_t guid, const Variant &field) const {
	const WorldObject *object = find(guid);
	const int index = field.get_type() == Variant::INT ? static_cast<int>(field) : field_index(field);
	if (!object || index < 0) {
		return 0;
	}
	auto it = object->fields.find(static_cast<uint16_t>(index));
	return it == object->fields.end() ? 0 : it->second;
}

double WowSession::get_field_float(int64_t guid, const Variant &field) const {
	const uint32_t bits = static_cast<uint32_t>(get_field(guid, field));
	float value = 0.0f;
	std::memcpy(&value, &bits, sizeof(value));
	return value;
}

void WowSession::_bind_methods() {
	ClassDB::bind_method(D_METHOD("login", "host", "port", "username", "password"), &WowSession::login);
	ClassDB::bind_method(D_METHOD("request_realms"), &WowSession::request_realms);
	ClassDB::bind_method(D_METHOD("select_realm", "index"), &WowSession::select_realm);
	ClassDB::bind_method(D_METHOD("request_characters"), &WowSession::request_characters);
	ClassDB::bind_method(D_METHOD("create_character", "character"), &WowSession::create_character);
	ClassDB::bind_method(D_METHOD("delete_character", "guid"), &WowSession::delete_character);
	ClassDB::bind_method(D_METHOD("enter_world", "guid"), &WowSession::enter_world);
	ClassDB::bind_method(D_METHOD("logout"), &WowSession::logout);
	ClassDB::bind_method(D_METHOD("send_movement", "opcode", "position", "orientation", "flags", "fall_time_msec", "jump_velocity", "pitch", "ack_counter", "ack_tail"), &WowSession::send_movement, DEFVAL(0), DEFVAL(Vector3()), DEFVAL(0.0), DEFVAL(-1), DEFVAL(PackedByteArray()));
	ClassDB::bind_method(D_METHOD("send_packet", "opcode", "payload"), &WowSession::send_packet);
	ClassDB::bind_method(D_METHOD("send_chat", "type", "message", "target"), &WowSession::send_chat, DEFVAL(String()));
	ClassDB::bind_method(D_METHOD("set_selection", "guid"), &WowSession::set_selection);
	ClassDB::bind_method(D_METHOD("cast_spell", "spell_id", "target_guid"), &WowSession::cast_spell, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("cancel_cast", "spell_id"), &WowSession::cancel_cast);
	ClassDB::bind_method(D_METHOD("attack", "target_guid"), &WowSession::attack);
	ClassDB::bind_method(D_METHOD("stop_attack"), &WowSession::stop_attack);
	ClassDB::bind_method(D_METHOD("cancel_aura", "spell_id"), &WowSession::cancel_aura);
	ClassDB::bind_method(D_METHOD("get_known_spells"), &WowSession::get_known_spells);
	ClassDB::bind_method(D_METHOD("get_action_buttons"), &WowSession::get_action_buttons);
	ClassDB::bind_method(D_METHOD("get_faction_flags"), &WowSession::get_faction_flags);
	ClassDB::bind_method(D_METHOD("get_faction_standings"), &WowSession::get_faction_standings);
	ClassDB::bind_method(D_METHOD("set_action_button", "slot", "packed"), &WowSession::set_action_button);
	ClassDB::bind_method(D_METHOD("get_object_name", "guid"), &WowSession::get_object_name);
	ClassDB::bind_method(D_METHOD("get_item_info", "entry"), &WowSession::get_item_info);
	ClassDB::bind_method(D_METHOD("get_creature_info", "guid"), &WowSession::get_creature_info);
	ClassDB::bind_method(D_METHOD("get_creature_template", "entry"), &WowSession::get_creature_template);
	ClassDB::bind_method(D_METHOD("get_game_object_info", "entry"), &WowSession::get_game_object_info);
	ClassDB::bind_method(D_METHOD("get_quest_info", "quest_id"), &WowSession::get_quest_info);
	ClassDB::bind_method(D_METHOD("get_npc_text", "text_id", "guid"), &WowSession::get_npc_text);
	ClassDB::bind_method(D_METHOD("get_player_path"), &WowSession::get_player_path);
	ClassDB::bind_method(D_METHOD("disconnect"), &WowSession::disconnect);
	ClassDB::bind_method(D_METHOD("poll"), &WowSession::poll);
	ClassDB::bind_method(D_METHOD("get_state"), &WowSession::get_state);
	ClassDB::bind_method(D_METHOD("get_player_guid"), &WowSession::get_player_guid);
	ClassDB::bind_method(D_METHOD("get_object_guids"), &WowSession::get_object_guids);
	ClassDB::bind_method(D_METHOD("has_object", "guid"), &WowSession::has_object);
	ClassDB::bind_method(D_METHOD("get_object_type", "guid"), &WowSession::get_object_type);
	ClassDB::bind_method(D_METHOD("get_object_position", "guid"), &WowSession::get_object_position);
	ClassDB::bind_method(D_METHOD("get_object_orientation", "guid"), &WowSession::get_object_orientation);
	ClassDB::bind_method(D_METHOD("get_object_speeds", "guid"), &WowSession::get_object_speeds);
	ClassDB::bind_method(D_METHOD("get_field", "guid", "field"), &WowSession::get_field);
	ClassDB::bind_method(D_METHOD("get_field_float", "guid", "field"), &WowSession::get_field_float);
	ClassDB::bind_method(D_METHOD("field_index", "name"), &WowSession::field_index);

	ADD_SIGNAL(MethodInfo("state_changed", PropertyInfo(Variant::INT, "state"), PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("realms_received", PropertyInfo(Variant::ARRAY, "realms")));
	ADD_SIGNAL(MethodInfo("characters_received", PropertyInfo(Variant::ARRAY, "characters")));
	ADD_SIGNAL(MethodInfo("character_created", PropertyInfo(Variant::BOOL, "success"), PropertyInfo(Variant::INT, "code")));
	ADD_SIGNAL(MethodInfo("character_deleted", PropertyInfo(Variant::BOOL, "success"), PropertyInfo(Variant::INT, "code")));
	ADD_SIGNAL(MethodInfo("character_login_failed", PropertyInfo(Variant::INT, "code")));
	ADD_SIGNAL(MethodInfo("world_entered", PropertyInfo(Variant::INT, "map_id"), PropertyInfo(Variant::VECTOR3, "position"), PropertyInfo(Variant::FLOAT, "orientation")));
	ADD_SIGNAL(MethodInfo("object_created", PropertyInfo(Variant::INT, "guid"), PropertyInfo(Variant::INT, "type_id")));
	ADD_SIGNAL(MethodInfo("object_updated", PropertyInfo(Variant::INT, "guid")));
	ADD_SIGNAL(MethodInfo("object_moved", PropertyInfo(Variant::INT, "guid"), PropertyInfo(Variant::DICTIONARY, "movement")));
	ADD_SIGNAL(MethodInfo("objects_destroyed", PropertyInfo(Variant::PACKED_INT64_ARRAY, "guids")));
	ADD_SIGNAL(MethodInfo("chat_received", PropertyInfo(Variant::DICTIONARY, "line")));
	ADD_SIGNAL(MethodInfo("spells_changed"));
	ADD_SIGNAL(MethodInfo("action_buttons_changed"));
	ADD_SIGNAL(MethodInfo("factions_changed"));
	ADD_SIGNAL(MethodInfo("player_teleported", PropertyInfo(Variant::VECTOR3, "position"), PropertyInfo(Variant::FLOAT, "orientation")));
	ADD_SIGNAL(MethodInfo("spell_cast_started", PropertyInfo(Variant::INT, "caster"), PropertyInfo(Variant::INT, "spell_id"), PropertyInfo(Variant::INT, "cast_time_msec")));
	ADD_SIGNAL(MethodInfo("spell_cast_finished", PropertyInfo(Variant::INT, "caster"), PropertyInfo(Variant::INT, "spell_id")));
	ADD_SIGNAL(MethodInfo("spell_cast_failed", PropertyInfo(Variant::INT, "caster"), PropertyInfo(Variant::INT, "spell_id"), PropertyInfo(Variant::INT, "reason")));
	ADD_SIGNAL(MethodInfo("spell_cast_delayed", PropertyInfo(Variant::INT, "caster"), PropertyInfo(Variant::INT, "delay_msec")));
	ADD_SIGNAL(MethodInfo("spell_channel_started", PropertyInfo(Variant::INT, "spell_id"), PropertyInfo(Variant::INT, "duration_msec")));
	ADD_SIGNAL(MethodInfo("spell_channel_updated", PropertyInfo(Variant::INT, "remaining_msec")));
	ADD_SIGNAL(MethodInfo("spell_cooldown", PropertyInfo(Variant::INT, "spell_id"), PropertyInfo(Variant::INT, "cooldown_msec")));
	ADD_SIGNAL(MethodInfo("aura_duration", PropertyInfo(Variant::INT, "slot"), PropertyInfo(Variant::INT, "duration_msec")));
	ADD_SIGNAL(MethodInfo("attack_swing_error", PropertyInfo(Variant::INT, "error")));
	ADD_SIGNAL(MethodInfo("melee_swing", PropertyInfo(Variant::INT, "attacker"), PropertyInfo(Variant::INT, "victim"), PropertyInfo(Variant::INT, "damage"), PropertyInfo(Variant::INT, "hit_info"), PropertyInfo(Variant::INT, "victim_state")));
	ADD_SIGNAL(MethodInfo("attack_started", PropertyInfo(Variant::INT, "attacker"), PropertyInfo(Variant::INT, "victim")));
	ADD_SIGNAL(MethodInfo("attack_stopped", PropertyInfo(Variant::INT, "attacker"), PropertyInfo(Variant::INT, "victim")));
	ADD_SIGNAL(MethodInfo("item_info_received", PropertyInfo(Variant::INT, "entry")));
	ADD_SIGNAL(MethodInfo("creature_info_received", PropertyInfo(Variant::INT, "entry")));
	ADD_SIGNAL(MethodInfo("game_object_info_received", PropertyInfo(Variant::INT, "entry")));
	ADD_SIGNAL(MethodInfo("quest_info_received", PropertyInfo(Variant::INT, "quest_id")));
	ADD_SIGNAL(MethodInfo("quest_giver_status_received", PropertyInfo(Variant::INT, "guid"), PropertyInfo(Variant::INT, "status")));
	ADD_SIGNAL(MethodInfo("gossip_received", PropertyInfo(Variant::DICTIONARY, "gossip")));
	ADD_SIGNAL(MethodInfo("gossip_closed"));
	ADD_SIGNAL(MethodInfo("npc_text_received", PropertyInfo(Variant::INT, "text_id")));
	ADD_SIGNAL(MethodInfo("quest_greeting_received", PropertyInfo(Variant::DICTIONARY, "greeting")));
	ADD_SIGNAL(MethodInfo("quest_details_received", PropertyInfo(Variant::DICTIONARY, "details")));
	ADD_SIGNAL(MethodInfo("quest_progress_received", PropertyInfo(Variant::DICTIONARY, "progress")));
	ADD_SIGNAL(MethodInfo("quest_reward_received", PropertyInfo(Variant::DICTIONARY, "reward")));
	ADD_SIGNAL(MethodInfo("quest_completed", PropertyInfo(Variant::INT, "quest_id"), PropertyInfo(Variant::INT, "xp"), PropertyInfo(Variant::INT, "money")));
	ADD_SIGNAL(MethodInfo("quest_kill_added", PropertyInfo(Variant::INT, "quest_id"), PropertyInfo(Variant::INT, "entry"), PropertyInfo(Variant::INT, "count"), PropertyInfo(Variant::INT, "required")));
	ADD_SIGNAL(MethodInfo("quest_objectives_completed", PropertyInfo(Variant::INT, "quest_id")));
	ADD_SIGNAL(MethodInfo("merchant_inventory_received", PropertyInfo(Variant::DICTIONARY, "inventory")));
	ADD_SIGNAL(MethodInfo("merchant_stock_changed", PropertyInfo(Variant::INT, "slot"), PropertyInfo(Variant::INT, "stock")));
	ADD_SIGNAL(MethodInfo("merchant_buy_failed", PropertyInfo(Variant::INT, "reason")));
	ADD_SIGNAL(MethodInfo("merchant_sell_failed", PropertyInfo(Variant::INT, "reason")));
	ADD_SIGNAL(MethodInfo("trainer_list_received", PropertyInfo(Variant::DICTIONARY, "trainer")));
	ADD_SIGNAL(MethodInfo("trainer_spell_bought", PropertyInfo(Variant::INT, "spell_id")));
	ADD_SIGNAL(MethodInfo("trainer_buy_failed", PropertyInfo(Variant::INT, "spell_id"), PropertyInfo(Variant::INT, "reason")));
	ADD_SIGNAL(MethodInfo("taxi_nodes_received", PropertyInfo(Variant::DICTIONARY, "taxi")));
	ADD_SIGNAL(MethodInfo("taxi_node_status_received", PropertyInfo(Variant::INT, "guid"), PropertyInfo(Variant::BOOL, "known")));
	ADD_SIGNAL(MethodInfo("taxi_path_discovered"));
	ADD_SIGNAL(MethodInfo("taxi_reply_received", PropertyInfo(Variant::INT, "code")));
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

	BIND_ENUM_CONSTANT(ATTACK_ERROR_NOT_IN_RANGE);
	BIND_ENUM_CONSTANT(ATTACK_ERROR_BAD_FACING);
	BIND_ENUM_CONSTANT(ATTACK_ERROR_NOT_STANDING);
	BIND_ENUM_CONSTANT(ATTACK_ERROR_DEAD_TARGET);
	BIND_ENUM_CONSTANT(ATTACK_ERROR_CANT_ATTACK);

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
