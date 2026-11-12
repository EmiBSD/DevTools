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
# tools/sysroot.sh <arm64|amd64> <userland artifact .tar.zst> <sha256>: the sysroot a build
# takes, by pin (docs/TOOLCHAIN.md): the userland repository's released artifact, checked
# against its sum, and from its base and comp sets only what a sysroot is: usr/include,
# usr/lib and usr/libexec (the libc and the system's libraries, static and shared, the
# start-up files, the headers, ld.so). Written to target/sysroot/<arch>, with the artifact's
# name and sum in target/sysroot/<arch>/.pin; EMIBSD_SYSROOT_<ARCH> then names that directory.
# The artifact is a file already on this machine: nothing is downloaded here.
set -eu
cd "$(dirname "$0")/.."
arch=${1:?arm64 or amd64}
artifact=${2:?the userland artifact, userland-<tag>-<arch>.tar.zst}
sum=${3:?its sha256}
case $arch in arm64|amd64) ;; *) echo "sysroot: unknown architecture $arch" >&2; exit 1 ;; esac
[ -f "$artifact" ] || { echo "sysroot: $artifact: no such file" >&2; exit 1; }
got=$(shasum -a 256 "$artifact" | cut -d' ' -f1)
[ "$got" = "$sum" ] || { echo "sysroot: $artifact is $got, not $sum" >&2; exit 1; }
out=target/sysroot/$arch
tmp=target/sysroot/.unpack-$arch
[ -d "$out" ] && chmod -R u+w "$out"
rm -rf "$out" "$tmp"
mkdir -p "$out" "$tmp"
zstd -dc "$artifact" | tar -xf - -C "$tmp"
top=$(ls "$tmp")
for s in base80 comp80; do
    [ -f "$tmp/$top/$s.tar.zst" ] || { echo "sysroot: no $s.tar.zst in $artifact" >&2; exit 1; }
    zstd -dc "$tmp/$top/$s.tar.zst" | tar -xf - -C "$out" ./usr/include ./usr/lib ./usr/libexec 2>/dev/null || true
done
rm -rf "$tmp"
for f in usr/lib/libc.a usr/lib/crt0.o usr/include/stdio.h usr/libexec/ld.so; do
    [ -f "$out/$f" ] || { echo "sysroot: $out lacks $f" >&2; exit 1; }
done
# Nothing of another compiler's: the C++ runtime and the compiler's own directory are DevTools'.
for f in usr/include/c++ usr/lib/clang; do
    [ -e "$out/$f" ] && { echo "sysroot: $out carries $f (another compiler's): refused" >&2; exit 1; }
done
ls "$out"/usr/lib/libc++* >/dev/null 2>&1 && { echo "sysroot: $out carries a libc++ (another compiler's): refused" >&2; exit 1; }
printf '%s %s\n' "$(basename "$artifact")" "$sum" > "$out/.pin"
echo "sysroot: $out from $(basename "$artifact") ($(ls "$out/usr/lib" | grep -c '\.so\.') shared libraries)"
