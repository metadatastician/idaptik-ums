#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
set -euo pipefail

ums_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
meta_root=$(cd "$ums_root/.." && pwd)
idaptik_root=${IDAPTIK_ROOT:-"$meta_root/IDApTIK"}
slavia_root=${SLAVIA_ROOT:-"$meta_root/chronicles-of-slavia"}
if [[ -d "$meta_root/enaction-engine" ]]; then
  default_enaction_root="$meta_root/enaction-engine"
else
  default_enaction_root="$meta_root/affective-engine"
fi
enaction_root=${ENACTION_ROOT:-"$default_enaction_root"}

for root in "$ums_root" "$idaptik_root" "$slavia_root" "$enaction_root"; do
  test -d "$root/.git" -o -f "$root/.git" || {
    echo "missing sibling repository: $root" >&2
    exit 1
  }
done

fail_match() {
  local label=$1
  local pattern=$2
  shift 2
  if rg -n -i "$pattern" "$@" >/tmp/ums-architecture-match.txt 2>/dev/null; then
    echo "forbidden dependency: $label" >&2
    sed -n '1,40p' /tmp/ums-architecture-match.txt >&2
    return 1
  fi
}

fail_match "Enaction must not depend on UMS" \
  'ums-|universal.modding|idaptik-ums' \
  "$enaction_root/Cargo.toml" "$enaction_root/crates"/*/Cargo.toml
fail_match "IDApTIK runtime must not depend on UMS or Slavia" \
  'ums-|universal.modding|slavia[_-](core|profile)' \
  "$idaptik_root/Cargo.toml" "$idaptik_root/crates"/*/Cargo.toml
fail_match "IDApTIK source must not import Slavia profile types" \
  '(^|[[:space:]])(use|extern[[:space:]]+crate)[[:space:]].*slavia|slavia_profile' \
  "$idaptik_root/crates"
fail_match "Slavia runtime must not depend on UMS or IDApTIK" \
  'ums-|universal.modding|idaptik[_-](core|profile)' \
  "$slavia_root/engine/Cargo.toml" "$slavia_root/engine"/*/Cargo.toml
fail_match "Slavia source must not import IDApTIK profile types" \
  '(^|[[:space:]])(use|extern[[:space:]]+crate)[[:space:]].*idaptik|idaptik_profile' \
  "$slavia_root/engine"
fail_match "UMS Rust core must not link either game runtime" \
  '^[[:space:]]*(idaptik-core|slavia-core|chronicles-of-slavia)[[:space:]]*=' \
  "$ums_root/Cargo.toml" "$ums_root/crates"/*/Cargo.toml

test -f "$idaptik_root/contracts/idaptik/v1/contract.json"
test -f "$idaptik_root/contracts/idaptik/v1/package.schema.json"
test -f "$ums_root/profiles/idaptik/v1/ghost-lobby.ums.json"
test -f "$ums_root/profiles/slavia/v1/profile.json"

echo "architecture boundaries: dependency direction and profile isolation verified"
