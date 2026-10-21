#!/usr/bin/env python3
"""Writes src/font.asm: the tile patterns of the 5×7 font (own design) for the PV-1000.

The PV-1000 reads tile patterns straight from the cartridge: tile N is the 32 bytes at
N × 32, as four 8-byte planes (the first one unused here, then red, green and blue; bit 7
is the leftmost pixel). Each character has three tiles:
  - the ASCII code (0x20–0x5F): white text (red + green + blue);
  - the ASCII code + 0x40 (0x60–0x9F): white text on a full-height blue bar (the title);
  - the ASCII code + 0x80 (0xA0–0xDF): yellow text on a red bar (the "lit" form).
The lit bar is as tall as the letters (7 rows); the title bar fills the tile (8 rows).
The output covers 0x0400–0x1BFF of the ROM, which src/control-test.asm includes.

Yellow text on black (the credit line) has no room for a whole set: tiles 0xE0–0xFF hold
the program. It uses the free tiles 0x02–0x1F instead, for the characters in YELLOW only;
they go to src/font-yellow.asm (0x0040–0x03FF). Tile 0x00 is skipped (0 ends a string), and
so is tile 0x01: it holds the interrupt vector at 0x0038.

Usage:
  python3 tools/font.py                 writes src/font.asm and src/font-yellow.asm
  python3 tools/font.py --yellow TEXT   prints TEXT as a `db` line of yellow tile codes
"""
from pathlib import Path

FONT = {
    " ": [], "-": ["", "", "", "#####"], ":": ["", "##", "##", "", "##", "##"], ".": ["", "", "", "", "", "##", "##"],
    "0": [" ### ", "#   #", "#  ##", "# # #", "##  #", "#   #", " ### "],
    "1": ["  #  ", " ##  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
    "2": [" ### ", "#   #", "    #", "   # ", "  #  ", " #   ", "#####"],
    "3": ["#####", "   # ", "  #  ", "   # ", "    #", "#   #", " ### "],
    "4": ["   # ", "  ## ", " # # ", "#  # ", "#####", "   # ", "   # "],
    "5": ["#####", "#    ", "#### ", "    #", "    #", "#   #", " ### "],
    "6": ["  ## ", " #   ", "#    ", "#### ", "#   #", "#   #", " ### "],
    "7": ["#####", "    #", "   # ", "  #  ", " #   ", " #   ", " #   "],
    "8": [" ### ", "#   #", "#   #", " ### ", "#   #", "#   #", " ### "],
    "9": [" ### ", "#   #", "#   #", " ####", "    #", "   # ", " ##  "],
    "A": [" ### ", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "B": ["#### ", "#   #", "#   #", "#### ", "#   #", "#   #", "#### "],
    "C": [" ### ", "#   #", "#    ", "#    ", "#    ", "#   #", " ### "],
    "D": ["#### ", "#   #", "#   #", "#   #", "#   #", "#   #", "#### "],
    "E": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#####"],
    "F": ["#####", "#    ", "#    ", "#### ", "#    ", "#    ", "#    "],
    "G": [" ### ", "#   #", "#    ", "# ###", "#   #", "#   #", " ####"],
    "H": ["#   #", "#   #", "#   #", "#####", "#   #", "#   #", "#   #"],
    "I": [" ### ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", " ### "],
    "L": ["#    ", "#    ", "#    ", "#    ", "#    ", "#    ", "#####"],
    "M": ["#   #", "## ##", "# # #", "# # #", "#   #", "#   #", "#   #"],
    "N": ["#   #", "##  #", "# # #", "#  ##", "#   #", "#   #", "#   #"],
    "O": [" ### ", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    "P": ["#### ", "#   #", "#   #", "#### ", "#    ", "#    ", "#    "],
    "R": ["#### ", "#   #", "#   #", "#### ", "# #  ", "#  # ", "#   #"],
    "S": [" ####", "#    ", "#    ", " ### ", "    #", "    #", "#### "],
    "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  ", "  #  ", "  #  "],
    "U": ["#   #", "#   #", "#   #", "#   #", "#   #", "#   #", " ### "],
    "V": ["#   #", "#   #", "#   #", "#   #", "#   #", " # # ", "  #  "],
    "W": ["#   #", "#   #", "#   #", "# # #", "# # #", "## ##", "#   #"],
    "X": ["#   #", "#   #", " # # ", "  #  ", " # # ", "#   #", "#   #"],
    "Y": ["#   #", "#   #", " # # ", "  #  ", "  #  ", "  #  ", "  #  "],
}


def glyph(ch):
    """8 bytes: the 5×7 glyph at column 1, row 0 (bit 7 = leftmost pixel)."""
    rows = FONT[ch] + [""] * (8 - len(FONT[ch]))
    return [sum(0x40 >> i for i, c in enumerate(r.ljust(5)) if c == "#") for r in rows[:8]]


def tile(code):
    """The 32 bytes of a tile: unused plane, then red, green and blue."""
    ch = chr(base_char(code))
    if ch not in FONT:
        return [0] * 32
    g = glyph(ch)
    bar = [0xFF if row < 7 else 0 for row in range(8)]   # the lit bar: as tall as the letters
    if code >= 0xA0:
        return [0] * 8 + bar + g + [0] * 8    # lit: yellow (red + green) on red
    if code >= 0x60:
        return [0] * 8 + g + g + [0xFF] * 8     # title: white on blue, the whole tile height
    return [0] * 8 + g + g + g                # white


def base_char(code):
    """The ASCII code a tile draws."""
    return code - 0x80 if code >= 0xA0 else code - 0x40 if code >= 0x60 else code


KIND = {0x20: "", 0x60: " (title)", 0xA0: " (lit)"}

# characters with a yellow tile, in tile order from 0x02 (at most 30)
YELLOW = " .0123456789BCEILPRSY"


def yellow_code(ch):
    return 0x02 + YELLOW.index(ch)


def yellow_tile(ch):
    """Yellow (red + green) on black, the same yellow as the lit labels."""
    g = glyph(ch)
    return [0] * 8 + g + g + [0] * 8


def db(values):
    return "    db " + ",".join(f"0x{v:02X}" for v in values)


def main():
    out = [
        "; Tile patterns of the 5x7 font: GENERATED by tools/font.py, do not edit by hand.",
        "; 0x0400-0x0BFF: tiles 0x20-0x5F (white text);",
        "; 0x0C00-0x13FF: tiles 0x60-0x9F (title: white text on a full-height blue bar);",
        "; 0x1400-0x1BFF: tiles 0xA0-0xDF (lit: yellow text on a red bar).",
        "",
    ]
    for first in (0x20, 0x60, 0xA0):
        for code in range(first, first + 0x40):
            t = tile(code)
            ch = chr(base_char(code))
            name = repr(ch) if ch in FONT else "empty"
            out += [f"; tile 0x{code:02X}: {name}{KIND[first]}", db(t[0:16]), db(t[16:32])]
    src = Path(__file__).resolve().parent.parent / "src"
    (src / "font.asm").write_text("\n".join(out) + "\n")
    assert len(YELLOW) <= 30, "too many yellow characters"
    out = [
        "; Yellow tiles (yellow text on black): GENERATED by tools/font.py, do not edit by hand.",
        f"; 0x0040-0x03FF: tiles 0x02-0x{len(YELLOW) + 1:02X}, one per character of {YELLOW!r}.",
        "",
    ]
    for ch in YELLOW:
        t = yellow_tile(ch)
        out += [f"; tile 0x{yellow_code(ch):02X}: {ch!r} (yellow)", db(t[0:16]), db(t[16:32])]
    (src / "font-yellow.asm").write_text("\n".join(out) + "\n")
    print(src / "font.asm", src / "font-yellow.asm")


if __name__ == "__main__":
    import sys
    if sys.argv[1:2] == ["--yellow"]:
        text = " ".join(sys.argv[2:])
        print(f"        db {','.join(f'0x{yellow_code(c):02X}' for c in text)},0   ; {text!r} in yellow")
    else:
        main()
