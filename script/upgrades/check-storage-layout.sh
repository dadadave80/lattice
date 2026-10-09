#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check-storage-layout.sh
#
# Lattice's ERC-7201 storage-layout guard: the storage-safety Action's checker
# (.github/actions/storage-layout/check-storage-layout.sh) run with Lattice's probe, baseline and
# resets file under the `ci` profile. See that file for how the check works.
#
# USAGE
#   script/upgrades/check-storage-layout.sh                          # drift vs the committed baseline
#   script/upgrades/check-storage-layout.sh --baseline-ref origin/dev # also append-only vs a trusted ref
#   script/upgrades/check-storage-layout.sh --update                 # regenerate the baseline
# ---------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec "${REPO_ROOT}/.github/actions/storage-layout/check-storage-layout.sh" \
    --root "${REPO_ROOT}" \
    --src src \
    --profile ci \
    --probe script/upgrades/StorageLayoutProbe.sol:StorageLayoutProbe \
    --baseline script/upgrades/storage-layout.baseline \
    --resets script/upgrades/storage-layout.resets \
    "$@"
