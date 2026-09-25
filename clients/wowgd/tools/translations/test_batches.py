import csv
import json
from pathlib import Path
import tempfile
import unittest

import batches
import local_mt


class FormattingTests(unittest.TestCase):
    def test_model_marker_round_trip(self):
        for source in ["%s %2$d", "$/1000;s1", "$gA:B;", "$lA:B;", "|4A:B;",
                       "|Hitem:9|h[A]|h", "|cffaabbcc$s1|r", "42%"]:
            masked, values = local_mt.mask(source, {})
            self.assertEqual(local_mt.restore(masked, values), source)
        masked, values = local_mt.mask("Alpha %s", {"Alpha": "Beta"})
        self.assertEqual(local_mt.restore(masked, values), "Beta %s")
        with self.assertRaises(ValueError):
            local_mt.restore("ZXQ0 ZXQ0", ["%s", "%d"])

    def test_argument_reordering_preserves_identity(self):
        self.assertEqual(batches.text_problems("%s: %d", "%2$d: %1$s"), [])
        self.assertTrue(batches.text_problems("%s: %d", "%d: %s"))
        self.assertTrue(batches.text_problems("%s %s", "%1$s %1$s"))

    def test_precision_width_and_escaped_percent(self):
        for source, translated in [
            ("%.3g", "%g"), ("%02d", "%d"), ("%s %%", "%s %"),
            ("%-32.32s", "%s"), ("%c", ""), ("%lx", "%x"),
        ]:
            with self.subTest(source=source):
                self.assertTrue(batches.text_problems(source, translated))
        self.assertEqual(batches.text_problems("5% faster", "5% schneller"), [])

    def test_spell_tokens_and_links(self):
        for token in ["$/1000;s1", "$*10;F1", "$123s1", "$o1", "$d", "|cffaabbcc", "|r", "%99w"]:
            self.assertTrue(batches.text_problems(token, ""))
        self.assertEqual(
            batches.text_problems("|Hitem:9|h[A]|h", "|Hitem:9|h[B]|h"), []
        )
        self.assertTrue(batches.text_problems("|Hitem:9|h[A]|h", "|Hitem:8|h[B]|h"))

    def test_gender_and_plural_structure(self):
        for marker in ["$g", "$l", "$G", "|4"]:
            source = marker + "a:b;"
            self.assertEqual(batches.text_problems(source, marker + "x:y;"), [])
            for target in [marker + "x:y", marker + "xy;", marker + "x:y:z;"]:
                self.assertTrue(batches.text_problems(source, target))

    def test_newlines_and_repeated_tokens(self):
        self.assertTrue(batches.text_problems("$s1\n$s1", "$s1\n"))
        self.assertTrue(batches.text_problems("a\nb", "a b"))


class WorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="wowgd-batches-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.source = self.directory / "source.csv"
        self.work = self.directory / "work"
        self.source_rows = {"alpha": "A %s", "beta": "A %s", "gamma": "B\nC"}
        batches.write_csv(self.source, self.source_rows.items())

    def test_csv_rejects_header_duplicates_and_malformed_quotes(self):
        for text in ['id,text\na,b\n', 'key,text\na,b\na,c\n', 'key,text\na,"broken\n',
                     'key,text\na,b,c\n']:
            self.source.write_text(text)
            with self.assertRaises((ValueError, csv.Error)):
                batches.read_csv(self.source)

    def test_partial_and_complete_coverage(self):
        source = {"a": "x", "b": "y"}
        self.assertEqual(batches.validate(source, {"a": "z", "b": ""}), [])
        self.assertTrue(batches.validate(source, {"a": "z", "b": ""}, complete=True))
        self.assertTrue(batches.validate(source, {"a": "z"}))
        self.assertTrue(batches.validate(source, {"a": "z", "b": "y", "c": "q"}))

    def test_resume_dedup_overrides_and_existing_edits(self):
        batches.prepare(self.source, self.work)
        batches.prepare(self.source, self.work)
        entries = json.loads((self.work / "manifest.json").read_text())["entries"]
        self.assertEqual(len(entries), 2)
        result = self.directory / "result.csv"
        batches.write_csv(result, [(next(iter(entries)), "D %s")], ("id", "text"))
        batches.accept(self.work, "deDE", result)
        output = self.directory / "batch.json"
        batches.batch(self.work, "deDE", output, 500, 16000)
        self.assertEqual(len(json.loads(output.read_text())["entries"]), 1)
        overrides = self.directory / "overrides.csv"
        batches.write_csv(overrides, [("beta", "E %s")])
        batches.accept(self.work, "deDE", overrides, override=True)
        destination = self.directory / "deDE.csv"
        batches.write_csv(destination, [("alpha", "F %s"), ("beta", ""), ("gamma", "")])
        batches.merge(self.work, "deDE", destination)
        self.assertEqual(batches.read_csv(destination), {"alpha": "F %s", "beta": "E %s", "gamma": ""})

    def test_invalid_batch_does_not_change_checkpoint(self):
        batches.prepare(self.source, self.work)
        entries = json.loads((self.work / "manifest.json").read_text())["entries"]
        result = self.directory / "result.csv"
        batches.write_csv(result, [(next(iter(entries)), "D")], ("id", "text"))
        with self.assertRaises(ValueError):
            batches.accept(self.work, "deDE", result)
        self.assertFalse((self.work / "deDE.json").exists())

    def test_changed_source_rejected(self):
        batches.prepare(self.source, self.work)
        batches.write_csv(self.source, [("alpha", "Changed")])
        with self.assertRaises(ValueError):
            batches.prepare(self.source, self.work)

    def test_reject_english_inside_repo(self):
        with self.assertRaises(ValueError):
            batches.outside_repo(batches.ROOT / "source.csv")


if __name__ == "__main__":
    unittest.main()
