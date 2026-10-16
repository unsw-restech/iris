"""Import every top-level module of every package listed in a requirements file.

Usage: python check_imports.py <requirements.lock>

Run inside the environment being checked. Prints one line per failure and
exits 1 if any package listed in the file is missing or fails to import.
"""

import importlib
import importlib.metadata as md
import re
import sys

# Top-level names that are installed by a package but are not meant to be
# imported on their own.
NOT_IMPORTABLE = {"__pycache__", "_distutils_hack"}


def requirement_names(path):
    names = []
    with open(path) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if not line or line.startswith("-"):
                continue
            m = re.match(r"[A-Za-z0-9][A-Za-z0-9._-]*", line)
            if m:
                names.append(m.group(0))
    return names


def top_level_modules(dist):
    text = dist.read_text("top_level.txt")
    if text:
        names = {n.strip() for n in text.splitlines() if n.strip()}
    else:
        names = set()
        for f in dist.files or []:
            first = f.parts[0]
            if first.endswith((".dist-info", ".data", ".libs", ".pth")) or first == "..":
                continue
            if len(f.parts) == 1:
                if first.endswith(".py"):
                    names.add(first[:-3])
                elif first.endswith(".so"):
                    names.add(first.split(".", 1)[0])
            else:
                names.add(first)
    return sorted(n.replace("/", ".") for n in names if n not in NOT_IMPORTABLE)


def main():
    failures = []
    checked = 0
    for name in requirement_names(sys.argv[1]):
        try:
            dist = md.distribution(name)
        except md.PackageNotFoundError:
            failures.append(f"{name}: not installed")
            continue
        for module in top_level_modules(dist):
            checked += 1
            try:
                importlib.import_module(module)
            except Exception as e:
                failures.append(f"{name}: import {module}: {type(e).__name__}: {e}")
    for line in failures:
        print(line)
    print(f"{checked} modules checked, {len(failures)} failures")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
