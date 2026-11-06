#!/usr/bin/env bash
# Build-bound constants for the one reviewed immutable ERC-3643 token profile.
set -euo pipefail
MODE=${1:---check}
PROFILE_ROOT=${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
[[ "$MODE" == --check || "$MODE" == --update ]] || { echo 'Usage: erc3643-profile.sh [--check|--update] [root]' >&2; exit 2; }
cd "$PROFILE_ROOT"
CONFIG=script/config/erc3643-profile.json
OUTPUT=src/tokens/ERC3643/libraries/ERC3643Profile.sol
PROFILE_TMP=$(mktemp -d)
trap 'rm -rf "$PROFILE_TMP"' EXIT
fail() { echo "erc3643-profile: $*" >&2; exit 1; }
for tool in forge cast jq; do command -v "$tool" >/dev/null || fail "missing $tool"; done
jq -e '
  .schemaVersion == 1 and .host.name == "Lattice" and .host.artifact == "src/Lattice.sol:Lattice"
  and (.facets | length > 0 and length < 63)
  and ([.facets[].name] | length == (unique | length))
  and ([.facets[].artifact] | length == (unique | length))
  and ([.facets[] | select(.optional)] | length == 1 and .[0].name == "ERC20TemporaryApproval")
  and all(.facets[]; (.name | test("^[A-Za-z][A-Za-z0-9_]*$")) and (.artifact | test("^[A-Za-z0-9_./-]+:[A-Za-z][A-Za-z0-9_]*$")) and (.optional | type == "boolean"))
' "$CONFIG" >/dev/null || fail 'invalid reviewed profile configuration'
# Cached builds are safe; source changes must be compiled before comparing hashes.
if ! FOUNDRY_PROFILE=ci forge build src lib/diamond-lib/src --locked --skip test script >"$PROFILE_TMP/build.log" 2>&1; then
  tail -n 100 "$PROFILE_TMP/build.log" >&2
  fail 'canonical source build failed'
fi

artifact_path() {
  local source=${1%:*} name=${1##*:}
  printf 'out/%s/%s.json\n' "${source##*/}" "$name"
}
validate_artifact() {
  local file=$1
  [[ -f "$file" ]] || fail "missing artifact $file"
  jq -e '
    (.deployedBytecode.object | test("^0x[0-9a-fA-F]+$"))
    and ((.deployedBytecode.linkReferences // {}) | length == 0)
    and ((.deployedBytecode.immutableReferences // .immutableReferences // {}) | length == 0)
    and (.rawMetadata | fromjson | .compiler.version | startswith("0.8.36+"))
    and (.rawMetadata | fromjson | .settings | .evmVersion == "cancun" and .optimizer.enabled == true and .optimizer.runs == 1000000 and (.viaIR // false) == false and .metadata.bytecodeHash == "ipfs")
  ' "$file" >/dev/null || fail "noncanonical, immutable, linked or empty artifact $file"
}
host_artifact=$(artifact_path "$(jq -r '.host.artifact' "$CONFIG")")
validate_artifact "$host_artifact"
host_hash=$(cast keccak "$(jq -r '.deployedBytecode.object' "$host_artifact")")
jq -cn --arg hash "$host_hash" --slurpfile config "$CONFIG" '{schemaVersion:1,compiler:"0.8.36",evmVersion:"cancun",optimizerRuns:1000000,viaIR:false,bytecodeHash:"ipfs",host:($config[0].host+{codeHash:$hash})}' > "$PROFILE_TMP/input.json"
: > "$PROFILE_TMP/facets.jsonl"
index=0
required=0
temporary_index=-1
while IFS=$'\t' read -r name artifact optional; do
  file=$(artifact_path "$artifact")
  validate_artifact "$file"
  jq -e '.rawMetadata | fromjson | .sources |
    (has("src/tokens/ERC3643/libraries/ERC3643Profile.sol") or
     has("src/tokens/ERC3643/libraries/ERC3643ProfileLib.sol") or
     has("src/tokens/ERC3643/ERC3643Init.sol")) | not' "$file" >/dev/null \
    || fail "facet imports admission data/initializer: $name"
  hash=$(cast keccak "$(jq -r '.deployedBytecode.object' "$file")")
  selectors=$(jq -r '[.methodIdentifiers | to_entries[] | select(.key != "exportSelectors()") ] | sort_by(.key) | map(.value) | join("")' "$file")
  [[ "$selectors" =~ ^([0-9a-f]{8})+$ ]] || fail "invalid/empty selectors $name"
  jq -cn --arg name "$name" --arg artifact "$artifact" --arg hash "$hash" --arg selectors "$selectors" --argjson optional "$optional" --argjson index "$index" '{name:$name,artifact:$artifact,codeHash:$hash,selectors:$selectors,optional:$optional,index:$index}' >> "$PROFILE_TMP/facets.jsonl"
  if [[ "$optional" == true ]]; then temporary_index=$index; else required=$((required | (1 << index))); fi
  index=$((index + 1))
done < <(jq -r '.facets[] | [.name,.artifact,.optional] | @tsv' "$CONFIG")
[[ "$temporary_index" -ge 0 ]] || fail 'missing temporary-approval alternative'
jq -se '[.[].codeHash] | length == (unique | length)' "$PROFILE_TMP/facets.jsonl" >/dev/null || fail 'duplicate facet runtime hash'
jq --slurpfile facets "$PROFILE_TMP/facets.jsonl" '.+{facets:$facets}' "$PROFILE_TMP/input.json" | jq -cS . > "$PROFILE_TMP/canonical.json"
input_hash=$(cast keccak "$(cat "$PROFILE_TMP/canonical.json")")
{
  cat <<'HEADER'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ERC3643Profile
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Generated admission data for the reviewed immutable token profile.
/// @dev Only initialization code imports this file. Regenerate with script/erc3643-profile.sh --update.
library ERC3643Profile {
HEADER
  printf '    bytes32 internal constant HOST_CODEHASH = %s;\n' "$host_hash"
  printf '    bytes32 internal constant INPUT_HASH = %s;\n' "$input_hash"
  printf '    uint256 internal constant REQUIRED_MASK = %s;\n' "$required"
  printf '    uint256 internal constant TEMPORARY_INDEX = %s;\n' "$temporary_index"
  printf '    function expected(bytes32 hash) internal pure returns (uint256, bytes memory) {\n'
  while IFS=$'\t' read -r name hash selectors facet_index; do
    printf '        // %s\n' "$name"
    printf '        if (hash == %s) return (%s, hex"%s");\n' "$hash" "$facet_index" "$selectors"
  done < <(jq -r '[.name,.codeHash,.selectors,.index] | @tsv' "$PROFILE_TMP/facets.jsonl")
  printf '        return (type(uint256).max, hex"");\n    }\n}\n'
} > "$PROFILE_TMP/ERC3643Profile.sol"
forge fmt "$PROFILE_TMP/ERC3643Profile.sol" >/dev/null 2>&1
if [[ "$MODE" == --update ]]; then
  cp "$PROFILE_TMP/ERC3643Profile.sol" "$OUTPUT"
  echo "erc3643-profile: updated host + $index facet fingerprints ($input_hash)"
else
  cmp -s "$PROFILE_TMP/ERC3643Profile.sol" "$OUTPUT" || { diff -u "$OUTPUT" "$PROFILE_TMP/ERC3643Profile.sol" || true; fail 'approved build/profile drift; review and regenerate'; }
  echo "erc3643-profile: approved host/facet hashes and exact routes match ($input_hash)"
fi
