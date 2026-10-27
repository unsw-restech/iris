#!/usr/bin/env python3
"""List what a pilot tester cannot read in a tree on Katana.

    bin/pilot-readable.py <path>
    ssh katana python3 - <path> < bin/pilot-readable.py    (as bin/syspull runs it)

A pilot tester is a member of katana_ai_ro and not of the tree's owning
group, so a path's katana_ai_ro entry decides their access, after the ACL
mask, or "other" where it has none. Every folder from / down to <path>
needs x; inside <path>, folders need r-x, files r, and files their owner
can run r-x. Prints "needs <perms>: <path>" for each one short of that and
exits 1 if any are. Runs on Katana's system python3, 3.6.
"""
import os
import stat
import subprocess
import sys

GROUP = "katana_ai_ro"


def acls(args):
    """Each "# file:" block of getfacl -p's output, as {path: [lines]}."""
    out = subprocess.run(["getfacl", "-p"] + args, stdout=subprocess.PIPE,
                         universal_newlines=True).stdout
    blocks, path = {}, None
    for line in out.splitlines():
        if line.startswith("# file: "):
            path = line[len("# file: "):]
            blocks[path] = []
        elif path and line and not line.startswith("#"):
            blocks[path].append(line)
    return blocks


def access(lines):
    """A pilot tester's effective rwx from one path's ACL lines."""
    other = "---"
    for line in lines:
        if line.startswith("group:%s:" % GROUP):
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
        for path, lines in sorted(acls(args).items()):
            want, have = needs(path, ancestor), access(lines)
            if any(w != "-" and h != w for w, h in zip(want, have)):
                short.append("needs %s: %s" % (want, path))
    for line in short:
        print(line)
    return 1 if short else 0


if __name__ == "__main__":
    sys.exit(main())
