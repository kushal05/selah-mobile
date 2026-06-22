#!/usr/bin/env python3
"""Set or bump the version (name and/or build number) in pubspec.yaml.

Interactive (run from a terminal / the VS Code Deploy task):
  Shows the current version name and build number and prompts for each.
  Press Enter to keep the version name and to auto-increment the build number.

Non-interactive:
  bump_version.py 22            # set build number to 22, keep version name
  bump_version.py 0.1.1+22      # set version name AND build number
  (no args, no TTY)             # keep version name, auto-increment build number
"""
import re, sys

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

path = "pubspec.yaml"
text = open(path).read()

m = re.search(r"^version:\s*(\S+?)\+(\d+)", text, flags=re.MULTILINE)
if not m:
    print("ERROR: could not find 'version: X.Y.Z+N' in pubspec.yaml", file=sys.stderr)
    sys.exit(1)

cur_name = m.group(1)            # e.g. "0.1.0"
cur_build = int(m.group(2))      # e.g. 21
default_build = cur_build + 1


def err(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def parse_build(raw):
    raw = raw.strip()
    if not raw.isdigit():
        err(f"build number must be a positive integer, got '{raw}'")
    return int(raw)


def parse_name(raw):
    raw = raw.strip()
    if "+" in raw or not re.fullmatch(r"[0-9A-Za-z.\-]+", raw):
        err(f"invalid version name '{raw}' (digits and dots, e.g. 0.1.1)")
    return raw


def ask(msg):
    try:
        return input(msg).strip()
    except EOFError:
        return ""


# Decide the new version name + build number.
new_name = cur_name
new_build = default_build

if len(sys.argv) > 1 and sys.argv[1].strip():
    arg = sys.argv[1].strip()
    if "+" in arg:
        name_part, _, build_part = arg.partition("+")
        new_name = parse_name(name_part)
        new_build = parse_build(build_part)
    else:
        new_build = parse_build(arg)   # build only, keep version name
elif sys.stdin.isatty():
    print(f"Current version: {cur_name}")
    raw_name = ask(f"Enter new version [press Enter to keep {cur_name}]: ")
    if raw_name:
        new_name = parse_name(raw_name)
    print(f"Current build number: {cur_build}")
    raw_build = ask(f"Enter new build number [press Enter for {default_build}]: ")
    new_build = default_build if raw_build == "" else parse_build(raw_build)
# else: non-interactive, no args → keep name, auto-increment build (defaults above)

if new_build <= cur_build:
    print(f"WARNING: build number {new_build} is not greater than current {cur_build}.", file=sys.stderr)
    print("         In-app updates and the Play Store both require a strictly increasing", file=sys.stderr)
    print("         build number — even when the version name changes. Updates won't trigger.", file=sys.stderr)

new_line = f"version: {new_name}+{new_build}"
new_text = text[:m.start()] + new_line + text[m.end():]
open(path, "w").write(new_text)

print(f"Bumped → {new_name}+{new_build}")
