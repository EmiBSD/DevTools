# llvm: integration

## How it is built

`build/build.sh` builds upstream LLVM with its own CMake and Ninja, under `target/llvm/`:

0. **The source.** `upstream/llvm-project` at the pin, copied to `target/llvm/src` (APFS
   clones) and the series of `UPSTREAM.toml` applied with `patch -p1`: the EmiBSD target
   (below). The copy is remade when the pin or a patch changes; the upstream is never
   touched.
1. **Stage 1, the host tools.** `cmake -S target/llvm/src/llvm -B target/llvm/host`
   with `LLVM_ENABLE_PROJECTS=clang;lld`, `LLVM_TARGETS_TO_BUILD=AArch64;X86`,
   `LLVM_DEFAULT_TARGET_TRIPLE=aarch64-emibsd-emibsd8.0`, `CMAKE_BUILD_TYPE=Release`,
   `LLVM_ENABLE_ASSERTIONS=OFF`; the distribution (`LLVM_DISTRIBUTION_COMPONENTS`, below)
   installed into `target/llvm/<host>/` with `install-distribution`, with clang's links
   `<triple>-clang` and `<triple>-clang++` for each target (below). The build tree
   `target/llvm/host/` keeps everything LLVM builds; rustc's `llvm-config` points there.
2. **Stage 2, the target runtimes**, once per target triple (arm64's, then amd64's: D-0008),
   in the two passes upstream's own runtimes bootstrap
   makes (`llvm/runtimes/CMakeLists.txt`), because CMake's compiler test links, and the link
   needs the builtins that this stage produces. **2a**: `cmake -S
   target/llvm/src/compiler-rt/lib/builtins -B target/llvm/builtins-<triple>`, the stage-1 clang as
   the compiler, `CMAKE_SYSTEM_NAME=EmiBSD` (CMake learns the system from
   `build/cmake/Platform/EmiBSD.cmake`), `CMAKE_SYSROOT` the architecture's sysroot
   (`EMIBSD_SYSROOT_ARM64`, `EMIBSD_SYSROOT_AMD64`), the triple, `CMAKE_{C,CXX,ASM}_COMPILER_WORKS=ON` as upstream passes them,
   `COMPILER_RT_DEFAULT_TARGET_ONLY=ON`; installed into the stage-1 tree under
   `lib/clang/23/lib/<triple>/`. **2b**: `cmake -S target/llvm/src/runtimes -B
   target/llvm/runtimes-<triple>` with `LLVM_ENABLE_RUNTIMES=libunwind;libcxxabi;libcxx`, the same
   compiler, system, sysroot and triple, static libraries only, `LIBCXX_USE_COMPILER_RT=ON`,
   `LIBCXXABI_USE_LLVM_UNWINDER=ON`; installed under `lib/<triple>/` and
   `include/<triple>/` (`LLVM_ENABLE_PER_TARGET_RUNTIME_DIR`), where the driver
   looks for them. **2c**: `cmake -S target/llvm/src/compiler-rt -B target/llvm/rt-<triple>`
   for the two compiler-rt runtimes the base system's compiler set carries beside the
   builtins, `profile` and `ubsan_minimal` (patch 0010), static, installed beside the
   builtins. No other sanitizer, no xray, no fuzzer.
3. **`tests/check.sh`** over the install tree: the compiler's identity and macros, the
   runtimes in place, a C program linked static PIE and dynamic, a C++ program over libc++;
   the ELF each must be (`DESIGN.md` of the kernel's loader, in a word: PIE, OS/ABI byte 12,
   `PT_OPENBSD_RANDOMIZE`, BTI). That they run is the kernel repository's smoke, T1's proof.

The install tree is the artifact (T3): `bin/` (the distribution), `lib/clang/23/` (the
builtin headers and the target's builtins), `lib/<triple>/` and `include/<triple>/` (the
target's runtimes and libc++'s headers).

Flags that differ from upstream's defaults, with the reason:

| Flag | Value | Why |
|---|---|---|
| `LLVM_ENABLE_ZSTD` | `OFF` | CMake found Homebrew's zstd and the tools loaded `/opt/homebrew/opt/zstd/lib/libzstd.1.dylib`, which no other Mac has, and rustc's link asked for `-lzstd` with no path; the host tools link only the SDK's libraries (zlib, libxml2, libedit); `tests/check.sh` refuses anything under `/opt/homebrew` |
| `LLVM_DEFAULT_TARGET_TRIPLE` | `aarch64-emibsd-emibsd8.0` | the system's clang emits for the system by default (D-0004), arm64 first (D-0008); the OS version is the EmiBSD release the ABI belongs to, `EMIBSD_OS_VERSION` in `build.sh`, bumped by the maintainer; the per-target runtime directories carry it |
| `CLANG_LINKS_TO_CREATE` | upstream's `clang++;clang-cl;clang-cpp`, plus `<triple>-clang` and `<triple>-clang++` for `aarch64-emibsd-emibsd8.0` and `x86_64-emibsd-emibsd8.0` | clang takes its target from a triple prefixed to its name; rustc passes no `--target` to a cc linker, so a Rust program for x86_64 links through `x86_64-emibsd-emibsd8.0-clang` (D-0008); installed with the `clang` component |
| `CMAKE_SYSTEM_NAME` (stage 2) | `EmiBSD`, with `build/cmake/Platform/EmiBSD.cmake` | CMake must name the system the runtimes are cross-compiled for; it knows no EmiBSD, so DevTools describes it (an ELF Unix without libdl) |
| `LLVM_ENABLE_PER_TARGET_RUNTIME_DIR` (stage 2) | `ON` | the runtimes land in `lib/<triple>/`, where clang's driver looks for a cross target |
| `LIBCXX_ENABLE_SHARED`, `LIBCXXABI_ENABLE_SHARED` | `ON` | the base system carries the shared C++ runtime, `libc++.so.13.0` and `libc++abi.so.10.0` (D-0010, names by patch 0008); the native tools link against it. The unversioned `.so` links CMake installs are removed, so `-lc++` takes the versioned library (patch 0005) and a static link the `.a` |
| `LIBCXXABI_ENABLE_STATIC_UNWINDER`, `LIBCXXABI_STATICALLY_LINK_UNWINDER_IN_SHARED_LIBRARY`, `..._IN_STATIC_LIBRARY`; `LIBUNWIND_ENABLE_SHARED`, `LIBUNWIND_INSTALL_LIBRARY` | `ON`, `ON`, `ON`; `OFF`, `OFF` | the unwinder lives inside libc++abi, shared and static, as the base system's lists expect (D-0010); libunwind is built only to be merged, and not installed on its own; the first option is the one the other two depend on in upstream's CMake |
| `LLVM_TARGETS_TO_BUILD` | `AArch64;X86` | arm64 and amd64 (decision D-0008); nothing else |
| `COMPILER_RT_BUILD_*` (stage 2c) | `PROFILE` on, `SANITIZERS` on with `COMPILER_RT_SANITIZERS_TO_BUILD=ubsan_minimal`; xray, fuzzer, memprof, orc, ctx_profile, gwp_asan off; the shared `ubsan_minimal` removed | the builtins and the two runtimes the base system's compiler set carries (`-fprofile-instr-generate`, `-fsanitize-minimal-runtime`), static as it has them; the full sanitizers need a port of sanitizer_common to the system, which is not claimed |
| `LLVM_ENABLE_ASSERTIONS` | `OFF` | a release compiler; assertions are for developing LLVM |
| `LLVM_DISTRIBUTION_COMPONENTS` | clang and its resource headers, `clang-scan-deps` (the base system's compiler set carries it), lld, `llvm-ar`, `llvm-ranlib`, `llvm-nm`, `llvm-objcopy`, `llvm-strip`, `llvm-objdump`, `llvm-readobj`, `llvm-readelf`, `llvm-size`, `llvm-strings`, `llvm-symbolizer`, `llvm-addr2line`, `llvm-cxxfilt`, `llvm-dwarfdump`, `llvm-cov`, `llvm-profdata` (`DISTRIBUTION` in `build.sh`) | a plain `install` is LLVM's development kit: 131 programs (`llc`, `opt`, `clang-repl`, the GPU wrappers, `bugpoint`...), the LLVM and clang static libraries and headers, 2.2 GB, each tool linked statically against LLVM as upstream links them; `LLVM_DISTRIBUTION_COMPONENTS` is the mechanism upstream gives a system that ships LLVM (its `clang/cmake/caches/` are examples), and the list is what a system build uses: the compiler, the linker and the binutils, about 300 MB, the same binaries linked the same way; nothing is built differently. rustc's build reads the build tree. The tools stay statically linked against LLVM: a toolchain that depends on a shared `libLLVM` breaks with it |

Everything else is upstream's default.

## Patches

The series is the EmiBSD target (decision D-0004): operating-system support written by us,
ISC, over the pinned tag, each file with its reason in its header. The fork stays a mirror:
no commit of ours lands on it; the series is re-applied at every pin bump and offered
upstream when it is stable.

| Patch | What |
|---|---|
| `0001-llvm-target-emibsd` | `Triple::EmiBSD` (`emibsd`); what the ABI needs of code generation: emulated TLS (the run-time link-editor has no ELF TLS), the stack protector through the libc's `__guard_local` and `__stack_smash_handler`, the ELF OS/ABI byte 12 in objects (what the kernel and ld.so recognise, and what lld keys the `PT_OPENBSD_RANDOMIZE` segment on) |
| `0002-clang-target-emibsd` | `EmiBSDTargetInfo`: `__EmiBSD__` and nothing of any other system, the libc's C types (`wchar_t` int, `int64_t` long long on AArch64 too), `__mcount`, malloc's 16-byte alignment; registered for aarch64 and x86_64 |
| `0003-clang-driver-emibsd` | `ToolChains/EmiBSD.{h,cpp}` (new): the link line (`__start`, `rcrt0.o` for a static PIE, `crtbegin`/`crtend`, `/usr/libexec/ld.so`, lld, compiler-rt's builtins around `-lc`, libc++ with libc++abi, which carries the unwinder), PIE by default (`-static-pie`, what rustc asks for a static PIE, is `-static` here), the strong stack protector, `/usr/include` of the sysroot for C and, for C++, libc++'s headers where clang's generic search finds them (the toolchain's `include/<triple>/c++/v1` and `include/c++/v1`, else the sysroot's `/usr/include/c++/v1`); the shared driver tables (toolchain selection, OS library name, no GCC tree, `-fpie`, no `-lrt`/`-ldl`, `-p`) and the hardening defaults below |
| `0004-runtimes-emibsd` | compiler-rt, libc++ and libc++abi choose their platform code by macro: `__EmiBSD__` joins the conditions for the libc interfaces this libc has (`<machine/endian.h>`, `elf_aux_info`, `arc4random`, pthreads, the rune table, `futex(2)`, `clock_gettime`); libc++ as the default C++ library in compiler-rt's CMake; since 23.1.4, `__get_locale_encoding` (`nl_langinfo_l(CODESET)`) in libc++'s OpenBSD locale support header, which upstream's `text_encoding.cpp` needs and that header lacks: a fix upstream needs for OpenBSD too, to be offered |
| `0005-lld-versioned-shared-libs` | `-l<name>` resolves to `lib<name>.so.<major>.<minor>` of the highest version when no `lib<name>.so` exists, before `lib<name>.a`: the system's shared libraries carry only the versioned name its `ld.so` looks up, and the linker, not a link per library, knows it, on every host it runs on |
| `0006-lld-emibsd-sections` | `.emibsd.randomdata`, `.emibsd.mutable` and `.emibsd.syscalls`, the system's names, give the same `PT_OPENBSD_RANDOMIZE`, `PT_OPENBSD_MUTABLE` and `PT_OPENBSD_SYSCALLS` segments (same values, flags and placement, `.emibsd.randomdata` in RELRO) as the `.openbsd.*` names, which stay accepted during the move; both syscalls names in one link are an error, not two segments |
| `0007-clang-driver-emibsd-link-defaults` | every link the driver makes passes `--undefined-version` and `--ignore-function-address-equality`, before the user's arguments: what the system's libraries are linked with (a version script naming a symbol the library lacks, protected symbols preemptible), which upstream lld does not default to; in the driver, so a direct `ld.lld` (the kernel's) is unchanged |
| `0008-runtimes-emibsd-sonames` | libc++'s and libc++abi's shared libraries take the system's names and sonames, `libc++.so.13.0` and `libc++abi.so.10.0`, which its `ld.so` looks up and the base system's lists expect (D-0010); upstream names them after the ABI version, with no option for the name alone; the ABI namespace stays `__1` |
| `0009-llvm-host-emibsd` | LLVM's support library and CMake learn EmiBSD as a host, as OpenBSD's interface (statfs, the executable's path from argv[0], no /proc, `getthrid`, `<pthread_np.h>`, `dl_iterate_phdr`, `<endian.h>`; no Mach, no `-z defs`): what the native toolchain needs to run there (T3b, D-0009); the macOS host build is unchanged |
| `0010-compiler-rt-profile-ubsan-emibsd` | compiler-rt builds `profile` and `ubsan_minimal` for EmiBSD: the system joins the two lists of `config-ix.cmake`, the profile runtime's ELF platform file (the linker's `__start_`/`__stop_` section symbols, as LLVM emits profile data for ELF) and `sanitizer_platform.h`'s list of known systems, which `ubsan_minimal` includes for its macros only |

Defaults the driver turns on for the target, which change what the compiler emits, each a
decision of this repository (D-0004) and reversible here:

| Default | On | Why |
|---|---|---|
| `-fpie`, PIE executables, `rcrt0.o` with `-static` | aarch64, x86_64 | the kernel loads PIE and randomises its base; a static executable relocates itself |
| `-mbranch-target-enforce`, `-msign-return-address=non-leaf` | aarch64 | the kernel enforces branch-target identification on user pages; the system's libraries are built with return-address signing |
| `-fcf-protection=branch`, `-fno-jump-tables` | x86_64 | indirect-branch tracking, as the system's libraries expect; jump tables would jump indirectly to labels with no `endbr64`; upstream's OpenBSD branch of the driver, which patch 0003 lets EmiBSD into (D-0008) |
| `-fstack-protector-strong` | all | the libc provides the guard and the handler; on by default as in the system |
| `-funwind-tables` (asynchronous) | all | libunwind unwinds through C frames (exceptions, backtraces) |
| `-fuse-ld=lld` | all | the one linker of the toolchain |

Not turned on, though the system's own compiler once did: `-mstrict-align` on aarch64 (a
performance policy, not an ABI need), `-mretguard` and `-fret-clean` (not in upstream LLVM;
if the maintainer wants that hardening, it is a decision and a patch of ours, D-0004).

## Concurrency

As upstream has it; Ninja runs `COMP_JOBS` compiles at once.

## Threat model and security

`tests/` proves the artifact: the versions the binaries print, a C hello compiled and linked
static for the target, a C++ hello against libc++; under the EmiBSD kernel in QEMU, that both run
(T1's proof). The CVE watch is `tools/cve.py llvm` over `llvm:llvm`.

## Dependencies

The host's CMake, Ninja, Python 3 and a C++ compiler (Apple clang on the Mac); the sysroot
for stage 2 (the userland repository's libc, crt and headers; until then the base sets the
kernel boots, given by path). No stage0: LLVM bootstraps from the host compiler.

## The native toolchain (T3b, D-0009, D-0010)

`build/native.sh` (`just native llvm [aarch64|x86_64]`), after `build.sh`: the same patched
source, cross-compiled by stage 1's clang for the host `<arch>-emibsd-emibsd8.0` against the
architecture's sysroot (`CMAKE_SYSTEM_NAME` EmiBSD, as stage 2), with stage 1's tablegens
(`LLVM_NATIVE_TOOL_DIR`); the same distribution as the cross toolchain, installed with
`DESTDIR` under prefix `/usr` into `target/llvm/native-<triple>/root`, then stage 2's runtimes
copied where the installed system has them (`usr/lib`, `usr/lib/clang/<major>`,
`usr/include/c++/v1` with `__config_site`) and `cc`, `c++`, `cpp`, `ld`, `ar` as links (`cpp`
is clang in its preprocessor mode, taken from the name; the base system runs `/usr/bin/cpp` by
that path), with `nm`,
`objdump`, `strip`, `ranlib`, `readelf`, `size`, `strings`, `objcopy`, `addr2line` and `c++filt`
to their LLVM tools (the maintainer, 2026-11-09 and 2026-11-11), so the base system's own
versions can go; the builtins also as `usr/lib/libcompiler_rt.a`, the name the system links; and
the manual pages (`build/man.sh`): `clang.1` and the `llvm-*` pages, rendered from the patched
source's command guide by Sphinx's man builder, lld's own `ld.lld.1`, and the same pages under
the system's names as links (`cc.1`, `ar.1`, `ld.1`...). Sphinx is a host tool, the user's
install. `build/man/conf.py` is ours, for the manual pages alone: upstream's `docs/conf.py`
builds the whole documentation and imports a helper from `llvm-project/utils/docs`, which is not
among the fetched paths; it lists the pages as upstream's does, so the pages' text is the same. Against the base system's lists the tree deliberately lacks: a shared `libLLVM` and LLVM's
headers and `llvm-config` (the tools are static against LLVM, D-0010, and the development kit is
not shipped), the profiled `_p` archives (D-0010), `lldb` (its source is not among the paths
fetched, and upstream has no native-process support for the OpenBSD interface: a decision of its
own). `clang-scan-deps` has no manual page upstream. The tools link
dynamically against the system's libc and `libc++.so.13.0`, LLVM's libraries static inside each
(D-0010); no rpath (`CMAKE_SKIP_RPATH`); zlib, zstd, libxml2, libedit, libpfm and libffi off,
none being a shared library of the system's in the sysroot yet. `tests/native-check.sh` checks
the tree and every program's ELF without running it; the proof is the run in QEMU.
