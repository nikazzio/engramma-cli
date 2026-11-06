"""Three-way merge of a JSON settings file between engramma and this computer.

engramma keeps the shared copy, the computer keeps the file the program reads
and rewrites (Claude Code replaces it at every change), and a base copy records
what the two had in common after the last merge. For every value:

- same on both sides: nothing to do;
- changed only on the computer: copied into engramma ("adopted");
- changed only in engramma: copied onto the computer ("applied");
- changed on both sides in different ways: a conflict, left as it is until
  chosen with --choose <number>=computer|engramma.

Objects are merged key by key; anything else (arrays included) is one value.
Without a base every key present on one side only is taken, as if added there.

Usage: json_merge.py <engramma> <computer> <base> <run|dry> [--choose N=side]...
Prints one tab-separated line per change: kind, path, detail. Kinds: applied,
adopted, conflict, invalid. In run mode it writes the files that changed.
"""

import json
import os
import sys
import tempfile

MISSING = object()


def load(path):
    if not os.path.exists(path):
        return MISSING
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def describe(value):
    if value is MISSING:
        return "assente"
    text = json.dumps(value, ensure_ascii=False)
    return text if len(text) <= 80 else text[:77] + "..."


def child(value, key):
    return value.get(key, MISSING) if isinstance(value, dict) else MISSING


def ordered_keys(first, second):
    keys = list(first) if isinstance(first, dict) else []
    return keys + [key for key in second if key not in keys] if isinstance(second, dict) else keys


class Merge:
    def __init__(self, choices):
        self.choices = choices
        self.events = []
        self.conflicts = 0

    def walk(self, engramma, computer, base, path):
        """Returns (engramma, computer, base) after the merge of one value."""
        if engramma == computer:
            return engramma, computer, engramma
        if isinstance(engramma, dict) and isinstance(computer, dict) and (base is MISSING or isinstance(base, dict)):
            results = {}
            for key in ordered_keys(computer, engramma):
                results[key] = self.walk(child(engramma, key), child(computer, key), child(base, key), path + [key])
            return tuple(self.collect(results, side, order) for side, order in ((0, engramma), (1, computer), (2, base)))
        name = ".".join(path)
        if engramma == base:
            self.events.append(("adopted", name, f"{describe(engramma)} → {describe(computer)}"))
            return computer, computer, computer
        if computer == base:
            self.events.append(("applied", name, f"{describe(computer)} → {describe(engramma)}"))
            return engramma, engramma, engramma
        self.conflicts += 1
        choice = self.choices.get(self.conflicts)
        if choice == "computer":
            self.events.append(("adopted", name, f"{describe(engramma)} → {describe(computer)}"))
            return computer, computer, computer
        if choice == "engramma":
            self.events.append(("applied", name, f"{describe(computer)} → {describe(engramma)}"))
            return engramma, engramma, engramma
        self.events.append(("conflict", name, f"engramma {describe(engramma)} | computer {describe(computer)}"))
        return engramma, computer, base

    @staticmethod
    def collect(results, side, order):
        merged = {}
        for key in ordered_keys(order, results):
            value = results[key][side]
            if value is not MISSING:
                merged[key] = value
        return merged


def write(path, value):
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    handle, temporary = tempfile.mkstemp(dir=directory, prefix=".engramma-merge.")
    with os.fdopen(handle, "w", encoding="utf-8") as output:
        json.dump(value, output, ensure_ascii=False, indent=2)
        output.write("\n")
    if os.path.exists(path):
        os.chmod(temporary, os.stat(path).st_mode & 0o777)
    os.replace(temporary, path)


def parse_choices(arguments):
    choices = {}
    for index, argument in enumerate(arguments):
        if argument == "--choose" and index + 1 < len(arguments):
            number, _, side = arguments[index + 1].partition("=")
            choices[int(number)] = side
    return choices


def main(arguments):
    engramma_path, computer_path, base_path, mode = arguments[:4]
    try:
        engramma, computer, base = load(engramma_path), load(computer_path), load(base_path)
    except ValueError as error:
        print(f"invalid\t\t{error}")
        return 0
    if engramma is MISSING:
        print(f"invalid\t\t{engramma_path} non esiste")
        return 0
    if computer is MISSING:
        computer, base = engramma, engramma

    merge = Merge(parse_choices(arguments[4:]))
    new_engramma, new_computer, new_base = merge.walk(engramma, computer, base, [])
    for event in merge.events:
        print("\t".join(event))

    if mode == "run":
        if new_engramma != load(engramma_path):
            write(engramma_path, new_engramma)
        if new_computer != load(computer_path):
            write(computer_path, new_computer)
        if new_base is not MISSING and new_base != load(base_path):
            write(base_path, new_base)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
