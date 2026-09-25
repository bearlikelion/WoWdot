#!/usr/bin/env python3
"""Translate checkpoint entries through a local llama.cpp TranslateGemma server."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import re
from urllib.request import Request, urlopen

import batches
import local_mt


TARGETS = {
    "deDE": ("German", "de-DE", "Use Ihr/Euch archaic formal address; never du or Sie."),
    "frFR": ("French", "fr-FR", "Address the player as vous."),
    "esES": ("Spanish (Spain)", "es-ES", "Use Spain vocabulary and vosotros."),
    "esMX": ("Spanish (Mexico)", "es-MX", "Use Latin American vocabulary and ustedes."),
    "zhCN": ("Simplified Chinese", "zh-CN", "Use Mainland terminology and Simplified Chinese."),
    "zhTW": ("Traditional Chinese", "zh-TW", "Use Taiwan terminology and Traditional Chinese."),
    "koKR": ("Korean", "ko-KR", "Use a consistent formal game UI register."),
}
MARKER = re.compile(r"ZXQ\s*(\d+)\s*QXZ", re.I)


def protected(text, glossary):
    return local_mt.mask(text, glossary)


def request(server, source, locale, glossary):
    language, code, note = TARGETS[locale]
    masked, replacements = protected(source, glossary)
    prompt = (
        "Translate the following World of Warcraft 1.12 user-interface string from English "
        f"to {language} ({code}). {note} Return only the translation. Keep every ZXQ<number>QXZ "
        "marker exactly once and in the same line. Keep line breaks, punctuation, and the meaning.\n\n"
        + masked
    )
    payload = {
        "prompt": "<bos><start_of_turn>user\n" + prompt +
                  "<end_of_turn>\n<start_of_turn>model\n",
        "temperature": 0.0, "n_predict": min(768, max(96, len(source) * 3)),
        "cache_prompt": True, "stop": ["<end_of_turn>", "<start_of_turn>"],
    }
    req = Request(server + "/completion", data=json.dumps(payload).encode(),
                  headers={"Content-Type": "application/json"})
    with urlopen(req, timeout=300) as response:
        target = json.load(response)["content"].strip()
    target = local_mt.restore(target, replacements)
    problems = batches.text_problems(source, target)
    return target, problems


def run(args):
    work, entries, state = batches.load_work(args.work, args.locale)
    review_path = work / f"review_{args.locale}.json"
    review = json.loads(review_path.read_text()) if review_path.exists() else {
        "rejected": {}, "fragmented": [], "unchanged": [],
    }
    glossary = {
        e["source"]: state["translations"][i]
        for i, e in entries.items()
        if i in state["translations"] and any(k.startswith(batches.GLOSSARY) for k in e["keys"])
    }
    pending = [(i, e) for i, e in entries.items() if i not in state["translations"]]
    if args.limit:
        pending = pending[:args.limit]
    for start in range(0, len(pending), args.batch):
        group = pending[start:start + args.batch]
        def translate(item):
            identity, entry = item
            try:
                target, problems = request(args.server, entry["source"], args.locale, glossary)
                return identity, target, problems
            except Exception as error:
                return identity, "", [str(error)]
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            results = list(pool.map(translate, group))
        for identity, target, problems in results:
            if problems or not target:
                review["rejected"][identity] = {"candidate": target, "problems": problems or ["empty"]}
                continue
            state["translations"][identity] = target
            review["rejected"].pop(identity, None)
            if target == entries[identity]["source"]:
                review["unchanged"].append(identity)
        state["engine"] = {"name": "TranslateGemma-4B-Q4_K_M", "server": args.server}
        batches.write_json(work / f"{args.locale}.json", state)
        batches.write_json(review_path, review)
        print(f"{args.locale}: {len(state['translations'])}/{len(entries)} translated; "
              f"{len(review['rejected'])} rejected", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--locale", choices=batches.LOCALES, required=True)
    parser.add_argument("--server", default="http://127.0.0.1:18765")
    parser.add_argument("--batch", type=int, default=32)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()
    run(args)


if __name__ == "__main__":
    main()
