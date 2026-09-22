# Legal and provenance

Not legal advice.

## WoWee base

| | |
| --- | --- |
| Upstream | Kelsidavis/WoWee, tag `v2.0.28-preview` |
| Commit | `db2768407ede4565e6904e7e04243d61521237e0` (Kelsi, 2026-07-21) |
| License at that commit | MIT, plus an all-rights-reserved clause covering WoWee's original music |
| Public mirror | `bearlikelion/WoWee`, branch `v2.0.28`, which adds only an archive notice (`72d0c9211`) |

The restriction on commercial game use was added after this tag.
Nothing after `db2768407` may be copied, cherry-picked or consulted while writing WoWdot code.

## How the code reached WoWdot

1. `mark/WoWee` (mWoWee) was reset to `db2768407` and developed further by Mark Arneman.
2. WoWGD vendored a subset of mWoWee at `d0c3f40bfb880a6a1d73f7f1c431b9dec4493629` into `extension/wowee/`: auth, network, packet parsing and the ADT, BLP, DBC, M2, WDT and WMO loaders.
   The local changes are listed in [extension/wowee/SOURCE](../extension/wowee/SOURCE).
3. WoWGD's history was imported into this repository on 2026-09-19 with its paths moved to `clients/wowgd/` and `extension/`.
   A paid editor addon that is not redistributable was removed from every commit.

Everything outside `extension/wowee/`, `extension/godot-cpp/` and `extension/thirdparty/` was written for WoWGD by Mark Arneman.

## Audit status

| Item | Status |
| --- | --- |
| WoWee code in `extension/wowee/` | MIT, base commit verified |
| WoWee music | Not included |
| `clients/*/ui/wow/*.tscn`, `tools/framexml/frames.json`, `data/classic/ui_sounds.json` | **Open.** Generated from Blizzard's FrameXML (layout, coordinates, texture paths, sound names) by `tools/framexml/convert.py`. No pixels are stored, but the layouts are derived from Blizzard files. Decide before the first public push, because pushed history cannot be recalled. |
| `data/*/opcodes.json`, `update_fields.json`, `dbc_layouts.json` | Protocol and file-format tables from WoWee (MIT) |
| `clients/wowgd/wowgd_icon.png` | **Open.** Confirm origin |
| Game fonts | Loaded from the player's MPQs at runtime, none bundled |
| Third-party libraries | All MIT, zlib, bzip2 or public domain, see [NOTICE.md](../NOTICE.md). OpenSSL was removed on 2026-09-19. |
