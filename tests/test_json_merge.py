import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

MERGE = pathlib.Path(__file__).resolve().parent.parent / "lib" / "json_merge.py"


class JsonMergeTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.directory.name)

    def tearDown(self):
        self.directory.cleanup()

    def files(self, engramma, computer, base):
        paths = []
        for name, value in (("engramma", engramma), ("computer", computer), ("base", base)):
            path = self.root / f"{name}.json"
            path.write_text(json.dumps(value), encoding="utf-8")
            paths.append(path)
        return paths

    def merge(self, paths, mode, *choices):
        arguments = [sys.executable, "-I", str(MERGE), *map(str, paths), mode]
        for choice in choices:
            arguments += ["--choose", choice]
        return subprocess.run(arguments, capture_output=True, text=True, check=True).stdout

    @staticmethod
    def read(path):
        return json.loads(path.read_text(encoding="utf-8"))

    def test_choice_follows_the_key_not_the_position(self):
        # The user answered about "y" only; meanwhile "x" became a conflict too.
        paths = self.files({"x": 1, "y": 1}, {"x": 2, "y": 2}, {"x": 0, "y": 0})
        self.merge(paths, "run", "y=computer")
        engramma, computer, _ = map(self.read, paths)
        self.assertEqual(engramma, {"x": 1, "y": 2})
        self.assertEqual(computer, {"x": 2, "y": 2})

    def test_emptied_computer_file_does_not_empty_engramma(self):
        paths = self.files({"a": 1, "b": 2}, {}, {"a": 1, "b": 2})
        output = self.merge(paths, "run")
        engramma, computer, _ = map(self.read, paths)
        self.assertEqual(engramma, {"a": 1, "b": 2})
        self.assertEqual(computer, {"a": 1, "b": 2})
        self.assertIn("applied", output)

    def test_single_key_removed_on_computer_is_adopted(self):
        paths = self.files({"a": 1, "b": 2}, {"a": 1}, {"a": 1, "b": 2})
        self.merge(paths, "run")
        self.assertEqual(self.read(paths[0]), {"a": 1})


if __name__ == "__main__":
    unittest.main()
