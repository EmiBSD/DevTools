# rust: delivery

What this toolchain ships, as artifacts a GitHub release carries (milestone T3) and as the
files of the `comp` set OS packages. Measured on the first builds, 2026-10-31.

| | |
|---|---|
| Artifact | `rust-<version>-<host triple>-<arch>.tar.zst` + `.sha256` for `arm64` and `amd64` (`just dist rust`, D-0008), the same host tools with one architecture's targets each: about 144 MB each for 628 MB installed (1.99.1 over LLVM 23.1.4); a directory `rustup toolchain link` takes; checked unpacked elsewhere by `tests/check.sh` |
| Host triples | aarch64-apple-darwin first (T1/T2); aarch64-emibsd-emibsd at T4 |
| Targets | `aarch64-emibsd-emibsd` and `x86_64-emibsd-emibsd` (D-0004, D-0008; `llvm-target` `<arch>-emibsd-emibsd8.0`): `std`, linked by `llvm/`'s `<arch>-emibsd-emibsd8.0-clang` against the architecture's sysroot, static PIE with `+crt-static` or dynamic; `aarch64-emibsd-none-softfloat` and `x86_64-emibsd-none-softfloat` (D-0006, D-0008): `core`, `alloc`, `compiler_builtins` |
| In the comp set | |
| Measured build time | about 15 min for rustc (two stages), `std` for the host and for `aarch64-emibsd-emibsd`, the kernel's `core`/`alloc`, cargo, rustdoc, clippy, rustfmt and `rust-src`, 6 jobs on the arm64 Mac, from a warm cargo cache; LLVM is T1's, not rebuilt |
| Size | 628 MB installed (`target/rust/install-<host>/`); nothing of Homebrew: cargo static (OpenSSL, curl, libgit2 vendored), rustc on the SDK's libraries |
