#!/usr/bin/env bash
# Native schema + cross-file status checks. Forge additionally checks CREATE2 and fresh artifact identities.
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "manifest: $*" >&2; exit 1; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || fail 'usage: validate-manifest.sh <release.json> [chain.json]'
json_object() {
    jq -e -s 'length == 1 and (.[0] | type == "object")' "$1" >/dev/null || fail "invalid JSON object: $1"
}
release=$1
json_object "$release"
jq -e --slurpfile schema deployments/schema/release.schema.json -f script/release/validate-schema.jq "$release" >/dev/null || fail "invalid release schema: $release"
jq -e '
  .initialOwner != "0x0000000000000000000000000000000000000000" and
  .lattice.version != "0.0.0" and
  (.lattice.version | split(".") | map(tonumber) | .[0] < 65536 and .[1] < 16777216 and .[2] < 16777216) and
  (.publication != "fixture" or (.lattice.tag | startswith("fixture/"))) and
  (.publication != "release" or .lattice.tag == ("v" + .lattice.version)) and
  ([.contracts[].name] | unique | length) == (.contracts | length) and
  ([.contracts[].address | ascii_downcase] | unique | length) == (.contracts | length) and
  .contracts[0].kind == "registry" and .contracts[0].name == "LatticeRegistry" and
  .contracts[1].kind == "factory" and .contracts[1].name == "LatticeFactory" and
  ([.contracts[] | select(.kind == "registry")] | length) == 1 and
  ([.contracts[] | select(.kind == "registry" and .name == "LatticeRegistry")] | length) == 1 and
  ([.contracts[] | select(.kind == "factory")] | length) == 1 and
  ([.contracts[] | select(.kind == "factory" and .name == "LatticeFactory")] | length) == 1 and
  all(.contracts[]; (.codehash != ("0x" + ("0" * 64))) and (.initCodeHash != ("0x" + ("0" * 64))))
' "$release" >/dev/null || fail 'inconsistent release identity'
deployer=$(jq -r '.deployer.address | ascii_downcase' "$release")
version=$(jq -r '.lattice.version' "$release")
owner=$(jq -r '.initialOwner' "$release")
registry=$(jq -r '.contracts[] | select(.kind == "registry") | .address' "$release")
while IFS=$'\t' read -r name kind at salt init_hash args name_hash selectors_hash; do
    digest=$(cast keccak "0xff${deployer#0x}${salt#0x}${init_hash#0x}")
    [ "$at" = "0x${digest:26}" ] || fail "$name CREATE2 prediction differs"
    expected_name_hash="0x$(printf '%064d' 0)"
    case "$kind" in
        registry) expected_salt=$(cast keccak 'lattice.LatticeRegistry'); expected_args=$(cast abi-encode 'constructor(address)' "$owner") ;;
        factory) expected_salt=$(cast keccak 'lattice.LatticeFactory'); expected_args=$(cast abi-encode 'constructor(address,address,address)' "$registry" 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000) ;;
        library) expected_salt="0x$(printf '%064d' 0)"; expected_args=0x ;;
        facet|init) expected_salt=$(cast keccak "lattice.$name.$version"); expected_args=0x ;;
    esac
    if [ "$kind" = facet ]; then
        expected_name_hash=$(cast keccak "lattice.$name")
        [ "$selectors_hash" != "0x$(printf '%064d' 0)" ] || fail "$name missing selector commitment"
    else
        [ "$selectors_hash" = "0x$(printf '%064d' 0)" ] || fail "$name is not a facet"
    fi
    [ "$salt" = "$expected_salt" ] && [ "$args" = "$expected_args" ] && [ "$name_hash" = "$expected_name_hash" ] || fail "$name salt, constructor arguments or name hash differ"
done < <(jq -r '.contracts[] | [.name,.kind,(.address|ascii_downcase),.salt,.initCodeHash,(.constructorArgs|ascii_downcase),.nameHash,.selectorsHash] | @tsv' "$release")
[ "$#" = 2 ] || exit 0
chain=$2
json_object "$chain"
jq -e --slurpfile schema deployments/schema/chain.schema.json -f script/release/validate-schema.jq "$chain" >/dev/null || fail "invalid chain schema: $chain"
release_hash=$(jq -cS . "$release" | tr -d '\n' | cast keccak)
jq -e --slurpfile release "$release" --arg hash "$release_hash" '
  $release[0] as $r |
  .lattice == $r.lattice and .publication == $r.publication and
  .releaseManifestHash == $hash and .chain.blockHash != ("0x" + ("0" * 64)) and
  ([.contracts[] | {name,address:(.address|ascii_downcase)}] | sort_by(.name)) ==
    ([$r.contracts[] | {name,address:(.address|ascii_downcase)}] | sort_by(.name)) and
  all(.contracts[]; . as $c |
    (.verified == (.verifier != null)) and
    (if .deployed == null then (.codeMatches == false and .verified == false and .registered == false and .latest == false) else true end) and
    (if .verified or .registered or .latest then .codeMatches else true end) and
    (if .latest then .registered else true end) and
    (if .registered then any($r.contracts[]; .name == $c.name and .kind == "facet") else true end))
' "$chain" >/dev/null || fail 'chain status contradicts release identity or verification evidence'
