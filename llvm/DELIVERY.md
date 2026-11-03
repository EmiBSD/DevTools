# llvm: delivery

What this toolchain ships, as artifacts a GitHub release carries (milestone T3) and as the
files of the `comp` set OS packages. Measured on 2026-10-31 (first build at 22.1.6, then 23.1.4).

| | |
|---|---|
| Artifact | `llvm-<version>-<host triple>-<arch>.tar.zst` + `.sha256` for `arm64` and `amd64` (`just dist llvm`, D-0008), the same host tools with one architecture's runtimes each: 67 MB each for about 306 MB installed at 23.1.4, unstripped (the distribution of `DESIGN.md`; the full install LLVM's plain `install` makes was 517 MB for 2.2 GB at 22.1.6); checked unpacked elsewhere by `tests/check.sh` |
| Host triples | aarch64-apple-darwin first (T1/T2); aarch64-emibsd-emibsd8.0 at T4 |
| Targets | aarch64-emibsd-emibsd8.0, the default, and x86_64-emibsd-emibsd8.0 (D-0004, D-0008), through `<triple>-clang` or `--target` |
| In the comp set | |
| Measured build time | stage 1 (clang, lld, the tools) about 30 min and stage 2 (builtins, libunwind, libc++abi, libc++) about 3 min, 6 jobs on the arm64 Mac, from a cold `target/` |
| Size | 306 MB installed, unstripped: `bin/` about 270 MB (clang 109, lld 65, the binutils; each linked statically against LLVM, as upstream links them), the target's runtimes and libc++'s headers 35 MB; the build tree under `target/llvm/host` keeps the other 2 GB (the LLVM libraries rustc links, `llc`, `opt`, the rest); patch series 5 files, about 1,000 lines |
