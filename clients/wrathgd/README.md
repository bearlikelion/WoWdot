<p align="center">
  <img src="wrathgd_icon.png" alt="WrathGD logo" width="200">
</p>

# WrathGD

A Godot 4.7 client for World of Warcraft 3.3.5a (build 12340) that will play on [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk).
Like [WoWGD](../wowgd), it will read the stock client's MPQs at runtime and ship no Blizzard data.

## Status

Plays: the real client logs in, makes a character and walks around Shadowglen.
The extension reads its expansion from **Project Settings > wowgd > expansion**, so one `wowdot` build serves both clients: WoWGD leaves the setting at `classic`, this project sets `wotlk`.
That choice picks the wire build, the client version, the realm list format, the packet parsers, the MPQ chain, the `data/wotlk/` tables, the movement layout and the chat type numbering.
The five checks in [`tests/`](tests) log in, create a character, enter the world, read its fields out of the update object, walk, run a GM command, take a near teleport and log out again, all against a stock AzerothCore.
They also load WotLK models and terrain tiles out of the archives: M2 version 264 geometry from its `.skin` files, and ADT water from MH2O.
The world socket also takes AzerothCore's five byte header for packets over 0x8000 bytes, which nothing the client does yet is big enough to ask for, so no check covers it.
`game/` links to [`shared/game`](../../shared/game), the GDScript both clients load, and `res://game/main.tscn` is this project's main scene, so `godot --path .` opens the 3.3.5a login screen.
The screens themselves are this client's own: [`ui/`](ui) holds the scenes `tools/framexml/convert.py` wrote from the 3.3.5a GlueXML, which the shared scenes reach by `res://ui/<name>.tscn`, so each client draws its own interface from one set of scripts.
`glue_check` drives it the way a player would: log in, create a character on the create screen, enter the world.
That run leaves no errors or warnings in its log, which took filling in 17 DBC layout tables, the columns WotLK moved, and the game object rotation field.

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
| Animations | Version 264 keeps the sequences without flag 0x20 in `<model><id>-<variation>.anim` files. A model has hundreds of them, so they want loading when an animation is asked for rather than with the model, which is work for whatever drives animation here. |

### Game code

`shared/game/` is about 21,000 lines of GDScript, linked in as `game/` by both clients, and roughly 75 to 85 percent of it should be reusable here.
The three tables it reads by path go through `WowLoader.data_path()`, which follows the expansion setting, so this client looks in `res://data/wotlk/` for them.

- **Data tables.** `ui_sounds.json`, `spell_failures.json` and `equip_failures.json` have no WotLK versions yet, so `WowLoader.data_table()` hands the game an empty one: UI sounds are silent and a refused cast or equip has no text. They come out of the 3.3.5a FrameXML with the UI.
- **Spell.dbc.** `dbc_layouts.json` names the Spell columns the client has asked for so far. The rest of what the game code reads (reagents, cooldowns, the effect blocks, descriptions) still wants placing. Three anchors pin the layout: Speed is 47, Name_lang starts at 136, and StartRecoveryCategory and StartRecoveryTime are 205 and 206. `tools/dbc_dump.gd` prints a table's columns, and `Spell:133` prints Fireball, whose values are known.
- **Update fields.** `update_fields.json` holds 237 of the 330 names the game code asks for, written by [`tools/update_fields.py`](tools/update_fields.py) from AzerothCore's own `UpdateFields.h`, so the indices are the server's.
The other 93 are names WotLK removed rather than renamed: the corpse, game object and dynamic object positions, which now travel in the movement block; the 12 field `PLAYER_VISIBLE_ITEM` stride, of which only the entry id survives; the aura arrays, virtual items and training points; the old weekly honour counters; and the game object state, type, art kit and animation progress, which WotLK packs into `GAMEOBJECT_BYTES_1`.
Seven of the hand written entries were wrong and the generator corrected them, `UNIT_FIELD_TARGET` from 6 to 18, `UNIT_FIELD_BYTES_1` from 137 to 74 and `UNIT_DYNAMIC_FLAGS` from 147 to 79 among them, so targeting, stand state and the tapped and lootable flags were reading the wrong indices.
- **Raw packets.** 14 scripts decode payloads in the vanilla layout (loot, merchant, party, taxi, talents, skills, combat events, NPC dialogs and others).
- **Constants.** Movement flag values and fixed DBC column numbers (Spell, SoundEntries, Light).
- **Character creation.** The create screen offers all ten races, Draenei and Blood Elves included, and the class lists come from `CharBaseInfo.dbc`, so Death Knight appears wherever 3.3.5a lists it.
The shared script reads the race order and the icon sheet's column width from the expansion, since 3.3.5a widened the sheet from four columns to eight, and it treats the faction info panel as optional, because 3.3.5a replaced it with headings over the two race columns.
The screen does not grey Death Knight out yet; the stock client hides it until the account has a level 55 character, and `CharacterCreate_DeathKnightSwap` swaps the Accept and Back buttons to the blue art while a Death Knight is chosen, which this does not do either.
`WowStrings` now turns WoW's `|n` line break into a real newline when it loads a string, since a plain label showed it as text in the race and class blurbs.
- **Auras.** `SMSG_AURA_UPDATE` and `SMSG_AURA_UPDATE_ALL` are tracked per unit in the session and read back through `WowSession.get_auras()`, which `UnitAuras` uses whenever the profile has no `UNIT_FIELD_AURAS`, so the buff and debuff bars work off the packets rather than the fields WotLK removed.
The entry carries the spell, stack count, caster, level, duration and whether the client draws it as a buff.
- **Converted anchors.** 1.12 nests an anchor's offset in `<Offset><AbsDimension/></Offset>` while 3.3.5a writes it as `x` and `y` on the anchor itself, and the converter only read the nested form, so every 3.3.5a offset came through as zero.
`CharacterCreate.xml` alone carries 73 of them, which is why the create screen's race, class and gender buttons all collapsed into the top left corner.
The converter now reads either form, so the screens regenerate with the positions the XML asks for.
- **UI.** The login screen, character list, create screen, realm list and glue dialog are converted from the 3.3.5a GlueXML with [`tools/framexml/frames.json`](tools/framexml/frames.json), and `wrathgd.xml` grafts this project's own realmlist box onto the login screen the way WoWGD's does. Everything else in `ui/` is still the 1.12 conversion, copied in so the HUD keeps working; each screen wants converting and then the shared script pointing at whatever 3.3.5a renamed. Run the converter with `python3 ../wowgd/tools/framexml/convert.py <dump> . tools/framexml/frames.json`, where the dump comes from `--script tools/framexml/dump.gd -- --out=<dir>`.
- **Login screen polish.** The glue scene now matches the stock client closely: `wow_model_frame.gd` draws it flat, since the textures carry their own light, and leaves the draw order to the viewport, which is what the wiki's own note on login screens asks for, because the batches are not authored in a drawable order and most of them turn depth writes off.
The camera follows the client's formula, `vfov = dfov / sqrt(1 + aspect^2)`, so the 120 degree diagonal this model carries becomes 72 degrees at 4:3 and 59 at 16:9.
The extension animates the M2's colour and texture weight tracks, which is what fades the frost wyrm in as it flies past, and it keeps a batch that rests at zero alpha when its alpha is keyed, since the wyrm's fifteen batches all rest invisible and used to be culled at mesh build time.
A batch's second texture is drawn too: a mask on either UV set multiplies the first, which is what shapes the clouds, and an environment mapped one draws as a flat additive sheen, which stands in for the spherical reflection the client samples until this has a shader of its own.
Two smaller gaps are left: 3.3.5a anchors the Remember Account Name tick to the label's left edge, which lands inside the text because the converted FontString is wider than its glyphs, and the label reads "Battle.net Account Name" because that is what 3.3.5a's own `ACCOUNT_NAME` string says.
- **Diagnostics.** [`tools/`](tools) holds the scripts that answered the questions above: `dbc_dump.gd` prints a DBC's columns (`Spell:133` for a known row), `m2_dump.gd` a model's batches with their blend mode and at-rest tint, and `blp_dump.gd` a texture's size, format and alpha spread.
- **Hidden by Lua.** 3.3.5a leaves frames like `ChangedOptionsDialog` and `AccountLoginDropDown` visible in the XML and hides them from `AccountLogin.lua`, so anything the client does not drive belongs in this project's `exclude` list, as those two now are.

### Order

The client runs, so the work left is what a player would notice: the update fields and Spell columns the interface reads, the packet layouts still parsed as vanilla, then the 3.3.5a FrameXML for the screens that differ.

## Checks

Each check prints `<name>: OK` or the number of failures.
Run one with `godot --headless --path . tests/<name>.tscn`.
`login_check` and `world_check` log into the developer server as `wowgd` / `wowgd`; the other two only read the archives.

| Check | Covers |
| --- | --- |
| `login_check` | Northrend out of Map.dbc, which only the WotLK chain's locale archive carries, then the handshake: SRP6 against the authserver, the realm list, the RC4 header cipher and the WotLK `CMSG_AUTH_SESSION`, through to `SMSG_CHAR_ENUM`. |
| `world_check` | A character of its own, made and deleted again: entering the world, its health and level read through the WotLK update field indices, walking on heartbeats that name the mover, a GM command as say with the answer read back, a near teleport whose ack has to land before the walk after it counts, a buff and a debuff applied and taken off again through `SMSG_AURA_UPDATE`, and the time sync the server asks for. |
| `model_check` | A character and a creature model: version 264, the batches and geometry that only arrive once the `.skin` beside the model is read. |
| `terrain_check` | An Azeroth and a Northrend tile: 256 terrain chunks each, and MH2O water through the LiquidType.dbc rows that name which of the four liquid materials to use. |
| `glue_check` | The client as a player drives it: the login screen against the local AzerothCore, every race on the character create screen with the classes `CharBaseInfo.dbc` gives it, and the world loading around the new character until it is active. |

## References

[wowdev.wiki](https://wowdev.wiki/Main_Page) documents the client's file formats and much of the protocol, and most of it is written against 3.3.5a (12340): M2 with `.skin` and `.anim`, ADT/v18 with MH2O, WMO and the WotLK DBC tables.
For packet layouts the AzerothCore source is the authority, since it is what the server sends.
