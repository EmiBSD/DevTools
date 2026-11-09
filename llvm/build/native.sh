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
# llvm/build/native.sh: the native toolchain (milestone T3b, D-0009, D-0010): clang, lld and
# the binutils that run on EmiBSD, cross-compiled on this machine from the same patched source
# by the toolchain build.sh made, and laid out as the installed system has them.
#
#   sh llvm/build/native.sh [aarch64|x86_64 ...]   (`just native llvm`; the sysroots set; COMP_JOBS)
#
# Needs build.sh's result: target/llvm/src (the patched source), target/llvm/host (its
# tablegens, which run here) and the install under target/llvm/<host> (the compiler that
# cross-compiles, and the target's runtimes, which the native tree carries). For each
# architecture, target/llvm/native-<triple>/build is the CMake build and
# target/llvm/native-<triple>/root the tree as installed (DESTDIR, prefix /usr):
#   usr/bin                  clang, clang++, clang-cpp, ld.lld, the llvm-* binutils;
#                            cc, c++, ld and ar as links (the system's names)
#   usr/lib/clang/<major>    clang's resource directory: its headers, the builtins
#   usr/lib                  libc++, libc++abi (the unwinder inside), static and shared
#   usr/include/c++/v1       libc++'s headers, __config_site among them
# The tools link dynamically against the system's libc and libc++ (libc++.so.13.0); LLVM's own
# libraries are static inside each, as upstream links them (D-0010). No rpath.
#
# Nothing of OpenBSD is read. Never touches upstream/.
set -eu
cd "$(dirname "$0")/../.."
ROOT=$PWD
SRC=target/llvm/src
OUT=target/llvm
HOST=$(cc -dumpmachine 2>/dev/null || echo host)
PREFIX=$ROOT/$OUT/$HOST
EMIBSD_OS_VERSION=8.0
JOBS=${COMP_JOBS:-6}
[ -f "$SRC/.emibsd-src" ] && [ -x "$OUT/host/bin/llvm-tblgen" ] && [ -x "$PREFIX/bin/clang" ] \
    || { echo "native: build.sh's result is missing (just build llvm first)" >&2; exit 1; }
grep -q 'llvm-host-emibsd' "$SRC/.emibsd-src" \
    || { echo "native: the source lacks the EmiBSD host patch (UPSTREAM.toml's series; just build llvm)" >&2; exit 1; }
for t in cmake ninja python3; do command -v $t >/dev/null || { echo "native: $t not found (the user's install)" >&2; exit 1; }; done
MAJOR=$("$PREFIX/bin/clang" -dumpversion | cut -d. -f1)
# The same distribution as the cross toolchain's (build.sh, DESIGN.md).
DISTRIBUTION="clang;clang-resource-headers;lld;llvm-ar;llvm-ranlib;llvm-nm;llvm-objcopy;llvm-strip;llvm-objdump;llvm-readobj;llvm-readelf;llvm-size;llvm-strings;llvm-symbolizer;llvm-addr2line;llvm-cxxfilt;llvm-dwarfdump;llvm-cov;llvm-profdata"

ARCHS=${*:-aarch64 x86_64}
for ARCH in $ARCHS; do
case $ARCH in
    aarch64) SYSROOT=${EMIBSD_SYSROOT_ARM64:?set EMIBSD_SYSROOT_ARM64} ;;
    x86_64)  SYSROOT=${EMIBSD_SYSROOT_AMD64:?set EMIBSD_SYSROOT_AMD64} ;;
    *) echo "native: unknown architecture $ARCH (aarch64, x86_64)" >&2; exit 1 ;;
esac
T=$ARCH-emibsd-emibsd$EMIBSD_OS_VERSION
B=$OUT/native-$T/build
DEST=$ROOT/$OUT/native-$T/root
[ -f "$PREFIX/lib/$T/libc++.so.13.0" ] || { echo "native: no runtimes for $T under $PREFIX (just build llvm)" >&2; exit 1; }

echo "== native: $T (on $HOST, $JOBS jobs)"
# Cross-compiled as stage 2's runtimes are (CMAKE_SYSTEM_NAME EmiBSD, build/cmake/Platform), by
# the stage-1 clang for the triple against the sysroot; the tools that run during the build
# (the tablegens) are stage 1's (LLVM_NATIVE_TOOL_DIR). The host's optional libraries are off:
# none is in the sysroot as a shared library of the system's yet.
cmake -G Ninja -S "$SRC/llvm" -B "$B" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MODULE_PATH="$ROOT/llvm/build/cmake" \
    -DCMAKE_SYSTEM_NAME=EmiBSD -DCMAKE_SYSTEM_PROCESSOR=$ARCH \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_C_COMPILER="$PREFIX/bin/clang" -DCMAKE_CXX_COMPILER="$PREFIX/bin/clang++" \
    -DCMAKE_ASM_COMPILER="$PREFIX/bin/clang" \
    -DCMAKE_C_COMPILER_TARGET="$T" -DCMAKE_CXX_COMPILER_TARGET="$T" -DCMAKE_ASM_COMPILER_TARGET="$T" \
    -DCMAKE_AR="$PREFIX/bin/llvm-ar" -DCMAKE_RANLIB="$PREFIX/bin/llvm-ranlib" \
    -DCMAKE_SYSROOT="$SYSROOT" \
    -DCMAKE_FIND_ROOT_PATH="$SYSROOT" -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_SKIP_RPATH=ON \
    -DLLVM_HOST_TRIPLE="$T" -DLLVM_DEFAULT_TARGET_TRIPLE="$T" \
    -DLLVM_NATIVE_TOOL_DIR="$ROOT/$OUT/host/bin" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="AArch64;X86" \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_LIBPFM=OFF -DLLVM_ENABLE_FFI=OFF \
    -DLLVM_ENABLE_LIBCXX=ON \
    -DLLVM_DISTRIBUTION_COMPONENTS="$DISTRIBUTION" \
    -DCLANG_LINKS_TO_CREATE="clang++;clang-cpp" \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_BUILD_UTILS=OFF -DCLANG_INCLUDE_TESTS=OFF
[ -d "$DEST" ] && chmod -R u+w "$DEST" && rm -rf "$DEST"
DESTDIR="$DEST" ninja -C "$B" -j "$JOBS" install-distribution

# The target's runtimes, from build.sh's install, where the installed system has them.
RES=$DEST/usr/lib/clang/$MAJOR
mkdir -p "$RES/lib/$T" "$DEST/usr/lib" "$DEST/usr/include/c++"
cp -R "$PREFIX/lib/clang/$MAJOR/lib/$T/" "$RES/lib/$T/"
for f in libc++.a libc++abi.a libc++experimental.a libc++.so.13.0 libc++abi.so.10.0; do
    cp "$PREFIX/lib/$T/$f" "$DEST/usr/lib/$f"
done
cp -R "$PREFIX/include/c++/v1" "$DEST/usr/include/c++/v1"
cp "$PREFIX/include/$T/c++/v1/__config_site" "$DEST/usr/include/c++/v1/__config_site"
# The system's names for the compiler, the linker and the archiver.
ln -sf clang "$DEST/usr/bin/cc"
ln -sf clang++ "$DEST/usr/bin/c++"
ln -sf ld.lld "$DEST/usr/bin/ld"
ln -sf llvm-ar "$DEST/usr/bin/ar"
echo "== native done: $DEST"
sh llvm/tests/native-check.sh "$DEST" "$T"
done
