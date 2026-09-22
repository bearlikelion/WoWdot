# WoWGD checks

The checks in [`tests/`](../tests) log in as `wowgd` / `wowgd` and use the account's first character.
They reach whatever `--realm=<address>` names, falling back to the realmlist the client saved last.
Run one with `godot --headless --path . tests/<name>.tscn -- --realm=<address>`, or without `--headless` for the ones that take screenshots.
Each prints `<name>: OK` or the number of failures.

The shell-driven checks (`*.sh`) follow the saved realmlist.
`party_check.sh` and `remote_movement_check.sh` need a second account, `wowgd2` / `wowgd2`, and `death_check.sh` makes and removes its own character.
A character left dead cannot use chat, which breaks the GM commands later checks rely on; revive it from the server with `bin/soap.sh "revive <name>"`.

| Check | Covers |
| --- | --- |
| `glue_check` | Login, realm list, character create and delete. |
| `play_check`, `targeting_check`, `combat_check`, `combat_log_check` | Entering the world, targeting and combat. |
| `panels_check` | Every panel, quest add and abandon. |
| `npc_check`, `npc_services_check.sh`, `bank_check` | Gossip, quests, vendor, trainer, flights, the bank. |
| `mail_check`, `auction_check` | The mailbox and the auction house. |
| `loot_check`, `party_check.sh` | Loot and parties. |
| `trade_check.sh`, `friends_check`, `guild_check` | Trading, the friends and ignore lists, the guild window. |
| `bubble_check`, `pet_check.sh` | Speech bubbles; a warlock's imp, its frame, bar and spellbook. |
| `level_check` | A GM level up: the chime, the notice, the stat gains, the rings, and nameplates coloured by reaction. |
| `hunter_check.sh` | Taming, naming, happiness and the stable, with a throwaway hunter. Needs a quiet machine. |
| `remote_motion_check`, `remote_movement_check.sh` | Other players' movement. |
| `movement_check`, `swim_check` | Forced speed, root, water walk, feather fall and knockback; swimming, the wake, the splash and the breath timer. |
| `stance_check`, `target_of_target_check` | The stance bar and the target of target frame. |
| `emote_check`, `channel_check` | Slash emotes and chat channels. |
| `read_check` | A GM-made book opens in the reading window and turns its page. |
| `zoning_check`, `death_check.sh` | Zoning between maps; dying, releasing and resurrecting. |
| `sheath_check`, `sky_check` | Sheathing; sky, light and weather. |
| `ribbon_check` | M2 ribbon emitters. No server needed. |
| `wmo_liquid_check` | A building's own water: Stormwind's canals answer the liquid height from inside. |
| `audio_check`, `effects_check` | Audio; scrolling textures and particle emitters. No server needed. |
| `spell_target_check`, `visual_check` | Self-only buffs cast on the caster; the spell visual chain resolves. No server needed. |
| `effect_check` | A fireball crosses to its target and a lootable corpse sparkles. |
| `chase_check` | A pulled creature closes to melee and follows a running player. |
| `outfit_check` | The create screen's preview wears what CharStartOutfit.dbc gives it. No server needed. |
| `realm_list_check` | A long realm list scrolls. No server needed. |
| `interface_options_check` | Answered options can be ticked, the rest are greyed. No server needed. |
| `key_binding_check` | The key binding window lists bindings and a press rebinds one. No server needed. |
| `footstep_check`, `map_poi_check` | The ground under a unit names its footstep; the map's landmarks follow their option. No server needed. |
| `gear_check` | Show Helm and Show Cloak reach the server. |
| `item_move_check` | Items move between the bags, the bank and the character, split and destroy. |
| `gameobject_check` | Using a game object: a chair seats the player. |
| `auction_bid_check.sh` | A second character lists an item and this one bids on it. |
| `tabard_check` | The guild crest designer previews and saves a choice. |
| `profession_check` | Learning Blacksmithing and its first recipe, then crafting the item. |
| `raid_check.sh` | Two accounts: converting to a raid, subgroups, assistants and target icons. |
| `area_trigger_check` | Walking into the Deadmines portal opens the instance. |
| `battleground_check` | The Warsong Gulch queue round trip. Needs a developer-level GM and leaves the character at level 20. |
| `transport_check` | A zeppelin carries the player along its taxi path; a Thunder Bluff lift runs its animation. |
| `petition_check.sh` | Buying, signing and handing back a guild charter. |
| `protocol_gaps_check` | Canned payloads through the newer handlers: log lines, played time, mount results, item cooldowns, proficiencies, the scoreboard, raid info and the keyring. No server needed. |
| `score_frame_check` | The battleground scoreboard fills from a canned `MSG_PVP_LOG_DATA`. No server needed. |
| `help_check` | The GM ticket window lists its categories, files a ticket and edits an open one. No server needed. |
| `stack_split_check` | The stack split window's arrows and Okay. No server needed. |
| `cinematic_check` | The human intro's camera model plays from the DBCs. No server needed. |
| `cinematic_flyover_check` | The server's `.debug play cinematic` takes the camera and hands it back. |
| `clutter_check` | Detail doodads scatter round the player and walking leaves footprints. |
| `horizon_check` | The WDL horizon mesh builds with the loaded tiles cut out. |
