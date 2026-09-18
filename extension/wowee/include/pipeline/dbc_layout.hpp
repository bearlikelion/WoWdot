#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <unordered_map>

namespace wowee {
namespace pipeline {

/**
 * Maps DBC field names to column indices for a single DBC file.
 * Column indices vary between WoW expansions.
 */
struct DBCFieldMap {
    std::unordered_map<std::string, uint32_t> fields;

    /** Get column index by field name. Returns 0xFFFFFFFF if unknown. */
    uint32_t field(const std::string& name) const {
        auto it = fields.find(name);
        return (it != fields.end()) ? it->second : 0xFFFFFFFF;
    }

    /** Convenience operator for shorter syntax: layout["Name"] */
    uint32_t operator[](const std::string& name) const { return field(name); }
};

/**
 * Maps DBC file names to their field layouts.
 * Loaded from JSON (e.g. Data/expansions/wotlk/dbc_layouts.json).
 */
class DBCLayout {
public:
    /** Load from JSON file. Returns true if successful. */
    bool loadFromJson(const std::string& path);

    /** Get the field map for a DBC file. Returns nullptr if unknown. */
    const DBCFieldMap* getLayout(const std::string& dbcName) const;

    /** Number of DBC layouts loaded. */
    size_t size() const { return layouts_.size(); }

private:
    std::unordered_map<std::string, DBCFieldMap> layouts_;
};

/**
 * Global active DBC layout (set by Application at startup).
 */
void setActiveDBCLayout(const DBCLayout* layout);
const DBCLayout* getActiveDBCLayout();

/** Convenience: get field index for a DBC field. */
inline uint32_t dbcField(const std::string& dbcName, const std::string& fieldName) {
    const auto* l = getActiveDBCLayout();
    if (!l) return 0xFFFFFFFF;
    const auto* fm = l->getLayout(dbcName);
    return fm ? fm->field(fieldName) : 0xFFFFFFFF;
}

// Forward declaration
class DBCFile;

/**
 * Resolved CharSections.dbc field indices.
 *
 * Stock WotLK 3.3.5a uses: Texture1=4, Texture2=5, Texture3=6, Flags=7,
 *   VariationIndex=8, ColorIndex=9  (textures first).
 * Classic/TBC/Turtle and HD-texture WotLK use: VariationIndex=4, ColorIndex=5,
 *   Texture1=6, Texture2=7, Texture3=8, Flags=9  (variation first).
 *
 * detectCharSectionsFields() auto-detects which layout the actual DBC uses
 * by sampling field-4 values: small integers (0-15) => variation-first,
 * large values (string offsets) => texture-first.
 */
struct CharSectionsFields {
    uint32_t raceId         = 1;
    uint32_t sexId          = 2;
    uint32_t baseSection    = 3;
    uint32_t variationIndex = 4;
    uint32_t colorIndex     = 5;
    uint32_t texture1       = 6;
    uint32_t texture2       = 7;
    uint32_t texture3       = 8;
    uint32_t flags          = 9;
};

/**
 * Detect the actual CharSections.dbc field layout by probing record data.
 * @param dbc  Loaded CharSections.dbc file (must not be null).
 * @param csL  JSON-derived field map (may be null — defaults used).
 * @return Resolved field indices for this particular DBC binary.
 */
CharSectionsFields detectCharSectionsFields(const DBCFile* dbc, const DBCFieldMap* csL);

/**
 * Resolve the SpellItemEnchantment.dbc name (description) field index.
 *
 * The record grew across expansions, so the name sits at a different column in
 * each: Vanilla/Turtle=10, TBC=13, WotLK=14. Reading the wrong column yields an
 * integer that getString() treats as a string-block offset, which silently
 * produces a garbled name ("Rockbiter 3" read as "ockbiter 3") instead of failing.
 *
 * @param dbc  Loaded SpellItemEnchantment.dbc (must not be null).
 * @param sieL JSON-derived field map (may be null — field count decides).
 * @return Name field index for this particular DBC binary.
 */
uint32_t detectEnchantmentNameField(const DBCFile* dbc, const DBCFieldMap* sieL);

/**
 * Resolve the SpellItemEnchantment.dbc ItemVisual field index, which likewise
 * shifted with the record: Vanilla/Turtle=19, TBC=30, WotLK=31.
 */
uint32_t detectEnchantmentItemVisualField(const DBCFile* dbc, const DBCFieldMap* sieL);

/**
 * Model paths for the effect an enchant puts on the item it is applied to — the
 * glint on a freshly sharpened blade.
 *
 * Chain: SpellItemEnchantment.ItemVisual → ItemVisuals.dbc (5 effect slots) →
 * ItemVisualEffects.dbc (M2 path). Slot index is meaningful: it selects which
 * attachment point on the item model the effect hangs from, so gaps are kept.
 *
 * @return Per-slot model paths; empty strings for unused slots.
 */
std::array<std::string, 5> resolveEnchantItemVisuals(uint32_t enchantId,
                                                     const DBCFile* spellItemEnchantment,
                                                     const DBCFile* itemVisuals,
                                                     const DBCFile* itemVisualEffects,
                                                     const DBCFieldMap* sieL);

/**
 * The tail of that chain, entered directly with an ItemVisuals.dbc id.
 *
 * SMSG_CHAR_ENUM reports an equipped item's enchant as its ItemVisual id already,
 * so the character-select preview has no SpellItemEnchantment lookup to do.
 */
std::array<std::string, 5> resolveItemVisualModels(uint32_t itemVisualId,
                                                   const DBCFile* itemVisuals,
                                                   const DBCFile* itemVisualEffects);

} // namespace pipeline
} // namespace wowee
