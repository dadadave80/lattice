#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "${ROOT}/.github/actions/storage-layout/check.py" \
  --working-directory "${ROOT}" \
  --probe script/upgrades/StorageLayoutProbe.sol:StorageLayoutProbe \
  --manifest script/upgrades/storage-layout.manifest.json \
  --baseline script/upgrades/storage-layout.baseline "$@"
