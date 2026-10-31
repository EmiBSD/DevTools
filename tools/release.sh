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
# tools/release.sh <llvm|rust>: the GitHub release of a toolchain's artifact, from the main
# session, by the maintainer (it publishes, like a push: the guard hook refuses `gh release`
# to an agent).
#
# The tag is `<name>-<version>` (`llvm-22.1.6+emibsd.1`): HEAD must carry it, the artifact in
# dist/ must have been made from it (`just dist <name>` writes the tag into MANIFEST), and the
# release gets the tarball, its .sha256 and notes that name the versions and the sums. A
# consumer then fetches by that tag and checks the sum before it unpacks.
set -eu
cd "$(dirname "$0")/.."
name=${1:?llvm or rust}
version=$(sed -n 's/^version *= *"\([^"]*\)".*/\1/p' "$name/UPSTREAM.toml")
tag="$name-$version"
git tag --points-at HEAD | grep -qx "$tag" \
    || { echo "release: HEAD is not tagged $tag (git tag -a $tag -m '...' first; a release is cut from a tagged commit)" >&2; exit 1; }
set -- dist/"$name-$version"-*.tar.zst
[ -f "$1" ] || { echo "release: no artifact in dist/ for $name $version (just dist $name)" >&2; exit 1; }
for t in "$@"; do
    [ -f "$t.sha256" ] || { echo "release: $t.sha256 missing" >&2; exit 1; }
    (cd dist && shasum -a 256 -c "$(basename "$t").sha256" >/dev/null) || { echo "release: $t does not match its .sha256" >&2; exit 1; }
    zstd -dc "$t" | tar -xOf - "$(basename "$t" .tar.zst)/MANIFEST" | grep -q "^tag: $tag\$" \
        || { echo "release: $t was not made from $tag (its MANIFEST says otherwise): just dist $name again" >&2; exit 1; }
done
notes=$(mktemp)
{
    echo "$name $version, built by EmiBSD DevTools from the tag \`$tag\`."
    echo
    echo "One tarball per host; fetch by this tag, check the sum, then unpack:"
    echo
    echo '```'
    cat dist/"$name-$version"-*.tar.zst.sha256
    echo '```'
    echo
    echo "Inside: the install tree, MANIFEST (commit, pins, patch series with sums), share/doc/emibsd/ (licences, the patches). See the repository's llvm/DELIVERY.md or rust/DELIVERY.md."
    echo
    echo "Not affiliated with or endorsed by the LLVM project or the Rust project."
} > "$notes"
echo "release: creating $tag on EmiBSD/DevTools with:"; for t in "$@"; do echo "  $t"; echo "  $t.sha256"; done
gh release create "$tag" "$@" $(for t in "$@"; do echo "$t.sha256"; done) --title "$tag" --notes-file "$notes" --verify-tag
rm -f "$notes"
