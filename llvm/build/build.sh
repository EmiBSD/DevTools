#!/bin/sh
# llvm/build/build.sh: upstream LLVM at the pin, built with its own CMake (DESIGN.md).
# Stage 1: clang, lld and the tools for the host, emitting for aarch64-unknown-openbsd.
# Stage 2: the runtimes (compiler-rt, libunwind, libc++abi, libc++) for the target, against
# EMIBSD_SYSROOT. Nothing of OpenBSD is read (Governance G-0015). Never touches upstream/.
set -eu
cd "$(dirname "$0")/../.."
SRC=upstream/llvm-project
[ -d "$SRC/llvm" ] || { echo "build: $SRC not fetched (just fetch)" >&2; exit 1; }
for t in cmake ninja python3; do command -v $t >/dev/null || { echo "build: $t not found (the user's install)" >&2; exit 1; }; done
HOST=$(cc -dumpmachine 2>/dev/null || echo host)
TRIPLE=aarch64-unknown-openbsd
JOBS=${COMP_JOBS:-6}
OUT=target/llvm
PREFIX=$PWD/$OUT/$HOST

echo "== stage 1: host tools ($HOST -> $TRIPLE)"
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

echo "== stage 2: target runtimes ($TRIPLE)"
: "${EMIBSD_SYSROOT:?set EMIBSD_SYSROOT to the target libc, crt and headers, see DESIGN.md}"
cmake -G Ninja -S "$SRC/runtimes" -B "$OUT/runtimes" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$PREFIX/bin/clang" -DCMAKE_CXX_COMPILER="$PREFIX/bin/clang++" \
    -DCMAKE_C_COMPILER_TARGET="$TRIPLE" -DCMAKE_CXX_COMPILER_TARGET="$TRIPLE" \
    -DCMAKE_ASM_COMPILER_TARGET="$TRIPLE" \
    -DCMAKE_SYSROOT="$EMIBSD_SYSROOT" -DCMAKE_SYSTEM_NAME=OpenBSD \
    -DLLVM_ENABLE_RUNTIMES="compiler-rt;libunwind;libcxxabi;libcxx" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$TRIPLE" \
    -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXXABI_USE_COMPILER_RT=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DCOMPILER_RT_BUILD_SANITIZERS=OFF -DCOMPILER_RT_BUILD_XRAY=OFF \
    -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_PROFILE=OFF -DCOMPILER_RT_BUILD_MEMPROF=OFF \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
ninja -C "$OUT/runtimes" -j "$JOBS" install
echo "== done: $PREFIX"
