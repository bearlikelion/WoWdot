#!/usr/bin/env python3
"""Write data/wotlk/vehicle_skins.json from VehicleMenuBar.lua's SkinsData table.

Usage: tools/vehicle_skins.py <path to FrameXML/VehicleMenuBar.lua>

Each skin's numbered entries are its art layers, kept in order under "layers".
"""
import json
import pathlib
import re
import sys

# Globals the table reads, from GameTooltip.lua.
GLOBALS = {"TOOLTIP_DEFAULT_BACKGROUND_COLOR": {"r": "0.09", "g": "0.09", "b": "0.19"}}
TOKEN = re.compile(r'\[\[(.*?)\]\]|"((?:[^"\\]|\\.)*)"|(-?\d+(?:\.\d+)?)|([A-Za-z_]\w*)|(\S)', re.S)


def tokens(text):
    text = re.sub(r"--[^\n]*", "", text)
    for long_string, string, number, name, symbol in TOKEN.findall(text):
        if long_string or string:
            yield ("str", long_string or string)
        elif number:
            yield ("num", float(number) if "." in number else int(number))
        elif name:
            yield ("name", name)
        else:
            yield ("sym", symbol)


def parse_table(stream):
    named, listed, numbered = {}, [], {}
    while True:
        kind, value = next(stream)
        if kind == "sym" and value == "}":
            break
        if kind == "sym" and value in ",;":
            continue
        key = None
        if kind == "sym" and value == "[":
            key = next(stream)[1]
            next(stream)  # ]
            next(stream)  # =
            kind, value = next(stream)
        elif kind == "name":
            peek = next(stream)
            if peek == ("sym", "="):
                key = value
                kind, value = next(stream)
            else:
                raise SystemExit(f"unexpected {value} {peek}")
        item = parse_table(stream) if (kind, value) == ("sym", "{") else value
        if kind == "name":
            item = {"true": True, "false": False, "nil": None}.get(value, value)
        if key is None:
            listed.append(item)
        elif isinstance(key, int):
            numbered[key] = item
        else:
            named[key] = item
    listed += [numbered[index] for index in sorted(numbered)]
    if listed and not named:
        return listed
    if listed:
        named["layers"] = listed
    return named


def main():
    source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
    for name, fields in GLOBALS.items():
        for field, value in fields.items():
            source = source.replace(f"{name}.{field}", value)
    start = source.index("local SkinsData = {") + len("local SkinsData = ")
    stream = tokens(source[start:])
    next(stream)  # {
    skins = parse_table(stream)
    out = pathlib.Path(__file__).resolve().parent.parent / "data" / "wotlk" / "vehicle_skins.json"
    out.write_text(json.dumps(skins, indent=1) + "\n", encoding="utf-8")
    print("wrote", out, "with", ", ".join(skins))


if __name__ == "__main__":
    main()
