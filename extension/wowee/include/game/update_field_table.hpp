#pragma once

#include <cstdint>
#include <string>
#include <unordered_map>

namespace wowee {
namespace game {

/**
 * Logical update field identifiers (expansion-agnostic).
 * Wire indices are loaded at runtime from JSON.
 */
enum class UF : uint16_t {
    // Object fields
    OBJECT_FIELD_ENTRY,
    OBJECT_FIELD_SCALE_X,

    // Unit fields
    UNIT_FIELD_TARGET_LO,
    UNIT_FIELD_TARGET_HI,
    UNIT_FIELD_BYTES_0,
    UNIT_FIELD_BYTES_1,  // byte2 = visibility flags; byte3 is expansion-dependent
    UNIT_FIELD_HEALTH,
    UNIT_FIELD_POWER1,
    UNIT_FIELD_MAXHEALTH,
    UNIT_FIELD_MAXPOWER1,
    UNIT_FIELD_LEVEL,
    UNIT_FIELD_FACTIONTEMPLATE,
    UNIT_FIELD_FLAGS,
    UNIT_FIELD_FLAGS_2,
    UNIT_FIELD_AURASTATE,      // Reactive combat opportunities (e.g. dodge/block/parry)
    UNIT_FIELD_DISPLAYID,
    UNIT_FIELD_MOUNTDISPLAYID,
    UNIT_FIELD_AURAS,           // Start of aura spell ID array (48 consecutive uint32 slots, pre-WotLK clients)
    UNIT_FIELD_AURAFLAGS,       // Aura flags packed 4-per-uint32 (12 uint32 slots); 0x01=cancelable,0x02=harmful,0x04=helpful
    UNIT_NPC_FLAGS,
    UNIT_NPC_EMOTESTATE,       // Persistent NPC emote animation ID (uint32)
    UNIT_DYNAMIC_FLAGS,
    UNIT_FIELD_RESISTANCES,   // Physical armor (index 0 of the resistance array)
    UNIT_FIELD_STAT0,         // Strength (effective base, includes items)
    UNIT_FIELD_STAT1,         // Agility
    UNIT_FIELD_STAT2,         // Stamina
    UNIT_FIELD_STAT3,         // Intellect
    UNIT_FIELD_STAT4,         // Spirit
    UNIT_END,

    // Unit combat fields (WotLK: PRIVATE+OWNER — only visible for the player character)
    UNIT_FIELD_ATTACK_POWER,         // Melee attack power (int32)
    UNIT_FIELD_RANGED_ATTACK_POWER,  // Ranged attack power (int32)

    // Player fields
    PLAYER_FLAGS,
    PLAYER_BYTES,
    PLAYER_BYTES_2,
    PLAYER_XP,
    PLAYER_NEXT_LEVEL_XP,
    PLAYER_REST_STATE_EXPERIENCE,
    PLAYER_FIELD_COINAGE,
    PLAYER_QUEST_LOG_START,
    PLAYER_FIELD_INV_SLOT_HEAD,
    PLAYER_FIELD_PACK_SLOT_1,
    PLAYER_FIELD_KEYRING_SLOT_1,
    PLAYER_FIELD_BANK_SLOT_1,
    PLAYER_FIELD_BANKBAG_SLOT_1,
    PLAYER_SKILL_INFO_START,
    PLAYER_EXPLORED_ZONES_START,
    PLAYER_CHOSEN_TITLE,         // Active title index (-1 = no title)

    // Player spell power / healing bonus (WotLK: PRIVATE — int32 per school)
    PLAYER_FIELD_MOD_DAMAGE_DONE_POS,  // Spell damage bonus (first of 7 schools)
    PLAYER_FIELD_MOD_HEALING_DONE_POS, // Healing bonus

    // Player combat stats (WotLK: PRIVATE — float values)
    PLAYER_BLOCK_PERCENTAGE,         // Block chance %
    PLAYER_DODGE_PERCENTAGE,         // Dodge chance %
    PLAYER_PARRY_PERCENTAGE,         // Parry chance %
    PLAYER_CRIT_PERCENTAGE,          // Melee crit chance %
    PLAYER_RANGED_CRIT_PERCENTAGE,   // Ranged crit chance %
    PLAYER_SPELL_CRIT_PERCENTAGE1,   // Spell crit chance % (first school; 7 consecutive float fields)
    PLAYER_FIELD_COMBAT_RATING_1,    // First of 25 int32 combat rating slots (CR_* indices)

    // Player PvP currency (TBC/WotLK only — Classic uses the old weekly honor system)
    PLAYER_FIELD_HONOR_CURRENCY,     // Accumulated honor points (uint32)
    PLAYER_FIELD_ARENA_CURRENCY,     // Accumulated arena points (uint32)

    // GameObject fields
    GAMEOBJECT_DISPLAYID,
    GAMEOBJECT_BYTES_1,

    // Item fields
    ITEM_FIELD_STACK_COUNT,
    ITEM_FIELD_DURABILITY,
    ITEM_FIELD_MAXDURABILITY,

    // Container fields
    CONTAINER_FIELD_NUM_SLOTS,
    CONTAINER_FIELD_SLOT_1,

    COUNT
};

/**
 * Maps logical update field names to expansion-specific wire indices.
 * Loaded from JSON (e.g. Data/expansions/wotlk/update_fields.json).
 */
class UpdateFieldTable {
public:
    /** Load from JSON file. Returns true if successful. */
    bool loadFromJson(const std::string& path);

    /** Get the wire index for a logical field. Returns 0xFFFF if unknown. */
    uint16_t index(UF field) const;

    /** Override a wire index at runtime (used for auto-detecting custom field layouts). */
    void setIndex(UF field, uint16_t idx) { fieldMap_[static_cast<uint16_t>(field)] = idx; }

    /** Check if a field is mapped. */
    bool hasField(UF field) const;

    /** Number of mapped fields. */
    size_t size() const { return fieldMap_.size(); }

private:
    std::unordered_map<uint16_t, uint16_t> fieldMap_;  // UF enum → wire index
};

/**
 * Global active update field table (set by Application at startup).
 */
void setActiveUpdateFieldTable(const UpdateFieldTable* table);
const UpdateFieldTable* getActiveUpdateFieldTable();

/** Convenience: get wire index for a logical field. */
inline uint16_t fieldIndex(UF field) {
    const auto* t = getActiveUpdateFieldTable();
    return t ? t->index(field) : 0xFFFF;
}

} // namespace game
} // namespace wowee
