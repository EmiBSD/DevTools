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
# rust/tests/check.sh PREFIX HOST LLVM_PREFIX [ARCH...]: what a build of this toolchain must be able to
# do on the host, run by build/build.sh after every build; `just build rust` is not done until
# it passes. For each architecture (arm64, amd64: D-0008), core and alloc for the kernel's
# target, and for the system's a Rust hello linked by llvm/'s clang named after its triple
# against that architecture's sysroot (EMIBSD_SYSROOT_ARM64, EMIBSD_SYSROOT_AMD64), static and
# dynamic, read as the ELF the kernel loads; that it runs is the kernel repository's smoke,
# T2's proof.
set -eu
prefix=${1:?prefix}
host=${2:?host}
llvm=${3:?llvm prefix}
shift 3
archs=${*:-aarch64 x86_64}             # LLVM's names; all of them unless named (dist.py checks one per tarball)
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

# std for the host, and the sources the kernel's rust-toolchain.toml asks for.
ls "$prefix/lib/rustlib/$host/lib/"libstd-*.rlib >/dev/null 2>&1 || bad "no std for $host"
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

# What each architecture's targets are given: a no_std crate for the kernel's, where core and
# alloc link and nothing else is asked for; a hello for the system's, with a panic caught.
cat > "$tmp/nostd.rs" <<'RS'
#![no_std]
extern crate alloc;
pub fn len(v: &alloc::vec::Vec<u8>) -> usize { v.len() }
RS
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
readelf="$llvm/bin/llvm-readelf"
default=$("$llvm/bin/clang" -print-target-triple)       # aarch64-emibsd-emibsd<release>: the release the triples carry
os=${default#aarch64-emibsd-}
targets=
for arch in $archs; do
    case $arch in
        aarch64) kernel=aarch64-emibsd-none-softfloat; sysroot=${EMIBSD_SYSROOT_ARM64:?set EMIBSD_SYSROOT_ARM64 to the arm64 libc, crt and headers}; machine="AArch64" ;;
        x86_64)  kernel=x86_64-emibsd-none-softfloat;            sysroot=${EMIBSD_SYSROOT_AMD64:?set EMIBSD_SYSROOT_AMD64 to the amd64 libc, crt and headers}; machine="Advanced Micro Devices X86-64" ;;
        *) bad "unknown architecture $arch (aarch64, x86_64)"; continue ;;
    esac
    target=$arch-emibsd-emibsd
    targets="$targets, core/alloc for $kernel, std for $target"

    for c in core alloc compiler_builtins; do
        ls "$prefix/lib/rustlib/$kernel/lib/lib$c-"*.rlib >/dev/null 2>&1 || bad "no $c for $kernel"
    done
    ls "$prefix/lib/rustlib/$kernel/lib/"libstd-*.rlib >/dev/null 2>&1 && bad "a std for $kernel: it is a no-std target"
    "$rustc" --target "$kernel" --crate-type rlib -O -o "$tmp/libnostd-$arch.rlib" "$tmp/nostd.rs" 2> "$tmp/nostd-$arch.err" \
        || bad "the no_std crate for $kernel did not compile: $(head -5 "$tmp/nostd-$arch.err")"

    # The system's target: std where rustc looks for it, and the hello linked by the clang
    # named after its LLVM triple against the sysroot: static PIE and dynamic, the ELF the kernel loads.
    cc="$llvm/bin/$arch-emibsd-$os-clang"
    [ -x "$cc" ] || { bad "no $cc (just build llvm first)"; continue; }
    ls "$prefix/lib/rustlib/$target/lib/"libstd-*.rlib >/dev/null 2>&1 || bad "no std for $target"
    "$rustc" --target "$target" --print cfg 2>/dev/null | grep -q '^target_os="emibsd"$' || bad "$target does not say target_os = emibsd"
    link="-C linker=$cc -C link-arg=--sysroot=$sysroot"
    if "$rustc" --target "$target" $link -C target-feature=+crt-static -O -o "$tmp/es-$arch" "$tmp/e.rs" 2> "$tmp/es-$arch.err"; then
        h=$("$readelf" -h "$tmp/es-$arch")
        echo "$h" | grep -q "Machine: *$machine" || bad "$arch es: not $machine"
        echo "$h" | grep -q "Type: *DYN" || bad "$arch es: not a PIE (ET_DYN)"
        echo "$h" | grep -q "OS/ABI: *UNIX - OpenBSD" || bad "$arch es: ELF OS/ABI byte is not 12 (what the kernel and ld.so recognise)"
        "$readelf" -d "$tmp/es-$arch" 2>/dev/null | grep -q 'NEEDED' && bad "$arch es: the static hello is dynamically linked"
        "$readelf" -l "$tmp/es-$arch" | grep -q 'OPENBSD_RANDOMIZE' || bad "$arch es: no PT_OPENBSD_RANDOMIZE segment"
        "$readelf" -s "$tmp/es-$arch" | grep -q '_Unwind_RaiseException' || bad "$arch es: no unwinder linked in (catch_unwind needs the unwinder libc++abi carries)"
    else
        bad "the hello for $target did not link statically: $(head -8 "$tmp/es-$arch.err")"
    fi
    if "$rustc" --target "$target" $link -O -o "$tmp/ed-$arch" "$tmp/e.rs" 2> "$tmp/ed-$arch.err"; then
        "$readelf" -l "$tmp/ed-$arch" | grep -q '/usr/libexec/ld.so' || bad "$arch ed: interpreter is not /usr/libexec/ld.so"
        "$readelf" -d "$tmp/ed-$arch" | grep -q 'libc.so' || bad "$arch ed: libc.so is not NEEDED"
        "$readelf" -d "$tmp/ed-$arch" | grep -q 'NEEDED.*\[libc++abi.so.10.0\]' || bad "$arch ed: libc++abi.so.10.0 (the unwinder) is not NEEDED"
        "$readelf" -d "$tmp/ed-$arch" | grep -q 'NEEDED.*libunwind' && bad "$arch ed: a separate libunwind is NEEDED"
    else
        bad "the hello for $target did not link dynamically: $(head -8 "$tmp/ed-$arch.err")"
    fi
done

[ "$fail" = 0 ] && echo "check.sh: $prefix: ok (rustc $version for $host$targets, LLVM $llvm_version)"
exit $fail
