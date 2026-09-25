#!/usr/bin/env python3
"""Offline, resumable translation batches. Source and checkpoints stay outside the repo."""

import argparse
from collections import Counter
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[4]
LOCALES = ("deDE", "frFR", "esES", "esMX", "zhCN", "zhTW", "koKR")
GLOSSARY = (
    "ChrRaces.", "ChrClasses.", "AreaTable.", "Faction.Name.", "SkillLine.Name.",
    "TalentTab.", "CreatureType.", "CreatureFamily.", "ItemSubClass.",
)
# A space after % is prose (e.g. a percentage), not a printf space flag in this corpus.
PRINTF = re.compile(r"%(?:(\d+)\$)?([-+#0]*\d*(?:\.\d+)?(?:hh|ll|[hlLzjt])?[sdcifuoxXeEgG])|%%")
TOKEN = re.compile(
    r"\|H[^|]*\|h|\|T[^|]*\|t|\|c[0-9a-fA-F]{8}|\|[rh4n]|\|\||"
    r"\$(?:[/\*][\d.]+;)?\d*[a-zA-Z]\d*|%\d+w"
)
GRAMMAR = re.compile(r"(\$[gGlL]|\|4)([^:;]*):([^;]*);")


def outside_repo(path):
    path = Path(path).resolve()
    if path == ROOT or ROOT in path.parents:
        raise ValueError("English source and work files must be outside the repository")
    return path


def read_csv(path, header=("key", "text")):
    with Path(path).open(encoding="utf-8", newline="") as file:
        reader = csv.reader(file, strict=True)
        if next(reader, None) != list(header):
            raise ValueError(f"{path}: expected {','.join(header)} header")
        rows = {}
        for row in reader:
            if len(row) != 2 or not row[0]:
                raise ValueError(f"{path}:{reader.line_num}: expected two columns and a key")
            if row[0] in rows:
                raise ValueError(f"{path}:{reader.line_num}: duplicate key {row[0]}")
            rows[row[0]] = row[1]
    return rows


def atomic_text(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    previous_mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as file:
            file.write(text)
            file.flush()
            os.fsync(file.fileno())
        os.chmod(temporary, previous_mode)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def write_csv(path, rows, header=("key", "text")):
    out = io.StringIO(newline="")
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(header)
    writer.writerows(rows)
    atomic_text(path, out.getvalue())


def write_json(path, value):
    atomic_text(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def signature(text):
    args = Counter()
    position = 1
    for found in PRINTF.finditer(text):
        if found[0] == "%%":
            args["%%"] += 1
        else:
            index = int(found[1]) if found[1] else position
            args[f"{index}:{found[2]}"] += 1
            position += 1
    tokens = Counter(TOKEN.findall(PRINTF.sub("", text)))
    grammar = Counter((found[1], found[3].count(":")) for found in GRAMMAR.finditer(text))
    return args, tokens, grammar


def text_problems(source, target):
    problems = []
    if source.count("\n") != target.count("\n"):
        problems.append("changed line breaks")
    for name, expected, actual in zip(
        ("printf arguments", "game tokens", "gender/plural expressions"),
        signature(source), signature(target),
    ):
        if expected != actual:
            problems.append(f"changed {name}")
    return problems


def validate(source, translated, complete=False):
    problems = []
    for key in translated.keys() - source.keys():
        problems.append(f"unknown key {key}")
    for key in source.keys() - translated.keys():
        problems.append(f"missing key {key}")
    for key, text in translated.items():
        if key not in source:
            continue
        if text:
            problems.extend(f"{key}: {issue}" for issue in text_problems(source[key], text))
        elif complete:
            problems.append(f"{key}: empty translation")
    return problems


def require_valid(problems):
    if problems:
        raise ValueError("\n".join(problems[:30]) + f"\n{len(problems)} problems")


def prepare(source_path, work):
    source_path = outside_repo(source_path)
    work = outside_repo(work)
    source = read_csv(source_path)
    if not source:
        raise ValueError("empty source export")
    digest = hashlib.sha256(source_path.read_bytes()).hexdigest()
    manifest = work / "manifest.json"
    if manifest.exists():
        if json.loads(manifest.read_text())["sha256"] != digest:
            raise ValueError("source changed; use a new work directory")
    else:
        entries = {}
        for key, text in source.items():
            identity = hashlib.sha256(text.encode()).hexdigest()[:20]
            entry = entries.setdefault(identity, {"source": text, "keys": []})
            if entry["source"] != text:
                raise ValueError("source identifier collision")
            entry["keys"].append(key)
        write_csv(work / "enUS.csv", source.items())
        write_json(manifest, {"sha256": digest, "entries": entries})
    data = json.loads(manifest.read_text())
    print(f"{len(source)} keys, {len(data['entries'])} unique strings; work: {work}")


def load_work(work, locale):
    work = outside_repo(work)
    manifest = json.loads((work / "manifest.json").read_text())
    path = work / f"{locale}.json"
    state = json.loads(path.read_text()) if path.exists() else {
        "sha256": manifest["sha256"], "translations": {}, "overrides": {},
    }
    if state["sha256"] != manifest["sha256"]:
        raise ValueError("checkpoint source mismatch")
    return work, manifest["entries"], state


def batch(work, locale, output, limit, max_chars):
    work, entries, state = load_work(work, locale)
    pending = [(i, e) for i, e in entries.items() if i not in state["translations"]]
    pending.sort(key=lambda pair: not any(k.startswith(GLOSSARY) for k in pair[1]["keys"]))
    selected, size = [], 0
    for identity, entry in pending:
        if selected and (len(selected) >= limit or size + len(entry["source"]) > max_chars):
            break
        selected.append({"id": identity, **entry})
        size += len(entry["source"])
    glossary = [
        {"source": e["source"], "text": state["translations"][i]}
        for i, e in entries.items()
        if i in state["translations"] and any(k.startswith(GLOSSARY) for k in e["keys"])
    ]
    write_json(outside_repo(output), {"locale": locale, "glossary": glossary, "entries": selected})
    print(f"{locale}: wrote {len(selected)} strings; {len(pending)} remaining")


def accept(work, locale, input_path, override=False):
    work, entries, state = load_work(work, locale)
    supplied = read_csv(outside_repo(input_path), ("key" if override else "id", "text"))
    source = read_csv(work / "enUS.csv") if override else {
        i: e["source"] for i, e in entries.items()
    }
    problems = []
    for identity, target in supplied.items():
        if identity not in source:
            problems.append(f"unknown identifier {identity}")
        elif not target.strip():
            problems.append(f"{identity}: empty translation")
        else:
            problems.extend(f"{identity}: {p}" for p in text_problems(source[identity], target))
    require_valid(problems)
    state["overrides" if override else "translations"].update(supplied)
    write_json(work / f"{locale}.json", state)
    unchanged = sum(t == source[i] for i, t in supplied.items())
    print(f"{locale}: accepted {len(supplied)}; {unchanged} unchanged source strings to review")


def merge(work, locale, destination):
    work, entries, state = load_work(work, locale)
    source = read_csv(work / "enUS.csv")
    destination = Path(destination)
    existing = read_csv(destination) if destination.exists() else dict.fromkeys(source, "")
    require_valid(validate(source, existing))
    by_key = {
        key: state["translations"][identity]
        for identity, entry in entries.items() if identity in state["translations"]
        for key in entry["keys"]
    }
    by_key.update(state["overrides"])
    merged = {key: existing.get(key) or by_key.get(key, "") for key in source}
    require_valid(validate(source, merged))
    write_csv(destination, merged.items())
    print(f"{locale}: {sum(bool(t) for t in merged.values())}/{len(source)} translated keys")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare")
    prep.add_argument("--source", required=True, type=Path)
    prep.add_argument("--work", required=True, type=Path)
    check = commands.add_parser("check")
    check.add_argument("--source", required=True, type=Path)
    check.add_argument("--file", required=True, type=Path)
    check.add_argument("--complete", action="store_true")
    for name in ("batch", "accept", "merge"):
        command = commands.add_parser(name)
        command.add_argument("--work", required=True, type=Path)
        command.add_argument("--locale", required=True, choices=LOCALES)
        if name == "batch":
            command.add_argument("--output", required=True, type=Path)
            command.add_argument("--limit", type=int, default=500)
            command.add_argument("--max-chars", type=int, default=16000)
        elif name == "accept":
            command.add_argument("--input", required=True, type=Path)
            command.add_argument("--override", action="store_true")
        else:
            command.add_argument("--destination", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            prepare(args.source, args.work)
        elif args.command == "batch":
            if args.limit < 1 or args.max_chars < 1:
                raise ValueError("batch limits must be positive")
            batch(args.work, args.locale, args.output, args.limit, args.max_chars)
        elif args.command == "accept":
            accept(args.work, args.locale, args.input, args.override)
        elif args.command == "merge":
            merge(args.work, args.locale, args.destination or ROOT / "translations/wowgd" / f"{args.locale}.csv")
        else:
            source = read_csv(outside_repo(args.source))
            translated = read_csv(args.file)
            problems = validate(source, translated, args.complete)
            print(f"{args.file.name}: {sum(bool(t) for t in translated.values())}/{len(source)} translated, "
                  f"{len(translated)} keys, {len(problems)} problems")
            require_valid(problems)
    except (OSError, ValueError, csv.Error) as error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
