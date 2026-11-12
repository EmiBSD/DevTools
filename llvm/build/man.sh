#!/bin/sh
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
# llvm/build/man.sh <man1 directory> [system]: the manual pages of the tools the distribution
# carries, written to <man1 directory>.
#
# LLVM's and clang's pages are the command guide of the patched source (target/llvm/src),
# rendered by Sphinx's man builder with man/conf.py (which says why upstream's own conf.py is
# not used); lld's is the mdoc page its source ships. Only the pages of what the toolchain
# installs are taken: clang, the llvm-* binutils, ld.lld. With `system`, also the pages under
# the system's names of those tools, as links (cc.1, c++.1 and cpp.1 to clang.1; ar.1, nm.1 and
# the others to their llvm-* page; ld.1 to ld.lld.1): the native tree, where those names are the
# system's commands. Reproducible: the pages' date is SOURCE_DATE_EPOCH's.
#
# Sphinx is a host tool (the user's install): EMIBSD_SPHINX_BUILD, else sphinx-build on PATH,
# else Homebrew's keg. Never touches upstream/.
set -eu
dest=${1:?the man1 directory to write}
system=${2:-}
case $dest in /*) ;; *) dest=$PWD/$dest ;; esac
cd "$(dirname "$0")/../.."
ROOT=$PWD
SRC=target/llvm/src
[ -f "$SRC/.emibsd-src" ] || { echo "man: $SRC is missing (just build llvm first)" >&2; exit 1; }
SPHINX=${EMIBSD_SPHINX_BUILD:-$(command -v sphinx-build || echo /opt/homebrew/opt/sphinx-doc/bin/sphinx-build)}
[ -x "$SPHINX" ] || { echo "man: sphinx-build not found (the user's install; EMIBSD_SPHINX_BUILD names it)" >&2; exit 1; }
EMIBSD_MAN_VERSION=$(python3 -I -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["upstream"]["version"].split("+")[0])' llvm/UPSTREAM.toml)
: "${SOURCE_DATE_EPOCH:=$(git log -1 --format=%ct)}"
EMIBSD_MAN_YEAR=$(python3 -I -c 'import sys,time; print(time.gmtime(int(sys.argv[1])).tm_year)' "$SOURCE_DATE_EPOCH")
export SOURCE_DATE_EPOCH EMIBSD_MAN_VERSION EMIBSD_MAN_YEAR

OUT=target/llvm/man
rm -rf "$OUT"
mkdir -p "$OUT" "$dest"
render() {      # <project directory> <project name> <authors line, upstream's>
    EMIBSD_MAN_DOCS="$ROOT/$SRC/$1/docs" EMIBSD_MAN_PROJECT="$2" EMIBSD_MAN_AUTHORS="$3" \
        "$SPHINX" -b man -q -c llvm/build/man -d "$OUT/$1.doctrees" "$SRC/$1/docs" "$OUT/$1" > "$OUT/$1.log" 2>&1 \
        || { echo "man: sphinx-build failed for $1:" >&2; tail -5 "$OUT/$1.log" >&2; exit 1; }
}
render llvm LLVM "Maintained by the LLVM Team (https://llvm.org/)."
render clang Clang "Maintained by the Clang / LLVM Team (<http://clang.llvm.org>)"

cp "$OUT/clang/clang.1" "$dest/clang.1"
# The binutils of the distribution (build.sh's DISTRIBUTION), each with its page.
TOOLS="ar ranlib nm objcopy strip objdump readobj readelf size strings symbolizer addr2line cxxfilt dwarfdump cov profdata"
for t in $TOOLS; do
    [ -f "$OUT/llvm/llvm-$t.1" ] || { echo "man: no page for llvm-$t in the command guide" >&2; exit 1; }
    cp "$OUT/llvm/llvm-$t.1" "$dest/llvm-$t.1"
done
cp "$SRC/lld/docs/ld.lld.1" "$dest/ld.lld.1"
if [ "$system" = system ]; then
    for n in cc c++ cpp; do ln -sf clang.1 "$dest/$n.1"; done
    for t in ar nm objdump strip ranlib readelf size strings objcopy addr2line; do ln -sf "llvm-$t.1" "$dest/$t.1"; done
    ln -sf llvm-cxxfilt.1 "$dest/c++filt.1"
    ln -sf ld.lld.1 "$dest/ld.1"
fi
chmod 644 "$dest"/*.1 2>/dev/null || true
echo "man: $(ls "$dest" | wc -l | tr -d ' ') pages in $dest"
