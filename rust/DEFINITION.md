# rust (imported; the pin moved here from the userland repository on 2026-10-31, decision D-0002)

STATUS: see `STATUS`. Compiled from its upstream at the pin of `UPSTREAM.toml`, never
rewritten (the user's decision of 2026-10-23). rust-lang/rust, mirrored at `EmiBSD/rust`.

## What it gives us

## What we build of it

The targets, libraries and tools taken from the source; what is left out and why.

## Constraints

The sysroots it links against, one per architecture (`EMIBSD_SYSROOT_ARM64`,
`EMIBSD_SYSROOT_AMD64`: libc, crt, headers); the stage0 it
bootstraps from; static or dynamic.

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

- One LLVM (decision D-0003, 2026-10-31): rustc is built against llvm/'s upstream LLVM 23.1.4 through llvm-config (rustc 1.99.1 needs >= 21); its own src/llvm-project submodule is not fetched. Built with x.py, host first, then the targets aarch64-emibsd-emibsd and x86_64-emibsd-emibsd (D-0004, D-0008; llvm-target <arch>-emibsd-emibsd8.0, their target specs a patch of ours in patches/): the std for the tier 3 targets is built as part of the toolchain, from a stable release's source, without nightly. Stage0: rustup's rustc on the host; on EmiBSD, the previous build. library/backtrace needs its mirror before T2.
