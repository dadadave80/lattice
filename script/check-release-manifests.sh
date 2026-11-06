#!/usr/bin/env bash
# Rebuild each frozen manifest from its actual source commit, never from unrelated HEAD bytecode.
set -euo pipefail
cd "$(dirname "$0")/.."
mode=${1:-golden}
[ "$mode" = golden ] || [ "$mode" = --schema-only ] || { echo 'usage: check-release-manifests.sh [--schema-only]' >&2; exit 1; }
root=$(pwd)
temporary=
cleanup() { if [ -n "$temporary" ]; then git worktree remove --force --force "$temporary" >/dev/null; fi; }
trap cleanup EXIT
count=0
while IFS= read -r manifest; do
    jq -e 'has("chain") | not' "$manifest" >/dev/null || continue
    ./script/release/validate-manifest.sh "$manifest"
    jq -e '.publication == "release"' "$manifest" >/dev/null || { echo 'golden: keep synthetic fixtures under test/fixtures' >&2; exit 1; }
    count=$((count + 1))
    if [ "$mode" = golden ]; then
        commit=$(jq -r '.lattice.commit' "$manifest")
        git cat-file -e "$commit^{commit}"
        git merge-base --is-ancestor "$commit" HEAD || { echo "golden: freeze an already-merged source commit: $manifest" >&2; exit 1; }
        if [ "$(jq -r '.publication' "$manifest")" = release ]; then
            tag=$(jq -r '.lattice.tag' "$manifest")
            # A release PR may precede its tag. An existing tag must preserve the exact frozen inputs.
            target=HEAD
            if git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then target=$tag; fi
            git merge-base --is-ancestor "$commit" "$target"
            git diff --exit-code "$commit" "$target" -- src script test/helpers/ArachnidProxy.sol lib foundry.toml foundry.lock remappings.txt .github/actions/foundry-setup/action.yml
        fi
        temporary=$(mktemp -d "${TMPDIR:-/tmp}/lattice-golden.XXXXXX")
        git worktree add --detach "$temporary" "$commit" >/dev/null
        git -C "$temporary" submodule update --init --recursive
        # The frozen checkout owns its toolchain guard and inventory. Later metadata changes cannot redefine it.
        (cd "$temporary"; ./script/release-manifest.sh generate \
            "$(jq -r '.lattice.version' "$root/$manifest")" "$(jq -r '.lattice.tag' "$root/$manifest")" \
            "$(jq -r '.initialOwner' "$root/$manifest")" "$(jq -r '.publication' "$root/$manifest")" deployments/.golden.json)
        diff -u <(jq -S . "$manifest") <(jq -S . "$temporary/deployments/.golden.json")
        if [ -n "${RELEASE_ASSET_DIR:-}" ] && [ "$(jq -r '.publication' "$manifest")" = release ]; then
            mkdir -p "$RELEASE_ASSET_DIR"
            cp "$temporary/out/release-build-inputs.json" "$RELEASE_ASSET_DIR/build-inputs-$(jq -r '.lattice.version' "$manifest").json"
        fi
        cleanup
        temporary=
    fi
    while IFS= read -r status; do
        if jq -e --slurpfile release "$manifest" 'has("chain") and .lattice == $release[0].lattice' "$status" >/dev/null; then
            ./script/release/validate-manifest.sh "$manifest" "$status"
        fi
    done < <(find deployments -type f -name 'release-*.json' | sort)
done < <(find deployments -type f -name 'release-*.json' | sort)
if [ "$count" = 0 ]; then
    echo 'golden: no published schema-v1 release yet; source freeze and canonical owner remain publication prerequisites'
fi
# Reject orphan chain files rather than silently omitting validation.
while IFS= read -r status; do
    jq -e 'has("chain")' "$status" >/dev/null || continue
    matched=false
    while IFS= read -r manifest; do
        if jq -e --slurpfile status "$status" 'has("chain") == false and .lattice == $status[0].lattice' "$manifest" >/dev/null; then matched=true; fi
    done < <(find deployments -type f -name 'release-*.json' | sort)
    [ "$matched" = true ] || { echo "golden: orphan chain status $status" >&2; exit 1; }
done < <(find deployments -type f -name 'release-*.json' | sort)
./script/release/validate-manifest.sh test/fixtures/release-manifests/release.json test/fixtures/release-manifests/chain.json
if [ "$mode" = golden ]; then ./script/check-release-reproducibility.sh; fi
echo "golden: checked $count published release identities ($mode) and synthetic schema fixtures"
