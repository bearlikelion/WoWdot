#!/usr/bin/env python3
"""Collect the PlaySound names of stock frames into data/classic/ui_sounds.json.

Usage: sounds.py <dump dir from dump.gd> <project dir>

Maps a frame's global name to its click, show and hide sounds, following templates and two calls
into the Lua. WowAudio hooks nodes of the same name at runtime, so scenes need no regeneration.
"""

import json
import re
import sys
from pathlib import Path

from convert import FRAME_TAGS, Library, child, strip

EVENTS = {"OnClick": "click", "OnShow": "show", "OnHide": "hide"}
PLAY_SOUND = re.compile(r'PlaySound\("([^"]+)"\)')
CALL = re.compile(r"\b([A-Za-z_]\w*)\s*\(")
FUNCTION = re.compile(r"^function\s+(\w+)\s*\([^)]*\)(.*?)^end", re.M | re.S)


def lua_functions(dump):
    functions = {}
    for path in Path(dump).glob("Interface/**/*.lua"):
        text = path.read_bytes().decode("utf-8", "replace").replace("\r", "")
        for match in FUNCTION.finditer(text):
            functions.setdefault(match.group(1), match.group(2))
    return functions


def sound_of(script, functions, depth=2):
    found = PLAY_SOUND.search(script)
    if found:
        return found.group(1)
    for call in CALL.findall(script) if depth else []:
        sound = sound_of(functions.get(call, ""), functions, depth - 1)
        if sound:
            return sound
    return None


def chain(library, node):
    """The element, then its templates, nearest first."""
    nodes = [node]
    for name in (node.get("inherits") or "").split(","):
        template = library.elements.get(name.strip())
        if template is not None:
            nodes += chain(library, template)
    return nodes


def visit(library, functions, node, parent, out):
    name = (node.get("name") or "").replace("$parent", parent)
    nodes = chain(library, node)
    sounds = {}
    for source in nodes:
        scripts = child(source, "Scripts")
        for script in scripts if scripts is not None else []:
            event = EVENTS.get(strip(script.tag))
            sound = sound_of(script.text or "", functions) if event else None
            if sound:
                sounds.setdefault(event, sound)
    if name and sounds and node.get("virtual") != "true":
        out[name] = sounds
    for source in nodes:
        frames = child(source, "Frames")
        for frame in frames if frames is not None else []:
            if strip(frame.tag) in FRAME_TAGS:
                visit(library, functions, frame, name or parent, out)


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    dump, project = sys.argv[1], Path(sys.argv[2])
    config = Path(__file__).with_name("frames.json")
    extra = [config.parent / p for p in json.loads(config.read_text()).get("xml", [])]
    library = Library(dump, extra)
    functions = lua_functions(dump)
    out = {}
    for name, node in library.elements.items():
        if strip(node.tag) in FRAME_TAGS and node.get("virtual") != "true":
            visit(library, functions, node, "", out)
    target = project / "data/classic/ui_sounds.json"
    target.write_text(json.dumps(out, indent="\t", sort_keys=True) + "\n")
    print(f"wrote {len(out)} frames to {target}")


if __name__ == "__main__":
    main()
