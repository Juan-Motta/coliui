#!/usr/bin/env python3
"""Regenerates the colour table of docs/DESIGN.md from Palette in DesignSystem.swift.

Usage: python3 scripts/make-design-swatches.py

Writes one SVG swatch per colour into docs/design/swatches (light half on the light window, dark half
on the dark window, so translucent colours show as they do in the app) and replaces the table between
the COLOURS markers in docs/DESIGN.md.
"""
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Sources/ColiUI/Shared/DesignSystem.swift"
DOC = ROOT / "docs/DESIGN.md"
SWATCHES = ROOT / "docs/design/swatches"

RGB = r"rgb\(([^)]*)\)|\.white"
LINE = re.compile(r"static let (\w+) = (?:dynamic\(\s*(" + RGB + r")\s*,\s*(" + RGB + r")\s*\)|Color\(nsColor: (" + RGB + r")\))")
COMMENT = re.compile(r"^\s*///\s?(.*)$")


def parse(color: str) -> tuple[int, int, int, float]:
    if color.strip() == ".white":
        return 255, 255, 255, 1.0
    parts = [p.strip() for p in color[color.index("(") + 1:color.rindex(")")].split(",")]
    r, g, b = (int(p, 0) for p in parts[:3])
    return r, g, b, float(parts[3]) if len(parts) > 3 else 1.0


def css(c: tuple[int, int, int, float]) -> str:
    r, g, b, a = c
    return f"#{r:02X}{g:02X}{b:02X}" if a == 1 else f"rgba({r}, {g}, {b}, {a:g})"


def swatch(light, dark) -> str:
    def fill(c):
        r, g, b, a = c
        return f'fill="rgb({r},{g},{b})" fill-opacity="{a:g}"'
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="24" viewBox="0 0 64 24">'
        '<rect width="32" height="24" fill="#FBFBFD"/><rect x="32" width="32" height="24" fill="#1C1C1E"/>'
        f'<rect x="4" y="4" width="24" height="16" rx="4" {fill(light)}/>'
        f'<rect x="36" y="4" width="24" height="16" rx="4" {fill(dark)}/>'
        '<rect x="0.5" y="0.5" width="63" height="23" rx="5.5" fill="none" stroke="#000" stroke-opacity="0.12"/>'
        "</svg>\n"
    )


def main() -> None:
    lines = SOURCE.read_text().splitlines()
    start = next(i for i, line in enumerate(lines) if line.startswith("enum Palette"))
    end = next(i for i in range(start, len(lines)) if lines[i].startswith("    private static func rgb"))
    SWATCHES.mkdir(parents=True, exist_ok=True)
    rows, note = [], []
    for line in lines[start:end]:
        if m := COMMENT.match(line):
            note.append(m.group(1))
            continue
        m = LINE.search(line)
        if not m:
            note = [] if not line.strip() else note
            continue
        name = m.group(1)
        if m.group(2):
            light, dark = parse(m.group(2)), parse(m.group(4))
        else:
            light = dark = parse(m.group(6))
        (SWATCHES / f"{name}.svg").write_text(swatch(light, dark))
        same = light == dark
        values = f"`{css(light)}`" + ("" if same else f" / `{css(dark)}`")
        # Notes point at canvas artboards ("Settings.dc.html: …"), which only the maintainer can open.
        text = re.sub(r"\s*\(\w+\.dc\.html[^)]*\)", "", " ".join(note))
        text = re.sub(r"\b\w+\.dc\.html(\s*/\s*\w+\.dc\.html)*:?\s*", "", text).strip()
        rows.append(f"| ![{name}](design/swatches/{name}.svg) | `Palette.{name}` | {values} | {text[:1].upper() + text[1:]} |")
        note = []
    table = "\n".join(["| | Token | Light / dark | Notes |", "| --- | --- | --- | --- |", *rows])
    doc = DOC.read_text()
    begin, finish = "<!-- COLOURS:BEGIN (scripts/make-design-swatches.py) -->", "<!-- COLOURS:END -->"
    doc = doc[: doc.index(begin) + len(begin)] + "\n" + table + "\n" + doc[doc.index(finish):]
    DOC.write_text(doc)
    print(f"{len(rows)} colours → {DOC.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
