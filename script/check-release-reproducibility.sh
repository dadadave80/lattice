#!/usr/bin/env bash
# Two clean builds of the current committed checkout: all shared addresses, hashes and compiler inputs.
set -euo pipefail
cd "$(dirname "$0")/.."
first=deployments/.reproducibility-first.json
second=deployments/.reproducibility-second.json
trap 'rm -f "$first" "$second"' EXIT
for destination in "$first" "$second"; do
    ./script/release-manifest.sh generate 99.0.0 fixture/reproducibility \
        0x000000000000000000000000000000000000bEEF fixture "$destination"
done
diff -u <(jq -S . "$first") <(jq -S . "$second")
echo 'release-reproducibility: two clean builds reproduce every shared identity, proxy hash and compiler input'
