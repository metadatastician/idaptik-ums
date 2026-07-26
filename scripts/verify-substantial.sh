#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2025-2026 Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# Fail-closed substantial-change verification for Universal Modding Studio.
set -euo pipefail

cd "$(dirname "$0")/.."

git diff --check
cargo fmt --check
cargo test --workspace
./scripts/gen.sh --check

grep -q '^= Universal Modding Studio$' README.adoc
grep -q 'profileId.*idaptik' profiles/idaptik/profile.json
grep -q 'profileId.*chronicles-of-slavia' profiles/chronicles-of-slavia/profile.json

if rg -n 'github\.com/(metadatastician|hyperpolymath)/idaptik-ums' \
    -g '!target' -g '!.git'; then
    echo "error: stale repository URL remains" >&2
    exit 1
fi

echo "substantial verification passed"
