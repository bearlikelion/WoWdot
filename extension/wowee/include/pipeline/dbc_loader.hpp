#pragma once

#include <vector>
#include <unordered_map>
#include <string>
#include <string_view>
#include <cstdint>
#include <memory>

#include "pipeline/dbc_layout.hpp"

namespace wowee {
namespace pipeline {

/**
 * DBC File - WoW Database Client file
 *
 * DBC files store game database tables (spells, items, maps, creatures, etc.)
 * Format: Fixed header + fixed-size records + string block
 * Format specification: https://wowdev.wiki/DBC
 */
class DBCFile {
public:
    DBCFile();
    ~DBCFile();

    /**
     * Load DBC file from byte data
     * @param dbcData Raw DBC file data
     * @return true if loaded successfully
     */
    [[nodiscard]] bool load(const std::vector<uint8_t>& dbcData);

    /**
     * Check if DBC is loaded
     */
    bool isLoaded() const { return loaded; }

    /**
     * Get record count
     */
    uint32_t getRecordCount() const { return recordCount; }

    /**
     * Get field count (number of 32-bit fields per record)
     */
    uint32_t getFieldCount() const { return fieldCount; }

    /**
     * Get record size in bytes
     */
    uint32_t getRecordSize() const { return recordSize; }

    /**
     * Get string block size
     */
    uint32_t getStringBlockSize() const { return stringBlockSize; }

    /**
     * Get a record by index
     * @param index Record index (0 to recordCount-1)
     * @return Pointer to record data (recordSize bytes) or nullptr
     */
    const uint8_t* getRecord(uint32_t index) const;

    /**
     * Get a 32-bit integer field from a record
     * @param recordIndex Record index
     * @param fieldIndex Field index (0 to fieldCount-1)
     * @return Field value
     */
    uint32_t getUInt32(uint32_t recordIndex, uint32_t fieldIndex) const;

    /**
     * Get a 32-bit signed integer field from a record
     * @param recordIndex Record index
     * @param fieldIndex Field index
     * @return Field value
     */
    int32_t getInt32(uint32_t recordIndex, uint32_t fieldIndex) const;

    /**
     * Get a float field from a record
     * @param recordIndex Record index
     * @param fieldIndex Field index
     * @return Field value
     */
    float getFloat(uint32_t recordIndex, uint32_t fieldIndex) const;

    /**
     * Get a string field from a record
     * @param recordIndex Record index
     * @param fieldIndex Field index (contains string offset)
     * @return String value
     */
    std::string getString(uint32_t recordIndex, uint32_t fieldIndex) const;

    /**
     * Get a string field as a view (no allocation; valid while this DBCFile lives)
     */
    std::string_view getStringView(uint32_t recordIndex, uint32_t fieldIndex) const;

    /**
     * Get string by offset in string block
     * @param offset Offset into string block
     * @return String value
     */
    std::string getStringByOffset(uint32_t offset) const;

    /**
     * Get string by offset as a view (no allocation; valid while this DBCFile lives)
     */
    std::string_view getStringViewByOffset(uint32_t offset) const;

    /**
     * Find a record by ID (assumes first field is ID)
     * @param id Record ID to find
     * @return Record index or -1 if not found
     */
    int32_t findRecordById(uint32_t id) const;

private:
    // DBC file header (20 bytes)
    struct DBCHeader {
        char magic[4];              // 'WDBC'
        uint32_t recordCount;       // Number of records
        uint32_t fieldCount;        // Number of fields per record
        uint32_t recordSize;        // Size of each record in bytes
        uint32_t stringBlockSize;   // Size of string block
    };

    bool loaded = false;
    uint32_t recordCount = 0;
    uint32_t fieldCount = 0;
    uint32_t recordSize = 0;
    uint32_t stringBlockSize = 0;

    std::vector<uint8_t> recordData;    // All record data
    std::vector<uint8_t> stringBlock;   // String block

    // Cache for record ID -> index lookup
    mutable std::unordered_map<uint32_t, uint32_t> idToIndexCache;
    mutable bool idCacheBuilt = false;

    void buildIdCache() const;

    /**
     * Load from CSV text format (produced by dbc_to_csv tool).
     * Rebuilds the same in-memory layout as binary load.
     */
    bool loadCSV(const std::vector<uint8_t>& csvData);

    bool loadJSON(const std::vector<uint8_t>& jsonData);
};

/**
 * Build the 8-element texture region field index array for ItemDisplayInfo.dbc.
 * Classic/Turtle 23-field DBCs have textures at 14-21;
 * TBC/WotLK 25-field DBCs have textures at 15-22.
 * Detects automatically from the loaded DBC's field count.
 */
inline void getItemDisplayInfoTextureFields(const DBCFile& dbc,
    const DBCFieldMap* layout,
    uint32_t (&out)[8])
{
    // 25-field DBCs (TBC/WotLK) shift textures +1 vs 23-field (Classic/Turtle)
    uint32_t base = (dbc.getFieldCount() >= 25) ? 15u : 14u;
    if (layout) {
        uint32_t idx = layout->field("TextureArmUpper");
        if (idx != 0xFFFFFFFF) {
            base = idx;
            // Correct JSON layouts written for 23-field when DBC is actually 25-field
            if (base == 14 && dbc.getFieldCount() >= 25) base = 15;
        }
    }
    for (int i = 0; i < 8; i++) out[i] = base + static_cast<uint32_t>(i);
}

} // namespace pipeline
} // namespace wowee
