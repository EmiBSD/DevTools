#!/usr/bin/env python3
#
# Copyright (c) 2026 Emilio Navarrete Lineros <enavarre@outlook.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
"""The licences of the crates a toolchain's build vendored, against docs/POLICIES.md.

usage: crates.py <toolchain dir>        every crate of upstream/<vendor dir>/, its licence, the verdict

Reads `[vendor] dir` of the directory's UPSTREAM.toml and each crate's Cargo.toml `license`
(an SPDX expression; `license-file` alone counts as unknown and is listed for the user).
The families: acceptable (ISC, MIT, BSD-2, BSD-3, Apache-2.0, Zlib, Unicode), MPL-2.0 with a
written reason in DESIGN.md, GPL/LGPL/AGPL never. An expression with OR passes if one side
passes; with AND, every side must. Exit 1 when a crate is forbidden or unknown. No network.
"""
import re
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OK = {"ISC", "MIT", "MIT-0", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "Apache-2.0 WITH LLVM-exception",
      "Zlib", "Unicode-3.0", "Unicode-DFS-2016", "0BSD", "CC0-1.0", "Unlicense", "BSL-1.0", "OpenSSL", "NCSA"}
REASONED = {"MPL-2.0"}
FORBIDDEN = re.compile(r"^(A?GPL|LGPL)")


def family(token: str) -> str:
    t = token.strip().strip("()").removesuffix("+")   # "MPL-2.0+": that licence or later
    if t in OK:
        return "ok"
    if t in REASONED:
        return "reasoned"
    if FORBIDDEN.match(t):
        return "forbidden"
    return "unknown"


def verdict(expr: str) -> str:
    # OR: the best side; AND: the worst side. Parentheses are rare in crates' expressions.
    rank = {"ok": 0, "reasoned": 1, "unknown": 2, "forbidden": 3}
    def worst(parts): return max(parts, key=rank.get)
    def best(parts): return min(parts, key=rank.get)
    return best([worst([family(t) for t in re.split(r"\s+AND\s+", side)])
                 for side in re.split(r"\s+OR\s+|/", expr)])


def main(argv):
    if len(argv) != 1:
        print(__doc__); return 2
    toml = tomllib.load(open(ROOT / argv[0] / "UPSTREAM.toml", "rb"))
    vendor = toml.get("vendor")
    if not vendor:
        print(f"crates: {argv[0]}: no [vendor] in UPSTREAM.toml"); return 0
    out = ROOT / "upstream" / vendor["dir"]
    if not (out / ".pin").exists():
        print(f"crates: {argv[0]}: {out.relative_to(ROOT)} not vendored (just fetch)"); return 0
    design = (ROOT / argv[0] / "DESIGN.md").read_text()   # a reasoned licence needs its crate named there
    rows, counts, bad = [], {}, 0
    for crate in sorted(p for p in out.iterdir() if p.is_dir()):
        meta = tomllib.load(open(crate / "Cargo.toml", "rb")).get("package", {})
        expr = meta.get("license") or ("license-file: " + meta.get("license-file", "?"))
        v = verdict(expr) if not expr.startswith("license-file") else "unknown"
        counts[expr] = counts.get(expr, 0) + 1
        name = meta.get("name", crate.name)
        if v == "reasoned":
            v = "reasoned in DESIGN.md" if f"`{name}`" in design else "reasoned, NOT in DESIGN.md"
        if v != "ok":
            rows.append((crate.name, expr, v))
        if v in ("forbidden", "unknown", "reasoned, NOT in DESIGN.md"):
            bad += 1
    print(f"crates: {argv[0]}: {sum(counts.values())} crates in {out.relative_to(ROOT)}")
    for expr, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print(f"  {n:4d}  {expr}")
    for name, expr, v in rows:
        print(f"crates: {v}: {name}: {expr}")
    if bad:
        print(f"crates: {bad} crate(s) forbidden, unknown, or MPL without a reason in DESIGN.md: docs/POLICIES.md", file=sys.stderr)
        return 1
    print("crates: every licence is acceptable")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
