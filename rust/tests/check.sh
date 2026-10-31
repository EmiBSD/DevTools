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
# rust/tests/check.sh PREFIX HOST KERNEL_TARGET [TARGET LLVM_PREFIX]: what a build of this
# toolchain must be able to do on the host, run by build/build.sh after every build; `just
# build rust` is not done until it passes. With TARGET (the system's) and llvm/'s install, a
# Rust hello is linked for it by that clang against EMIBSD_SYSROOT, static and dynamic, and
# read as the ELF the kernel loads; that it runs is the kernel repository's smoke, T2's proof.
set -eu
prefix=${1:?prefix}
host=${2:?host}
kernel=${3:?kernel target}
target=${4:-}
llvm=${5:-}
here=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 's/^version *= *"\([^+"]*\).*/\1/p' "$here/UPSTREAM.toml")
llvm_version=$(sed -n 's/^version *= *"\([^+"]*\).*/\1/p' "$here/../llvm/UPSTREAM.toml")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/emibsd-rust-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
bad() { echo "check.sh: $*" >&2; fail=1; }
rustc="$prefix/bin/rustc"
cargo="$prefix/bin/cargo"
for p in bin/rustc bin/cargo bin/rustdoc bin/clippy-driver bin/cargo-clippy bin/rustfmt bin/cargo-fmt; do
    [ -x "$prefix/$p" ] || bad "missing $p"
done
[ "$fail" = 0 ] || exit 1

# The host tools carry nothing of Homebrew: the artifact runs on a Mac that has none.
case $(uname) in Darwin)
    for b in "$prefix"/bin/* "$prefix"/lib/*.dylib; do
        [ -L "$b" ] && continue
        otool -L "$b" 2>/dev/null | grep -q /opt/homebrew && bad "$(basename "$b") loads a Homebrew library: $(otool -L "$b" | grep /opt/homebrew | head -1)"
    done ;;
esac

# The compiler says who it is, for which host, and which LLVM it carries (llvm/'s, T1).
vv=$("$rustc" -vV)
echo "$vv" | grep -q "^rustc $version" || bad "rustc -vV does not say $version: $(echo "$vv" | head -1)"
echo "$vv" | grep -q "^host: $host\$" || bad "rustc's host is not $host"
echo "$vv" | grep -q "^LLVM version: $llvm_version\$" || bad "rustc's LLVM is not $llvm_version (llvm/'s): $(echo "$vv" | grep LLVM)"
"$cargo" --version | grep -q "^cargo $version" || bad "cargo --version does not say $version"
[ "$("$rustc" --print sysroot)" = "$prefix" ] || bad "sysroot is $("$rustc" --print sysroot), not $prefix"

# The libraries, where rustc looks for them: std for the host, core and alloc for the kernel.
ls "$prefix/lib/rustlib/$host/lib/"libstd-*.rlib >/dev/null 2>&1 || bad "no std for $host"
for c in core alloc compiler_builtins; do
    ls "$prefix/lib/rustlib/$kernel/lib/lib$c-"*.rlib >/dev/null 2>&1 || bad "no $c for $kernel"
done
ls "$prefix/lib/rustlib/$kernel/lib/"libstd-*.rlib >/dev/null 2>&1 && bad "a std for $kernel: it is a no-std target"
[ -d "$prefix/lib/rustlib/src/rust/library/core" ] || bad "rust-src is not installed (the kernel's rust-toolchain.toml asks for it)"

# A hello for the host, compiled by the built rustc and run here.
cat > "$tmp/hello.rs" <<'RS'
fn main() { println!("hello from {}", std::env::consts::OS); }
RS
if "$rustc" -O -o "$tmp/hello" "$tmp/hello.rs" 2> "$tmp/hello.err"; then
    "$tmp/hello" | grep -q '^hello from ' || bad "the host hello did not print"
else
    bad "the host hello did not compile: $(head -5 "$tmp/hello.err")"
fi

# A no_std crate for the kernel's target: core and alloc link, nothing else is asked for.
cat > "$tmp/nostd.rs" <<'RS'
#![no_std]
extern crate alloc;
pub fn len(v: &alloc::vec::Vec<u8>) -> usize { v.len() }
RS
"$rustc" --target "$kernel" --crate-type rlib -O -o "$tmp/libnostd.rlib" "$tmp/nostd.rs" 2> "$tmp/nostd.err" \
    || bad "the no_std crate for $kernel did not compile: $(head -5 "$tmp/nostd.err")"

# The system's target: std where rustc looks for it, and a hello linked by llvm/'s clang
# against the sysroot: static PIE and dynamic, the ELF the kernel loads.
if [ -n "$target" ]; then
    : "${EMIBSD_SYSROOT:?set EMIBSD_SYSROOT to the target libc, crt and headers}"
    cc="$llvm/bin/clang"; readelf="$llvm/bin/llvm-readelf"
    [ -x "$cc" ] || bad "no clang at $llvm/bin (just build llvm first)"
    ls "$prefix/lib/rustlib/$target/lib/"libstd-*.rlib >/dev/null 2>&1 || bad "no std for $target"
    "$rustc" --target "$target" --print cfg 2>/dev/null | grep -q '^target_os="emibsd"$' || bad "$target does not say target_os = emibsd"
    cat > "$tmp/e.rs" <<'RS'
use std::io::Write;
fn main() {
    let v: Vec<String> = std::env::args().collect();
    let mut out = std::io::stdout().lock();
    writeln!(out, "hello from {} ({} args)", std::env::consts::OS, v.len()).unwrap();
    let r = std::panic::catch_unwind(|| { if v.len() > 100 { panic!("x") } });
    std::process::exit(if r.is_ok() { 0 } else { 1 });
}
RS
    link="-C linker=$cc -C link-arg=--sysroot=$EMIBSD_SYSROOT"
    if "$rustc" --target "$target" $link -C target-feature=+crt-static -O -o "$tmp/es" "$tmp/e.rs" 2> "$tmp/es.err"; then
        h=$("$readelf" -h "$tmp/es")
        echo "$h" | grep -q "Machine: *AArch64" || bad "es: not AArch64"
        echo "$h" | grep -q "Type: *DYN" || bad "es: not a PIE (ET_DYN)"
        echo "$h" | grep -q "OS/ABI: *UNIX - OpenBSD" || bad "es: ELF OS/ABI byte is not 12 (what the kernel and ld.so recognise)"
        "$readelf" -d "$tmp/es" 2>/dev/null | grep -q 'NEEDED' && bad "es: the static hello is dynamically linked"
        "$readelf" -l "$tmp/es" | grep -q 'OPENBSD_RANDOMIZE' || bad "es: no PT_OPENBSD_RANDOMIZE segment"
        "$readelf" -s "$tmp/es" | grep -q '_Unwind_RaiseException' || bad "es: no unwinder linked in (catch_unwind needs libunwind)"
    else
        bad "the hello for $target did not link statically: $(head -8 "$tmp/es.err")"
    fi
    if "$rustc" --target "$target" $link -O -o "$tmp/ed" "$tmp/e.rs" 2> "$tmp/ed.err"; then
        "$readelf" -l "$tmp/ed" | grep -q '/usr/libexec/ld.so' || bad "ed: interpreter is not /usr/libexec/ld.so"
        "$readelf" -d "$tmp/ed" | grep -q 'libc.so' || bad "ed: libc.so is not NEEDED"
    else
        bad "the hello for $target did not link dynamically: $(head -8 "$tmp/ed.err")"
    fi
fi

[ "$fail" = 0 ] && echo "check.sh: $prefix: ok (rustc $version for $host, core/alloc for $kernel${target:+, std for $target}, LLVM $llvm_version)"
exit $fail
