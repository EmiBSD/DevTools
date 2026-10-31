# rust: integration

## How it is built

The source at the pin, copied to `target/`, `patches/` applied, built by `build/build.sh`
against the sysroot it is given (`EMIBSD_SYSROOT`: the userland's libc, crt and headers).
Flags that differ from upstream's build, with the reason.

## Patches

One line per patch of `patches/`: what it changes and why it could not stay upstream.

## Concurrency

As upstream has it; nothing added.

## Threat model and security

What the upstream restricts (pledge, unveil, privilege separation) and the proof we kept it:
the tests that run it under our kernel.

## Dependencies

The sysroot it links against (`EMIBSD_SYSROOT`), the stage0 it bootstraps from, `llvm/`'s
`llvm-config`, and any other upstream it needs.
