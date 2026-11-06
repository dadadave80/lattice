#!/usr/bin/env bash
# Offline release identities and compiler-input witnesses. No RPC and no broadcast.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "release-manifest: $*" >&2; exit 1; }
[ "$#" = 6 ] && [ "$1" = generate ] || fail 'usage: release-manifest.sh generate <version> <tag> <initial-owner> <fixture|release> <destination>'
version=$2 tag=$3 owner=$4 publication=$5 destination=$6
[[ "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail 'version must be canonical semver'
[[ "$owner" =~ ^0x[0-9a-fA-F]{40}$ ]] && [[ ! "$owner" =~ ^0x0{40}$ ]] || fail 'explicit nonzero initial owner required'
case "$publication:$tag" in fixture:fixture/*) ;; release:v"$version") ;; *) fail 'use fixture/<name> or the exact release tag v<version>' ;; esac
[[ "$destination" == deployments/* ]] && [[ "$destination" != *..* ]] || fail 'destination must be below deployments/'
inputs=(src script test/helpers/ArachnidProxy.sol lib foundry.toml foundry.lock remappings.txt .github/actions/foundry-setup/action.yml)
if [ "$publication" = release ]; then
    grep -Fq "VERSION = \"$version\"" src/LatticeVersion.sol || fail 'release version differs from LatticeVersion'
    if git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
        git diff --quiet "$tag" HEAD -- "${inputs[@]}" || fail 'existing tag has different build inputs; use its historical source or explicit fixture mode'
    fi
    ./script/release/source-boundary.sh "$(git rev-parse HEAD)"
fi
# The source witness is an existing commit. A later manifest-only commit may contain its output.
git diff --quiet HEAD -- "${inputs[@]}" || fail 'commit build-input changes before freezing a manifest'
[ -z "$(git ls-files --others --exclude-standard -- "${inputs[@]}")" ] || fail 'commit untracked build inputs before freezing a manifest'
./script/check-release-build.sh
source_commit=$(git rev-parse HEAD)
export FOUNDRY_PROFILE=ci
forge clean
forge build --locked --build-info --skip test
# This re-export has no local definition; force its dynamic inventory artifact on filtered builds.
forge build --locked --build-info lib/diamond-lib/src/facets/OwnableFacet.sol
mkdir -p "$(dirname "$destination")"
snapshot=deployments/.release-identities.tmp.json
trap 'rm -f "$snapshot"' EXIT
forge script script/release/GenerateManifest.s.sol:GenerateManifest \
    --sig 'generate(string,address,string)' "$version" "$owner" "$snapshot" --non-interactive
./script/release/package-build-info.sh out/release-build-inputs.json
input_hash=$(tr -d '\n' < out/release-build-inputs.json | cast keccak)
foundry=$(awk '$1 == "version:" {print $2}' .github/actions/foundry-setup/action.yml)
jq -S --arg version "$version" --arg tag "$tag" --arg commit "$source_commit" \
    --arg owner "$owner" --arg publication "$publication" --arg foundry "$foundry" --arg inputHash "$input_hash" '
    . + {schemaVersion:1, publication:$publication,
      lattice:{version:$version,tag:$tag,commit:$commit},initialOwner:$owner,
      deployer:{kind:"arachnid",address:"0x4e59b44847b379578588920cA78FbF26c0B4956C",librarySalt:("0x"+("0"*64))},
      compiler:{foundry:$foundry,solc:"0.8.36",evmVersion:"cancun",optimizerRuns:1000000,viaIR:false,bytecodeHash:"ipfs",libraries:{},inputHash:$inputHash}}
' "$snapshot" > "$destination"
./script/release/validate-manifest.sh "$destination"
echo "release-manifest: wrote $destination (source $source_commit, $publication evidence)"
