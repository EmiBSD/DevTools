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
# llvm/tests/native-check.sh <root> <triple>: what can be checked of the native toolchain
# (T3b) on the machine that built it, without running it: the tree as the installed system has
# it (D-0010), and every program an ELF for the triple's machine that EmiBSD's ld.so loads
# (OS/ABI 12, /usr/libexec/ld.so, the system's libc and libc++ by name, no rpath, the
# stack-guard segment). Running it is the proof in QEMU (DESIGN.md), not this.
set -u
root=${1:?root of the native tree}
triple=${2:?target triple}
here=$(cd "$(dirname "$0")/../.." && pwd)
host=$(cc -dumpmachine 2>/dev/null || echo host)
tools=$here/target/llvm/$host/bin
readelf=$tools/llvm-readelf
fail=0
bad() { echo "native-check: $*"; fail=1; }
case $triple in
    aarch64-*) machine="AArch64" ;;
    x86_64-*)  machine="Advanced Micro Devices X86-64" ;;
    *) echo "native-check: unknown triple $triple" >&2; exit 2 ;;
esac
major=$("$tools/clang" -dumpversion | cut -d. -f1)

for f in usr/bin/clang usr/bin/ld.lld usr/bin/llvm-ar usr/bin/llvm-nm usr/bin/llvm-objdump usr/bin/llvm-readelf \
         usr/lib/libc++.a usr/lib/libc++abi.a usr/lib/libc++.so.13.0 usr/lib/libc++abi.so.10.0 \
         usr/include/c++/v1/vector usr/include/c++/v1/__config_site \
         usr/lib/clang/$major/include/stddef.h usr/lib/clang/$major/lib/$triple/libclang_rt.builtins.a; do
    [ -f "$root/$f" ] || bad "missing $f"
done
for l in cc:clang c++:clang++ ld:ld.lld ar:llvm-ar nm:llvm-nm objdump:llvm-objdump strip:llvm-strip ranlib:llvm-ranlib \
         readelf:llvm-readelf size:llvm-size strings:llvm-strings objcopy:llvm-objcopy clang++:clang clang-cpp:clang; do
    n=${l%%:*}; want=${l#*:}
    [ "$(readlink "$root/usr/bin/$n" 2>/dev/null)" = "$want" ] || bad "usr/bin/$n is not a link to $want"
done
for f in libunwind.a libunwind.so libc++.so libc++abi.so; do
    [ -e "$root/usr/lib/$f" ] && bad "usr/lib/$f: the runtimes go by the system's names, the unwinder inside libc++abi"
done

n=0
for p in "$root"/usr/bin/*; do
    [ -L "$p" ] && continue
    n=$((n + 1))
    b=usr/bin/$(basename "$p")
    h=$("$readelf" -h "$p" 2>/dev/null) || { bad "$b: not an ELF"; continue; }
    echo "$h" | grep -q "Machine: *$machine" || bad "$b: not $machine"
    echo "$h" | grep -q "OS/ABI: *UNIX - OpenBSD" || bad "$b: ELF OS/ABI byte is not 12"
    l=$("$readelf" -lW "$p")
    echo "$l" | grep -q '/usr/libexec/ld.so' || bad "$b: interpreter is not /usr/libexec/ld.so"
    echo "$l" | grep -q 'OPENBSD_RANDOMIZE' || bad "$b: no PT_OPENBSD_RANDOMIZE segment"
    d=$("$readelf" -d "$p")
    echo "$d" | grep -q 'NEEDED.*\[libc\.so\.' || bad "$b: the system's libc is not NEEDED"
    echo "$d" | grep -q 'NEEDED.*\[libc++\.so\.13\.0\]' || bad "$b: libc++.so.13.0 is not NEEDED"
    echo "$d" | grep -q 'RPATH\|RUNPATH' && bad "$b: carries an rpath"
done
[ "$n" -gt 10 ] || bad "only $n programs in usr/bin"

[ "$fail" = 0 ] && echo "native-check: $root: ok ($n programs for $triple, clang $major)"
exit $fail
