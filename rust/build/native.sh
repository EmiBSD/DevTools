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
# rust/build/native.sh: the native Rust (milestone T3b, D-0009, D-0010): rustc, cargo, clippy,
# rustfmt, rust-src and std that run on EmiBSD, with the kernel's target, cross-built on this
# machine by x.py from build.sh's patched source, and installed under /usr as the system has it.
#
#   sh rust/build/native.sh [aarch64|x86_64 ...]   (`just native rust`; the sysroots set; COMP_JOBS)
#
# Needs build.sh's result (target/rust/src, the patched and vendored source) and llvm/'s native
# tree for the same architecture (`just native llvm`): rustc for an EmiBSD host links that
# tree's LLVM libraries, read through llvm-config-native.sh. x.py builds a stage 1 compiler for
# this machine first, then the stage 2 compiler, its tools and std for the EmiBSD host with it.
# target/rust/native-<triple>/build is x.py's build directory, target/rust/native-<triple>/root
# the tree as installed (DESTDIR, prefix /usr): usr/bin/{rustc,cargo,rustdoc,clippy-driver,
# cargo-clippy,rustfmt,cargo-fmt}, usr/lib/rustlib (std for the host, core and alloc for the
# kernel's target, the sources).
#
# Nothing of OpenBSD is read. Never touches upstream/.
set -eu
cd "$(dirname "$0")/../.."
ROOT=$PWD
SRC=target/rust/src
[ -f "$SRC/.emibsd-src" ] && [ -d "$SRC/vendor" ] || { echo "native: build.sh's source is missing (just build rust first)" >&2; exit 1; }
for t in python3 cmake ninja rustup; do command -v $t >/dev/null || { echo "native: $t not found (the user's install)" >&2; exit 1; }; done
STAGE0_RUSTC=$(rustup which rustc)
STAGE0_CARGO=$(rustup which cargo)
HOST=$("$STAGE0_RUSTC" -vV | sed -n 's/^host: //p')
LLVM=$ROOT/target/llvm/$(cc -dumpmachine 2>/dev/null || echo host)
LLVM_CONFIG=$ROOT/target/llvm/host/bin/llvm-config
[ -x "$LLVM/bin/clang" ] && [ -x "$LLVM_CONFIG" ] || { echo "native: llvm/'s build is missing (just build llvm first)" >&2; exit 1; }
EMIBSD_OS_VERSION=8.0
JOBS=${COMP_JOBS:-6}
FULLVERSION=$(python3 -I -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["upstream"]["version"])' rust/UPSTREAM.toml)   # with our patch level: in rustc's description

# The native build's own source: build.sh's, cloned, its vendored crates taught the EmiBSD
# host by emibsd-vendor.py (as patches 0003 and 0004 teach std and its libc); build.sh's copy,
# which the cross toolchain builds from, stays as it is. Made again when that or the script changed.
NSRC=target/rust/native-src
stamp="$(cat "$SRC/.emibsd-src")
$(shasum -a 256 rust/build/emibsd-vendor.py)"
if [ ! -f "$NSRC/.emibsd-native-src" ] || [ "$(cat "$NSRC/.emibsd-native-src")" != "$stamp" ]; then
    echo "== native source: $SRC cloned to $NSRC, vendored crates taught the EmiBSD host"
    [ -d "$NSRC" ] && chmod -R u+w "$NSRC" && rm -rf "$NSRC"
    cp -c -R "$SRC" "$NSRC" 2>/dev/null || cp -R "$SRC" "$NSRC"
    python3 -I rust/build/emibsd-vendor.py "$NSRC/vendor"
    printf '%s\n' "$stamp" > "$NSRC/.emibsd-native-src"
fi
# The two cargo configurations, at the root and in library/, as build.sh writes them before
# every build: the rust-src step rewrites library/'s to a relative `vendor`, which must point
# at this copy's vendored crates by absolute path when x.py runs again.
for d in "$NSRC" "$NSRC/library"; do
    mkdir -p "$d/.cargo"
    cat > "$d/.cargo/config.toml" <<CARGO
# Written by rust/build/native.sh: cargo reads crates.io from the native copy's vendored crates.
[source.crates-io]
replace-with = "vendored-sources"
[source.vendored-sources]
directory = "$ROOT/$NSRC/vendor"
CARGO
done
# openssl-sys knows LibreSSL up to 4.3.x and the system's is 4.4.x: it is told 4.4.x follows
# 4.3.x (the bindings it chooses for 4.3 hold for 4.4), in the native copy only, once. Cargo
# never rebuilds a vendored crate whose files change, so what it built of one is removed too.
for d in "$NSRC"/vendor/openssl-sys-*; do
    python3 -I - "$d" <<'PY' || continue
import json, sys
d = sys.argv[1]; f = d + '/build/main.rs'; t = open(f).read()
old = "            (4, 3, _) => ('4', '3', 'x'),\n"
if "(4, 4, _)" in t or old not in t:
    sys.exit(1)
open(f, 'w').write(t.replace(old, old + "            (4, 4, _) => ('4', '4', 'x'),\n"))
c = d + '/.cargo-checksum.json'; j = json.load(open(c)); j['files'] = {}; json.dump(j, open(c, 'w'))
PY
    echo "== $(basename "$d"): LibreSSL 4.4.x accepted"
    find target/rust -path 'target/rust/native-*-emibsd-emibsd/build/*' \( -name 'openssl-sys-*' -o -name 'openssl-*' \) \
        \( -path '*/release/build/*' -o -path '*/release/.fingerprint/*' -o -path '*/release/deps/*' \) -prune -exec rm -rf {} +
done

ARCHS=${*:-aarch64 x86_64}
for ARCH in $ARCHS; do
case $ARCH in
    aarch64) sysroot=${EMIBSD_SYSROOT_ARM64:?set EMIBSD_SYSROOT_ARM64}; kernel=aarch64-emibsd-none-softfloat ;;
    x86_64)  sysroot=${EMIBSD_SYSROOT_AMD64:?set EMIBSD_SYSROOT_AMD64}; kernel=x86_64-emibsd-none-softfloat ;;
    *) echo "native: unknown architecture $ARCH (aarch64, x86_64)" >&2; exit 1 ;;
esac
T=$ARCH-emibsd-emibsd                       # Rust's name
LT=$ARCH-emibsd-emibsd$EMIBSD_OS_VERSION    # LLVM's triple
NATIVE_LLVM=$ROOT/target/llvm/native-$LT/build
[ -f "$NATIVE_LLVM/lib/libLLVMCore.a" ] || { echo "native: no LLVM libraries in $NATIVE_LLVM (just native llvm $ARCH)" >&2; exit 1; }
clang=$LLVM/bin/$LT-clang
OUT=target/rust/native-$T
DEST=$ROOT/$OUT/root
mkdir -p "$OUT"

# x.py, as build.sh's, with the EmiBSD target as the host: this machine builds, EmiBSD runs.
cat > "$OUT/config.toml" <<TOML
# Written by rust/build/native.sh; DESIGN.md explains each line.
change-id = "ignore"

[build]
build = "$HOST"
host = ["$T"]
target = ["$T", "$kernel"]
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
description = "EmiBSD DevTools $FULLVERSION"

[install]
prefix = "/usr"
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
strip = true
jemalloc = false
llvm-tools = false
lld = false

[target.$HOST]
llvm-config = "$LLVM_CONFIG"

[target.$T]
llvm-config = "$ROOT/rust/build/llvm-config-native.sh"
cc = "$clang"
cxx = "$clang++"
linker = "$clang"
ar = "$LLVM/bin/llvm-ar"
ranlib = "$LLVM/bin/llvm-ranlib"
rustflags = ["-C", "link-arg=--sysroot=$sysroot"]

[target.$kernel]
cc = "$LLVM/bin/clang"
ar = "$LLVM/bin/llvm-ar"
TOML
v=$(echo "$T" | tr - _)
# The cc crate passes --target with Rust's name (no OS version); clang's per-target directories
# (libc++'s __config_site) go by LLVM's triple, which a later --target restores.
export "CFLAGS_$v=--sysroot=$sysroot --target=$LT" "CXXFLAGS_$v=--sysroot=$sysroot --target=$LT"
# rustc_llvm's build script: the native tree's llvm-config, and libc++ (the system's) for its
# C++ (LLVM_USE_LIBCXX, upstream's switch).
export EMIBSD_NATIVE_LLVM="$NATIVE_LLVM" EMIBSD_NATIVE_TRIPLE="$LT" LLVM_USE_LIBCXX=1
# The cc crate's C++ library for the target, which it does not know: the system's libc++.
export "CXXSTDLIB_$v=c++"
# cargo's TLS: the system's LibreSSL from the sysroot, not OpenSSL built from source (which
# does not know the target); shared, as the system's own programs link it (D-0010), when the
# sysroot carries libssl.so.<major>.<minor>, which lld resolves -lssl to (llvm/'s patch 0005).
# openssl-sys looks for an unversioned libssl.so to choose, so it is told. A sysroot with the
# static libraries alone (one given by path, before the userland releases the architecture)
# leaves cargo carrying them.
V=$(echo "$T" | tr a-z- A-Z_)
if ls "$sysroot"/usr/lib/libssl.so.* >/dev/null 2>&1; then ssl_static=0; else ssl_static=1; fi
export "${V}_OPENSSL_NO_VENDOR=1" "${V}_OPENSSL_DIR=$sysroot/usr" "${V}_OPENSSL_STATIC=$ssl_static"

# rust.strip has rustc strip what it links, and for this machine's own objects (the stage 1
# compiler's std, which the build scripts and proc macros link) rustc runs `rust-objcopy`.
# Bootstrap puts that program in the compiler's sysroot only with llvm-tools on, and they are
# off here: the native tree's tools do not run on this machine. It is llvm-objcopy under
# another name, so stage 1's is given under that name on PATH, where rustc looks next.
mkdir -p "$OUT/host-tools"
ln -sf "$LLVM/bin/llvm-objcopy" "$OUT/host-tools/rust-objcopy"
PATH="$ROOT/$OUT/host-tools:$PATH"
export PATH
echo "== native rust: $T (on $HOST, $JOBS jobs; LLVM $NATIVE_LLVM)"
[ -d "$DEST" ] && chmod -R u+w "$DEST" && rm -rf "$DEST"
(cd "$NSRC" && DESTDIR="$DEST" python3 x.py install --config "$ROOT/$OUT/config.toml" --build-dir "$ROOT/$OUT/build")
# Built for this host, rustc's own proc macros land in its sysroot's lib beside the driver, and
# x.py's install copies them; they serve only to compile rustc. As the cross toolchain's install
# has it, lib/ keeps the driver alone.
find "$DEST/usr/lib" -maxdepth 1 -name 'lib*.so' ! -name 'librustc_driver-*.so' -delete
# What the install leaves that has no place in the installed system: rust-installer's own
# records (they name this machine's paths, and the system's sets own the files), the bash
# completion under usr/etc (no such directory there), and the debugger wrappers with their
# scripts (the system has no gdb or lldb to wrap).
rm -f "$DEST"/usr/lib/rustlib/install.log "$DEST"/usr/lib/rustlib/uninstall.sh "$DEST"/usr/lib/rustlib/manifest-* \
      "$DEST"/usr/lib/rustlib/components "$DEST"/usr/lib/rustlib/rust-installer-version \
      "$DEST"/usr/bin/rust-gdb "$DEST"/usr/bin/rust-gdbgui "$DEST"/usr/bin/rust-lldb
rm -rf "$DEST/usr/etc" "$DEST/usr/lib/rustlib/etc"
echo "== native rust done: $DEST"
sh rust/tests/native-check.sh "$DEST" "$T" "$sysroot"
done
