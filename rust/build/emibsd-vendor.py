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
#
"""rust/build/emibsd-vendor.py <vendor dir>: the vendored crates learn the EmiBSD host.

rustc and cargo for an EmiBSD host (T3b, D-0009) compile some 45 vendored crates that choose
their code by target_os and know no "emibsd". EmiBSD's libc presents OpenBSD's interface
(D-0003), so what patches 0003 and 0004 do by hand for std and its libc, this does to every
vendored crate, mechanically, in the native build's own copy of the source (never in
build.sh's, never in upstream/):

  target_os = "openbsd"          ->  any(target_os = "openbsd", target_os = "emibsd")
                                     (in the sources and in Cargo.toml's target tables)
  <x> == "openbsd"  (build.rs)   ->  (<x> == "openbsd" || <x> == "emibsd")
  "openbsd" =>      (a match)    ->  "openbsd" | "emibsd" =>

with one exception, the one patch 0004 makes: libc's OpenBSD module links libexecinfo, which
EmiBSD does not have. A crate already naming "emibsd" before it ran (the libc std links,
patched by 0004) is left alone; a crate it changed carries .emibsd-vendor, and running it again
changes only what is still unchanged. Each crate it changes has its per-file checksums emptied,
so cargo, which checks the package against Cargo.lock, accepts the edited files. It prints what
it changed.
"""
import json
import os
import re
import sys

COND = re.compile(r'target_os\s*=\s*"openbsd"(?!\s*,\s*target_os\s*=\s*"emibsd")')
COND_ESC = re.compile(r'target_os\s*=\s*\\"openbsd\\"(?!\s*,\s*target_os\s*=\s*\\"emibsd\\")')
EQ = re.compile(r'(?<![\w.&*])((?:[A-Za-z_][\w.]*(?:\(\))?)|&\*?[A-Za-z_][\w.]*)\s*==\s*"openbsd"(?!\s*\|\|\s*\1\s*==\s*"emibsd")')
ARM = re.compile(r'"openbsd"(\s*)=>')
EXECINFO = '#[link(name = "execinfo")]'
EXECINFO_EMIBSD = ('// EmiBSD has no libexecinfo: the declarations stay, the library is not asked for.\n'
                   '#[cfg_attr(not(target_os = "emibsd"), link(name = "execinfo"))]')


def edit(text, path):
    new = COND.sub('any(target_os = "openbsd", target_os = "emibsd")', text)
    if path.endswith('Cargo.toml'):
        return COND_ESC.sub('any(target_os = \\"openbsd\\", target_os = \\"emibsd\\")', new)
    if path.endswith('build.rs') or '/build/' in path:
        new = EQ.sub(lambda m: f'({m.group(1)} == "openbsd" || {m.group(1)} == "emibsd")', new)
        new = ARM.sub(r'"openbsd" | "emibsd"\1=>', new)
    if path.replace(os.sep, '/').endswith('netbsdlike/openbsd/mod.rs'):
        new = new.replace(EXECINFO, EXECINFO_EMIBSD)
    return new


def main(vendor):
    changed = []
    for crate in sorted(os.listdir(vendor)):
        root = os.path.join(vendor, crate)
        if not os.path.isdir(root):
            continue
        files = []
        for d, _, names in os.walk(root):
            files += [os.path.join(d, n) for n in names if n.endswith('.rs') or n == 'Cargo.toml']
        texts = {}
        for f in files:
            with open(f, encoding='utf-8', errors='surrogateescape') as fh:
                texts[f] = fh.read()
        marker = os.path.join(root, '.emibsd-vendor')
        if not os.path.exists(marker) and any('"emibsd"' in t for t in texts.values()):
            continue
        n = 0
        for f, t in texts.items():
            new = edit(t, f)
            if new != t:
                with open(f, 'w', encoding='utf-8', errors='surrogateescape') as fh:
                    fh.write(new)
                n += 1
        if n:
            open(marker, 'w').close()
            ck = os.path.join(root, '.cargo-checksum.json')
            if os.path.exists(ck):
                with open(ck) as fh:
                    data = json.load(fh)
                data['files'] = {}
                with open(ck, 'w') as fh:
                    json.dump(data, fh)
            changed.append(f'{crate} ({n} files)')
    print(f'emibsd-vendor: {len(changed)} crates: ' + ', '.join(changed))


if __name__ == '__main__':
    main(sys.argv[1])
