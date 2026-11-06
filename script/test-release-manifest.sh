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
# Isolated consumer-candidate fixture: old `jq ... || continue` silently accepted this malformed file.
fixture_gate=$temporary/candidate-gate
mkdir -p "$fixture_gate/script/release" "$fixture_gate/deployments"
cp script/check-release-manifests.sh "$fixture_gate/script/"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture_gate/script/release/validate-manifest.sh"
chmod +x "$fixture_gate/script/release/validate-manifest.sh"
bash "$fixture_gate/script/check-release-manifests.sh" --schema-only > "$temporary/candidate-baseline.log" 2>&1
if RELEASE_ASSET_DIR="$fixture_gate/out/release-assets" bash "$fixture_gate/script/check-release-manifests.sh" --schema-only > "$temporary/asset-boundary.log" 2>&1; then
    echo 'manifest gate accepted asset staging under its forge output' >&2; exit 1
fi
grep -q 'release asset staging must be outside the checkout' "$temporary/asset-boundary.log"
printf '{"schemaVersion":1,\n' > "$fixture_gate/deployments/release-broken.json"
if bash "$fixture_gate/script/check-release-manifests.sh" --schema-only > "$temporary/candidate-invalid.log" 2>&1; then
    echo 'manifest gate silently skipped malformed committed candidate' >&2; exit 1
fi
grep -q 'invalid JSON object candidate' "$temporary/candidate-invalid.log"
# An existing published tag cannot be relabelled with a later source tree (the v0.5.0 boundary).
fixture_repo=$temporary/tag-boundary
mkdir -p "$fixture_repo/script" "$fixture_repo/src"
cp script/release-manifest.sh "$fixture_repo/script/"
printf 'string constant VERSION = "99.0.0";\n' > "$fixture_repo/src/LatticeVersion.sol"
git -C "$fixture_repo" init -q
git -C "$fixture_repo" add .
git -C "$fixture_repo" -c user.name=Fixture -c user.email=fixture@example.test -c commit.gpgsign=false commit -qm source
git -C "$fixture_repo" -c tag.gpgSign=false tag v99.0.0
retained_commit=$(git -C "$fixture_repo" rev-parse HEAD)
git -C "$fixture_repo" update-ref refs/remotes/origin/dev "$retained_commit"
printf '// later source\n' >> "$fixture_repo/src/LatticeVersion.sol"
git -C "$fixture_repo" add .
git -C "$fixture_repo" -c user.name=Fixture -c user.email=fixture@example.test -c commit.gpgsign=false commit -qm later
feature_commit=$(git -C "$fixture_repo" rev-parse HEAD)
git -C "$fixture_repo" -c user.name=Fixture -c user.email=fixture@example.test -c commit.gpgsign=false commit --allow-empty -qm feature-child
git -C "$fixture_repo" merge-base --is-ancestor "$feature_commit" HEAD
./script/release/source-boundary.sh "$retained_commit" "$fixture_repo"
if ./script/release/source-boundary.sh "$feature_commit" "$fixture_repo" > "$temporary/source-boundary.log" 2>&1; then
    echo 'source boundary accepted an unmerged feature ancestor' >&2; exit 1
fi
grep -q 'already-merged commit retained by origin/dev or origin/main' "$temporary/source-boundary.log"
if bash "$fixture_repo/script/release-manifest.sh" generate 99.0.0 v99.0.0 0x000000000000000000000000000000000000bEEF release deployments/release-99.0.0.json > "$temporary/tag-boundary.log" 2>&1; then
    echo 'manifest fixture accepted a historical tag with different build inputs' >&2; exit 1
fi
grep -q 'existing tag has different build inputs' "$temporary/tag-boundary.log"
echo 'manifest fixtures: 20 invalid mutations, malformed committed candidate and mismatched historical tag, unmerged source and unsafe asset staging rejected'
