#!/bin/sh
# llvm/build/build.sh: upstream LLVM at the pin of UPSTREAM.toml, with DevTools' patch series
# (the EmiBSD target), built with LLVM's own CMake (DESIGN.md).
#
#   sh llvm/build/build.sh            (`just build llvm`; EMIBSD_SYSROOT_ARM64 and _AMD64 set; COMP_JOBS)
#
# 1. target/llvm/src: the fetched source copied (APFS clones: instant) and the series
#    applied with patch -p1; made again when the pin, the paths or the series changed
#    (.emibsd-src).
# 2. target/llvm/host, installed under target/llvm/<host>: clang, lld and the tools of a
#    toolchain for this machine (DISTRIBUTION below, LLVM's own mechanism for a system that
#    ships LLVM), emitting for aarch64-emibsd-emibsd8.0 by default, and for x86_64 through
#    <triple>-clang (D-0008). The build tree keeps everything LLVM builds; rustc's build takes
#    its llvm-config from there.
# 3. For each target triple, target/llvm/builtins-<triple>, then target/llvm/runtimes-<triple>,
#    installed under the same prefix in lib/clang/<major>/lib/<triple>/, lib/<triple>/ and
#    include/<triple>/: compiler-rt's builtins first, then libunwind, libc++abi and libc++,
#    compiled by stage 1's clang against that architecture's sysroot (its libc, crt, headers);
#    then target/llvm/rt-<triple>, compiler-rt's profile and ubsan_minimal runtimes.
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
: "${EMIBSD_SYSROOT_ARM64:?set EMIBSD_SYSROOT_ARM64 to the arm64 libc, crt and headers, see DESIGN.md}"
: "${EMIBSD_SYSROOT_AMD64:?set EMIBSD_SYSROOT_AMD64 to the amd64 libc, crt and headers, see DESIGN.md}"
for s in "$EMIBSD_SYSROOT_ARM64" "$EMIBSD_SYSROOT_AMD64"; do
    [ -f "$s/usr/lib/libc.a" ] || { echo "build: $s: no usr/lib/libc.a" >&2; exit 1; }
done
HOST=$(cc -dumpmachine 2>/dev/null || echo host)
EMIBSD_OS_VERSION=8.0                       # the EmiBSD release the ABI belongs to; in the triple, as the BSDs do; bumped by the maintainer
TRIPLE=aarch64-emibsd-emibsd$EMIBSD_OS_VERSION      # the default: arm64 first (D-0001)
TRIPLES="$TRIPLE x86_64-emibsd-emibsd$EMIBSD_OS_VERSION"   # the runtimes are built for each (D-0008)
# clang takes its target from a <triple>- prefix in its name: what a build that cannot pass
# --target (rustc linking through cc) names as its linker.
LINKS="clang++;clang-cl;clang-cpp"
for t in $TRIPLES; do LINKS="$LINKS;$t-clang;$t-clang++"; done
VERSION=$(python3 -I -c 'import sys,tomllib; print(tomllib.load(open(sys.argv[1],"rb"))["upstream"]["version"].split("+")[0])' llvm/UPSTREAM.toml)
JOBS=${COMP_JOBS:-6}
OUT=target/llvm
PREFIX=$ROOT/$OUT/$HOST
# What the install carries (LLVM_DISTRIBUTION_COMPONENTS, DESIGN.md): the compiler and its
# builtin headers, the linker (ld.lld comes with lld), and the binutils a system build uses;
# the symlinked names (ranlib, strip, readelf, addr2line) are components of their own.
DISTRIBUTION="clang;clang-resource-headers;clang-scan-deps;lld;llvm-ar;llvm-ranlib;llvm-nm;llvm-objcopy;llvm-strip;llvm-objdump;llvm-readobj;llvm-readelf;llvm-size;llvm-strings;llvm-symbolizer;llvm-addr2line;llvm-cxxfilt;llvm-dwarfdump;llvm-cov;llvm-profdata"

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

echo "== stage 1: host tools ($HOST -> $TRIPLES, $JOBS jobs)"
cmake -G Ninja -S "$SRC/llvm" -B "$OUT/host" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD="AArch64;X86" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$TRIPLE" \
    -DCLANG_LINKS_TO_CREATE="$LINKS" \
    -DLLVM_ENABLE_ASSERTIONS=OFF \
    -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_DISTRIBUTION_COMPONENTS="$DISTRIBUTION" \
    -DLLVM_INCLUDE_TESTS=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF
# Everything first (rustc's build reads llvm-config and the LLVM tools it ships from this
# build tree), then the distribution alone is installed.
ninja -C "$OUT/host" -j "$JOBS" all install-distribution

# Stage 2, as upstream's own runtimes bootstrap does it (llvm/runtimes/CMakeLists.txt):
# first compiler-rt's builtins alone, telling CMake the compilers work (its link test
# would need the builtins themselves) and, as llvm_ExternalProject_Add does, the LLVM
# build tree and version, so that they install under lib/clang/<major>/lib/<triple>/,
# where the driver looks for them; then the other runtimes, which link against them.
# Once per target triple, each against its architecture's sysroot.
for T in $TRIPLES; do
ARCH=${T%%-*}
case $ARCH in
    aarch64) SYSROOT=$EMIBSD_SYSROOT_ARM64 ;;
    x86_64)  SYSROOT=$EMIBSD_SYSROOT_AMD64 ;;
esac
echo "== stage 2a: compiler-rt builtins ($T)"
cmake -G Ninja -S "$SRC/compiler-rt/lib/builtins" -B "$OUT/builtins-$T" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MODULE_PATH="$ROOT/llvm/build/cmake" \
    -DCMAKE_SYSTEM_NAME=EmiBSD -DCMAKE_SYSTEM_PROCESSOR=$ARCH \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$PREFIX/bin/clang" -DCMAKE_CXX_COMPILER="$PREFIX/bin/clang++" \
    -DCMAKE_ASM_COMPILER="$PREFIX/bin/clang" \
    -DCMAKE_C_COMPILER_TARGET="$T" -DCMAKE_CXX_COMPILER_TARGET="$T" \
    -DCMAKE_ASM_COMPILER_TARGET="$T" \
    -DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON -DCMAKE_ASM_COMPILER_WORKS=ON \
    -DCMAKE_AR="$PREFIX/bin/llvm-ar" -DCMAKE_RANLIB="$PREFIX/bin/llvm-ranlib" \
    -DCMAKE_SYSROOT="$SYSROOT" \
    -DLLVM_CMAKE_DIR="$ROOT/$OUT/host" \
    -DLLVM_LIBRARY_OUTPUT_INTDIR="$ROOT/$OUT/host/lib" -DLLVM_RUNTIME_OUTPUT_INTDIR="$ROOT/$OUT/host/bin" \
    -DPACKAGE_VERSION="$VERSION" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$T" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON
ninja -C "$OUT/builtins-$T" -j "$JOBS" install

echo "== stage 2b: target runtimes ($T)"
cmake -G Ninja -S "$SRC/runtimes" -B "$OUT/runtimes-$T" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MODULE_PATH="$ROOT/llvm/build/cmake" \
    -DCMAKE_SYSTEM_NAME=EmiBSD -DCMAKE_SYSTEM_PROCESSOR=$ARCH \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$PREFIX/bin/clang" -DCMAKE_CXX_COMPILER="$PREFIX/bin/clang++" \
    -DCMAKE_ASM_COMPILER="$PREFIX/bin/clang" \
    -DCMAKE_C_COMPILER_TARGET="$T" -DCMAKE_CXX_COMPILER_TARGET="$T" \
    -DCMAKE_ASM_COMPILER_TARGET="$T" \
    -DCMAKE_C_COMPILER_WORKS=ON -DCMAKE_CXX_COMPILER_WORKS=ON -DCMAKE_ASM_COMPILER_WORKS=ON \
    -DCMAKE_AR="$PREFIX/bin/llvm-ar" -DCMAKE_RANLIB="$PREFIX/bin/llvm-ranlib" \
    -DCMAKE_SYSROOT="$SYSROOT" \
    -DCMAKE_FIND_ROOT_PATH="$SYSROOT" -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    -DCMAKE_EXE_LINKER_FLAGS="-fuse-ld=lld" -DCMAKE_SHARED_LINKER_FLAGS="-fuse-ld=lld" \
    -DLLVM_ENABLE_RUNTIMES="libunwind;libcxxabi;libcxx" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$T" -DLLVM_HOST_TRIPLE="$T" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    -DLIBCXXABI_ENABLE_SHARED=ON -DLIBCXX_ENABLE_SHARED=ON \
    -DLIBUNWIND_ENABLE_SHARED=OFF -DLIBUNWIND_INSTALL_LIBRARY=OFF \
    -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
    -DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_SHARED_LIBRARY=ON \
    -DLIBCXXABI_STATICALLY_LINK_UNWINDER_IN_STATIC_LIBRARY=ON \
    -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXXABI_USE_COMPILER_RT=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBUNWIND_USE_COMPILER_RT=ON \
    -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBUNWIND_INCLUDE_TESTS=OFF
ninja -C "$OUT/runtimes-$T" -j "$JOBS" install
# The shared runtimes go by the system's names alone (D-0010, patch 0008): the unversioned
# links CMake installs beside libc++.so.13.0 and libc++abi.so.10.0 are not the system's; and
# no libunwind of its own, though an install made before D-0010 left one in the prefix.
rm -f "$PREFIX/lib/$T/libc++.so" "$PREFIX/lib/$T/libc++abi.so" "$PREFIX/lib/$T"/libunwind.*

# 2c: the two compiler-rt runtimes the base system's compiler set carries beside the builtins
# (patch 0010): profile, for -fprofile-instr-generate and coverage, and ubsan_minimal, for
# -fsanitize-minimal-runtime; static only, as the system has them. No other sanitizer, no
# xray, no fuzzer. They install beside the builtins, in lib/clang/<major>/lib/<triple>/.
echo "== stage 2c: compiler-rt profile and ubsan_minimal ($T)"
cmake -G Ninja -S "$SRC/compiler-rt" -B "$OUT/rt-$T" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_MODULE_PATH="$ROOT/llvm/build/cmake" \
    -DCMAKE_SYSTEM_NAME=EmiBSD -DCMAKE_SYSTEM_PROCESSOR=$ARCH \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_C_COMPILER="$PREFIX/bin/clang" -DCMAKE_CXX_COMPILER="$PREFIX/bin/clang++" \
    -DCMAKE_ASM_COMPILER="$PREFIX/bin/clang" \
    -DCMAKE_C_COMPILER_TARGET="$T" -DCMAKE_CXX_COMPILER_TARGET="$T" \
    -DCMAKE_ASM_COMPILER_TARGET="$T" \
    -DCMAKE_AR="$PREFIX/bin/llvm-ar" -DCMAKE_RANLIB="$PREFIX/bin/llvm-ranlib" \
    -DCMAKE_SYSROOT="$SYSROOT" \
    -DLLVM_CMAKE_DIR="$ROOT/$OUT/host" \
    -DLLVM_LIBRARY_OUTPUT_INTDIR="$ROOT/$OUT/host/lib" -DLLVM_RUNTIME_OUTPUT_INTDIR="$ROOT/$OUT/host/bin" \
    -DPACKAGE_VERSION="$VERSION" \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$T" \
    -DLLVM_ENABLE_PER_TARGET_RUNTIME_DIR=ON \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON -DCOMPILER_RT_USE_BUILTINS_LIBRARY=ON \
    -DCOMPILER_RT_BUILD_BUILTINS=OFF -DCOMPILER_RT_BUILD_PROFILE=ON \
    -DCOMPILER_RT_BUILD_SANITIZERS=ON -DCOMPILER_RT_SANITIZERS_TO_BUILD=ubsan_minimal \
    -DCOMPILER_RT_BUILD_XRAY=OFF -DCOMPILER_RT_BUILD_LIBFUZZER=OFF -DCOMPILER_RT_BUILD_MEMPROF=OFF \
    -DCOMPILER_RT_BUILD_ORC=OFF -DCOMPILER_RT_BUILD_CTX_PROFILE=OFF -DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
    -DCOMPILER_RT_INCLUDE_TESTS=OFF
ninja -C "$OUT/rt-$T" -j "$JOBS" install
rm -f "$PREFIX/lib/clang/${VERSION%%.*}/lib/$T"/libclang_rt.*.so
done
echo "== done: $PREFIX"
sh llvm/tests/check.sh "$PREFIX"
