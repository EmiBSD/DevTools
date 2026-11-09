#!/bin/sh
# llvm/tests/check.sh PREFIX [ARCH...]: what a build of this toolchain must be able to do on the host,
# run by build/build.sh after every build; `just build llvm` is not done until it passes.
# Every target architecture is checked against its own sysroot (D-0008): aarch64 against
# EMIBSD_SYSROOT_ARM64, x86_64 against EMIBSD_SYSROOT_AMD64, as the build takes them. What it
# cannot check here (that the programs it links run) is Kernel's smoke under EmiBSD in QEMU:
# the proof of T1.
set -eu
prefix=${1:?prefix}
shift 1
archs=${*:-aarch64 x86_64}             # LLVM's names; all of them unless named (dist.py checks one per tarball)
here=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n 's/^version *= *"\([^+"]*\).*/\1/p' "$here/UPSTREAM.toml")
major=${version%%.*}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/emibsd-llvm-check.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
bad() { echo "check.sh: $*" >&2; fail=1; }
cc="$prefix/bin/clang"
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

# The compiler says who it is and for whom it emits by default: arm64 first (D-0001).
"$cc" --version | head -1 | grep -q "clang version $version" || bad "clang --version does not say $version"
default=$("$cc" -print-target-triple)
case $default in aarch64-emibsd-emibsd*) ;; *) bad "default target is $default, not aarch64-emibsd-emibsd<release>" ;; esac
os=${default#aarch64-emibsd-}

# The programs linked for each target: a C hello and a C++ one with exceptions and iostreams.
cat > "$tmp/h.c" <<'C'
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) { char s[64]; strlcpy(s, argc > 1 ? argv[1] : "hello", sizeof s); puts(s); return 0; }
C
cat > "$tmp/x.cpp" <<'CXX'
#include <iostream>
#include <stdexcept>
#include <string>
int main() { try { throw std::runtime_error("x"); } catch (const std::exception &e) { std::cout << std::string(e.what()) << '\n'; } return 0; }
CXX
triples=
for arch in $archs; do
    triple=$arch-emibsd-$os
    triples="$triples $triple"
    case $arch in
        aarch64) sysroot=${EMIBSD_SYSROOT_ARM64:?set EMIBSD_SYSROOT_ARM64 to the arm64 libc, crt and headers}; machine="AArch64" ;;
        x86_64)  sysroot=${EMIBSD_SYSROOT_AMD64:?set EMIBSD_SYSROOT_AMD64 to the amd64 libc, crt and headers}; machine="Advanced Micro Devices X86-64" ;;
        *) bad "unknown architecture $arch (aarch64, x86_64)"; continue ;;
    esac
    # The compiler named after the triple, what rustc links through, emits for it.
    cc="$prefix/bin/$triple-clang"
    cxx="$prefix/bin/$triple-clang++"
    [ -x "$cc" ] && [ -x "$cxx" ] || { bad "missing bin/$triple-clang or bin/$triple-clang++"; continue; }
    [ "$("$cc" -print-target-triple)" = "$triple" ] || bad "$triple-clang emits for $("$cc" -print-target-triple)"
    macros=$("$cc" -dM -E -x c /dev/null)
    echo "$macros" | grep -q '#define __EmiBSD__ 1' || bad "__EmiBSD__ is not predefined ($triple)"
    echo "$macros" | grep -q '__OpenBSD__' && bad "__OpenBSD__ is predefined: nothing of OpenBSD here ($triple)"
    echo "$macros" | grep -q '#define __ELF__ 1' || bad "__ELF__ is not predefined ($triple)"
    echo "$macros" | grep -q '#define __INT64_TYPE__ long long int' || bad "int64_t is not long long ($triple)"
    echo "$macros" | grep -q '#define __WCHAR_TYPE__ int' || bad "wchar_t is not int ($triple)"

    # The runtimes for the target, where the driver looks for them.
    for f in lib/$triple/libc++.a lib/$triple/libc++abi.a lib/$triple/libc++.so.13.0 lib/$triple/libc++abi.so.10.0 \
             include/$triple/c++/v1/__config_site include/c++/v1/vector \
             lib/clang/$major/include/stddef.h lib/clang/$major/lib/$triple/libclang_rt.builtins.a; do
        [ -f "$prefix/$f" ] || bad "missing $f ($triple)"
    done

    # The shared C++ runtime by the system's names, the unwinder inside libc++abi (D-0010).
    for f in libc++.so libc++abi.so libunwind.a libunwind.so; do
        [ -e "$prefix/lib/$triple/$f" ] && bad "lib/$triple/$f installed: the runtimes go by the system's names, the unwinder inside libc++abi"
    done
    for l in libc++.so.13.0 libc++abi.so.10.0; do
        [ -f "$prefix/lib/$triple/$l" ] || continue
        "$readelf" -d "$prefix/lib/$triple/$l" | grep -q "SONAME.*\[$l\]" || bad "$triple: $l's SONAME is not $l"
    done
    [ -f "$prefix/lib/$triple/libc++.so.13.0" ] && { "$readelf" -d "$prefix/lib/$triple/libc++.so.13.0" | grep -q 'NEEDED.*\[libc++abi.so.10.0\]' || bad "$triple: libc++.so.13.0 does not need libc++abi.so.10.0"; }
    [ -f "$prefix/lib/$triple/libc++abi.so.10.0" ] && { "$prefix/bin/llvm-nm" -D --defined-only "$prefix/lib/$triple/libc++abi.so.10.0" | grep -q ' _Unwind_RaiseException$' || bad "$triple: libc++abi.so.10.0 does not export the unwinder"; }
    [ -f "$prefix/lib/$triple/libc++abi.a" ] && { "$prefix/bin/llvm-nm" --defined-only "$prefix/lib/$triple/libc++abi.a" 2>/dev/null | grep -q ' _Unwind_RaiseException$' || bad "$triple: libc++abi.a does not carry the unwinder"; }

    # A C program compiled and linked, static PIE, against the sysroot: the ELF the kernel loads.
    if "$cc" --sysroot="$sysroot" -static -O2 -o "$tmp/h-$arch" "$tmp/h.c" 2> "$tmp/h-$arch.err"; then
        h=$("$readelf" -h "$tmp/h-$arch")
        echo "$h" | grep -q "Machine: *$machine" || bad "$arch h: not $machine"
        echo "$h" | grep -q "Type: *DYN" || bad "$arch h: not a PIE (ET_DYN); rcrt0.o was not used"
        echo "$h" | grep -q "OS/ABI: *UNIX - OpenBSD" || bad "$arch h: ELF OS/ABI byte is not 12 (what the kernel and ld.so recognise)"
        "$readelf" -d "$tmp/h-$arch" 2>/dev/null | grep -q 'NEEDED' && bad "$arch h: dynamically linked"
        "$readelf" -l "$tmp/h-$arch" | grep -q 'OPENBSD_RANDOMIZE' || bad "$arch h: no PT_OPENBSD_RANDOMIZE segment: the stack guard would stay zero"
        # Branch-target enforcement on by default: on aarch64 every input carries BTI, so the
        # note survives the link; on x86_64 the libc's assembly starts with endbr64 but carries no
        # note (the system's kernel does not read it), so the code itself is what is checked.
        case $arch in
            aarch64) "$readelf" -n "$tmp/h-$arch" | grep -q 'BTI' || bad "$arch h: no BTI in .note.gnu.property: branch target enforcement is off" ;;
            x86_64)  "$prefix/bin/llvm-objdump" -d --no-show-raw-insn --disassemble-symbols=main "$tmp/h-$arch" | grep -A1 '<main>:' | grep -q endbr64 \
                         || bad "$arch h: main does not start with endbr64: -fcf-protection=branch is off" ;;
        esac
    else
        bad "$arch: h.c did not compile and link: $(head -5 "$tmp/h-$arch.err")"
    fi

    # A dynamic one: ld.so and the shared libc.
    if "$cc" --sysroot="$sysroot" -O2 -o "$tmp/d-$arch" "$tmp/h.c" 2> "$tmp/d-$arch.err"; then
        "$readelf" -l "$tmp/d-$arch" | grep -q '/usr/libexec/ld.so' || bad "$arch d: interpreter is not /usr/libexec/ld.so"
        "$readelf" -d "$tmp/d-$arch" | grep -q 'libc.so' || bad "$arch d: libc.so is not NEEDED"
    else
        bad "$arch: h.c did not link dynamically: $(head -5 "$tmp/d-$arch.err")"
    fi

    # A C++ program, static, over libc++, libc++abi and libunwind: exceptions and iostreams.
    if "$cxx" --sysroot="$sysroot" -static -O2 -o "$tmp/x-$arch" "$tmp/x.cpp" 2> "$tmp/x-$arch.err"; then
        "$readelf" -h "$tmp/x-$arch" | grep -q "Machine: *$machine" || bad "$arch x: not $machine"
        "$prefix/bin/llvm-nm" "$tmp/x-$arch" | grep -q '__cxa_throw' || bad "$arch x: libc++abi was not linked in"
    else
        bad "$arch: x.cpp did not compile and link: $(head -8 "$tmp/x-$arch.err")"
    fi

    # A dynamic C++ program needs the system's shared C++ runtime by its name.
    if "$cxx" --sysroot="$sysroot" -O2 -o "$tmp/xd-$arch" "$tmp/x.cpp" 2> "$tmp/xd-$arch.err"; then
        "$readelf" -d "$tmp/xd-$arch" | grep -q 'NEEDED.*\[libc++.so.13.0\]' || bad "$arch xd: libc++.so.13.0 is not NEEDED"
    else
        bad "$arch: x.cpp did not link dynamically: $(head -8 "$tmp/xd-$arch.err")"
    fi

    # The driver links with the system's link defaults (patch 0007).
    ll=$("$cc" --sysroot="$sysroot" -### -o "$tmp/l-$arch" "$tmp/h.c" 2>&1)
    for o in --undefined-version --ignore-function-address-equality; do
        echo "$ll" | grep -q -- "\"$o\"" || bad "$arch: the driver's link line lacks $o"
    done

    # The system's section names give the OpenBSD-ABI segments (patch 0006); the two
    # syscalls names in one link are refused.
    printf '%s\n' 'int r __attribute__((section(".emibsd.randomdata"))) = 1;' \
        'int m __attribute__((section(".emibsd.mutable"))) = 1;' \
        'int s __attribute__((section(".emibsd.syscalls"))) = 1;' 'void _start(void) {}' > "$tmp/e.c"
    echo 'int t __attribute__((section(".openbsd.syscalls"))) = 1;' > "$tmp/o.c"
    if "$cc" -c -o "$tmp/e-$arch.o" "$tmp/e.c" && "$cc" -c -o "$tmp/o-$arch.o" "$tmp/o.c" &&
       "$prefix/bin/ld.lld" -o "$tmp/e-$arch" "$tmp/e-$arch.o" 2> "$tmp/e-$arch.err"; then
        l=$("$readelf" -lW "$tmp/e-$arch")
        for seg in OPENBSD_RANDOMIZE OPENBSD_MUTABLE OPENBSD_SYSCALLS; do
            echo "$l" | grep -q "$seg" || bad "$arch e: .emibsd.* gave no PT_$seg segment"
        done
        "$prefix/bin/ld.lld" -o "$tmp/eo-$arch" "$tmp/e-$arch.o" "$tmp/o-$arch.o" 2> "$tmp/eo-$arch.err" &&
            bad "$arch: .openbsd.syscalls and .emibsd.syscalls linked together"
    else
        bad "$arch: the .emibsd.* sections did not link: $(head -5 "$tmp/e-$arch.err")"
    fi
done

[ "$fail" = 0 ] && echo "check.sh: $prefix: ok (clang $version for$triples)"
exit $fail
