#!/usr/bin/env python3
"""List what a pilot tester cannot read in a tree on Katana.

    bin/pilot-readable.py <path>
    ssh katana python3 - <path> < bin/pilot-readable.py    (as bin/syspull runs it)

A pilot tester is a member of katana_ai_ro and of no other group the tree
grants anything to, so their access is katana_ai_ro's after the ACL mask:
the path's group entry where katana_ai_ro owns it, its named entry, or
"other" where it has neither. Every folder from / down to <path> needs x;
inside <path>, folders need r-x, files r, and files their owner can run
r-x. Prints "needs <perms>: <path>" for each one short of that, and
getfacl's own errors, and exits 1 if there are any. Runs on Katana's
system python3, 3.6.
"""
import os
import re
import stat
import subprocess
import sys

# The pilot's group (Patrick, 2026-10-23; see AGENTS.md).
GROUP = "katana_ai_ro"


def unescape(name):
    """A path as getfacl writes it, with odd bytes as \\ooo, made usable."""
    raw = re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), name)
    return raw.encode("latin-1").decode("utf-8", "surrogateescape")


def acls(args):
    """Each "# file:" block of getfacl -p's output, as {path: [lines]},
    with the "# group:" line kept; and getfacl's errors."""
    p = subprocess.run(["getfacl", "-p"] + args, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, universal_newlines=True)
    blocks, path = {}, None
    for line in p.stdout.splitlines():
        if line.startswith("# file: "):
            path = unescape(line[len("# file: "):])
            blocks[path] = []
        elif path and line and (line.startswith("# group: ") or not line.startswith("#")):
            blocks[path].append(line)
    return blocks, p.stderr.splitlines()


def access(lines):
    """A pilot tester's effective rwx from one path's ACL lines."""
    owned = "# group: %s" % GROUP in lines
    other = "---"
    for line in lines:
        if line.startswith("group::" if owned else "group:%s:" % GROUP):
            if "#effective:" in line:
                return line.split("#effective:")[1].strip()[:3]
            return line.split(":")[2].split()[0]
        if line.startswith("other::"):
            other = line[len("other::"):][:3]
    return other


def needs(path, ancestor):
    """The rwx a pilot tester needs on path."""
    mode = os.lstat(path).st_mode
    if stat.S_ISDIR(mode):
        return "--x" if ancestor else "r-x"
    return "r-x" if mode & stat.S_IXUSR else "r--"


def main():
    root = os.path.abspath(sys.argv[1])
    parents, p = [], os.path.dirname(root)
    while p != os.path.dirname(p):
        parents.append(p)
        p = os.path.dirname(p)
    short = []
    for args, ancestor in ((parents, True), (["-R", root], False)):
        blocks, errors = acls(args)
        short += errors
        for path, lines in sorted(blocks.items()):
            want, have = needs(path, ancestor), access(lines)
            if any(w != "-" and h != w for w, h in zip(want, have)):
                short.append("needs %s: %s" % (want, path))
    for line in short:
        print(line)
    return 1 if short else 0


if __name__ == "__main__":
    sys.exit(main())
