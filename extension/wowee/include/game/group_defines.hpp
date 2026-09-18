#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace wowee {
namespace game {

/**
 * Party/Group member data
 */
struct GroupMember {
    std::string name;
    uint64_t guid = 0;
    uint8_t isOnline = 0;      // 0 = offline, 1 = online
    uint8_t subGroup = 0;      // Raid subgroup (0 for party)
    uint8_t flags = 0;         // Assistant, main tank, etc.
    uint8_t roles = 0;         // LFG roles (3.3.5a)

    // Party member stats (from SMSG_PARTY_MEMBER_STATS)
    uint32_t curHealth = 0;
    uint32_t maxHealth = 0;
    uint8_t powerType = 0;
    uint16_t curPower = 0;
    uint16_t maxPower = 0;
    uint16_t level = 0;
    uint16_t zoneId = 0;
    int16_t posX = 0;
    int16_t posY = 0;
    uint16_t onlineStatus = 0;   // GROUP_UPDATE_FLAG_STATUS bitmask
    bool hasPartyStats = false;  // true once we've received stats
};

/**
 * Full group/party data from SMSG_GROUP_LIST
 */
struct GroupListData {
    uint8_t groupType = 0;       // 0 = party, 1 = raid
    uint8_t subGroup = 0;
    uint8_t flags = 0;
    uint8_t roles = 0;
    uint8_t lootMethod = 0;      // 0=free for all, 1=round robin, 2=master loot
    uint64_t looterGuid = 0;
    uint8_t lootThreshold = 0;
    uint8_t difficultyId = 0;
    uint8_t raidDifficultyId = 0;
    uint32_t memberCount = 0;
    std::vector<GroupMember> members;
    uint64_t leaderGuid = 0;

    bool isValid() const { return true; }
    bool isEmpty() const { return memberCount == 0; }
};

/**
 * Party command types
 */
enum class PartyCommand : uint32_t {
    INVITE = 0,
    UNINVITE = 1,
    LEAVE = 2,
    SWAP = 3
};

/**
 * Party command result codes
 */
enum class PartyResult : uint32_t {
    OK = 0,
    BAD_PLAYER_NAME = 1,
    TARGET_NOT_IN_GROUP = 2,
    TARGET_NOT_IN_INSTANCE = 3,
    GROUP_FULL = 4,
    ALREADY_IN_GROUP = 5,
    NOT_IN_GROUP = 6,
    NOT_LEADER = 7,
    PLAYER_WRONG_FACTION = 8,
    IGNORING_YOU = 9,
    LFG_PENDING = 12,
    INVITE_RESTRICTED = 13
};

} // namespace game
} // namespace wowee
