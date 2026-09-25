# Machine translation handoff

Status as of 2026-09-24: the client reads the translations and the resumable local machine-translation
pipeline is implemented. English export, model files, and checkpoints stay outside the repository.
German is the active pilot; its reviewed glossary is complete and its prose translation is running in
`/tmp/wowgd-translations`. Locale CSVs are not considered ready until the strict checker and in-game
review pass.

## What exists

- `translations/wowgd/<locale>.csv` for `koKR`, `frFR`, `deDE`, `zhCN`, `zhTW`, `esES` and `esMX`: 59,015 keys each, every `text` empty.
- `translations/wowgd/README.md`: the format and contributor steps.
- `clients/wowgd/tools/translations/translations.gd`: `--export`, `--check=<locale>` and `--scaffold`.
- `clients/wowgd/tools/translations/batches.py`: outside-repository source manifests, deduplicated batches,
  atomic checkpoints, token/line-break validation, and locale merges.
- `clients/wowgd/tools/translations/local_mt.py`: offline NLLB batch runner for fallback or CPU-only hosts.
- `clients/wowgd/tools/translations/gemma_mt.py`: resumable TranslateGemma runner through a localhost
  llama.cpp server, with protected WoW placeholders and a rejection queue.
- `shared/game/translations.gd`: loads the chosen locale's CSV at startup; `WowDBC.get_text` and `WowStrings` use it when the MPQs lack that language.
- Video Options lists a language once its file has at least one translated line; a language change applies after a restart.

Uncommitted files to commit with the first translation: `extension/src/wow_dbc.*`, `extension/src/wow_session.*`, `shared/game/translations.gd`, `shared/game/video_settings.gd`, `shared/game/wow_assets.gd`, the `get_text` call sites in `shared/game/world` and `clients/wowgd/ui`, `clients/wowgd/tools/translations/`, `packaging/publish.sh` and `translations/`.

## Rules

- Never commit English: the repo holds only `key,text` per locale, because WoWGD ships no Blizzard data.
  The English source and every work file below live in `/tmp`.
- Keep every code the game fills in: `%s`, `%d`, `$s1`, `$d`, `$o1`, `$123s1`, `|cffffd100`, `|r` and `|4`.
  Arguments may be reordered with positional `%1$s` and `%2$s`; the check accepts that.
- `$gmale:female;` and `$lsingular:plural;` keep their `$g`/`$l`, `:` and `;`, with the words inside translated.
- Keep line breaks inside a string where the English has them.
- An empty `text` falls back to English, so a partial translation is safe to ship.

## Language notes

| Locale | Language | Notes |
| --- | --- | --- |
| deDE | German | Address the player as "Ihr/Euch", the archaic formal register German WoW uses. |
| frFR | French | Address the player as "vous". |
| esES | Spanish (Spain) | Spain vocabulary and "vosotros". |
| esMX | Spanish (Mexico) | Latin American vocabulary and "ustedes"; not a copy of esES. |
| koKR | Korean | Consistent formal game UI register. |
| zhCN | Simplified Chinese | Mainland terminology. |
| zhTW | Traditional Chinese | Taiwan terminology, translated rather than converted from zhCN. |

Use a place, race or class name's well known localized form where one exists (Stormwind is Sturmwind in German), and use it the same way everywhere.

## Steps

The implemented local workflow uses these additional commands after exporting the source:

```
python3 clients/wowgd/tools/translations/batches.py prepare \
  --source /tmp/enUS.csv --work /tmp/wowgd-translations
python3 clients/wowgd/tools/translations/gemma_mt.py \
  --work /tmp/wowgd-translations --locale deDE
python3 clients/wowgd/tools/translations/batches.py merge \
  --work /tmp/wowgd-translations --locale deDE
```

The model server is deliberately separate from the repository and should be started on localhost with
the pinned TranslateGemma model. Rejected strings remain in `review_<locale>.json` until corrected or
retranslated. Run `python3 -m unittest discover -s clients/wowgd/tools/translations -p 'test_*.py'`
before accepting a batch.

Run these from the repo root.

### 1. Export the English source

```
godot --headless --path clients/wowgd -s tools/translations/translations.gd -- --export=/tmp/enUS.csv
```

### 2. Collapse duplicates

Only about 28,000 of the 59,015 English strings are unique (spell names and ranks repeat), so translate each once:

```python
import csv
rows = list(csv.reader(open("/tmp/enUS.csv", newline="", encoding="utf-8")))[1:]
unique = dict.fromkeys(text for _, text in rows)
out = csv.writer(open("/tmp/unique.csv", "w", newline="", encoding="utf-8"), lineterminator="\n")
out.writerow(["source", "text"])
out.writerows([text, ""] for text in unique)
```

### 3. Build a glossary first

Translate the names before the prose, so spells and quests use them consistently.
Pull the rows whose keys start with `ChrRaces.`, `ChrClasses.`, `AreaTable.`, `Faction.Name`, `SkillLine.Name`, `TalentTab.`, `CreatureType.`, `CreatureFamily.` and `ItemSubClass.` from `/tmp/enUS.csv`, translate them, and keep the result as `/tmp/glossary_<locale>.csv`.
Pass that glossary along with every later batch.

### 4. Translate

Copy `/tmp/unique.csv` to `/tmp/unique_<locale>.csv` and fill its `text` column in batches of about 500 rows.
A prompt that works for Codex or any model:

> Translate the `source` column of this CSV into <language> for World of Warcraft 1.12's user interface and fill the `text` column.
> Keep every `%s`, `%d`, `%1$s`, `$s1`, `$d`, `$o1`, `|cffxxxxxx`, `|r` and `|4` code exactly; inside `$g…:…;` and `$l…:…;` translate the words and keep the markers.
> Keep line breaks.
> Use this glossary for names: <glossary>.
> <the locale's note from the table above>
> Return valid CSV with the same rows in the same order.

Crowdin works too: upload `/tmp/unique.csv` as the source with the identifier and source columns mapped, then download the translation as `/tmp/unique_<locale>.csv`.

### 5. Write the locale file

This fills every key from the unique translations and keeps any text already in the file, so community fixes survive a rerun:

```python
import csv, sys
locale = sys.argv[1]
read = lambda path: list(csv.reader(open(path, newline="", encoding="utf-8")))[1:]
done = {source: text for source, text in read(f"/tmp/unique_{locale}.csv") if text}
path = f"translations/wowgd/{locale}.csv"
kept = {key: text for key, text in read(path) if text}
out = csv.writer(open(path, "w", newline="", encoding="utf-8"), lineterminator="\n")
out.writerow(["key", "text"])
out.writerows([key, kept.get(key) or done.get(english, "")] for key, english in read("/tmp/enUS.csv"))
```

### 6. Check

```
godot --headless --path clients/wowgd -s tools/translations/translations.gd -- --check=<locale>
```

Fix every reported line, in `/tmp/unique_<locale>.csv` for a shared string or directly in the locale file, until it reports no problems.

### 7. Try it in game

Pick the language in Video Options, restart, and look at character creation (race and class names), the spellbook tooltips, the talent tabs, the world map and the login screen buttons.

### 8. Commit

Commit only `translations/wowgd/<locale>.csv`, one locale per commit, and open the PR.

## Order

Do deDE first as the pilot and review it in game before running the other six.
Then frFR, esES, esMX, zhCN, zhTW and koKR.
