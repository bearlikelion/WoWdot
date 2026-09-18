#pragma once

#include <cstdint>

// WoW 3.3.5a (12340) protocol constants.
// Centralised so every handler references a single source of truth.

namespace wowee {
namespace game {

// ---------------------------------------------------------------------------
// Currency
// ---------------------------------------------------------------------------
constexpr uint32_t COPPER_PER_GOLD   = 10000;
constexpr uint32_t COPPER_PER_SILVER = 100;

// ---------------------------------------------------------------------------
// Unit flags (UNIT_FIELD_FLAGS — index 59 in UnitFields for 3.3.5a;
// 46 in Classic/TBC/Turtle. Bitmask values below are stable across expansions.)
// ---------------------------------------------------------------------------
constexpr uint32_t UNIT_FLAG_TAXI_FLIGHT = 0x00000100;
constexpr uint32_t UNIT_FLAG_IN_COMBAT   = 0x00080000;

// Unit visibility flags (byte 2 of UNIT_FIELD_BYTES_1).
// CREEP marks a unit using the client-side stealth presentation. The server
// still decides whether an undetected stealthed unit is sent to the client.
constexpr uint8_t UNIT_VIS_FLAG_CREEP = 0x02;

// ---------------------------------------------------------------------------
// NPC flags (UNIT_NPC_FLAGS — index 82 in UnitFields for 3.3.5a;
// 147 in Classic/Turtle. Bitmask values below are stable across expansions.)
// ---------------------------------------------------------------------------
constexpr uint32_t NPC_FLAG_FLIGHT_MASTER = 0x00002000;
constexpr uint32_t NPC_FLAG_SPIRIT_GUIDE  = 0x00004000;
constexpr uint32_t NPC_FLAG_SPIRIT_HEALER = 0x00008000;

// ---------------------------------------------------------------------------
// Default action-bar spell IDs
// ---------------------------------------------------------------------------
constexpr uint32_t SPELL_ID_ATTACK     = 6603;
constexpr uint32_t SPELL_ID_HEARTHSTONE = 8690;

// ---------------------------------------------------------------------------
// Class IDs
// ---------------------------------------------------------------------------
constexpr uint32_t CLASS_WARRIOR = 1;
constexpr uint32_t CLASS_PALADIN = 2;
constexpr uint32_t CLASS_HUNTER  = 3;
constexpr uint32_t CLASS_ROGUE   = 4;
constexpr uint32_t CLASS_PRIEST  = 5;
constexpr uint32_t CLASS_DK      = 6;
constexpr uint32_t CLASS_SHAMAN  = 7;
constexpr uint32_t CLASS_MAGE    = 8;
constexpr uint32_t CLASS_WARLOCK = 9;
constexpr uint32_t CLASS_DRUID   = 11;

// ---------------------------------------------------------------------------
// Class-specific stance / form / presence spell IDs
// ---------------------------------------------------------------------------
// Warrior stances
constexpr uint32_t SPELL_BATTLE_STANCE    = 2457;
constexpr uint32_t SPELL_DEFENSIVE_STANCE = 71;
constexpr uint32_t SPELL_BERSERKER_STANCE = 2458;

// Death Knight presences
constexpr uint32_t SPELL_BLOOD_PRESENCE  = 48266;
constexpr uint32_t SPELL_FROST_PRESENCE  = 48263;
constexpr uint32_t SPELL_UNHOLY_PRESENCE = 48265;

// Druid forms
constexpr uint32_t SPELL_BEAR_FORM       = 5487;
constexpr uint32_t SPELL_DIRE_BEAR_FORM  = 9634;
constexpr uint32_t SPELL_CAT_FORM        = 768;
constexpr uint32_t SPELL_AQUATIC_FORM    = 1066;
constexpr uint32_t SPELL_TRAVEL_FORM     = 783;
constexpr uint32_t SPELL_MOONKIN_FORM    = 24858;
constexpr uint32_t SPELL_FLIGHT_FORM     = 33943;
constexpr uint32_t SPELL_SWIFT_FLIGHT    = 40120;
constexpr uint32_t SPELL_TREE_OF_LIFE    = 33891;

// Rogue
constexpr uint32_t SPELL_STEALTH         = 1784;

// Priest
constexpr uint32_t SPELL_SHADOWFORM      = 15473;

// ---------------------------------------------------------------------------
// Session / network timing
// ---------------------------------------------------------------------------
constexpr uint32_t RX_SILENCE_WARNING_MS       = 10000;  // 10 s
constexpr uint32_t RX_SILENCE_CRITICAL_MS      = 15000;  // 15 s
constexpr float    CLASSIC_PING_INTERVAL_SEC    = 10.0f;

// ---------------------------------------------------------------------------
// Heartbeat / area-trigger intervals (seconds)
// ---------------------------------------------------------------------------
constexpr float HEARTBEAT_INTERVAL_TAXI             = 0.25f;
constexpr float HEARTBEAT_INTERVAL_STATIONARY_COMBAT = 0.75f;
constexpr float HEARTBEAT_INTERVAL_MOVING_COMBAT    = 0.20f;
constexpr float AREA_TRIGGER_CHECK_INTERVAL         = 0.25f;

// ---------------------------------------------------------------------------
// Gameplay distance thresholds
// ---------------------------------------------------------------------------
constexpr float ENTITY_UPDATE_RADIUS      = 150.0f;
constexpr float NPC_INTERACT_MAX_DISTANCE = 15.0f;

// ---------------------------------------------------------------------------
// Skill categories (from SkillLine DBC)
// ---------------------------------------------------------------------------
constexpr uint32_t SKILL_CATEGORY_PROFESSION = 11;
constexpr uint32_t SKILL_CATEGORY_SECONDARY  = 9;

// ---------------------------------------------------------------------------
// DBC field-index sentinel (field lookup failure)
// ---------------------------------------------------------------------------
constexpr uint32_t DBC_FIELD_INVALID = 0xFFFFFFFF;

// ---------------------------------------------------------------------------
// Appearance byte packing
// ---------------------------------------------------------------------------
constexpr uint32_t APPEARANCE_SKIN_MASK       = 0xFF;
constexpr uint32_t APPEARANCE_FACE_SHIFT      = 8;
constexpr uint32_t APPEARANCE_HAIRSTYLE_SHIFT = 16;
constexpr uint32_t APPEARANCE_HAIRCOLOR_SHIFT = 24;

// ---------------------------------------------------------------------------
// Critter detection
// ---------------------------------------------------------------------------
constexpr uint32_t CRITTER_MAX_HEALTH_THRESHOLD = 100;

} // namespace game
} // namespace wowee
