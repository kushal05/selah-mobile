#!/usr/bin/env bash
# Run a Python 3 script with whatever interpreter this machine actually has.
#
#   bash scripts/python.sh scripts/bump_version.py 22
#   bash scripts/python.sh - arg1 arg2 <<'PY' ... PY
#
# `python3` is the correct name on macOS and Linux and is routinely ABSENT on
# Windows: the python.org installer provides python.exe and the py launcher,
# not python3.exe, and Git Bash adds no alias. Hardcoding `python3` therefore
# works on exactly one of the two platforms this repo is built from — which is
# why the tooling here reaches for it in some places and avoids it in others.
#
# Resolution order, first hit wins:
#   python3   macOS, Linux, and Windows installs that provide the alias
#   python    Windows python.org installs — verified to be 3.x, because on
#             older systems `python` is still 2.x and would fail obscurely
#             partway through instead of here
#   py -3     the Windows launcher, when neither name is on PATH
set -euo pipefail

if command -v python3 >/dev/null 2>&1; then
  exec python3 "$@"
fi

if command -v python >/dev/null 2>&1 \
   && python -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
  exec python "$@"
fi

if command -v py >/dev/null 2>&1; then
  exec py -3 "$@"
fi

echo "ERROR: no Python 3 interpreter found (tried python3, python, py -3)." >&2
echo "       Install Python 3 and make sure it is on PATH." >&2
exit 1
