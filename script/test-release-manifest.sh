#!/usr/bin/env bash
# Mutations of real generated identities/status, never a parallel manual contract catalog.
set -euo pipefail
cd "$(dirname "$0")/.."
release=${1:-test/fixtures/release-manifests/release.json}
chain=${2:-test/fixtures/release-manifests/chain.json}
temporary=$(mktemp -d "${TMPDIR:-/tmp}/lattice-manifest-fixtures.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
if [ "${3:-}" = --hash-local-fixture ]; then
    # Four generated representatives exercise the schema; the Forge test separately asserts the full catalog.
    jq '.contracts = ([.contracts[] | select(.kind == "registry")][0:1] + [.contracts[] | select(.kind == "factory")][0:1] + [.contracts[] | select(.kind == "facet")][0:1] + [.contracts[] | select(.kind == "init")][0:1])' "$release" > "$temporary/baseline-release.json"
    release=$temporary/baseline-release.json
    jq --slurpfile release "$release" '.contracts |= map(select(.name as $name | any($release[0].contracts[]; .name == $name)))' "$chain" > "$temporary/filtered-chain.json"
    chain=$temporary/filtered-chain.json
    release_hash=$(jq -cS . "$release" | tr -d '\n' | cast keccak)
    jq --arg hash "$release_hash" '. + {releaseManifestHash:$hash}' "$chain" > "$temporary/baseline-chain.json"
    chain=$temporary/baseline-chain.json
fi
check() { ./script/release/validate-manifest.sh "$@" >/dev/null 2>&1; }
check "$release" "$chain" || { echo 'manifest fixture baseline failed' >&2; exit 1; }
reject_release() {
    jq "$2" "$release" > "$temporary/release.json"
    if check "$temporary/release.json"; then echo "manifest fixture accepted: $1" >&2; exit 1; fi
}
reject_chain() {
    jq "$2" "$chain" > "$temporary/chain.json"
    if check "$release" "$temporary/chain.json"; then echo "manifest fixture accepted: $1" >&2; exit 1; fi
}
reject_release unknown-field '.invented = true'
reject_release missing-creation-hash 'del(.contracts[2].initCodeHash)'
reject_release wrong-address '.contracts[2].address = "0x0000000000000000000000000000000000000001"'
reject_release wrong-initcode '.contracts[2].initCodeHash = ("0x" + ("1" * 64))'
reject_release wrong-salt '.contracts[2].salt = ("0x" + ("1" * 64))'
reject_release wrong-name-hash '.contracts[2].nameHash = ("0x" + ("1" * 64))'
reject_release wrong-owner '.initialOwner = "0x000000000000000000000000000000000000CAFE"'
reject_release absent-owner '.initialOwner = "0x0000000000000000000000000000000000000000"'
reject_release missing-constructor '.contracts[0].constructorArgs = "0x"'
reject_release duplicate-name '.contracts[2].name = .contracts[3].name'
reject_release wrong-compiler '.compiler.evmVersion = "osaka"'
reject_release fake-release-label '.publication = "release"'
reject_chain unknown-field '.chain.invented = true'
reject_chain wrong-source '.lattice.commit = ("2" * 40)'
reject_chain wrong-hash '.releaseManifestHash = ("0x" + ("1" * 64))'
reject_chain missing-contract '.contracts |= .[1:]'
reject_chain invented-contract '.contracts[2].address = "0x0000000000000000000000000000000000000001"'
reject_chain unobserved-verification '.contracts[2] += {deployed:null,verified:true,verifier:"sourcify"}'
reject_chain verifier-without-verification '.contracts[2] += {verified:false,verifier:"sourcify"}'
reject_chain latest-without-registration '.contracts[2] += {latest:true,registered:false}'
echo 'manifest fixtures: 20 invalid mutations rejected'
