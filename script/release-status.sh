#!/usr/bin/env bash
# Observe real chain state after deployment. A Forge broadcast simulation is not deployment evidence.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "release-status: $*" >&2; exit 1; }
[ "$#" = 3 ] || fail 'usage: release-status.sh <release.json> <rpc-url-or-alias> <destination>'
release=$1 rpc=$2 destination=$3
[[ "$destination" == deployments/* ]] && [[ "$destination" != *..* ]] || fail 'destination must be below deployments/'
./script/release/validate-manifest.sh "$release"
observed=$(cast block latest --rpc-url "$rpc" --json)
number=$(jq -r '.number' <<< "$observed")
if [[ "$number" == 0x* ]]; then number=$(cast to-dec "$number"); fi
hash=$(jq -r '.hash' <<< "$observed")
chain=$(cast chain-id --rpc-url "$rpc")
[[ "$destination" == "deployments/$chain/release-"* || "$destination" == deployments/fixtures/* ]] || fail 'destination must identify the observed chain'
mkdir -p "$(dirname "$destination")"
raw=deployments/.release-status.tmp.json
trap 'rm -f "$raw"' EXIT
FOUNDRY_PROFILE=ci forge script script/release/ObserveManifest.s.sol:ObserveManifest \
    --sig 'run(string,bytes32,string)' "$release" "$hash" "$raw" \
    --rpc-url "$rpc" --fork-block-number "$number" --non-interactive
# Detect a reorg or inconsistent endpoint rather than claiming the wrong block's state.
[ "$(cast block "$number" --rpc-url "$rpc" --json | jq -r '.hash')" = "$hash" ] || fail 'observed block changed; retry'
release_hash=$(jq -cS . "$release" | tr -d '\n' | cast keccak)
jq -S --arg hash "$release_hash" '. + {releaseManifestHash:$hash}' "$raw" > "$destination"
./script/release/validate-manifest.sh "$release" "$destination"
echo "release-status: observed chain $chain at block $number; verification remains unknown"
