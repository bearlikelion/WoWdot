<p align="center">
  <img src="wrathgd_icon.png" alt="WrathGD logo" width="200">
</p>

# WrathGD

A Godot 4.7 client for World of Warcraft 3.3.5a (build 12340) that will play on [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk).
Like [WoWGD](../wowgd), it reads the stock client's MPQs at runtime and ships no Blizzard data.

## Status

Walks around: the client logs in, makes a character and walks around Shadowglen on a stock AzerothCore.
One `wowdot` build serves both clients; **Project Settings > wowgd > expansion** is `wotlk` here, which picks the wire build, packet parsers, MPQ chain and the `data/wotlk/` tables.
`game/` links to [`shared/game`](../../shared/game), the GDScript both clients share.
The login, character list and create screens in [`ui/`](ui) are converted from the 3.3.5a GlueXML; the rest of `ui/` is still the 1.12 conversion.

## Requirements

- Godot 4.7 and the `wowdot` extension built from [`extension/`](../../extension); see the [top-level README](../../README.md#building).
- A 3.3.5a client folder with its `Data` directory, including the locale folder (for example `enUS/`), which carries the DBCs and every string.
  Set **Project Settings > wowgd > client_data_dir** to that `Data` folder.

## Server setup

WrathGD targets the latest AzerothCore `master` with no source changes and no modules.
The developer server runs from AzerothCore's own `docker-compose.yml` with its published images:

```sh
cd <your azerothcore-wotlk checkout>
docker compose pull
docker compose up -d --no-build
```

`ac-client-data-init` downloads the extracted maps, vmaps, mmaps and DBCs, so the extractors need not run.
A gitignored `.env` moves every port off its default, since the vMaNGOS stack holds those for WoWGD:

| Port | Service |
| --- | --- |
| 3725 | authserver |
| 8095 | worldserver |
| 127.0.0.1:3307 | MySQL |
| 127.0.0.1:7879 | SOAP, once `SOAP.Enabled` is on in `worldserver.conf` |

`acore_auth.realmlist` must name the host's world port (`127.0.0.1`, `8095`), not the container's.
Create the account from the worldserver console (`docker attach ac-worldserver`, detach with ctrl-p ctrl-q): `account create wowgd wowgd`, then `account set gmlevel wowgd 3 -1`.

## Running

Open this folder in Godot and run; `res://game/main.tscn` opens the 3.3.5a login screen.

## Still to do

Most of the WotLK protocol and format code is already in the vendored WoWee sources; what is left is the code that still reads the vanilla layout regardless of the expansion setting.

| Area | Work |
| --- | --- |
| Hand-parsed packets | `wow_session.cpp` still parses learned spells, cast failed, spell cooldown, quest query, quest giver status, gossip, vendor, trainer and taxi lists in the vanilla layout. |
| Animations | Version 264 keeps most sequences in `.anim` files, hundreds per model, which want loading on demand. |
| Data tables | `data/wotlk/` has no `ui_sounds.json`, `spell_failures.json` or `equip_failures.json` yet, so UI sounds are silent and refusals have no text. |
| Spell.dbc | `dbc_layouts.json` names only the Spell columns asked for so far; reagents, cooldowns, effects and descriptions still want placing. |
| Update fields | 93 names the game code reads were removed in WotLK (object positions, most of `PLAYER_VISIBLE_ITEM`, the aura arrays, game object bytes) and need new sources. |
| Raw packets | 14 scripts in `shared/game` decode payloads in the vanilla layout: loot, merchant, party, taxi, talents, skills, combat events, NPC dialogs. |
| Constants | Movement flags and fixed DBC column numbers (Spell, SoundEntries, Light). |
| Character create | Death Knight is offered without the level 55 gate and without the blue button art. |
| Interface | Every screen past the glue is still the 1.12 conversion; convert each from the 3.3.5a FrameXML with `python3 ../wowgd/tools/framexml/convert.py <dump> . tools/framexml/frames.json`. |

The order: the update fields and Spell columns the HUD reads, then the packets still parsed as vanilla, then the 3.3.5a FrameXML.

## Checks

Run one with `godot --headless --path . tests/<name>.tscn`; each prints `<name>: OK` or the number of failures.
`login_check`, `world_check` and `glue_check` use the developer server as `wowgd` / `wowgd`; the other two only read the archives.

| Check | Covers |
| --- | --- |
| `login_check` | SRP6 against the authserver, the realm list, the RC4 header cipher and the WotLK `CMSG_AUTH_SESSION`, through to `SMSG_CHAR_ENUM`. |
| `world_check` | A throwaway character enters the world, walks, runs a GM command, takes a teleport, gains and loses an aura through `SMSG_AURA_UPDATE`, and logs out. |
| `model_check` | A character and a creature model: version 264 geometry from the `.skin` beside the model. |
| `terrain_check` | An Azeroth and a Northrend tile with MH2O water. |
| `glue_check` | The login screen, every race on the create screen, and the world loading round the new character. |

## References

[wowdev.wiki](https://wowdev.wiki/Main_Page) documents the file formats and protocol, mostly against 3.3.5a.
For packet layouts the AzerothCore source is the authority.
