#include "game/character.hpp"
#include "game/expansion_profile.hpp"
#include <unordered_map>
#include <string>

namespace wowee {
namespace game {

namespace {
std::unordered_map<uint32_t, std::string> g_raceNames, g_classNames, g_raceModels;
bool g_openRaceClass = false;
}

void setProfileOverrides(const ExpansionProfile& profile) {
    g_raceNames = profile.raceNames;
    g_classNames = profile.classNames;
    g_raceModels = profile.raceModels;
    g_openRaceClass = profile.openRaceClass;
}

bool hasRaceModelOverride(Race race) {
    return g_raceModels.count(static_cast<uint32_t>(race)) != 0;
}

bool isValidRaceClassCombo(Race race, Class cls) {
    if (g_openRaceClass && g_raceModels.count(static_cast<uint32_t>(race))) return true;
    // WoW 3.3.5a valid race/class combinations
    switch (race) {
        case Race::HUMAN:
            return cls == Class::WARRIOR || cls == Class::PALADIN || cls == Class::ROGUE ||
                   cls == Class::PRIEST || cls == Class::MAGE || cls == Class::WARLOCK ||
                   cls == Class::DEATH_KNIGHT;
        case Race::ORC:
            return cls == Class::WARRIOR || cls == Class::HUNTER || cls == Class::ROGUE ||
                   cls == Class::SHAMAN || cls == Class::WARLOCK || cls == Class::DEATH_KNIGHT;
        case Race::DWARF:
            return cls == Class::WARRIOR || cls == Class::PALADIN || cls == Class::HUNTER ||
                   cls == Class::ROGUE || cls == Class::PRIEST || cls == Class::DEATH_KNIGHT;
        case Race::NIGHT_ELF:
            return cls == Class::WARRIOR || cls == Class::HUNTER || cls == Class::ROGUE ||
                   cls == Class::PRIEST || cls == Class::DRUID || cls == Class::DEATH_KNIGHT;
        case Race::UNDEAD:
            return cls == Class::WARRIOR || cls == Class::ROGUE || cls == Class::PRIEST ||
                   cls == Class::MAGE || cls == Class::WARLOCK || cls == Class::DEATH_KNIGHT;
        case Race::TAUREN:
            return cls == Class::WARRIOR || cls == Class::HUNTER || cls == Class::DRUID ||
                   cls == Class::SHAMAN || cls == Class::DEATH_KNIGHT;
        case Race::GNOME:
            return cls == Class::WARRIOR || cls == Class::ROGUE || cls == Class::MAGE ||
                   cls == Class::WARLOCK || cls == Class::DEATH_KNIGHT;
        case Race::TROLL:
            return cls == Class::WARRIOR || cls == Class::HUNTER || cls == Class::ROGUE ||
                   cls == Class::PRIEST || cls == Class::SHAMAN || cls == Class::MAGE ||
                   cls == Class::DEATH_KNIGHT;
        case Race::BLOOD_ELF:
            return cls == Class::PALADIN || cls == Class::HUNTER || cls == Class::ROGUE ||
                   cls == Class::PRIEST || cls == Class::MAGE || cls == Class::WARLOCK ||
                   cls == Class::DEATH_KNIGHT;
        case Race::DRAENEI:
            return cls == Class::WARRIOR || cls == Class::PALADIN || cls == Class::HUNTER ||
                   cls == Class::PRIEST || cls == Class::SHAMAN || cls == Class::MAGE ||
                   cls == Class::DEATH_KNIGHT;
        default:
            return false;
    }
}

uint8_t getMaxSkin(Race /*race*/, Gender /*gender*/) { return 9; }
uint8_t getMaxFace(Race /*race*/, Gender /*gender*/) { return 9; }
uint8_t getMaxHairStyle(Race /*race*/, Gender /*gender*/) { return 11; }
uint8_t getMaxHairColor(Race /*race*/, Gender /*gender*/) { return 9; }
uint8_t getMaxFacialFeature(Race /*race*/, Gender /*gender*/) { return 8; }

const char* getRaceName(Race race) {
    if (auto it = g_raceNames.find(static_cast<uint32_t>(race)); it != g_raceNames.end()) return it->second.c_str();
    switch (race) {
        case Race::HUMAN:       return "Human";
        case Race::ORC:         return "Orc";
        case Race::DWARF:       return "Dwarf";
        case Race::NIGHT_ELF:   return "Night Elf";
        case Race::UNDEAD:      return "Undead";
        case Race::TAUREN:      return "Tauren";
        case Race::GNOME:       return "Gnome";
        case Race::TROLL:       return "Troll";
        case Race::GOBLIN:      return "Goblin";
        case Race::BLOOD_ELF:   return "Blood Elf";
        case Race::DRAENEI:     return "Draenei";
        default:                return "Unknown";
    }
}

const char* getClassName(Class characterClass) {
    if (auto it = g_classNames.find(static_cast<uint32_t>(characterClass)); it != g_classNames.end()) return it->second.c_str();
    switch (characterClass) {
        case Class::WARRIOR:        return "Warrior";
        case Class::PALADIN:        return "Paladin";
        case Class::HUNTER:         return "Hunter";
        case Class::ROGUE:          return "Rogue";
        case Class::PRIEST:         return "Priest";
        case Class::DEATH_KNIGHT:   return "Death Knight";
        case Class::SHAMAN:         return "Shaman";
        case Class::MAGE:           return "Mage";
        case Class::WARLOCK:        return "Warlock";
        case Class::DRUID:          return "Druid";
        default:                    return "Unknown";
    }
}

const char* getGenderName(Gender gender) {
    switch (gender) {
        case Gender::MALE:      return "Male";
        case Gender::FEMALE:    return "Female";
        case Gender::NONBINARY: return "Nonbinary";
        default:                return "Unknown";
    }
}

std::string getPlayerModelPath(Race race, Gender gender, bool useFemaleModel) {
    if (auto it = g_raceModels.find(static_cast<uint32_t>(race)); it != g_raceModels.end()) return it->second;
    // Female always uses female model
    // Nonbinary uses chosen model (useFemaleModel parameter)
    // Male always uses male model
    bool useFemale = (gender == Gender::FEMALE) ||
                     (gender == Gender::NONBINARY && useFemaleModel);

    switch (race) {
        case Race::HUMAN:
            return useFemale
                ? "Character\\Human\\Female\\HumanFemale.m2"
                : "Character\\Human\\Male\\HumanMale.m2";
        case Race::ORC:
            return useFemale
                ? "Character\\Orc\\Female\\OrcFemale.m2"
                : "Character\\Orc\\Male\\OrcMale.m2";
        case Race::DWARF:
            return useFemale
                ? "Character\\Dwarf\\Female\\DwarfFemale.m2"
                : "Character\\Dwarf\\Male\\DwarfMale.m2";
        case Race::NIGHT_ELF:
            return useFemale
                ? "Character\\NightElf\\Female\\NightElfFemale.m2"
                : "Character\\NightElf\\Male\\NightElfMale.m2";
        case Race::UNDEAD:
            return useFemale
                ? "Character\\Scourge\\Female\\ScourgeFemale.m2"
                : "Character\\Scourge\\Male\\ScourgeMale.m2";
        case Race::TAUREN:
            return useFemale
                ? "Character\\Tauren\\Female\\TaurenFemale.m2"
                : "Character\\Tauren\\Male\\TaurenMale.m2";
        case Race::GNOME:
            return useFemale
                ? "Character\\Gnome\\Female\\GnomeFemale.m2"
                : "Character\\Gnome\\Male\\GnomeMale.m2";
        case Race::TROLL:
            return useFemale
                ? "Character\\Troll\\Female\\TrollFemale.m2"
                : "Character\\Troll\\Male\\TrollMale.m2";
        case Race::BLOOD_ELF:
            return useFemale
                ? "Character\\BloodElf\\Female\\BloodElfFemale.m2"
                : "Character\\BloodElf\\Male\\BloodElfMale.m2";
        case Race::DRAENEI:
            return useFemale
                ? "Character\\Draenei\\Female\\DraeneiFemale.m2"
                : "Character\\Draenei\\Male\\DraeneiMale.m2";
        default:
            return "Character\\Human\\Male\\HumanMale.m2";
    }
}

std::string knightModelVariant(Race race, const std::string& modelPath, uint8_t face) {
    if (!hasRaceModelOverride(race) || face == 0) return modelPath;
    const int body = face % kKnightBodies;
    if (body == 0) return modelPath;
    const auto dot = modelPath.rfind('.');
    if (dot == std::string::npos) return modelPath;
    return modelPath.substr(0, dot) + "_b" + std::to_string(body + 1) + modelPath.substr(dot);
}

std::string knightSkinTexture(uint8_t skin) {
    const int palette = skin % kKnightSkins;
    return palette == 0 ? std::string{} : "character/mwow/knights_skin" + std::to_string(palette) + ".png";
}

std::string getPlayerModelPath(const Character& character) {
    return getPlayerModelPath(character.race, character.gender, character.useFemaleModel);
}

} // namespace game
} // namespace wowee
