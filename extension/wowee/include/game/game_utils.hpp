#pragma once

#include <cstdio>
#include <cstring>
#include <string>

// WoWGD rewrite: the client only speaks 1.12.1, so the expansion checks answer for classic.
namespace wowee {
namespace game {

inline bool isActiveExpansion(const char *expansionId) {
	return std::strcmp(expansionId, "classic") == 0;
}

inline bool isClassicLikeExpansion() {
	return true;
}

inline bool isPreWotlk() {
	return true;
}

inline std::string buildItemLink(uint32_t itemId, uint32_t quality, const std::string& name) {
    static const char* kQualHex[] = {
        "9d9d9d",  // 0 Poor
        "ffffff",  // 1 Common
        "1eff00",  // 2 Uncommon
        "0070dd",  // 3 Rare
        "a335ee",  // 4 Epic
        "ff8000",  // 5 Legendary
        "e6cc80",  // 6 Artifact
        "e6cc80",  // 7 Heirloom
    };
    uint32_t qi = quality < 8 ? quality : 1u;
    char buf[512];
    snprintf(buf, sizeof(buf), "|cff%s|Hitem:%u:0:0:0:0:0:0:0:0|h[%s]|h|r",
             kQualHex[qi], itemId, name.c_str());
    return buf;
}

} // namespace game
} // namespace wowee
