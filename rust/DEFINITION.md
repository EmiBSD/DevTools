# rust (imported; moved from Userland/compiler/rust on 2026-10-31, Governance G-0012)

STATUS: see `STATUS`. Compiled from its upstream at the pin of `UPSTREAM.toml`, never
rewritten (the user's decision of 2026-10-23). rust-lang/rust, mirrored at `EmiBSD/rust`.

## What it gives us

## What we build of it

The targets, libraries and tools taken from the source; what is left out and why.

## Constraints

Which libc, libtls and other libraries of this repository it must link; static or dynamic;
privileges.

## Compatibility

Who in the base system depends on it and how (flags, output, exit codes, configuration
paths). Our patches, if any, never change what callers see.

## Configuration we ship

The defaults installed under /etc, and how they differ from upstream's.

## Performance budget

As upstream builds it, on the same machine and input; a build flag that changes it is a
decision in DESIGN.

## Security history

Tracked against the upstream (`UPSTREAM.toml` `[security] cpe`): open advisories at the pin,
what the pin bump that closes them is, and `tests/cve/` for what we patched ourselves.

| CVE | Upstream fix | Here |
|---|---|---|

## Open questions

- One LLVM (Governance G-0015, 2026-10-31): rustc is built against llvm/'s upstream LLVM 22.1.6 through llvm-config (rustc 1.98.1 needs >= 21); its own src/llvm-project submodule is not fetched. Built with x.py, host first, then the target aarch64-unknown-openbsd: the std for the tier 3 target is built as part of the toolchain, from a stable release's source, without nightly. Stage0: rustup's rustc on the host; on EmiBSD, the previous build. library/backtrace needs its mirror before T2.
