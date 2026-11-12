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
# rust/tests/native-check.sh <root> <target>: what can be checked of the native Rust (T3b) on
# the machine that built it, without running it: the tree as the installed system has it
# (D-0010), every program and the driver an ELF for the target's machine that EmiBSD's ld.so
# loads (OS/ABI 12, /usr/libexec/ld.so, the system's libc by name, no rpath but upstream's
# $ORIGIN/../lib, the stack-guard segment wherever the stack guard is used), std for the host, core and alloc for the kernel's target, the sources. Running it
# is the proof in QEMU, not this.
set -u
root=${1:?root of the native tree}
target=${2:?the EmiBSD target, <arch>-emibsd-emibsd}
sysroot=${3:-}                          # the sysroot it was built against, when known
here=$(cd "$(dirname "$0")/../.." && pwd)
readelf=$here/target/llvm/$(cc -dumpmachine 2>/dev/null || echo host)/bin/llvm-readelf
fail=0
bad() { echo "native-check: $*"; fail=1; }
case $target in
    aarch64-*) machine="AArch64";                       kernel=aarch64-emibsd-none-softfloat ;;
    x86_64-*)  machine="Advanced Micro Devices X86-64"; kernel=x86_64-emibsd-none-softfloat ;;
    *) echo "native-check: unknown target $target" >&2; exit 2 ;;
esac

for f in rustc rustdoc cargo clippy-driver cargo-clippy rustfmt cargo-fmt; do
    [ -f "$root/usr/bin/$f" ] || bad "missing usr/bin/$f"
done
ls "$root"/usr/lib/librustc_driver-*.so >/dev/null 2>&1 || bad "missing usr/lib/librustc_driver-*.so"
ls "$root/usr/lib/rustlib/$target/lib/"libstd-*.rlib >/dev/null 2>&1 || bad "no std for $target"
ls "$root/usr/lib/rustlib/$kernel/lib/"libcore-*.rlib >/dev/null 2>&1 || bad "no core for $kernel"
[ -d "$root/usr/lib/rustlib/src/rust/library/std" ] || bad "no rust-src"
for f in "$root"/usr/lib/lib*.so; do
    case $(basename "$f") in librustc_driver-*) ;; *) bad "usr/lib/$(basename "$f"): only the driver belongs in usr/lib" ;; esac
done

# The manual pages upstream installs, where the system keeps them.
for f in rustc rustdoc cargo cargo-build; do
    [ -s "$root/usr/share/man/man1/$f.1" ] || bad "missing usr/share/man/man1/$f.1"
done
# Nothing of the installer's records, the misplaced completion or the debugger wrappers.
for f in usr/lib/rustlib/install.log usr/lib/rustlib/uninstall.sh usr/lib/rustlib/components usr/etc usr/bin/rust-gdb usr/bin/rust-lldb; do
    [ -e "$root/$f" ] && bad "$f: has no place in the installed system"
done
ls "$root"/usr/lib/rustlib/manifest-* >/dev/null 2>&1 && bad "usr/lib/rustlib/manifest-*: has no place in the installed system"
# cargo links the system's LibreSSL shared when the sysroot has it, and then carries no path
# of the machine that built that library.
if [ -n "$sysroot" ] && ls "$sysroot"/usr/lib/libssl.so.* >/dev/null 2>&1; then
    d=$("$readelf" -d "$root/usr/bin/cargo" 2>/dev/null)
    echo "$d" | grep -q 'NEEDED.*\[libssl\.so\.' || bad "usr/bin/cargo: libssl.so is not NEEDED though the sysroot has it"
    echo "$d" | grep -q 'NEEDED.*\[libcrypto\.so\.' || bad "usr/bin/cargo: libcrypto.so is not NEEDED though the sysroot has it"
    LC_ALL=C grep -q -a '/Users/' "$root/usr/bin/cargo" && bad "usr/bin/cargo: carries paths of the build machine"
fi

n=0
for p in "$root"/usr/bin/* "$root"/usr/lib/librustc_driver-*.so; do
    [ -L "$p" ] && continue
    case $p in *.so) so=1 ;; *) so=0; head -c 4 "$p" | grep -q 'ELF' || continue ;; esac
    n=$((n + 1))
    b=${p#"$root"/}
    h=$("$readelf" -h "$p" 2>/dev/null) || { bad "$b: not an ELF"; continue; }
    echo "$h" | grep -q "Machine: *$machine" || bad "$b: not $machine"
    echo "$h" | grep -q "OS/ABI: *UNIX - OpenBSD" || bad "$b: ELF OS/ABI byte is not 12"
    d=$("$readelf" -d "$p")
    echo "$d" | grep -q 'NEEDED.*\[libc\.so\.' || bad "$b: the system's libc is not NEEDED"
    # rustc's own rpath (rust.rpath, upstream's default), the driver beside the programs; no other.
    echo "$d" | grep 'RPATH\|RUNPATH' | grep -v -q '\[\$ORIGIN/\.\./lib\]' && bad "$b: carries an rpath other than \$ORIGIN/../lib"
    l=$("$readelf" -lW "$p")
    # The segment exists where the stack guard is used: a program with no C or C++ in it (rustc,
    # whose code lives in the driver) references no __guard_local, and the linker keeps no section.
    "$readelf" -sW "$p" | grep -q '__guard_local' && { echo "$l" | grep -q 'OPENBSD_RANDOMIZE' || bad "$b: uses the stack guard and has no PT_OPENBSD_RANDOMIZE segment"; }
    [ $so = 1 ] && continue
    echo "$l" | grep -q '/usr/libexec/ld.so' || bad "$b: interpreter is not /usr/libexec/ld.so"
done
[ "$n" -ge 8 ] || bad "only $n ELF files checked"

[ "$fail" = 0 ] && echo "native-check: $root: ok ($n ELF files for $target, std, core/alloc for $kernel, rust-src)"
exit $fail
