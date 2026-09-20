<p align="center">
  <img src="wrathgd_icon.png" alt="WrathGD logo" width="200">
</p>

# WrathGD

A Godot 4.7 client for World of Warcraft 3.3.5a (build 12340) that will play on [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk).
Like [WoWGD](../wowgd), it will read the stock client's MPQs at runtime and ship no Blizzard data.

## Status

Enters the world and walks around.
The extension reads its expansion from **Project Settings > wowgd > expansion**, so one `wowdot` build serves both clients: WoWGD leaves the setting at `classic`, this project sets `wotlk`.
That choice picks the wire build, the client version, the realm list format, the packet parsers, the MPQ chain, the `data/wotlk/` tables, the movement layout and the chat type numbering.
The four checks in [`tests/`](tests) log in, create a character, enter the world, read its fields out of the update object, walk, run a GM command, take a near teleport and log out again, all against a stock AzerothCore.
They also load WotLK models and terrain tiles out of the archives: M2 version 264 geometry from its `.skin` files, and ADT water from MH2O.
The world socket also takes AzerothCore's five byte header for packets over 0x8000 bytes, which nothing the client does yet is big enough to ask for, so no check covers it.
`game/` links to [`shared/game`](../../shared/game), the GDScript both clients load, but this project still lacks the settings that code needs, so there is nothing to run but the checks.

## Requirements

- Godot 4.7 and the `wowdot` extension built from [`extension/`](../../extension) (see the [top-level README](../../README.md#building)).
- A 3.3.5a (build 12340) client folder with its `Data` directory: `common.MPQ`, `common-2.MPQ`, `expansion.MPQ`, `lichking.MPQ`, the `patch*.MPQ` files and the locale folder (for example `enUS/`).
  Set **Project Settings > wowgd > client_data_dir** to that `Data` folder; it points at `/mnt/Storage/mWoW/WOTLK_Client/Data` here.
  The locale folder's archives carry the DBCs and every string, so a `Data` folder without it loads nothing.

## Server setup

WrathGD targets the latest AzerothCore `master` commit with no source changes, no modules, and the shipped defaults for anything the client can see.
A fork with custom modules is not a valid test server.

The developer server runs from the stock checkout in `/mnt/Storage/mWoW/azerothcore-wotlk` with AzerothCore's own `docker-compose.yml` and its published `master` images, so nothing is compiled here:

```sh
cd /mnt/Storage/mWoW/azerothcore-wotlk
docker compose pull
docker compose up -d --no-build
```

`ac-client-data-init` downloads the extracted maps, vmaps, mmaps and DBCs into a volume, so the extractors need not run.
`docker compose --profile tools run ac-tools` still runs them against the client folder named by `DOCKER_AC_CLIENT_FOLDER` when a fresher set is wanted.

The gitignored `.env` also names the client folder for `ac-tools`, and moves every port off its default, since the vMaNGOS stack in `/mnt/Storage/mWoW/Vanilla/server` holds those for WoWGD:

| Port | Service |
| --- | --- |
| 3725 | authserver |
| 8095 | worldserver |
| 127.0.0.1:3307 | MySQL |
| 127.0.0.1:7879 | SOAP, once `SOAP.Enabled` is turned on in `worldserver.conf` |

The realm list the authserver hands out has to name the host's world port rather than the container's, so `acore_auth.realmlist` holds address `127.0.0.1` and port `8095`.

The account comes from the worldserver console, which is the container's tty: `docker attach ac-worldserver`, then `account create wowgd wowgd` and `account set gmlevel wowgd 3 -1` for the GM commands later checks will want.
Detach with ctrl-p ctrl-q, since ctrl-c would stop the server.

A separate server runs at `root@192.168.1.250`.
It is a deployment rather than a check target, and it was unreachable from here when this was written.

## Still to do

Most of the protocol and file format code is already in the vendored WoWee sources under `extension/wowee/`, where WotLK is the default path.
The profile setting decides what the extension speaks; what is left is the code that still reads the vanilla layout whatever the profile says.

### Extension (`extension/src`)

| Area | Work |
| --- | --- |
| Hand-parsed packets | `wow_session.cpp` still parses these in the vanilla layout: learned spells (u16 ids), cast failed, spell cooldown, quest query, quest giver status, gossip options, vendor, trainer and taxi lists, and the flying spline flag. |
| Auras | `SMSG_UPDATE_AURA_DURATION` and the `UNIT_FIELD_AURAS` fields are both gone. WotLK sends `SMSG_AURA_UPDATE` and `SMSG_AURA_UPDATE_ALL`, which arrive in the world check and are dropped, so nothing tracks a buff yet. |
| Time sync | AzerothCore asks every ten seconds with `SMSG_TIME_SYNC_REQ` and nothing answers. It only measures the clock with the reply, so nothing breaks, but the stock client does answer. |
| Animations | Version 264 keeps the sequences without flag 0x20 in `<model><id>-<variation>.anim` files. A model has hundreds of them, so they want loading when an animation is asked for rather than with the model, which is work for whatever drives animation here. |

### Game code

`shared/game/` is about 21,000 lines of GDScript, linked in as `game/` by both clients, and roughly 75 to 85 percent of it should be reusable here.
The three tables it reads by path go through `WowLoader.data_path()`, which follows the expansion setting, so this client looks in `res://data/wotlk/` for them.

- **Project settings.** This `project.godot` has no `[autoload]`, `[input]` or `[rendering]` section, so `WowClient`, `WowAssets` and every input action the world and interface bind are missing. Bringing those across is what it takes to run `res://game/main.tscn` here at all.
- **Data tables.** `data/wotlk/` holds only the three protocol tables: `ui_sounds.json`, `spell_failures.json` and `equip_failures.json` have no WotLK versions yet. `dbc_layouts.json` also lacks tables the game reads (ChrRaces, ChrClasses, SpellCastTimes, SpellDuration, SpellRadius, HelmetGeosetVisData, QuestSort, WorldMapOverlay and others), and `update_fields.json` has 62 entries where the game code uses 324.
- **Removed fields.** `UNIT_FIELD_AURAS`, `UNIT_VIRTUAL_ITEM_*` and the 12-field `PLAYER_VISIBLE_ITEM` stride are gone in WotLK, and quest log slots grow from 3 fields to 5.
- **Raw packets.** 14 scripts decode payloads in the vanilla layout (loot, merchant, party, taxi, talents, skills, combat events, NPC dialogs and others).
- **Constants.** Movement flag values, fixed DBC column numbers (Spell, SoundEntries, Light), and the character create screen's 8 races without Death Knights.
- **UI.** The 3.3.5a FrameXML differs from 1.12's, so `tools/framexml/convert.py` has to run against the WotLK interface files, with a `frames.json` of its own.

### Order

The game code is shared and the extension answers for both expansions everywhere a check reaches, so the work left is on the GDScript side: the project settings first, so `main.tscn` runs, then the tables and the packet layouts the interface reads, then the 3.3.5a FrameXML.

## Checks

Each check prints `<name>: OK` or the number of failures.
Run one with `godot --headless --path . tests/<name>.tscn`.
`login_check` and `world_check` log into the developer server as `wowgd` / `wowgd`; the other two only read the archives.

| Check | Covers |
| --- | --- |
| `login_check` | Northrend out of Map.dbc, which only the WotLK chain's locale archive carries, then the handshake: SRP6 against the authserver, the realm list, the RC4 header cipher and the WotLK `CMSG_AUTH_SESSION`, through to `SMSG_CHAR_ENUM`. |
| `world_check` | A character of its own, made and deleted again: entering the world, its health and level read through the WotLK update field indices, walking on heartbeats that name the mover, a GM command as say with the answer read back, and a near teleport whose ack has to land before the walk after it counts. |
| `model_check` | A character and a creature model: version 264, the batches and geometry that only arrive once the `.skin` beside the model is read. |
| `terrain_check` | An Azeroth and a Northrend tile: 256 terrain chunks each, and MH2O water through the LiquidType.dbc rows that name which of the four liquid materials to use. |

## References

[wowdev.wiki](https://wowdev.wiki/Main_Page) documents the client's file formats and much of the protocol, and most of it is written against 3.3.5a (12340): M2 with `.skin` and `.anim`, ADT/v18 with MH2O, WMO and the WotLK DBC tables.
For packet layouts the AzerothCore source is the authority, since it is what the server sends.
