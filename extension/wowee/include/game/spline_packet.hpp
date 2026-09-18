// include/game/spline_packet.hpp
// Consolidated spline packet parsing — replaces 7 duplicated parsing locations.
#pragma once
#include "network/packet.hpp"
#include <glm/glm.hpp>
#include <vector>
#include <cstdint>

namespace wowee::game {

/// Decoded spline data from a movement or MonsterMove packet.
struct SplineBlockData {
    uint32_t splineFlags = 0;
    uint32_t duration = 0;

    // Animation (splineFlag 0x00400000)
    bool     hasAnimation = false;
    uint8_t  animationType = 0;
    uint32_t animationStartTime = 0;

    // Parabolic (splineFlag 0x00000800 for MonsterMove, 0x00000008 for MoveUpdate)
    bool     hasParabolic = false;
    float    verticalAcceleration = 0.0f;
    uint32_t parabolicStartTime = 0;

    // FINAL_POINT / FINAL_TARGET / FINAL_ANGLE (movement update only)
    bool     hasFinalPoint = false;
    glm::vec3 finalPoint{0};
    bool     hasFinalTarget = false;
    uint64_t finalTarget = 0;
    bool     hasFinalAngle = false;
    float    finalAngle = 0.0f;

    // Timing (movement update only)
    uint32_t timePassed = 0;
    uint32_t splineId = 0;

    // Waypoints (server coordinates, decoded from packed-delta if compressed)
    std::vector<glm::vec3> waypoints;
    glm::vec3 destination{0};
    bool hasDest = false;

    // SplineMode (movement update WotLK only)
    uint8_t splineMode = 0;
    glm::vec3 endPoint{0};
    bool hasEndPoint = false;
};

// ── Spline flag constants ───────────────────────────────────────
namespace SplineFlag {
    // Classic/TBC ground locomotion for SMSG_MONSTER_MOVE: set means Run,
    // clear means Walk. WotLK repurposed this bit as DONE and sends separate
    // SET_WALK_MODE / SET_RUN_MODE opcodes instead.
    constexpr uint32_t PRE_WOTLK_RUNMODE = 0x00000100;
    constexpr uint32_t FINAL_POINT    = 0x00010000;
    constexpr uint32_t FINAL_TARGET   = 0x00020000;
    constexpr uint32_t FINAL_ANGLE    = 0x00040000;
    constexpr uint32_t CATMULLROM     = 0x00080000; // Uncompressed Catmull-Rom
    constexpr uint32_t CYCLIC         = 0x00100000; // Cyclic path
    constexpr uint32_t ENTER_CYCLE    = 0x00200000; // Entering cyclic path
    constexpr uint32_t ANIMATION      = 0x00400000; // Animation spline
    constexpr uint32_t PARABOLIC_MM   = 0x00000800; // Parabolic in MonsterMove
    constexpr uint32_t PARABOLIC_MU   = 0x00000008; // Parabolic in MoveUpdate

    // Mask: if any of these are set, waypoints are uncompressed
    constexpr uint32_t UNCOMPRESSED_MASK = CATMULLROM | CYCLIC | ENTER_CYCLE;
    // TBC-era alternative for uncompressed check
    constexpr uint32_t UNCOMPRESSED_MASK_TBC = CATMULLROM | 0x00002000;
} // namespace SplineFlag

[[nodiscard]] constexpr bool isPreWotlkSplineWalking(uint32_t splineFlags) {
    return (splineFlags & SplineFlag::PRE_WOTLK_RUNMODE) == 0;
}

/// Decode a single packed-delta waypoint.
/// Format: bits [0:10] = X (11-bit signed), [11:21] = Y (11-bit signed), [22:31] = Z (10-bit signed).
/// Each component is multiplied by 0.25 and subtracted from `midpoint`.
[[nodiscard]] glm::vec3 decodePackedDelta(uint32_t packed, const glm::vec3& midpoint);

/// Parse a MonsterMove spline body (after splineFlags has already been read).
/// Handles: Animation, duration, Parabolic, pointCount, compressed/uncompressed waypoints.
/// `startPos` is the creature's current position (needed for packed-delta midpoint calculation).
/// `splineFlags` is the already-read spline flags value.
/// `useTbcUncompressedMask`: if true, use 0x00080000|0x00002000 for uncompressed check (TBC format).
[[nodiscard]] bool parseMonsterMoveSplineBody(
    network::Packet& packet,
    SplineBlockData& out,
    uint32_t splineFlags,
    const glm::vec3& startPos,
    bool useTbcUncompressedMask = false);

/// Parse a MonsterMove spline body where waypoints are always compressed (Vanilla format).
/// `startPos` is the creature's current position.
[[nodiscard]] bool parseMonsterMoveSplineBodyVanilla(
    network::Packet& packet,
    SplineBlockData& out,
    uint32_t splineFlags,
    const glm::vec3& startPos);

/// Parse a Classic/Turtle movement update spline block.
/// Format: splineFlags, FINAL_POINT/TARGET/ANGLE, timePassed, duration, splineId,
/// pointCount, uncompressed waypoints (12 bytes each), endPoint (no splineMode).
[[nodiscard]] bool parseClassicMoveUpdateSpline(
    network::Packet& packet,
    SplineBlockData& out);

/// Parse a WotLK movement update spline block.
/// Format: splineFlags, FINAL_POINT/TARGET/ANGLE, timePassed, duration, splineId,
/// then WotLK header (durationMod, durationModNext, [Animation], [Parabolic],
/// pointCount, splineMode, endPoint) with multi-strategy fallback.
[[nodiscard]] bool parseWotlkMoveUpdateSpline(
    network::Packet& packet,
    SplineBlockData& out,
    const glm::vec3& entityPos = glm::vec3(0));

} // namespace wowee::game
