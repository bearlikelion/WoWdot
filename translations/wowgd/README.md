# WoWGD translations

Each `<locale>.csv` here translates WoWGD into a language the 1.12.1 client's own data lacks: `koKR`, `frFR`, `deDE`, `zhCN`, `zhTW`, `esES` or `esMX`.
A language shows up in Video Options once its file has at least one translated line.
The client uses the file only when the game's own MPQs have no text in that language, so a localized client keeps Blizzard's translation.

## Format

Two columns, `key,text`, under a `key,text` header row.
A key names a DBC string by table, column and record ID (`Spell.Name.133`), or an interface string by its GlobalStrings key (`ACCEPT`).
A missing or empty text falls back to English.
The files hold no English, because WoWGD ships no Blizzard data.

## Contributing

Export the English source from your own 1.12.1 client, and keep that file out of the repo:

```
godot --headless --path clients/wowgd -s tools/translations/translations.gd -- --export=/tmp/enUS.csv
```

Fix lines in the locale's CSV, then check it before opening a pull request:

```
godot --headless --path clients/wowgd -s tools/translations/translations.gd -- --check=deDE
```

The check fails when a translation drops or adds a code the game fills in, such as `%s`, `$d`, `$o1`, `|cffffd100` or `|r`.
Keep every one of them, in whatever order the sentence needs.

When the client starts translating a new DBC column, bring every locale's file up to the new keys; existing translations are kept:

```
godot --headless --path clients/wowgd -s tools/translations/translations.gd -- --scaffold
```

Players can also edit the `translations` folder beside the WoWGD executable; a change applies on the next launch.
