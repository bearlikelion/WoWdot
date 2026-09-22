<p align="center">
  <img src="wowgd_icon.png" alt="WoWGD logo" width="200">
</p>

# WoWGD

A Godot 4.7 client for World of Warcraft 1.12.1 (build 5875) that plays on [vMaNGOS](https://github.com/vmangos/core).
It reads the stock client's MPQs at runtime and ships no Blizzard data.

## Status

Playable: log in, create a character, quest, fight, loot, group, train and fly on an unmodified vMaNGOS server.

| Area | Working |
| --- | --- |
| Login | Account, realm list, character select, create and delete, loading screen. |
| World | Streaming terrain, buildings, water, sky and weather from Light.dbc, ground clutter, the distant horizon, zone music. |
| Characters | Skin and hair, equipment on the model, sheathing, mounts, portraits, footprints. |
| Movement | Run, jump, fall, swim with a wake, taxi flights, other players' movement, server speed changes, roots, knockbacks. |
| Zoning | Continents, dungeons and portals. |
| Death | Release, corpse run, resurrect offers, spirit healer. |
| Combat | Targeting, auto attack, casts, cooldowns, auras, floating text, combat log. |
| HUD | Action bars, unit frames, cast bar, minimap, tooltips, nameplates, breath timers. |
| Chat | All channels, /who, /roll, emotes, speech bubbles. |
| Panels | Character, bags, keyring, spellbook, talents, quests, skills, reputation, world map, options, key bindings, macros, help. |
| NPCs | Gossip, quests, vendors, trainers, flight masters, bankers, auctioneers. |
| Items | Bags, bank, equipping, stack splitting, readable books and plaques. |
| Mail | Inbox, attachments, sending, returning. |
| Groups | Invites, party frames with debuffs, loot rolls, master loot, ready check, raid window, raid info. |
| Social | Trade, duels, friends, guild, charters, tabards, inspect, honor. |
| PvP | Battleground queue, scoreboard, team blips on the map. |
| Pets | Taming, pet bar, happiness, stable. |
| Effects | Particles, ribbon trails, spell visuals, missiles, cinematic flyovers. |

## Requirements

- Godot 4.7 and the `wowdot` extension built from [`extension/`](../../extension); see the [top-level README](../../README.md#building).
- A 1.12.1 client folder with its `Data` directory.
  Only stock servers are supported; ones that ship a patched client are left to forks.

## Server setup

WoWGD targets the latest vMaNGOS `development` commit with no source changes.

1. Build vMaNGOS with its default CMake options.
2. Create the `realmd`, `characters`, `mangos` and `logs` databases and load the schemas, the world database from [brotalnia/database](https://github.com/brotalnia/database) and the migrations.
3. Run `MapExtractor` from the client folder and point `DataDir` in `mangosd.conf` at the output.
4. Copy the two `.conf.dist` files, fill in the database connections, and set `StrictVersionCheck = 0` in `realmd.conf` (that check wants a hash of the stock executable, which WoWGD does not ship).
5. Set the realm's address in `realmd.realmlist` and create an account from the mangosd console: `account create wowgd wowgd`.
6. For the checks, which use GM commands: `account set gmlevel wowgd 6`.

## Running

Open this folder in Godot, set **Project Settings > wowgd > client_data_dir** to the client's `Data` folder, and run.
The login screen starts on `127.0.0.1` and remembers what you last logged in with.

Options after `--` fill the login screen for one run: `--realm=<address>`, `--account=`, `--password=`, `--character=` (logs straight in) and `--data=<Data folder>`.

## Exporting

`export_presets.cfg` has Linux and Windows presets writing to `export/wowgd/`.
Build the release libraries first (`scons target=template_release`, and `platform=windows` for Windows).
Both presets encrypt the pck, so the export needs the key and export templates compiled with it; this is why releases are built here, not in CI.
`packaging/publish.sh <tag>` then zips both exports and attaches them to a GitHub release.

## Checks

The checks in `tests/` log in as `wowgd` / `wowgd` and drive the client against a live server.
Run one with `godot --headless --path . tests/<name>.tscn -- --realm=<address>`; drop `--headless` for the ones that take screenshots.
Each prints `<name>: OK` or the number of failures.
[docs/checks.md](docs/checks.md) lists every check and what it covers.

## Still to do

| Area | Work |
| --- | --- |
| Transports | Riding a ferry across a continent boundary; other units riding a transport are not attached to it. |
| PvP | The match itself is unproven: it needs four players a side. |
| Raid | Target marks over the units wearing them, and the pulled out raid frames. |
| Looking for group | The minimap button and the browser over `MSG_LOOKING_FOR_GROUP`. |
| Other riders | Only the player's own mount is drawn. |

After that come the content tools: spells, creatures, items, quests and maps authored in Godot and exported to vMaNGOS.

## References

[wowdev.wiki](https://wowdev.wiki/Main_Page) documents the file formats and protocol, mostly for 3.3.5a, so check each page's version notes.
For packet layouts the vMaNGOS source is the authority.
