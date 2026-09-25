# WoWGD translations

Each `<locale>.csv` here translates WoWGD into a language the 1.12.1 client's own data lacks: `koKR`, `frFR`, `deDE`, `zhCN`, `zhTW`, `esES` or `esMX`.
A language shows up in Video Options once its file has at least one translated line.
The client uses the file only when the game's own MPQs have no text in that language, so a localized client keeps Blizzard's translation.

## Format

Two columns, `key,text`, under a `key,text` header row.
A key names a DBC string by table, column and record ID (`Spell.Name.133`), or an interface string by its GlobalStrings key (`ACCEPT`).
A missing or empty text falls back to English.
The files hold no English text.

## Contributing

Fix lines in the locale's CSV and keep every code the game fills in, such as `%s`, `$d`, `$o1`, `|cffffd100` or `|r`, in whatever order the sentence needs.
Players can also edit the `translations` folder beside the WoWGD executable; a change applies on the next launch.
