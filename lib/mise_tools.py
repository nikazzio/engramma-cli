"""The tools one mise config file asks for, read from `mise ls --current --json`.

mise lists every tool active in a folder, from all the config files it loads
(the global one, the folder's, its parents'). Only the tools whose source is
the given file are kept, so each list shows what that file asks for.

Usage: mise ls --current --json | mise_tools.py <config file>
Prints one tab-separated line per tool: name, requested version, 1 if installed.
"""

import json
import os
import sys


def main(arguments):
    target = os.path.realpath(arguments[0])
    try:
        tools = json.load(sys.stdin)
    except ValueError:
        return 1
    for name, versions in sorted(tools.items()):
        for version in versions:
            source = (version.get("source") or {}).get("path")
            if not source or os.path.realpath(source) != target:
                continue
            requested = version.get("requested_version") or version.get("version") or ""
            print(f"{name}\t{requested}\t{1 if version.get('installed') else 0}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
