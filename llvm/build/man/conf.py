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
# llvm/build/man/conf.py: Sphinx's configuration for the manual pages alone (llvm/build/man.sh).
# Upstream's docs/conf.py builds the whole documentation and imports a helper module from
# llvm-project/utils/docs, which is not among the paths DevTools fetches; the manual pages are
# the command guide's pages and need none of it. This reads only <docs>/CommandGuide/*.rst and
# lists the pages as upstream's conf.py does: one per file, its name the file's, its
# description what follows " - " in the title line, section 1, upstream's authors line.
import os

docs = os.environ["EMIBSD_MAN_DOCS"]            # <project>/docs of the patched source
project = os.environ["EMIBSD_MAN_PROJECT"]      # "LLVM" or "Clang"
version = release = os.environ["EMIBSD_MAN_VERSION"]
authors = os.environ["EMIBSD_MAN_AUTHORS"]
copyright = "2003-%s, LLVM Project" % os.environ["EMIBSD_MAN_YEAR"]

source_suffix = {".rst": "restructuredtext"}
include_patterns = ["CommandGuide/*.rst"]
primary_domain = "std"
nitpicky = False
suppress_warnings = ["ref", "toc", "misc.highlighting_failure"]
today_fmt = "%Y-%m-%d"

man_pages = []
guide = os.path.join(docs, "CommandGuide")
for name in sorted(os.listdir(guide)):
    if not name.endswith(".rst") or name == "index.rst":
        continue
    with open(os.path.join(guide, name), encoding="utf-8") as f:
        title = f.readline().rstrip("\n")
        header = f.readline().rstrip("\n")
    if len(header) != len(title) or " - " not in title:
        continue
    page = name[: -len(".rst")]
    man_pages.append(("CommandGuide/" + page, page, title.partition(" - ")[2], authors, 1))

# Sphinx wants a root document among the sources; the command guide's index is Markdown in
# LLVM's docs (it would need another parser) and nothing here needs a table of contents, so the
# index when it is reStructuredText, else the first page.
root_doc = "CommandGuide/index" if os.path.exists(os.path.join(guide, "index.rst")) else man_pages[0][0]
