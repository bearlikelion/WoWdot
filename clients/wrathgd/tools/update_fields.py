#!/usr/bin/env python3
"""Write data/wotlk/update_fields.json from AzerothCore's UpdateFields.h.

Usage: tools/update_fields.py <path to UpdateFields.h> [--write]

The names come from the classic table, since those are what the game code asks for. A name
WotLK renamed is listed in ALIASES; a name it removed is reported and left out.
"""
import json
import pathlib
import re
import sys

# 3.3.5a renames, classic name -> AzerothCore name.
ALIASES = {
    "GAMEOBJECT_ROTATION": "GAMEOBJECT_PARENTROTATION",
    "GAMEOBJECT_DYN_FLAGS": "GAMEOBJECT_DYNAMIC",
    "PLAYER_QUEST_LOG_START": "PLAYER_QUEST_LOG_1_1",
    "PLAYER_SKILL_INFO_START": "PLAYER_SKILL_INFO_1_1",
    "PLAYER_EXPLORED_ZONES_START": "PLAYER_EXPLORED_ZONES_1",
    "ITEM_FIELD_ENCHANTMENT": "ITEM_FIELD_ENCHANTMENT_1_1",
    "UNIT_FIELD_TARGET_LO": "UNIT_FIELD_TARGET",
    "PLAYER_FIELD_LIFETIME_HONORBALE_KILLS": "PLAYER_FIELD_LIFETIME_HONORABLE_KILLS",
    "PLAYER_FIELD_RESISTANCEBUFFMODSPOSITIVE": "UNIT_FIELD_RESISTANCEBUFFMODSPOSITIVE",
    "PLAYER_FIELD_RESISTANCEBUFFMODSNEGATIVE": "UNIT_FIELD_RESISTANCEBUFFMODSNEGATIVE",
}
# The stat buff mods moved from the player block to the unit block.
for stat in range(5):
    ALIASES["PLAYER_FIELD_POSSTAT%d" % stat] = "UNIT_FIELD_POSSTAT%d" % stat
    ALIASES["PLAYER_FIELD_NEGSTAT%d" % stat] = "UNIT_FIELD_NEGSTAT%d" % stat
# A visible item slot keeps two fields instead of twelve, of which only the entry id survives.
for slot in range(1, 20):
    ALIASES["PLAYER_VISIBLE_ITEM_%d_0" % slot] = "PLAYER_VISIBLE_ITEM_%d_ENTRYID" % slot

# Names whose WotLK field sits one index past another, since the header only declares the first.
OFFSETS = {"UNIT_FIELD_TARGET_HI": ("UNIT_FIELD_TARGET", 1)}

# Fields the game code asks for that vanilla never had.
EXTRA = {
    "PLAYER_CHOSEN_TITLE",
    "PLAYER_FIELD_ARENA_CURRENCY",
    "PLAYER_FIELD_HONOR_CURRENCY",
    "PLAYER_FIELD_MOD_HEALING_DONE_POS",
    "PLAYER_SPELL_CRIT_PERCENTAGE1",
    "UNIT_FIELD_FLAGS_2",
    "UNIT_VIRTUAL_ITEM_SLOT_ID",
    "PLAYER_FIELD_GLYPH_SLOTS_1",
    "PLAYER_FIELD_GLYPHS_1",
    "PLAYER_GLYPHS_ENABLED",
    "PLAYER__FIELD_KNOWN_TITLES",
    "PLAYER_FIELD_KILLS",
    "PLAYER_FIELD_TODAY_CONTRIBUTION",
    "PLAYER_FIELD_ARENA_TEAM_INFO_1_1",
}

ENTRY = re.compile(r"^\s*([A-Z][A-Z0-9_]+)\s*=\s*([^,]+),", re.MULTILINE)


def parse(header: pathlib.Path) -> dict[str, int]:
    values: dict[str, int] = {}
    for name, expression in ENTRY.findall(header.read_text()):
        total = 0
        for term in expression.split("+"):
            term = term.strip()
            if term.startswith("0x") or term.isdigit():
                total += int(term, 0)
            elif term in values:
                total += values[term]
            else:
                total = None
                break
        if total is not None:
            values[name] = total
    return values


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    header = pathlib.Path(sys.argv[1])
    root = pathlib.Path(__file__).resolve().parent.parent
    out = root / "data/wotlk/update_fields.json"
    wanted = set(json.loads((root.parent / "wowgd/data/classic/update_fields.json").read_text()))
    wanted |= EXTRA
    values = parse(header)
    table: dict[str, int] = {}
    absent: list[str] = []
    for name in sorted(wanted):
        source = ALIASES.get(name, name)
        if source in values:
            table[name] = values[source]
        elif name in OFFSETS and OFFSETS[name][0] in values:
            table[name] = values[OFFSETS[name][0]] + OFFSETS[name][1]
        else:
            absent.append(name)
    print("resolved %d of %d names, %d absent in WotLK" % (len(table), len(wanted), len(absent)))
    print("absent:", ", ".join(absent))
    if "--write" in sys.argv:
        out.write_text(json.dumps(table, indent=1, sort_keys=True) + "\n")
        print("wrote", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
