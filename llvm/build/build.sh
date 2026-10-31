#!/bin/sh
# llvm/build/build.sh: upstream LLVM at the pin of UPSTREAM.toml, with DevTools' patch series
# (the EmiBSD target), built with LLVM's own CMake (DESIGN.md).
#
#   sh llvm/build/build.sh            (`just build llvm`; EMIBSD_SYSROOT set; COMP_JOBS)
#
# 1. target/llvm/src: the fetched source copied (APFS clones: instant) and the series
#    applied with patch -p1; made again when the pin, the paths or the series changed
#    (.emibsd-src).
# 2. target/llvm/host, installed under target/llvm/<host>: clang, lld and the tools for
#    this machine, emitting for aarch64-emibsd-emibsd8.0 by default.
# 3. target/llvm/builtins, then target/llvm/runtimes, installed under the same prefix in
#    lib/clang/<major>/lib/<triple>/, lib/<triple>/ and include/<triple>/: compiler-rt's
#    builtins first, then libunwind, libc++abi and libc++ for the target, compiled by
#    stage 1's clang against EMIBSD_SYSROOT (the target's libc, crt, headers).
# 4. tests/check.sh over the result.
#
# Nothing of OpenBSD is read. Never touches upstream/.
set -eu
cd "$(dirname "$0")/../.."
ROOT=$PWD
UP=upstream/llvm-project
SRC=target/llvm/src
[ -f "$UP/.pin" ] || { echo "build: $UP not fetched (just fetch)" >&2; exit 1; }
for t in cmake ninja python3; do command -v $t >/dev/null || { echo "build: $t not found (the user's install)" >&2; exit 1; }; done
pin=$(cat "$UP/.pin")
[ "$pin" = "$(python3 -I -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["upstream"]["commit"])' llvm/UPSTREAM.toml)" ] \
    || { echo "build: $UP is not at UPSTREAM.toml's commit (just fetch)" >&2; exit 1; }
: "${EMIBSD_SYSROOT:?set EMIBSD_SYSROOT to the target libc, crt and headers, see DESIGN.md}"
[ -f "$EMIBSD_SYSROOT/usr/lib/libc.a" ] || { echo "build: $EMIBSD_SYSROOT: no usr/lib/libc.a" >&2; exit 1; }
HOST=$(cc -dumpmachine 2>/dev/null || echo host)
EMIBSD_OS_VERSION=8.0                       # the EmiBSD release the ABI belongs to; in the triple, as the BSDs do; bumped by the maintainer
TRIPLE=aarch64-emibsd-emibsd$EMIBSD_OS_VERSION
VERSION=$(python3 -I -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["upstream"]["version"].split("+")[0])' llvm/UPSTREAM.toml)
JOBS=${COMP_JOBS:-6}
OUT=target/llvm
PREFIX=$ROOT/$OUT/$HOST

# 1. The source copy, patched.
series=$(python3 -I -c 'import sys,tomllib; print(" ".join(tomllib.load(open(sys.argv[1],"rb"))["patches"]["series"]))' llvm/UPSTREAM.toml)
paths=$(python3 -I -c 'import sys,tomllib; print(" ".join(tomllib.load(open(sys.argv[1],"rb"))["upstream"]["path"]))' llvm/UPSTREAM.toml)
stamp="pin $pin
paths $paths
series $series"
for p in $series; do stamp="$stamp
$(shasum -a 256 "llvm/patches/$p")"; done
if [ ! -f "$SRC/.emibsd-src" ] || [ "$(cat "$SRC/.emibsd-src")" != "$stamp" ]; then
    echo "== source: $UP at $(printf %.12s "$pin") copied to $SRC, series: ${series:-none}"
    [ -d "$SRC" ] && chmod -R u+w "$SRC"
    rm -rf "$SRC"
    mkdir -p "$OUT"
    cp -c -R "$UP/" "$SRC" 2>/dev/null || cp -R "$UP/" "$SRC"
    chmod -R u+w "$SRC"
    rm -rf "$SRC/.git"
    for p in $series; do
        echo "== patch: $p"
        patch -p1 -d "$SRC" -s -N < "llvm/patches/$p"
    done
    printf '%s\n' "$stamp" > "$SRC/.emibsd-src"
fi

echo "== stage 1: host tools ($HOST -> $TRIPLE, $JOBS jobs)"
cmake -G Ninja -S "$SRC/llvm" -B "$OUT/host" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="AArch64;X86" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$TRIPLE" \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_INSTALL_UTILS=ON \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF
ninja -C "$OUT/host" -j "$JOBS" install

# Stage 2, as upstream's own runtimes bootstrap does it (llvm/runtimes/CMakeLists.txt):
# first compiler-rt's builtins alone, telling CMake the compilers work (its link test
# would need the builtins themselves) and, as llvm_ExternalProject_Add does, the LLVM
# build tree and version, so that they install under lib/clang/<major>/lib/<triple>/,
# where the driver looks for them; then the other runtimes, which link against them.
echo "== stage 2a: compiler-rt builtins ($TRIPLE)"
cmake -G Ninja -S "$SRC/compiler-rt/lib/builtins" -B "$OUT/builtins" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MODULE_PATH="$ROOT/llvm/build/cmake" \
    -DCMAKE_SYSTEM_NAME=EmiBSD -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$PREFIX/bin/clang" -DCMAKE_CXX_COMPILER="$PREFIX/bin/clang++" \
    -DCMAKE_ASM_COMPILER="$PREFIX/bin/clang" \
    -DCMAKE_C_COMPILER_TARGET="$TRIPLE" -DCMAKE_CXX_COMPILER_TARGET="$TRIPLE" \
    -DCMAKE_ASM_COMPILER_TARGET="$TRIPLE" \
    -DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON -DCMAKE_ASM_COMPILER_WORKS=ON \
    -DCMAKE_AR="$PREFIX/bin/llvm-ar" -DCMAKE_RANLIB="$PREFIX/bin/llvm-ranlib" \
    -DCMAKE_SYSROOT="$EMIBSD_SYSROOT" \
    -DLLVM_CMAKE_DIR="$ROOT/$OUT/host" \
    -DLLVM_LIBRARY_OUTPUT_INTDIR="$ROOT/$OUT/host/lib" -DLLVM_RUNTIME_OUTPUT_INTDIR="$ROOT/$OUT/host/bin" \
    -DPACKAGE_VERSION="$VERSION" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$TRIPLE" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
ninja -C "$OUT/builtins" -j "$JOBS" install

echo "== stage 2b: target runtimes ($TRIPLE)"
cmake -G Ninja -S "$SRC/runtimes" -B "$OUT/runtimes" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MODULE_PATH="$ROOT/llvm/build/cmake" \
    -DCMAKE_SYSTEM_NAME=EmiBSD -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$PREFIX/bin/clang" -DCMAKE_CXX_COMPILER="$PREFIX/bin/clang++" \
    -DCMAKE_ASM_COMPILER="$PREFIX/bin/clang" \
    -DCMAKE_C_COMPILER_TARGET="$TRIPLE" -DCMAKE_CXX_COMPILER_TARGET="$TRIPLE" \
    -DCMAKE_ASM_COMPILER_TARGET="$TRIPLE" \
    -DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON -DCMAKE_ASM_COMPILER_WORKS=ON \
    -DCMAKE_AR="$PREFIX/bin/llvm-ar" -DCMAKE_RANLIB="$PREFIX/bin/llvm-ranlib" \
    -DCMAKE_SYSROOT="$EMIBSD_SYSROOT" \
    -DCMAKE_FIND_ROOT_PATH="$EMIBSD_SYSROOT" -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld" -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld" \
    -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$TRIPLE" -DLLVM_HOST_TRIPLE="$TRIPLE" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBCXXABI_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_SHARED=OFF \
    -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXXABI_USE_COMPILER_RT=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBUNWIND_INCLUDE_TESTS=OFF
ninja -C "$OUT/runtimes" -j "$JOBS" install
echo "== done: $PREFIX"
sh llvm/tests/check.sh "$PREFIX" "$TRIPLE"
