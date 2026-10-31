#!/usr/bin/env python3
#
# Copyright (c) 2026 Emilio Navarrete Lineros <enavarre@outlook.com>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
"""Run a command under an advisory lock, so that two heavy builds on this machine never run
at once (decision D-0007: `just build` takes /tmp/emibsd/ci.lock, the lock the kernel
repository's heavy runs take).

usage: lock.py <lock file> <command> [args...]

flock(2) on the file, exclusive, blocking: when the lock is held it says so and waits, then
says how long it waited. The file is created if missing (and its directory); it is never
removed. The command's exit status is this program's. macOS has no flock(1), hence this.
"""
import fcntl
import os
import subprocess
import sys
import time


def main(argv):
    if len(argv) < 2:
        print(__doc__); return 2
    path, cmd = argv[0], argv[1:]
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT, 0o644)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print(f"lock: {path} is held (another build on this machine): waiting", file=sys.stderr, flush=True)
        t0 = time.monotonic()
        fcntl.flock(fd, fcntl.LOCK_EX)
        print(f"lock: {path} taken after {time.monotonic() - t0:.0f} s", file=sys.stderr, flush=True)
    try:
        return subprocess.run(cmd).returncode
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
