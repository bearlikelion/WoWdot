<p align="center">
  <img src="wowdot_extension_logo.png" alt="wowdot extension logo" width="200">
</p>

# wowdot extension

The C++ GDExtension behind the WoWdot clients.
It reads a stock World of Warcraft install (MPQ archives, DBC tables, BLP textures, M2 and WMO models, ADT terrain) and speaks the game's network protocol, and exposes both to GDScript.
Both [WoWGD](../clients/wowgd) and [WotLKGD](../clients/wotlkgd) load the same library through the shared addon in [`shared/wowdot`](../shared/wowdot).

## Classes

| Class | Purpose |
| --- | --- |
| `WowArchive` | Read-only view over the client's MPQ chain, later patches overriding earlier archives. |
| `WowDBC` | A DBC table, with columns addressed by index or by name from the client's `dbc_layouts.json`. |
| `WowTexture` | A `Texture2D` that stores only an archive path, so scenes and themes reference Blizzard art without embedding pixels. |
| `WowLoader` | Turns archive files into Godot resources and nodes: textures, M2 models with skeletons and animations, WMOs, terrain tiles and map info. One shared loader per project, safe to call from worker threads. |
| `WowStreamer` | Builds map tiles on worker threads and hands them back through `poll()`, so no script runs off the main thread. |
| `WowSession` | Login (SRP6), realm list, character list, world connection with header encryption, the object store from update packets, movement, chat, spells and NPC packets. Opcodes it does not handle reach GDScript through `packet_received`. |
| `WowCoords` | The one conversion between WoW space (X north, Y west, Z up, yards) and Godot space (Y up, -Z north, metres). |

The API reference for each client, generated from the class docs, is part of the project website.

## Layout

```text
src/            Godot-facing classes and register_types.cpp
wowee/          Vendored WoWee code (MIT): auth, network, packet parsing, ADT, BLP, DBC, M2, WDT and WMO loaders
thirdparty/     Submodules: StormLib, zlib, bzip2, GLM, nlohmann/json
godot-cpp/      Submodule
api/            extension_api.json dumped from the engine build the project uses
SConstruct      Builds into ../shared/wowdot/bin/
```

## Building

Needs SCons, a C++20 compiler and the submodules (`git submodule update --init --recursive`).
Every library is compiled in, so there are no system packages to install.

```sh
scons -j8 target=template_debug             # editor and debug runs
scons -j8 target=template_release           # Linux exports
scons -j8 platform=windows target=template_release   # Windows exports, cross-built with mingw-w64
scons -j8 target=template_debug sanitize=yes         # ASan and UBSan
```

`custom.py` points godot-cpp at `api/extension_api.json`; after changing engine builds, regenerate it with `godot --dump-extension-api` and move the file into `api/`.
Our own sources in `src/` build with `-Wall -Wextra -Wpedantic -Wshadow`, while the vendored code keeps its upstream flags.
Windows builds force-include `thirdparty/tommath_llp64.h` so LibTomMath uses digits that fit Windows' 32-bit `long`; without it every Windows login sends a broken SRP value.

`shared/wowdot/wowdot.gdextension` sets `reloadable = true` so the editor picks up a rebuilt library without restarting.
That needs an editor with the extension instance-binding fix, because stock Godot races on its binding list when `WowStreamer`'s worker threads create objects; on a stock editor set `reloadable = false`.

## Vendored WoWee code

`wowee/` comes from WoWee as of tag `v2.0.28-preview` (commit `db2768407`), when WoWee was MIT licensed, by way of Mark Arneman's fork.
[`wowee/SOURCE`](wowee/SOURCE) records the exact commit and every local change, and [docs/legal-and-provenance.md](../docs/legal-and-provenance.md) explains the licensing.
Never copy or consult WoWee code from after that tag.
The server projects (vMaNGOS, AzerothCore) are GPL: read them to learn the protocol, never copy their code.

## Expansion support

The extension currently assumes vanilla 1.12.1 (build 5875) in several places: the build number and auth flow in `WowSession`, the classic packet parsers, the MPQ list in `WowArchive`, the DBC layout path, and M2 loading without `.skin` files.
The [WotLKGD README](../clients/wotlkgd/README.md#extension-extensionsrc) lists what 3.3.5a needs.
