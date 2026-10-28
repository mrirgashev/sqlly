#!/usr/bin/env python3
"""Retain upstream embedded-code notices, in addition to PostgreSQL COPYRIGHT.

The scan intentionally includes conditional portability implementations, making
the retained notices independent of which macOS libc functions configure finds.
No source is relicensed by collecting its original notices here.
"""
from pathlib import Path
import re
import shutil
import sys

source, runtime = map(Path, sys.argv[1:3])
project = Path(__file__).resolve().parent.parent
notices = project / "licenses"
notices.mkdir(parents=True, exist_ok=True)

parts = [
    "SQLLY bundled PostgreSQL 18.6 — upstream third-party notices\n\n"
    "PostgreSQL is distributed under its own license, reproduced separately.\n"
    "Its upstream source also contains permissively licensed components.\n"
    "This notice preserves embedded licenses, including conditional portability\n"
    "implementations that may not be used on every supported macOS version.\n\n"
    "Snowball source snapshot: d19326ac6c1b9a417fc872f7c2f845265a5e9ece\n"
    "https://github.com/snowballstem/snowball/tree/d19326ac6c1b9a417fc872f7c2f845265a5e9ece\n"
    "Unicode generated data version: 16.0 (upstream src/include/common/unicode_version.h)\n"
    "https://www.unicode.org/Public/16.0.0/ucd/ReadMe.txt\n"
    "Unicode License V3 notice retrieved from https://www.unicode.org/license.txt on 2026-10-28.\n"
]

for original, name in [
    (source / "COPYRIGHT", "LICENSE-PostgreSQL.txt"),
    (source / "src/backend/regex/COPYRIGHT", "LICENSE-Regex-Tcl.txt"),
    (notices / "LICENSE-Snowball.txt", "LICENSE-Snowball.txt"),
    (notices / "LICENSE-Unicode.txt", "LICENSE-Unicode.txt"),
    (notices / "LICENSE-Boost.txt", "LICENSE-Boost.txt"),
]:
    text = original.read_text()
    parts.append(f"\n{'=' * 72}\n{name}\n{'=' * 72}\n\n{text}\n")
    if original.resolve() != (notices / name).resolve(): shutil.copyfile(original, notices / name)
    shutil.copyfile(original, runtime / name)

roots = ["src/backend", "src/common", "src/port", "src/include", "src/timezone", "src/interfaces/libpq"]
roots += [f"src/bin/{name}" for name in ["psql", "initdb", "pg_ctl", "pg_isready", "pg_dump"]]
seen = set()
for folder in roots:
    for path in sorted((source / folder).rglob("*")):
        if path.suffix not in [".c", ".h"]: continue
        for match in re.finditer(r"/\*.*?\*/", path.read_text(errors="replace"), re.S):
            block = match.group(0)
            foreign_copyright = "\n".join(line for line in block.splitlines() if not re.search(r"Copyright.*(?:PostgreSQL|Regents of the University of California)", line, re.I))
            if not re.search(r"Redistribution and use|Permission to use|Permission is hereby|public domain|Boost Software License|LICENSE-Boost", block, re.I) and not re.search(r"copyright", foreign_copyright, re.I): continue
            # Preserve the original block in full, including punctuation and
            # copyright holders. Deduplicate identical repeated license blocks.
            if block in seen: continue
            seen.add(block)
            parts.append(f"\n{'=' * 72}\nUpstream {path.relative_to(source)}\n{'=' * 72}\n\n{block}\n")

data = source / "src/timezone/data/tzdata.zi"
parts.append("\nIANA timezone data header, upstream src/timezone/data/tzdata.zi:\n" + "\n".join(data.read_text().splitlines()[:4]) + "\n")
output = "\n".join(parts)
(notices / "THIRD-PARTY-NOTICES.txt").write_text(output)
(runtime / "THIRD-PARTY-NOTICES.txt").write_text(output)
print(f"Retained upstream notices: {len(seen)} distinct embedded blocks plus PostgreSQL/regex/Tcl/Snowball/Unicode/Boost licenses.")
