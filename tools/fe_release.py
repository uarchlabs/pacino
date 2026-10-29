#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Jeff Nye, uarchlabs.com
# SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com>
#
# fe_release.py -- the frontend release tags (DOC-008,
# planning/showcase/showcase_release_decisions.md SR-1, SR-4)
#
# A release tag is fe-<major>.<minor>.<patch>, each field a decimal number
# with no leading zero (SR-1). The latest tag is the one with the highest
# version, compared field by field as numbers (SR-4). Any other name is
# not a release tag and is ignored.
#
# Read by tools/publish_waves.py (the tag gate) and by the docs build in
# .github/workflows/docs.yml (the tag the Showcase pages come from).
# Nothing here runs git.
#
# USAGE:
#
#   git tag -l 'fe-*' | tools/fe_release.py latest
#       prints the latest release tag of the names on stdin, one name per
#       line, or nothing when there is none; exits 0 either way
#   tools/fe_release.py check <name>
#       exits 0 when <name> is a release tag, 1 when it is not

import re
import sys

# [0-9], not \d: \d also matches non-ASCII digits.
TAG_RE = re.compile(r"fe-(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")


def parse_tag(name):
    """The (major, minor, patch) of a release tag, or None for any other
    name."""
    m = TAG_RE.fullmatch(name)
    if not m:
        return None
    return tuple(int(f) for f in m.groups())


def latest_tag(names):
    """The release tag of names with the highest version (SR-4), or None
    when names holds none; None selects the branch."""
    tags = [(parse_tag(n), n) for n in names]
    tags = [t for t in tags if t[0] is not None]
    if not tags:
        return None
    return max(tags)[1]


def main(argv):
    if len(argv) == 2 and argv[1] == "latest":
        tag = latest_tag(sys.stdin.read().split())
        if tag:
            print(tag)
        return 0
    if len(argv) == 3 and argv[1] == "check":
        return 0 if parse_tag(argv[2]) else 1
    print("usage: fe_release.py latest < names\n"
          "       fe_release.py check <name>", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
