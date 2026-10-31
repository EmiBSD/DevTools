#!/bin/sh
# llvm/tests/check.sh PREFIX TRIPLE: what a build of this toolchain must be able to do on
# the host, run by build/build.sh after every build; `just build llvm` is not done until it
# passes. What it cannot check here (that the programs it links run) is Kernel's smoke under
# EmiBSD in QEMU: the proof of T1. Needs EMIBSD_SYSROOT, as the build does.
set -eu
prefix=${1:?prefix}
triple=${2:?triple}
: "${EMIBSD_SYSROOT:?set EMIBSD_SYSROOT to the target libc, crt and headers}"
here=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 's/^version *= *"\([^+"]*\).*/\1/p' "$here/UPSTREAM.toml")
major=${version%%.*}
case $triple in
    aarch64-*) machine="AArch64" ;;
    x86_64-*)  machine="Advanced Micro Devices X86-64" ;;
    *) echo "check.sh: unknown triple $triple" >&2; exit 2 ;;
esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/emibsd-llvm-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
bad() { echo "check.sh: $*" >&2; fail=1; }
cc="$prefix/bin/clang"
cxx="$prefix/bin/clang++"
readelf="$prefix/bin/llvm-readelf"
for p in bin/clang bin/clang++ bin/clang-cpp bin/ld.lld bin/llvm-ar bin/llvm-ranlib bin/llvm-nm bin/llvm-objcopy \
         bin/llvm-objdump bin/llvm-readobj bin/llvm-readelf bin/llvm-strip bin/llvm-size bin/llvm-strings \
         bin/llvm-symbolizer bin/llvm-addr2line bin/llvm-cxxfilt bin/llvm-dwarfdump bin/llvm-cov bin/llvm-profdata; do
    [ -x "$prefix/$p" ] || bad "missing $p"
done
# A toolchain, not LLVM's development kit (DESIGN.md: LLVM_DISTRIBUTION_COMPONENTS).
for p in bin/llc bin/opt bin/clang-repl bin/llvm-config lib/libLLVMCore.a include/llvm; do
    [ ! -e "$prefix/$p" ] || bad "$p installed: not of the distribution"
done
[ "$fail" = 0 ] || exit 1

# The host tools carry nothing of Homebrew: the artifact runs on a Mac that has none.
case $(uname) in Darwin)
    for b in "$prefix"/bin/*; do
        [ -L "$b" ] && continue
        otool -L "$b" 2>/dev/null | grep -q /opt/homebrew && bad "$(basename "$b") loads a Homebrew library: $(otool -L "$b" | grep /opt/homebrew | head -1)"
    done ;;
esac

# The compiler says who it is and for whom it emits by default.
"$cc" --version | head -1 | grep -q "clang version $version" || bad "clang --version does not say $version"
[ "$("$cc" -print-target-triple)" = "$triple" ] || bad "default target is $("$cc" -print-target-triple), not $triple"
macros=$("$cc" -dM -E -x c /dev/null)
echo "$macros" | grep -q '#define __EmiBSD__ 1' || bad "__EmiBSD__ is not predefined"
echo "$macros" | grep -q '__OpenBSD__' && bad "__OpenBSD__ is predefined: nothing of OpenBSD here"
echo "$macros" | grep -q '#define __ELF__ 1' || bad "__ELF__ is not predefined"
echo "$macros" | grep -q '#define __INT64_TYPE__ long long int' || bad "int64_t is not long long"
echo "$macros" | grep -q '#define __WCHAR_TYPE__ int' || bad "wchar_t is not int"

# The runtimes for the target, where the driver looks for them.
for f in lib/$triple/libc++.a lib/$triple/libc++abi.a lib/$triple/libunwind.a \
         include/$triple/c++/v1/__config_site include/c++/v1/vector \
         lib/clang/$major/include/stddef.h lib/clang/$major/lib/$triple/libclang_rt.builtins.a; do
    [ -f "$prefix/$f" ] || bad "missing $f"
done

# A C program compiled and linked, static PIE, against the sysroot: the ELF the kernel loads.
cat > "$tmp/h.c" <<'C'
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) { char s[64]; strlcpy(s, argc > 1 ? argv[1] : "hello", sizeof s); puts(s); return 0; }
C
if "$cc" --sysroot="$EMIBSD_SYSROOT" -static -O2 -o "$tmp/h" "$tmp/h.c" 2> "$tmp/h.err"; then
    h=$("$readelf" -h "$tmp/h")
    echo "$h" | grep -q "Machine: *$machine" || bad "h: not $machine"
    echo "$h" | grep -q "Type: *DYN" || bad "h: not a PIE (ET_DYN); rcrt0.o was not used"
    echo "$h" | grep -q "OS/ABI: *UNIX - OpenBSD" || bad "h: ELF OS/ABI byte is not 12 (what the kernel and ld.so recognise)"
    "$readelf" -d "$tmp/h" 2>/dev/null | grep -q 'NEEDED' && bad "h: dynamically linked"
    "$readelf" -l "$tmp/h" | grep -q 'OPENBSD_RANDOMIZE' || bad "h: no PT_OPENBSD_RANDOMIZE segment: the stack guard would stay zero"
    "$readelf" -n "$tmp/h" | grep -q 'BTI' || bad "h: no BTI in .note.gnu.property: branch target enforcement is off"
else
    bad "h.c did not compile and link: $(head -5 "$tmp/h.err")"
fi

# A dynamic one: ld.so and the shared libc.
if "$cc" --sysroot="$EMIBSD_SYSROOT" -O2 -o "$tmp/d" "$tmp/h.c" 2> "$tmp/d.err"; then
    "$readelf" -l "$tmp/d" | grep -q '/usr/libexec/ld.so' || bad "d: interpreter is not /usr/libexec/ld.so"
    "$readelf" -d "$tmp/d" | grep -q 'libc.so' || bad "d: libc.so is not NEEDED"
else
    bad "h.c did not link dynamically: $(head -5 "$tmp/d.err")"
fi

# A C++ program, static, over libc++, libc++abi and libunwind: exceptions and iostreams.
cat > "$tmp/x.cpp" <<'CXX'
#include <iostream>
#include <stdexcept>
#include <string>
int main() { try { throw std::runtime_error("x"); } catch (const std::exception &e) { std::cout << std::string(e.what()) << '\n'; } return 0; }
CXX
if "$cxx" --sysroot="$EMIBSD_SYSROOT" -static -O2 -o "$tmp/x" "$tmp/x.cpp" 2> "$tmp/x.err"; then
    "$readelf" -h "$tmp/x" | grep -q "Machine: *$machine" || bad "x: not $machine"
    "$prefix/bin/llvm-nm" "$tmp/x" | grep -q '__cxa_throw' || bad "x: libc++abi was not linked in"
else
    bad "x.cpp did not compile and link: $(head -8 "$tmp/x.err")"
fi

[ "$fail" = 0 ] && echo "check.sh: $prefix: ok (clang $version for $triple)"
exit $fail
