#!/bin/sh
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
#
# rust/build/llvm-config-native.sh: the llvm-config of llvm/'s native tree (T3b), for rustc
# built for an EmiBSD host. The native tree's own llvm-config runs only on EmiBSD; this runs
# stage 1's (the same source, version, targets and components) and points its answers at the
# native build tree: its libraries and generated headers, its tools, its host triple, the
# system libraries the native build links (zlib, zstd, libxml2 off: llvm/build/native.sh), and
# none of the macOS linker's flags.
#
#   EMIBSD_NATIVE_LLVM=<target/llvm/native-<triple>/build> EMIBSD_NATIVE_TRIPLE=<triple> \
#       llvm-config-native.sh <llvm-config arguments>
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
host=$here/target/llvm/host
native=${EMIBSD_NATIVE_LLVM:?the native LLVM build tree}
triple=${EMIBSD_NATIVE_TRIPLE:?the native host triple}
for a in "$@"; do
    case $a in
        --system-libs) echo "-lpthread -lm"; exit 0 ;;
        --host-target) echo "$triple"; exit 0 ;;
    esac
done
"$host/bin/llvm-config" "$@" | sed \
    -e "s|$host/lib|$native/lib|g" -e "s|$host/include|$native/include|g" -e "s|$host/bin|$native/bin|g" \
    -e 's| -Wl,-search_paths_first||g' -e 's| -Wl,-headerpad_max_install_names||g'
