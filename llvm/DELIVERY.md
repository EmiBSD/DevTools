# llvm: delivery

What this toolchain ships, as artifacts a GitHub release carries (milestone T3) and as the
files of the `comp` set OS packages. Measured on the first build, 2026-10-31.

| | |
|---|---|
| Artifact | `llvm-<version>-<host triple>.tar.zst` + `.sha256` (`just dist llvm`): 62 MB for 296 MB installed, unstripped (`+emibsd.3`, the distribution of `DESIGN.md`; the full install of `+emibsd.1` and `.2` was 517 MB for 2.2 GB); checked unpacked elsewhere by `tests/check.sh` |
| Host triples | aarch64-apple-darwin first (T1/T2); aarch64-emibsd-emibsd8.0 at T4 |
| Targets | aarch64-emibsd-emibsd8.0 (D-0004); the X86 backend compiled, no x86_64 target until D-0001 lifts |
| In the comp set | |
| Measured build time | stage 1 (clang, lld, the tools) about 30 min and stage 2 (builtins, libunwind, libc++abi, libc++) about 3 min, 6 jobs on the arm64 Mac, from a cold `target/` |
| Size | 296 MB installed, unstripped: `bin/` 261 MB (clang 109, lld 65, the binutils; each linked statically against LLVM, as upstream links them), the target's runtimes and libc++'s headers 35 MB; the build tree under `target/llvm/host` keeps the other 2 GB (the LLVM libraries rustc links, `llc`, `opt`, the rest); patch series 5 files, about 1,000 lines |
