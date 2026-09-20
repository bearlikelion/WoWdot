#!/usr/bin/env python3
"""Convert stock FrameXML frames into Godot scenes that draw with WowTexture.

Usage: convert.py <dump dir from dump.gd> <project dir> [frames.json] [frame name ...]

Layout, textures and fonts come from the XML; behaviour stays in the GDScript named in frames.json.
Generated scenes only hold archive paths and coordinates, never Blizzard pixels.
"""

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

POINTS = {
    "TOPLEFT": (0.0, 0.0), "TOP": (0.5, 0.0), "TOPRIGHT": (1.0, 0.0),
    "LEFT": (0.0, 0.5), "CENTER": (0.5, 0.5), "RIGHT": (1.0, 0.5),
    "BOTTOMLEFT": (0.0, 1.0), "BOTTOM": (0.5, 1.0), "BOTTOMRIGHT": (1.0, 1.0),
}
LAYERS = ["BACKGROUND", "BORDER", "ARTWORK", "OVERLAY", "HIGHLIGHT"]
BUTTON_TEXTURES = ["NormalTexture", "PushedTexture", "DisabledTexture", "CheckedTexture",
                   "DisabledCheckedTexture", "HighlightTexture"]
# Where each button state texture draws among the frame's layers.
BUTTON_TEXTURE_LAYER = {
    "NormalTexture": "BORDER", "PushedTexture": "BORDER", "DisabledTexture": "BORDER",
    "CheckedTexture": "OVERLAY", "DisabledCheckedTexture": "OVERLAY", "HighlightTexture": "HIGHLIGHT",
}
FRAME_TAGS = {"Frame", "Button", "CheckButton", "StatusBar", "EditBox", "ScrollFrame", "Slider",
              "Model", "ModelFFX", "PlayerModel", "DressUpModel", "TabardModel", "MessageFrame",
              "ScrollingMessageFrame", "SimpleHTML", "ColorSelect", "GameTooltip", "Minimap",
              "Cooldown", "LootButton", "MovieFrame", "WorldFrame"}
REGION_TAGS = {"Texture", "FontString"}
# Blizzard font names that are also Godot class names, which a theme variation cannot be.
RENAMED_FONTS = {"SystemFont": "WowSystemFont"}
WOW_BUTTON = "res://game/ui/wow/wow_button.gd"
WOW_BACKDROP = "res://game/ui/wow/wow_backdrop.gd"
WOW_MESSAGE_FRAME = "res://game/ui/wow/wow_message_frame.gd"
WOW_SCROLLING_MESSAGE_FRAME = "res://game/ui/wow/wow_scrolling_message_frame.gd"
WOW_MODEL_FRAME = "res://game/ui/wow/wow_model_frame.tscn"
WOW_SCROLL_FRAME = "res://game/ui/wow/wow_scroll_frame.gd"
# Frames that show a 3D scene; plain Models are cooldown spirals and sparkles drawn another way.
MODEL_TAGS = {"ModelFFX", "PlayerModel", "DressUpModel", "TabardModel"}
# Two root sizes the layout is solved at; how an edge moves between them gives its Godot anchor.
LAYOUT_STRETCH = 2.0
# The glue screens are laid out on the stock 1024x768 screen.
SCREEN_SIZE = (1024.0, 768.0)
FULL_RECT = [("layout_mode", "1"), ("anchors_preset", "15"), ("anchor_right", "1.0"), ("anchor_bottom", "1.0")]
# Kinds that draw content of their own, which their BACKGROUND and BORDER layers must sit under.
SELF_DRAWING = {"LineEdit", "TextureProgressBar"}


def strip(tag):
    return tag.split("}", 1)[-1]


def fnum(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def dimension(node):
    """(x, y) from <Size>/<Offset> in either the attribute or the AbsDimension form."""
    if node is None:
        return None
    if "x" in node.attrib or "y" in node.attrib:
        return fnum(node.get("x")), fnum(node.get("y"))
    for child in node:
        if strip(child.tag) == "AbsDimension":
            return fnum(child.get("x")), fnum(child.get("y"))
    return None


def value(node):
    if node is None:
        return None
    for child in node:
        if strip(child.tag) == "AbsValue":
            return fnum(child.get("val"))
    return None


def color(node):
    if node is None:
        return None
    return (fnum(node.get("r"), 1.0), fnum(node.get("g"), 1.0), fnum(node.get("b"), 1.0),
            fnum(node.get("a"), 1.0))


def child(node, tag):
    for c in node:
        if strip(c.tag) == tag:
            return c
    return None


class Library:
    """Every named element across the dumped XML, plus fonts and global strings."""

    def __init__(self, dump, extra=()):
        self.dump = Path(dump)
        self.extra = [Path(p) for p in extra]
        self.elements = {}
        self.fonts = {}
        # Top-level frames that name another frame as parent="...", in load order.
        self.parented = {}
        for path in self._load_order():
            text = path.read_bytes().decode("utf-8", "replace").replace("\r", "")
            text = re.sub(r"<\?xml[^>]*\?>", "", text)
            try:
                root = ET.fromstring(text)
            except ET.ParseError as error:
                print(f"skipping {path.name}: {error}", file=sys.stderr)
                continue
            self._index(root)
        self.textures = {k: tuple(v) for k, v in json.loads((self.dump / "textures.json").read_text()).items()}
        self.strings = {}
        for strings in (self.dump / "Interface/FrameXML/GlobalStrings.lua", self.dump / "Interface/GlueXML/GlueStrings.lua"):
            if strings.exists():
                for m in re.finditer(r'^(\w+)\s*=\s*"((?:[^"\\]|\\.)*)";', strings.read_text("utf-8", "replace"), re.M):
                    self.strings.setdefault(m.group(1), m.group(2).replace('\\"', '"').replace("\\n", "\n"))

    def _load_order(self):
        """FrameXML files in FrameXML.toc order, then everything else."""
        frame_xml = self.dump / "Interface/FrameXML"
        ordered = []
        toc = frame_xml / "FrameXML.toc"
        if toc.exists():
            for line in toc.read_text("latin-1").splitlines():
                line = line.strip()
                if line.lower().endswith(".xml") and (frame_xml / line).exists():
                    ordered.append(frame_xml / line)
        rest = [p for p in sorted(self.dump.glob("Interface/**/*.xml")) if p not in ordered]
        return ordered + rest + self.extra

    def _index(self, node, top=True):
        for c in node:
            tag = strip(c.tag)
            name = c.get("name")
            if tag == "Font" and name:
                self.fonts[name] = c
            elif name and "$parent" not in name:
                self.elements.setdefault(name, c)
            if top and c.get("parent") and c.get("virtual") != "true":
                self.parented.setdefault(c.get("parent"), []).append(c)
            if tag in ("Frames", "Layers", "Layer") or tag in FRAME_TAGS:
                self._index(c, False)

    def texture_size(self, file):
        key = (file if file.lower().endswith(".blp") else file + ".blp").lower()
        return self.textures.get(key)

    def font(self, name):
        """Merged font attributes following the inherits chain."""
        node = self.fonts.get(name)
        if node is None:
            return None
        base = self.font(node.get("inherits")) if node.get("inherits") else {}
        font = dict(base or {})
        if node.get("font"):
            font["file"] = node.get("font")
        height = value(child(node, "FontHeight"))
        if height:
            font["size"] = height
        if child(node, "Color") is not None:
            font["color"] = color(child(node, "Color"))
        shadow = child(node, "Shadow")
        if shadow is not None:
            font["shadow"] = (dimension(child(shadow, "Offset")) or (1, -1), color(child(shadow, "Color")))
        if node.get("outline"):
            font["outline"] = node.get("outline")
        return font


class Widget:
    """One FrameXML element with templates merged in, its $parent names resolved."""

    def __init__(self, tag, name, attrs, xml_nodes):
        self.tag = tag
        self.name = name
        self.attrs = attrs
        self.size = None
        self.anchors = None
        self.layers = {level: [] for level in LAYERS}
        self.frames = []
        self.special = {}
        self.backdrop = None
        self.tex_coords = None
        self.color = None
        self.template_scene = None
        self.rect = None
        self.own_ids = set()
        for node in xml_nodes:
            self._absorb(node)
        own = xml_nodes[-1]
        for c in own.iter():
            self.own_ids.add(id(c))

    def _absorb(self, node):
        size = dimension(child(node, "Size"))
        if size is not None:
            self.size = size
        anchors = child(node, "Anchors")
        if anchors is not None:
            self.anchors = []
            for a in anchors:
                self.anchors.append((a.get("point", "TOPLEFT"), a.get("relativeTo"),
                                     a.get("relativePoint") or a.get("point", "TOPLEFT"),
                                     dimension(child(a, "Offset")) or (0.0, 0.0)))
        coords = child(node, "TexCoords")
        if coords is not None:
            self.tex_coords = (fnum(coords.get("left")), fnum(coords.get("right"), 1.0),
                               fnum(coords.get("top")), fnum(coords.get("bottom"), 1.0))
        if child(node, "Color") is not None:
            self.color = color(child(node, "Color"))
        backdrop = child(node, "Backdrop")
        if backdrop is not None:
            inset_node = child(backdrop, "BackgroundInsets")
            insets = child(inset_node, "AbsInset") if inset_node is not None else None
            self.backdrop = {
                "bg": backdrop.get("bgFile"), "edge": backdrop.get("edgeFile"),
                "tile": backdrop.get("tile") == "true",
                "tile_size": value(child(backdrop, "TileSize")) or 0,
                "edge_size": value(child(backdrop, "EdgeSize")) or 0,
                "insets": tuple(fnum(insets.get(k)) for k in ("left", "right", "top", "bottom")) if insets is not None else (0, 0, 0, 0),
            }
        for c in node:
            tag = strip(c.tag)
            if tag == "Layers":
                for layer in c:
                    level = layer.get("level", "ARTWORK")
                    self.layers.setdefault(level, [])
                    self.layers[level].extend(layer)
            elif tag == "Frames":
                self.frames.extend(c)
            elif tag in BUTTON_TEXTURES or tag in ("ButtonText", "BarTexture", "BarColor", "ScrollChild",
                                                   "ThumbTexture", "NormalFont", "HighlightFont",
                                                   "DisabledFont", "FontString", "TextInsets"):
                self.special[tag] = c


class Converter:
    def __init__(self, library, project, config):
        self.lib = library
        self.project = Path(project)
        self.config = config
        self.scene_of_template = {s["frame"]: s for s in config["scenes"] if s.get("template")}
        self._template_children = {}
        # Frames left out of the port, such as the EULA pages and the billing notices.
        self.exclude = set(config.get("exclude", []))
        # Frames moved under another frame so their anchors resolve inside one scene.
        for frame, new_parent in config.get("graft", {}).items():
            node = library.elements[frame]
            for children in library.parented.values():
                if node in children:
                    children.remove(node)
            library.parented.setdefault(new_parent, []).append(node)

    # The nodes a written template scene already holds, so instances do not add them twice.
    def template_children(self, out):
        if out not in self._template_children:
            path = self.project / out
            text = path.read_text() if path.exists() else ""
            self._template_children[out] = {
                m.group(1) for m in re.finditer(r'\[node name="([^"]+)" [^\]]*parent="\."', text)
            }
        return self._template_children[out]

    # ---- widget tree ----

    def build(self, node, parent_name, as_template_root=False):
        """Widget for an XML node, templates merged, children built recursively."""
        tag = strip(node.tag)
        raw = node.get("name") or ""
        name = raw.replace("$parent", parent_name or "")
        chain = []
        inherits = node.get("inherits")
        scene_template = None
        while inherits and inherits in self.lib.elements:
            if inherits in self.scene_of_template:
                scene_template = scene_template or inherits
            base = self.lib.elements[inherits]
            chain.insert(0, base)
            inherits = base.get("inherits")
        attrs = {}
        for n in chain + [node]:
            attrs.update(n.attrib)
        widget = Widget(tag, name, attrs, chain + [node])
        widget.template_scene = scene_template
        widget.script = None
        for base in chain:
            widget.script = self.config.get("template_scripts", {}).get(base.get("name"), widget.script)
        widget.script = self.config.get("frame_scripts", {}).get(name, widget.script)
        self._inject(widget, name)
        widget.font = attrs.get("inherits") if attrs.get("inherits") in self.lib.fonts else None
        widget.children = []

        def add(xml, layer, tag=None, state=None, fallback=None):
            w = self.build(xml, name)
            if w.name in self.exclude:
                return w
            if w.name in getattr(widget, "injected", {}):
                w.attrs["file"] = widget.injected[w.name]
            w.layer = layer
            w.own = id(xml) in widget.own_ids
            if tag:
                w.tag = tag
            if state:
                w.state = state
            if fallback and not w.name:
                w.name = name + fallback
            widget.children.append(w)
            return w

        for level in LAYERS:
            for c in widget.layers.get(level, []):
                add(c, level)
        for key in BUTTON_TEXTURES:
            if key in widget.special:
                add(widget.special[key], BUTTON_TEXTURE_LAYER[key], "Texture", key, key)
        if "ButtonText" in widget.special:
            text = add(widget.special["ButtonText"], "OVERLAY", "FontString", None, "Text")
            text.font = text.font or self._button_font(widget)
            if attrs.get("text") and not text.attrs.get("text"):
                text.attrs["text"] = attrs["text"]
            normal = widget.special.get("NormalFont")
            if normal is not None and normal.get("justifyH") and not text.attrs.get("justifyH"):
                text.attrs["justifyH"] = normal.get("justifyH")
        elif "NormalFont" in widget.special:
            # SetText gives a button without a ButtonText a centred one on demand.
            text = add(ET.Element("ButtonText"), "OVERLAY", "FontString", None, "Text")
            text.font = text.font or self._button_font(widget)
        order = {level: i for i, level in enumerate(LAYERS)}
        widget.children.sort(key=lambda w: order.get(w.layer, 2))
        for c in widget.frames:
            add(c, "FRAME")
        if not node.get("virtual") == "true":
            for c in self.lib.parented.get(name, []):
                add(c, "FRAME").own = True
        if "ScrollChild" in widget.special:
            for c in widget.special["ScrollChild"]:
                add(c, "FRAME").scroll_child = True
        if "ThumbTexture" in widget.special:
            widget.thumb = self.build(widget.special["ThumbTexture"], name)
        if tag == "Minimap" and attrs.get("minimapPlayerModel"):
            # The player arrow is a model in FrameXML; its flat texture of the same name stands in.
            file = re.sub(r"\.(mdx|mdl|m2)$", "", attrs["minimapPlayerModel"], flags=re.I)
            arrow = ET.fromstring(
                f'<Texture name="MinimapArrow" file="{file}"><Size><AbsDimension x="32" y="32"/></Size>'
                '<Anchors><Anchor point="CENTER"/></Anchors></Texture>')
            add(arrow, "OVERLAY").own = True
        return widget

    def _inject(self, widget, name):
        """Textures FrameXML's Lua assigns at load time, declared in frames.json instead."""
        for key, file in self.config.get("inject", {}).get(name, {}).items():
            if key in BUTTON_TEXTURES:
                xml = ET.Element(key, {"file": file})
                if key == "HighlightTexture":
                    xml.set("alphaMode", "ADD")
                widget.special[key] = xml
                widget.own_ids.add(id(xml))
            else:
                widget.injected = getattr(widget, "injected", {})
                widget.injected[name + key] = file

    def _button_font(self, widget):
        normal = widget.special.get("NormalFont")
        return normal.get("inherits") if normal is not None else "GameFontNormal"

    # ---- layout ----

    def layout(self, root, root_size):
        registry = {}

        def register(w):
            if w.name:
                registry[w.name] = w
            for c in w.children:
                register(c)

        register(root)
        root.rect = (0.0, 0.0, root_size[0], root_size[1])
        root.parent = None

        def assign_parents(w):
            for c in w.children:
                c.parent = w
                assign_parents(c)

        assign_parents(root)
        solving = set()

        def solve(w):
            if w.rect is not None:
                return w.rect
            if id(w) in solving:
                return w.parent.rect
            solving.add(id(w))
            prect = solve(w.parent)
            width, height = w.size or self.natural_size(w)
            if w.tag == "FontString" and not height:
                # A FontString without a height is one line of its font tall until its text wraps.
                height = (self.lib.font(w.font) or {}).get("size", 0.0) if w.font else 0.0
            if not w.anchors:
                if w.size:
                    w.rect = (prect[0], prect[1], width or prect[2], height or prect[3])
                else:
                    w.rect = prect
                solving.discard(id(w))
                return w.rect
            h = {"lo": None, "hi": None, "mid": None}
            v = {"lo": None, "hi": None, "mid": None}
            for point, rel, rel_point, offset in w.anchors:
                target = None
                if rel and rel not in ("$parent",):
                    target = registry.get(rel.replace("$parent", w.parent.name or ""))
                rect = solve(target) if target is not None and target is not w else prect
                qx, qy = POINTS.get(rel_point.upper(), (0, 0))
                px = rect[0] + qx * rect[2] + offset[0]
                py = rect[1] + qy * rect[3] - offset[1]
                fx, fy = POINTS.get(point.upper(), (0, 0))
                h["lo" if fx == 0 else "hi" if fx == 1 else "mid"] = px
                v["lo" if fy == 0 else "hi" if fy == 1 else "mid"] = py
            x, width, auto_x = self._span(h, width)
            y, height, auto_y = self._span(v, height)
            w.rect = (x, y, width, height)
            w.grow = (auto_x, auto_y)
            solving.discard(id(w))
            return w.rect

        def walk(w):
            solve(w)
            for c in w.children:
                walk(c)

        for c in root.children:
            walk(c)

    def natural_size(self, w):
        """A texture without a Size shows at its file's pixel size, cut down by its TexCoords."""
        if w.tag != "Texture" or not w.attrs.get("file"):
            return (0.0, 0.0)
        size = self.lib.texture_size(w.attrs["file"])
        if not size:
            return (0.0, 0.0)
        left, right, top, bottom = w.tex_coords or (0.0, 1.0, 0.0, 1.0)
        return (abs(right - left) * size[0], abs(bottom - top) * size[1])

    @staticmethod
    def _span(axis, size):
        """(start, size, grow) along one axis; grow says which way auto-sized text extends."""
        if axis["lo"] is not None and axis["hi"] is not None:
            return axis["lo"], axis["hi"] - axis["lo"], None
        if axis["lo"] is not None:
            return axis["lo"], size, "end"
        if axis["hi"] is not None:
            return axis["hi"] - size, size, "begin"
        if axis["mid"] is not None:
            return axis["mid"] - size / 2, size, "both"
        return 0.0, size, "end"

    # ---- scene writing ----

    def convert(self, entry):
        frame = entry["frame"]
        node = self.lib.elements.get(frame)
        if node is None:
            raise SystemExit(f"no frame named {frame}")
        root = self.build(node, "", as_template_root=True)
        root.template_scene = None
        root.name = frame
        size = root.size or (0.0, 0.0)
        if root.attrs.get("setAllPoints") == "true":
            size = SCREEN_SIZE
        # Frames get resized at runtime (SetWidth), so every sized root is solved at two sizes.
        if size[0] and size[1]:
            self.layout(root, (size[0] * LAYOUT_STRETCH, size[1] * LAYOUT_STRETCH))
            for w in widgets(root):
                w.stretched, w.rect = w.rect, None
        self.layout(root, size)
        scene = SceneWriter(self, entry)
        scene.write_root(root)
        write_keeping_uid(self.project / entry["out"], scene.text())
        print(f"wrote {entry['out']}")

    def write_theme(self, path):
        names = sorted(self.lib.fonts)
        lines = ['[gd_resource type="Theme" format=3]', "", "[resource]"]
        files = {}
        for name in names:
            font = self.lib.font(name)
            if not font:
                continue
            variation = RENAMED_FONTS.get(name, name)
            lines.append(f'{variation}/base_type = &"Label"')
            if font.get("color"):
                lines.append(f"{variation}/colors/font_color = Color{self._tuple(font['color'])}")
            if font.get("shadow"):
                offset, shadow = font["shadow"]
                lines.append(f"{variation}/colors/font_shadow_color = Color{self._tuple(shadow or (0, 0, 0, 1))}")
                lines.append(f"{variation}/constants/shadow_offset_x = {int(offset[0])}")
                lines.append(f"{variation}/constants/shadow_offset_y = {int(-offset[1])}")
            if font.get("outline"):
                lines.append(f"{variation}/colors/font_outline_color = Color(0, 0, 0, 1)")
                lines.append(f"{variation}/constants/outline_size = {4 if font['outline'] == 'THICKOUTLINE' else 2}")
            if font.get("size"):
                lines.append(f"{variation}/font_sizes/font_size = {int(font['size'])}")
            if font.get("file"):
                files[variation] = font["file"]
        # The font files are Blizzard data, so the game loads them from the archive by these names.
        lines.append("metadata/wow_fonts = " + json.dumps(files))
        write_keeping_uid(self.project / path, "\n".join(lines) + "\n")
        print(f"wrote {path}")

    @staticmethod
    def _tuple(c):
        return "(" + ", ".join(f"{x:g}" for x in c) + ")"


class SceneWriter:
    def __init__(self, converter, entry):
        self.conv = converter
        self.lib = converter.lib
        self.entry = entry
        self.ext = []
        self.subs = []
        self.sub_ids = {}
        self.nodes = []
        self.unique = {}

    def ext_resource(self, kind, path):
        for i, (k, p) in enumerate(self.ext):
            if (k, p) == (kind, path):
                return f'ExtResource("{i + 1}")'
        self.ext.append((kind, path))
        return f'ExtResource("{len(self.ext)}")'

    def sub_resource(self, kind, props):
        key = (kind, tuple(props))
        if key not in self.sub_ids:
            sid = f"{kind}_{len(self.subs) + 1}"
            self.sub_ids[key] = sid
            self.subs.append((kind, sid, props))
        return f'SubResource("{self.sub_ids[key]}")'

    def texture(self, file, coords):
        path = file if file.lower().endswith(".blp") else file + ".blp"
        base = self.sub_resource("WowTexture", [("file", quote(path))])
        if not coords or coords == (0.0, 1.0, 0.0, 1.0):
            return base
        size = self.lib.texture_size(path) or (256, 256)
        left, right, top, bottom = coords
        x0, x1 = sorted((left, right))
        y0, y1 = sorted((top, bottom))
        region = f"Rect2({x0 * size[0]:g}, {y0 * size[1]:g}, {(x1 - x0) * size[0]:g}, {(y1 - y0) * size[1]:g})"
        return self.sub_resource("AtlasTexture", [("atlas", base), ("region", region)])

    @staticmethod
    def short_name(w, parent):
        full = w.name or ""
        if parent is not None and parent.name and full.startswith(parent.name) and len(full) > len(parent.name):
            return full[len(parent.name):]
        return full

    def node_name(self, w, parent):
        """WoW's global name in frame scenes; $parent-relative names inside template scenes."""
        state = getattr(w, "state", None)
        if state:
            name = state
        elif self.entry.get("template"):
            name = self.short_name(w, parent)
        else:
            name = w.name
        return re.sub(r"[^A-Za-z0-9_]", "_", name or w.tag)

    def write_root(self, root):
        root.parent = None
        if root.attrs.get("setAllPoints") == "true":
            full = [("anchor_right", "1"), ("anchor_bottom", "1"), ("grow_horizontal", "2"), ("grow_vertical", "2")]
            self.emit(root, None, ".", full, is_root=True)
            return
        anchors = root.anchors or [("TOPLEFT", None, "TOPLEFT", (0.0, 0.0))]
        point, rel, rel_point, offset = anchors[0]
        qx, qy = POINTS.get(rel_point.upper(), (0, 0))
        fx, fy = POINTS.get(point.upper(), (0, 0))
        width, height = root.size or (0.0, 0.0)
        left = offset[0] - fx * width
        top = -offset[1] - fy * height
        props = [
            ("anchor_left", f"{qx:g}"), ("anchor_top", f"{qy:g}"),
            ("anchor_right", f"{qx:g}"), ("anchor_bottom", f"{qy:g}"),
            ("offset_left", f"{left:g}"), ("offset_top", f"{top:g}"),
            ("offset_right", f"{left + width:g}"), ("offset_bottom", f"{top + height:g}"),
            ("grow_horizontal", "2" if qx == 0.5 else "0" if qx == 1 else "1"),
            ("grow_vertical", "2" if qy == 0.5 else "0" if qy == 1 else "1"),
        ]
        self.emit(root, None, ".", props, is_root=True)

    def emit(self, w, parent, parent_path, extra=None, is_root=False, in_template=()):
        name = (self.entry.get("name") or w.name) if is_root else self.node_name(w, parent)
        if not is_root:
            siblings = [n for n in self.nodes if n["parent"] == parent_path]
            base, i = name, 2
            while any(n["name"] == name for n in siblings):
                name = f"{base}{i}"
                i += 1
        props = list(extra or [])
        kind, script = self.kind(w)
        instance = None
        if w.template_scene and not is_root:
            scene = self.conv.scene_of_template[w.template_scene]
            instance = self.ext_resource("PackedScene", "res://" + scene["out"])
        if not is_root:
            props += self.placement(w, parent)
            grow = getattr(w, "grow", None)
            if w.tag == "FontString" and grow and not (w.size and w.size[1]):
                names = {"end": "1", "begin": "0", "both": "2", None: "1"}
                props += [("grow_horizontal", names[grow[0]]), ("grow_vertical", names[grow[1]])]
        if parent is not None and self.kind(parent)[0] in SELF_DRAWING and getattr(w, "layer", "") in ("BACKGROUND", "BORDER"):
            props.append(("show_behind_parent", "true"))
        if w.attrs.get("hidden") == "true" or getattr(w, "state", None) in (
                "PushedTexture", "DisabledTexture", "CheckedTexture", "DisabledCheckedTexture", "HighlightTexture"):
            props.append(("visible", "false"))
        if not instance:
            props += self.kind_props(w, kind)
        script = w.script or script
        if is_root and self.entry.get("script"):
            props.append(("script", self.ext_resource("Script", self.entry["script"])))
        elif script and not instance:
            props.append(("script", self.ext_resource("Script", script)))
        # A child the template scene already holds is edited in place, or Godot renames one of them.
        override = name in in_template
        if override:
            props = [(k, v) for k, v in props if k != "script"]
        record = {"name": name, "parent": parent_path, "type": None if instance or override else kind,
                  "instance": instance, "props": props, "unique": False}
        if w.name and not is_root:
            key = name
            if key in self.unique:
                self.unique[key]["unique"] = False
                self.unique[key]["clash"] = True
            else:
                self.unique[key] = record
                record["unique"] = True
        self.nodes.append(record)
        path = "." if is_root else (name if parent_path == "." else f"{parent_path}/{name}")
        if w.backdrop and not instance:
            self.emit_backdrop(w, path)
        if w.tag in MODEL_TAGS and not instance:
            self.emit_model(w, path)
        if instance:
            # The template scene already holds the inherited children; only the frame's own are added.
            inherited = self.conv.template_children(self.conv.scene_of_template[w.template_scene]["out"])
            for c in w.children:
                if c.own:
                    self.emit(c, w, path, in_template=inherited)
            return
        for c in w.children:
            if not getattr(c, "scroll_child", False):
                self.emit(c, w, path)
        scrolled = [c for c in w.children if getattr(c, "scroll_child", False)]
        if scrolled:
            # Only the scroll child is clipped; the scroll bar hangs outside the frame.
            clip = f"{self.node_name(w, w.parent)}Clip"
            self.nodes.append({"name": clip, "parent": path, "type": "Control", "instance": None,
                               "props": FULL_RECT + [("mouse_filter", "2"), ("clip_contents", "true")],
                               "unique": False})
            for c in scrolled:
                self.emit(c, w, clip if path == "." else f"{path}/{clip}")
        if w.tag == "ScrollingMessageFrame":
            self.emit_message_lines(w, path)

    def emit_message_lines(self, w, path):
        """A clipped area whose line list grows upward from the bottom, newest line last."""
        clip = f"{self.node_name(w, w.parent)}Clip"
        full = [("anchor_right", "1.0"), ("anchor_bottom", "1.0"), ("mouse_filter", "2")]
        self.nodes.append({"name": clip, "parent": path, "type": "Control", "instance": None,
                           "props": full + [("clip_contents", "true")], "unique": False})
        clip_path = clip if path == "." else f"{path}/{clip}"
        self.nodes.append({"name": "MessageLines", "parent": clip_path, "type": "VBoxContainer",
                           "instance": None, "props": full + [("grow_vertical", "0"), ("alignment", "2")],
                           "unique": True})

    def emit_model(self, w, path):
        """The frame's 3D scene, drawn under its children like the stock model frames."""
        props = FULL_RECT + [("mouse_filter", "2")]
        if w.attrs.get("file"):
            props.append(("model_file", quote(re.sub(r"\.(mdx|mdl)$", ".m2", w.attrs["file"], flags=re.I))))
        for attr, prop in (("fogNear", "fog_near"), ("fogFar", "fog_far"), ("glow", "glow")):
            if w.attrs.get(attr):
                props.append((prop, f"{fnum(w.attrs[attr]):g}"))
        self.nodes.append({"name": f"{w.name}Model", "parent": path, "type": None,
                           "instance": self.ext_resource("PackedScene", WOW_MODEL_FRAME),
                           "props": props, "unique": True})

    def emit_backdrop(self, w, path):
        b = w.backdrop
        props = FULL_RECT + [("mouse_filter", "2"), ("script", self.ext_resource("Script", WOW_BACKDROP))]
        if self.kind(w)[0] in SELF_DRAWING:
            props.append(("show_behind_parent", "true"))
        if b["bg"]:
            props.append(("background", self.texture(b["bg"], None)))
        if b["edge"]:
            props.append(("edge", self.texture(b["edge"], None)))
        props += [("tile", "true" if b["tile"] else "false"), ("tile_size", f"{b['tile_size']:g}"),
                  ("edge_size", f"{b['edge_size']:g}"),
                  ("insets", "Vector4({:g}, {:g}, {:g}, {:g})".format(*b["insets"]))]
        self.nodes.append({"name": "Backdrop", "parent": path, "type": "Control", "instance": None,
                           "props": props, "unique": False})

    @staticmethod
    def placement(w, parent):
        """Anchors and offsets that keep the edges where both layout solves put them."""
        anchors, offsets = [], []
        for edge, axis, side in (("left", 0, 0.0), ("top", 1, 0.0), ("right", 0, 1.0), ("bottom", 1, 1.0)):
            near, far = w.rect, getattr(w, "stretched", None) or w.rect
            pnear, pfar = parent.rect, getattr(parent, "stretched", None) or parent.rect
            at_near = near[axis] + side * near[axis + 2] - pnear[axis]
            at_far = far[axis] + side * far[axis + 2] - pfar[axis]
            anchor = 0.0
            if pfar[axis + 2] != pnear[axis + 2]:
                anchor = round((at_far - at_near) / (pfar[axis + 2] - pnear[axis + 2]), 6)
            if anchor:
                anchors.append((f"anchor_{edge}", f"{anchor:g}"))
            offsets.append((f"offset_{edge}", f"{at_near - anchor * pnear[axis + 2]:g}"))
        # Without the layout mode the editor reads anchors as position mode and drops them on save.
        return ([("layout_mode", "1")] if anchors else []) + anchors + offsets

    def kind(self, w):
        tag = w.tag
        if tag == "Texture":
            if not w.attrs.get("file") and w.color:
                return "ColorRect", None
            return "TextureRect", None
        if tag == "FontString":
            return "Label", None
        if tag in ("Button", "CheckButton", "LootButton"):
            return "TextureButton", WOW_BUTTON
        if tag == "StatusBar":
            return "TextureProgressBar", None
        if tag == "EditBox":
            return "LineEdit", None
        if tag == "ScrollFrame":
            return "Control", WOW_SCROLL_FRAME
        if tag == "Slider":
            return ("HSlider" if w.attrs.get("orientation") == "HORIZONTAL" else "VSlider"), None
        if tag == "MessageFrame":
            return "VBoxContainer", WOW_MESSAGE_FRAME
        if tag == "ScrollingMessageFrame":
            return "Control", WOW_SCROLLING_MESSAGE_FRAME
        if tag == "SimpleHTML":
            return "RichTextLabel", None
        return "Control", None

    def kind_props(self, w, kind):
        props = []
        mouse = w.tag in ("Button", "CheckButton", "LootButton", "EditBox", "Slider", "ScrollFrame") \
            or w.attrs.get("enableMouse") == "true"
        if kind != "TextureButton":
            props.append(("mouse_filter", "0" if mouse else "2"))
        if kind == "TextureRect":
            if w.attrs.get("file"):
                props.append(("texture", self.texture(w.attrs["file"], w.tex_coords)))
            props += [("expand_mode", "1")]
            if w.tex_coords and w.tex_coords[0] > w.tex_coords[1]:
                props.append(("flip_h", "true"))
            if w.tex_coords and w.tex_coords[2] > w.tex_coords[3]:
                props.append(("flip_v", "true"))
            if w.color:
                props.append(("self_modulate", f"Color{Converter._tuple(w.color)}"))
            if w.attrs.get("alphaMode") == "ADD":
                props.append(("material", self.sub_resource("CanvasItemMaterial", [("blend_mode", "1")])))
        elif kind == "ColorRect":
            props.append(("color", f"Color{Converter._tuple(w.color)}"))
        elif kind == "Label":
            if w.font:
                props.append(("theme_type_variation", f'&"{RENAMED_FONTS.get(w.font, w.font)}"'))
            text = w.attrs.get("text")
            if text:
                props.append(("text", quote(self.lib.strings.get(text, text))))
            justify = {"LEFT": "0", "CENTER": "1", "RIGHT": "2"}
            props.append(("horizontal_alignment", justify.get(w.attrs.get("justifyH", "CENTER").upper(), "1")))
            vjustify = {"TOP": "0", "MIDDLE": "1", "BOTTOM": "2"}
            props.append(("vertical_alignment", vjustify.get(w.attrs.get("justifyV", "MIDDLE").upper(), "1")))
            if w.size and w.size[1]:
                # Text larger than its box spills out around the side it is justified to.
                spill = {"LEFT": "1", "TOP": "1", "CENTER": "2", "MIDDLE": "2", "RIGHT": "0", "BOTTOM": "0"}
                props.append(("grow_horizontal", spill.get(w.attrs.get("justifyH", "CENTER").upper(), "2")))
                props.append(("grow_vertical", spill.get(w.attrs.get("justifyV", "MIDDLE").upper(), "2")))
        elif kind == "TextureProgressBar":
            bar = w.special.get("BarTexture")
            if bar is not None and bar.get("file"):
                props.append(("texture_progress", self.texture(bar.get("file"), None)))
                props.append(("nine_patch_stretch", "true"))
            bar_color = color(w.special.get("BarColor"))
            if bar_color:
                props.append(("tint_progress", f"Color{Converter._tuple(bar_color)}"))
            props += [("max_value", "1.0"), ("step", "0.0"), ("value", "1.0")]
            if w.attrs.get("orientation") == "VERTICAL":
                props.append(("fill_mode", "3"))
        elif kind == "TextureButton":
            props.append(("ignore_texture_size", "true"))
        elif w.tag == "ScrollingMessageFrame":
            line = w.special.get("FontString")
            if line is not None and line.get("inherits"):
                props.append(("font_variation", f'&"{RENAMED_FONTS.get(line.get("inherits"), line.get("inherits"))}"'))
            props.append(("display_duration", f'{fnum(w.attrs.get("displayDuration"), 120.0):g}'))
            props.append(("max_lines", str(int(fnum(w.attrs.get("maxLines"), 128)))))
        elif kind == "VBoxContainer" and w.tag == "MessageFrame":
            line = w.special.get("FontString")
            if line is not None and line.get("inherits"):
                props.append(("font_variation", f'&"{RENAMED_FONTS.get(line.get("inherits"), line.get("inherits"))}"'))
            props.append(("display_duration", f'{fnum(w.attrs.get("displayDuration"), 10.0):g}'))
            props.append(("insert_at_top", "true" if w.attrs.get("insertMode") == "TOP" else "false"))
        elif kind == "RichTextLabel":
            props += [("scroll_following", "true"), ("fit_content", "false")]
        elif kind in ("VSlider", "HSlider"):
            thumb = getattr(w, "thumb", None)
            if thumb is not None and thumb.attrs.get("file"):
                icon = self.texture(thumb.attrs["file"], thumb.tex_coords)
                props += [("theme_override_icons/grabber", icon), ("theme_override_icons/grabber_highlight", icon)]
            # WoW sliders draw only their thumb.
            empty = self.sub_resource("StyleBoxEmpty", [])
            props += [(f"theme_override_styles/{style}", empty) for style in ("slider", "grabber_area", "grabber_area_highlight")]
            props += [("max_value", "0.0"), ("step", "0.0")]
        elif kind == "LineEdit":
            line = w.special.get("FontString")
            if line is not None and line.get("inherits"):
                props.append(("theme_type_variation", f'&"{RENAMED_FONTS.get(line.get("inherits"), line.get("inherits"))}"'))
            if w.attrs.get("password") == "1":
                props.append(("secret", "true"))
            if w.attrs.get("letters"):
                props.append(("max_length", str(int(fnum(w.attrs["letters"])))))
            props.append(("caret_blink", "true"))
            # The frame's backdrop is the box, so the only style left is the TextInsets padding.
            insets = w.special.get("TextInsets")
            inset = child(insets, "AbsInset") if insets is not None else None
            inset = inset if inset is not None else insets
            margins = [(f"content_margin_{k}", f"{fnum(inset.get(k)):g}") for k in ("left", "right", "top", "bottom")
                       if inset is not None and inset.get(k)]
            style = self.sub_resource("StyleBoxEmpty", margins)
            props += [(f"theme_override_styles/{state}", style) for state in ("normal", "focus", "read_only")]
        return props

    def text(self):
        out = ["[gd_scene format=3]", ""]
        for i, (kind, path) in enumerate(self.ext):
            out.append(f'[ext_resource type="{kind}" path="{path}" id="{i + 1}"]')
        if self.ext:
            out.append("")
        for kind, sid, props in self.subs:
            out.append(f'[sub_resource type="{kind}" id="{sid}"]')
            out += [f"{k} = {v}" for k, v in props]
            out.append("")
        for n in self.nodes:
            head = f'[node name="{n["name"]}"'
            if n["type"]:
                head += f' type="{n["type"]}"'
            if n["parent"] is not None and not (n["parent"] == "." and n is self.nodes[0]):
                head += f' parent="{n["parent"]}"'
            if n["instance"]:
                head += f" instance={n['instance']}"
            out.append(head + "]")
            if n["unique"]:
                out.append("unique_name_in_owner = true")
            # The script goes first so the properties it declares exist when they are assigned.
            props = sorted(n["props"], key=lambda prop: prop[0] != "script")
            out += [f"{k} = {v}" for k, v in props]
            out.append("")
        return "\n".join(out)


def write_keeping_uid(path, text):
    """Rewrites a scene or resource, keeping the uid Godot gave it so references by uid still resolve."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        uid = re.search(r'^\[gd_\w+ [^\]]*(uid="[^"]+")', path.read_text())
        if uid:
            head, rest = text.split("]", 1)
            text = f"{head} {uid.group(1)}]{rest}"
    path.write_text(text)


def widgets(w):
    yield w
    for c in w.children:
        yield from widgets(c)


def quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    dump, project = sys.argv[1], sys.argv[2]
    configs = [a for a in sys.argv[3:] if a.endswith(".json")]
    only = [a for a in sys.argv[3:] if not a.endswith(".json")]
    config_path = Path(configs[0]) if configs else Path(__file__).with_name("frames.json")
    config = json.loads(config_path.read_text())
    # WoWGD's own frames, added to the stock screens it converts.
    extra = [config_path.parent / p for p in config.get("xml", [])]
    converter = Converter(Library(dump, extra), project, config)
    converter.write_theme(config["theme"])
    for entry in config["scenes"]:
        if not only or entry["frame"] in only:
            converter.convert(entry)


if __name__ == "__main__":
    main()
