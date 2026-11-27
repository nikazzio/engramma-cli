"""Fit a terminal progress line using Unicode column widths."""

import sys
import unicodedata


def fit(text, columns):
    cells = []
    width = 0
    for character in text:
        category = unicodedata.category(character)
        if category in {"Cc", "Cs"}:
            character = "?"
        if category in {"Mn", "Me", "Cf"}:
            if cells:
                cells[-1][0] += character
            continue
        size = 2 if unicodedata.east_asian_width(character) in {"F", "W"} else 1
        if width + size > columns:
            while cells and width >= columns:
                _, removed_width = cells.pop()
                width -= removed_width
            return "".join(cell for cell, _ in cells) + "…"
        cells.append([character, size])
        width += size
    return "".join(cell for cell, _ in cells)


if __name__ == "__main__":
    print(fit(sys.argv[2], int(sys.argv[1])))
