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
# rust/tests/check.sh PREFIX HOST KERNEL_TARGET: what a build of this toolchain must be able
# to do on the host, run by build/build.sh after every build; `just build rust` is not done
# until it passes. The system's target (slice 2 of T2) joins when its std exists.
set -eu
prefix=${1:?prefix}
host=${2:?host}
kernel=${3:?kernel target}
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

[ "$fail" = 0 ] && echo "check.sh: $prefix: ok (rustc $version for $host, core/alloc for $kernel, LLVM $llvm_version)"
exit $fail
