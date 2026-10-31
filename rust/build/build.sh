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
# rust/build/build.sh: rust-lang/rust at the pin of UPSTREAM.toml, with DevTools' patch
# series, built with its own x.py against llvm/'s LLVM (DESIGN.md).
#
#   sh rust/build/build.sh            (`just build rust`; EMIBSD_SYSROOT set; COMP_JOBS)
#
# 1. target/rust/src: the fetched source copied (APFS clones: instant), the series applied
#    with patch -p1, the crates `just fetch` vendored copied in as vendor/ and the two
#    .cargo/config.toml pointing cargo at them: nothing is downloaded. Made again when the pin or the
#    series changed (.emibsd-src).
# 2. target/rust/build: x.py install with target/rust/config.toml: stage0 the host's pinned
#    rustc and cargo (rust-toolchain.toml), llvm-config from llvm/'s install (T1), rustc,
#    cargo, clippy, rustfmt and the sources for the host, std for the host, core and alloc
#    for the kernel's target; installed under target/rust/install-<host>/, a directory
#    `rustup toolchain link` accepts.
# 3. tests/check.sh over the result.
#
# Never touches upstream/.
set -eu
cd "$(dirname "$0")/../.."
ROOT=$PWD
UP=upstream/rust
SRC=target/rust/src
OUT=target/rust
[ -f "$UP/.pin" ] || { echo "build: $UP not fetched (just fetch)" >&2; exit 1; }
VENDOR_SRC=$ROOT/upstream/rust-vendor            # what just fetch vendored, read-only
VENDOR=$ROOT/$SRC/vendor                           # its copy inside the source copy, writable: what cargo reads
[ -f "$VENDOR_SRC/.pin" ] || { echo "build: $VENDOR_SRC not vendored (just fetch)" >&2; exit 1; }
for t in python3 cmake ninja rustup; do command -v $t >/dev/null || { echo "build: $t not found (the user's install)" >&2; exit 1; }; done
pin=$(cat "$UP/.pin")
[ "$pin" = "$(python3 -I -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["upstream"]["commit"])' rust/UPSTREAM.toml)" ] \
    || { echo "build: $UP is not at UPSTREAM.toml's commit (just fetch)" >&2; exit 1; }
: "${EMIBSD_SYSROOT:?set EMIBSD_SYSROOT to the target libc, crt and headers, see DESIGN.md}"
[ -f "$EMIBSD_SYSROOT/usr/lib/libc.a" ] || { echo "build: $EMIBSD_SYSROOT: no usr/lib/libc.a" >&2; exit 1; }

# The host and its stage0: the toolchain rust-toolchain.toml pins, resolved to real binaries
# (the rustup proxies would pick a toolchain by the directory x.py runs cargo in).
STAGE0_RUSTC=$(rustup which rustc)
STAGE0_CARGO=$(rustup which cargo)
HOST=$("$STAGE0_RUSTC" -vV | sed -n 's/^host: //p')
LLVM=$ROOT/target/llvm/$(cc -dumpmachine 2>/dev/null || echo host)
[ -x "$LLVM/bin/llvm-config" ] || { echo "build: $LLVM/bin/llvm-config missing: just build llvm first" >&2; exit 1; }
KERNEL_TARGET=aarch64-unknown-none-softfloat          # the kernel's: core and alloc, no std (D-0006)
TARGETS="\"$HOST\", \"$KERNEL_TARGET\""
JOBS=${COMP_JOBS:-6}
# Not named after the host tuple: rustc derives its sysroot from its dylib's directory and
# takes a directory so named for lib/rustlib/<host>/lib, three levels deeper than it is.
PREFIX=$ROOT/$OUT/install-$HOST

# 1. The source copy, patched, pointed at the vendored crates.
series=$(python3 -I -c 'import sys,tomllib; print(" ".join(tomllib.load(open(sys.argv[1],"rb"))["patches"]["series"]))' rust/UPSTREAM.toml)
paths=$(python3 -I -c 'import sys,tomllib; print(" ".join(tomllib.load(open(sys.argv[1],"rb"))["upstream"]["path"]))' rust/UPSTREAM.toml)
stamp="pin $pin
paths $paths
vendor $(cat "$VENDOR_SRC/.pin")
series $series"
for p in $series; do stamp="$stamp
$(shasum -a 256 "rust/patches/$p")"; done
if [ ! -f "$SRC/.emibsd-src" ] || [ "$(cat "$SRC/.emibsd-src")" != "$stamp" ]; then
    echo "== source: $UP at $(printf %.12s "$pin") copied to $SRC, series: ${series:-none}"
    [ -d "$SRC" ] && chmod -R u+w "$SRC"
    rm -rf "$SRC"
    mkdir -p "$OUT"
    cp -c -R "$UP/" "$SRC" 2>/dev/null || cp -R "$UP/" "$SRC"
    chmod -R u+w "$SRC"
    find "$SRC" -name .git -prune -exec rm -rf {} +
    # The vendored crates, copied too: build scripts copy files with fs::copy, which keeps
    # the read-only mode of upstream/ and then cannot overwrite its own copy (libnghttp2-sys);
    # and bootstrap's rust-src step prunes the vendor directory it is pointed at.
    cp -c -R "$VENDOR_SRC" "$VENDOR" 2>/dev/null || cp -R "$VENDOR_SRC" "$VENDOR"
    chmod -R u+w "$VENDOR"
    for p in $series; do
        echo "== patch: $p"
        patch -p1 -d "$SRC" -s -N < "rust/patches/$p"
    done
    printf '%s\n' "$stamp" > "$SRC/.emibsd-src"
fi
# As the official source tarball lays it out: one cargo config at the root, one in library/
# (the rust-src component's vendoring names the latter by path). Written before every build:
# that component copies library/ with hard links and rewrites the latter to the tarball's
# relative `vendor`, which must not point back into the read-only vendor directory.
for d in "$SRC" "$SRC/library"; do
    mkdir -p "$d/.cargo"
    cat > "$d/.cargo/config.toml" <<CARGO
# Written by rust/build/build.sh: cargo reads crates.io from what just fetch vendored.
[source.crates-io]
replace-with = "vendored-sources"
[source.vendored-sources]
directory = "$VENDOR"
CARGO
done
# An older copy may still carry the vendor as a link into upstream/: replaced by the copy.
if [ -L "$VENDOR" ] || [ ! -d "$VENDOR" ]; then
    rm -f "$VENDOR"
    cp -c -R "$VENDOR_SRC" "$VENDOR" 2>/dev/null || cp -R "$VENDOR_SRC" "$VENDOR"
    chmod -R u+w "$VENDOR"
fi
# The copy has no .git; bootstrap treats a tree with git-commit-info as the official source
# tarball (the file it writes there): no submodule is demanded, the channel comes from
# src/ci/channel, and rustc --version carries the pin's commit and date as upstream's does.
if [ ! -f "$SRC/git-commit-info" ]; then
    date=$(git -C "$UP" show -s --format=%cs HEAD)
    printf '%s\n%.9s\n%s\n' "$pin" "$pin" "$date" > "$SRC/git-commit-info"
    printf '%s' "$pin" > "$SRC/git-commit-hash"
fi
# compiler_builtins' C sources (build.optimized-compiler-builtins = true) are read from
# src/llvm-project/compiler-rt; the submodule is not fetched (D-0003): llvm/'s pinned, patched copy, linked.
[ -d "$ROOT/target/llvm/src/compiler-rt" ] || { echo "build: target/llvm/src/compiler-rt missing: just build llvm first" >&2; exit 1; }
# The rust-src component ships src/llvm-project/libunwind too (the `unwind` crate builds it
# for the targets that bundle it); the same pinned copy.
mkdir -p "$SRC/src/llvm-project"
for d in compiler-rt libunwind; do
    [ -e "$SRC/src/llvm-project/$d" ] || ln -s "$ROOT/target/llvm/src/$d" "$SRC/src/llvm-project/$d"
done

# 2. x.py. Every line that is not upstream's default has its reason in DESIGN.md.
cat > "$OUT/config.toml" <<TOML
# Written by rust/build/build.sh; DESIGN.md explains each line.
change-id = "ignore"

[build]
build = "$HOST"
host = ["$HOST"]
target = [$TARGETS]
rustc = "$STAGE0_RUSTC"
cargo = "$STAGE0_CARGO"
local-rebuild = true
submodules = false
vendor = true
locked-deps = true
docs = false
compiler-docs = false
extended = true
tools = ["rustdoc", "cargo", "clippy", "rustfmt", "src"]
jobs = $JOBS
optimized-compiler-builtins = true
patch-binaries-for-nix = false
cargo-native-static = true
description = "EmiBSD DevTools"

[install]
prefix = "$PREFIX"
sysconfdir = "etc"

[llvm]
download-ci-llvm = false
ninja = true
link-shared = false

[rust]
channel = "stable"
download-rustc = false
optimize = true
debug = false
debug-assertions = false
jemalloc = false
llvm-tools = true
lld = false

[target.$HOST]
llvm-config = "$LLVM/bin/llvm-config"

[target.$KERNEL_TARGET]
cc = "$LLVM/bin/clang"
ar = "$LLVM/bin/llvm-ar"
TOML

echo "== x.py install ($HOST; targets: $TARGETS; $JOBS jobs; LLVM $LLVM)"
rm -rf "$PREFIX"
(cd "$SRC" && python3 x.py install --config "$ROOT/$OUT/config.toml" --build-dir "$ROOT/$OUT/build")
echo "== done: $PREFIX"
sh rust/tests/check.sh "$PREFIX" "$HOST" "$KERNEL_TARGET"
