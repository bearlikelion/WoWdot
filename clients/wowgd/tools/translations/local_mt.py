#!/usr/bin/env python3
"""Translate prepared batches with a local CTranslate2 NLLB model, without network calls."""

import argparse
from collections import Counter
import ctypes
import json
import os
from pathlib import Path
import re
import site
import time

import batches


LANGUAGES = {
    "deDE": "deu_Latn", "frFR": "fra_Latn", "esES": "spa_Latn",
    "esMX": "spa_Latn", "zhCN": "zho_Hans", "zhTW": "zho_Hant", "koKR": "kor_Hang",
}
MARKER = re.compile(r"ZXQ\s*(\d+)\s*QXZ", re.IGNORECASE)
NUMBERS = re.compile(r"(?<!\w)\d+(?:[.,]\d+)*(?!\w)")


def protected_spans(text, glossary):
    spans = []
    for grammar in batches.GRAMMAR.finditer(text):
        spans.extend([
            (grammar.start(1), grammar.end(1), grammar[1]),
            (grammar.end(2), grammar.end(2) + 1, ":"),
            (grammar.end() - 1, grammar.end(), ";"),
        ])
    for pattern in (batches.PRINTF, batches.TOKEN, NUMBERS):
        for found in pattern.finditer(text):
            if not any(start < found.end() and found.start() < end for start, end, _ in spans):
                spans.append((found.start(), found.end(), found[0]))
    if glossary:
        names = re.compile(r"(?<!\w)(?:" + "|".join(
            re.escape(term) for term in sorted(glossary, key=len, reverse=True)
        ) + r")(?!\w)")
        for found in names.finditer(text):
            if not any(start < found.end() and found.start() < end for start, end, _ in spans):
                spans.append((found.start(), found.end(), glossary[found[0]]))
    return sorted(spans)


def mask(text, glossary):
    spans = protected_spans(text, glossary)
    parts, replacements, at = [], [], 0
    for start, end, replacement in spans:
        parts.extend([text[at:start], f"ZXQ{len(replacements)}QXZ"])
        replacements.append(replacement)
        at = end
    parts.append(text[at:])
    return "".join(parts), replacements


def restore(text, replacements):
    found = [int(m[1]) for m in MARKER.finditer(text)]
    if Counter(found) != Counter(range(len(replacements))):
        raise ValueError("model changed protected markers")
    return MARKER.sub(lambda m: replacements[int(m[1])], text)


def style(source, text, locale):
    if locale == "deDE":
        # Convert common player-directed constructions; avoid third-person narrative pronouns.
        if re.search(r"\byou(?:r|rs|rself)?\b", source, re.I):
            for old, new in [
                ("Sie müssen", "Ihr müsst"), ("Sie können", "Ihr könnt"),
                ("Sie haben", "Ihr habt"), ("Sie sind", "Ihr seid"),
                ("Sie werden", "Ihr werdet"), ("Sie wollen", "Ihr wollt"),
                ("Sie dürfen", "Ihr dürft"), ("Sie sollten", "Ihr solltet"),
                ("Sie benötigen", "Ihr benötigt"), ("Sie erhalten", "Ihr erhaltet"),
                ("Sie versuchen", "Ihr versucht"), ("Sie befinden sich", "Ihr befindet Euch"),
                ("Sie wurden", "Ihr wurdet"), ("Sie waren", "Ihr wart"),
                ("du musst", "Ihr müsst"), ("du kannst", "Ihr könnt"),
                ("du hast", "Ihr habt"), ("du bist", "Ihr seid"),
            ]:
                text = text.replace(old, new)
            text = re.sub(r"\bIhnen\b", "Euch", text)
            for old, new in [("deinen", "Euren"), ("deinem", "Eurem"), ("deiner", "Eurer"),
                             ("deines", "Eures"), ("deine", "Eure"), ("dein", "Euer")]:
                text = re.sub(r"\b" + old + r"\b", new, text, flags=re.I)
        for old, new in [
            ("Klicken Sie", "Klickt"), ("Wählen Sie", "Wählt"),
            ("Drücken Sie", "Drückt"), ("Geben Sie", "Gebt"),
            ("Halten Sie", "Haltet"), ("Ziehen Sie", "Zieht"),
            ("Bewegen Sie", "Bewegt"), ("Benutzen Sie", "Benutzt"),
            ("Verwenden Sie", "Verwendet"), ("Stellen Sie", "Stellt"),
        ]:
            text = text.replace(old, new)
    elif locale == "esMX":
        for old, new in [("ordenador", "computadora"), ("ratón", "mouse"),
                         ("vosotros", "ustedes"), ("vosotras", "ustedes")]:
            text = re.sub(r"\b" + old + r"\b", new, text)
    return text


class Model:
    def __init__(self, path, device, batch_size):
        os.environ.setdefault("CUDA_MODULE_LOADING", "LAZY")
        # The optional CUDA wheel can coexist with a different system CUDA major version.
        for directory in site.getsitepackages():
            library = Path(directory) / "nvidia/cublas/lib"
            for name in ("libcublasLt.so.12", "libcublas.so.12"):
                if (library / name).exists():
                    ctypes.CDLL(str(library / name), mode=ctypes.RTLD_GLOBAL)
        import ctranslate2
        import sentencepiece
        self.processor = sentencepiece.SentencePieceProcessor(
            model_file=str(path / "sentencepiece.bpe.model")
        )
        self.translator = ctranslate2.Translator(
            str(path), device=device, compute_type="int8_float16" if device == "cuda" else "int8",
            inter_threads=1, intra_threads=6,
        )
        self.batch_size = batch_size
        self.cache = {}

    def translate(self, texts, language):
        pending = list(dict.fromkeys(t for t in texts if t.strip() and (language, t) not in self.cache))
        pending.sort(key=len)
        for start in range(0, len(pending), self.batch_size):
            group = pending[start:start + self.batch_size]
            tokens = [["eng_Latn"] + self.processor.encode(t, out_type=str) + ["</s>"] for t in group]
            if any(len(t) > 512 for t in tokens):
                raise ValueError("input exceeds model context; split the source before translating")
            results = self.translator.translate_batch(
                tokens, target_prefix=[[language]] * len(tokens), beam_size=2,
                max_input_length=512, max_decoding_length=min(512, max(map(len, tokens)) * 3 + 32),
            )
            for source, result in zip(group, results):
                self.cache[language, source] = self.processor.decode(result.hypotheses[0][1:]).strip()
        return [self.cache[language, t] if t.strip() else t for t in texts]


def pieces(text, processor):
    if len(processor.encode(text)) <= 380:
        return [text]
    parts = re.split(r"(?<=[.!?;]) +", text)
    out, current = [], ""
    for part in parts:
        if len(processor.encode(current + " " + part)) > 380:
            if current:
                out.append(current)
            current = ""
            if len(processor.encode(part)) > 380:
                words = part.split(" ")
                for word in words:
                    if len(processor.encode(current + " " + word)) > 380:
                        out.append(current)
                        current = ""
                    current = (current + " " + word).strip()
                continue
        current = (current + " " + part).strip()
    if current:
        out.append(current)
    return out


def translate_entries(model, entries, glossary, locale):
    prepared, inputs = [], []
    for identity, entry in entries:
        lines = []
        for line in entry["source"].split("\n"):
            sentence_parts = []
            for part in pieces(line, model.processor):
                masked, replacements = mask(part, glossary)
                sentence_parts.append((len(inputs), part, replacements))
                inputs.append(masked)
            lines.append(sentence_parts)
        prepared.append((identity, entry["source"], lines))
    translated = model.translate(inputs, LANGUAGES[locale])
    completed, rejected, fragmented = {}, {}, []
    for identity, source, lines in prepared:
        output = []
        for line in lines:
            parts = []
            for index, original, replacements in line:
                try:
                    target = restore(translated[index], replacements)
                    if original.strip() and not target.strip():
                        raise ValueError("empty model output")
                except ValueError:
                    # A dropped marker cannot be guessed back into place. Translate its neighbors.
                    spans = protected_spans(original, glossary)
                    fragments, at = [], 0
                    for start, end, replacement in spans:
                        fragments.extend([(False, original[at:start]), (True, replacement)])
                        at = end
                    fragments.append((False, original[at:]))
                    prose = [t for protected, t in fragments if not protected]
                    values = iter(model.translate(prose, LANGUAGES[locale]))
                    target_parts = []
                    for protected, value in fragments:
                        if protected:
                            target_parts.append(value)
                        else:
                            result = next(values)
                            leading = re.match(r"\s*", value)[0]
                            trailing = re.search(r"\s*$", value)[0] if value.strip() else ""
                            target_parts.append(leading + result.strip() + trailing)
                    target = "".join(target_parts)
                    fragmented.append(identity)
                parts.append(style(original, target, locale))
            output.append(" ".join(parts))
        target = "\n".join(output)
        problems = batches.text_problems(source, target)
        if not target.strip() or problems:
            rejected[identity] = {"candidate": target, "problems": problems or ["empty translation"]}
        else:
            completed[identity] = target
    return completed, rejected, fragmented


def run(args):
    work, entries, state = batches.load_work(args.work, args.locale)
    model = Model(args.model, args.device, args.batch_size)
    review_path = work / f"review_{args.locale}.json"
    review = json.loads(review_path.read_text()) if review_path.exists() else {
        "rejected": {}, "fragmented": [], "unchanged": [],
    }
    start_time, processed = time.monotonic(), 0
    for glossary_phase in (True, False):
        if args.glossary_only and not glossary_phase:
            break
        glossary = {
            e["source"]: state["translations"][i]
            for i, e in entries.items()
            if i in state["translations"] and any(k.startswith(batches.GLOSSARY) for k in e["keys"])
            and len(e["source"]) >= 4
        }
        pending = [
            (i, e) for i, e in entries.items() if i not in state["translations"]
            and any(k.startswith(batches.GLOSSARY) for k in e["keys"]) == glossary_phase
        ]
        for start in range(0, len(pending), 64):
            group = pending[start:start + 64]
            if args.limit:
                group = group[:args.limit - processed]
            if not group:
                return
            done, rejected, fragmented = translate_entries(model, group, glossary, args.locale)
            state["translations"].update(done)
            state["engine"] = {"name": "NLLB-200-distilled-600M", "language": LANGUAGES[args.locale]}
            review["rejected"].update(rejected)
            for identity in done:
                review["rejected"].pop(identity, None)
            review["fragmented"] = sorted(set(review["fragmented"] + fragmented))
            review["unchanged"] = sorted(set(review["unchanged"] + [
                i for i, text in done.items() if text == entries[i]["source"]
            ]))
            batches.write_json(work / f"{args.locale}.json", state)
            batches.write_json(review_path, review)
            processed += len(group)
            print(f"{args.locale}: {len(state['translations'])}/{len(entries)} unique translated; "
                  f"{len(review['rejected'])} rejected; {len(review['fragmented'])} fragmented; "
                  f"{time.monotonic() - start_time:.0f}s", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--locale", choices=batches.LOCALES, required=True)
    parser.add_argument("--device", choices=("cpu", "cuda"), default="cpu")
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--glossary-only", action="store_true")
    args = parser.parse_args()
    if args.batch_size < 1 or args.limit < 0:
        parser.error("batch size must be positive and limit nonnegative")
    run(args)


if __name__ == "__main__":
    main()
