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
"""Run a command under the machine's build lock, so that two heavy builds never run at once
(decision D-0007: `just build` takes /tmp/emibsd/ci.lock, the lock the kernel repository's
heavy runs take).

usage: lock.py <lock dir> <command> [args...]

The lock is a directory made with mkdir(2), which is atomic: whoever creates it holds it,
and removes it when done; while it exists, the others wait (the kernel repository's
mechanism, adopted here). A `pid` file inside names the holder; a directory whose holder is
gone is taken over. It says when it waits and for how long it waited. The command's exit
status is this program's.
"""
import os
import pathlib
import shutil
import subprocess
import sys
import time

POLL = 5  # seconds between attempts


def holder_alive(path):
    try:
        pid = int((pathlib.Path(path) / "pid").read_text().split()[0])
    except (OSError, ValueError, IndexError):
        return True  # not ours to judge: another repository's holder keeps no pid, or a race
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def take(path):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    waited = None
    while True:
        try:
            os.mkdir(path)
            break
        except FileExistsError:
            if not holder_alive(path):
                print(f"lock: {path} left by a dead holder: taking it over", file=sys.stderr, flush=True)
                shutil.rmtree(path, ignore_errors=True)
                continue
            if waited is None:
                print(f"lock: {path} is held (another build on this machine): waiting", file=sys.stderr, flush=True)
                waited = time.monotonic()
            time.sleep(POLL)
    if waited is not None:
        print(f"lock: {path} taken after {time.monotonic() - waited:.0f} s", file=sys.stderr, flush=True)
    (pathlib.Path(path) / "pid").write_text(f"{os.getpid()} devtools\n")


def main(argv):
    if len(argv) < 2:
        print(__doc__); return 2
    path, cmd = argv[0], argv[1:]
    take(path)
    try:
        return subprocess.run(cmd).returncode
    finally:
        shutil.rmtree(path, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
