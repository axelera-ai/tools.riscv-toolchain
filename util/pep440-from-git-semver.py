#!/usr/bin/env python3
"""Convert a semver-from-git.sh GIT_SEMVER_FROM_TAG value to a PEP 440 version.

semver-from-git.sh emits formats like:
  "0.5.4"                                            (exact tag)
  "0.5.4.<branch>+<commits>.<hash>"                  (ahead of tag)
  "0.5.4.<branch>+<commits>.<hash>.SNAPSHOT.<host>"  (dirty tree)

PEP 440 disallows arbitrary branch names in the public-version segment and
disallows hyphens in the local-version segment. So non-tag builds are mapped
to "<base>.dev<commits>+<local>" where <local> is the branch and hash with
non-alphanumerics collapsed to dots.

Usage:
  GIT_SEMVER_FROM_TAG=0.5.4.branch+4.deadbee python3 util/pep440-from-git-semver.py
"""

import os
import re
import sys


def convert(raw: str) -> str:
    raw = raw.lstrip("v")
    if re.fullmatch(r"[0-9]+(?:\.[0-9]+)*(?:[a-zA-Z][a-zA-Z0-9]*)?", raw):
        return raw
    m = re.match(r"^([0-9]+(?:\.[0-9]+)*)\.(.+?)\+([0-9]+)\.([^.]+)(.*)$", raw)
    if not m:
        raise SystemExit(f"Unrecognized GIT_SEMVER_FROM_TAG: {raw}")
    base, branch, commits, hash_, extra = m.groups()
    local = re.sub(r"[^a-zA-Z0-9]+", ".", f"{branch}.{hash_}{extra}").strip(".").lower()
    return f"{base}.dev{commits}+{local}"


if __name__ == "__main__":
    try:
        raw = os.environ["GIT_SEMVER_FROM_TAG"]
    except KeyError:
        sys.exit("GIT_SEMVER_FROM_TAG must be set in the environment")
    print(convert(raw))
