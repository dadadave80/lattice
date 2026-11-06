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
jq -e '
  if has("accounts") then
    (.accounts | length) as $count |
    (.publication == "fixture" or $count == 6) and
    ([.accounts[].initializer] | unique | length) == $count and
    ([.accounts[].factory] | unique | length) == $count and
    ([.accounts[] | [.entryPointVersion,.proxyKind]] | unique | length) == $count and
    ([.contracts[] | select(.kind == "account-init" or .kind == "account-factory")] | length) == (2 * $count)
  else all(.contracts[]; .kind != "account-init" and .kind != "account-factory") end
' "$release" >/dev/null || fail 'inconsistent account release bindings'
# The per-binding constructors below are definitive; this metadata must identify each listed pair once.
if jq -e 'has("accounts")' "$release" >/dev/null; then
    jq -e '. as $r | all(.accounts[]; . as $a |
      any($r.contracts[]; .name == $a.initializer and .kind == "account-init") and
      any($r.contracts[]; .name == $a.factory and .kind == "account-factory"))' "$release" >/dev/null || fail 'account binding references a missing identity'
fi
deployer=$(jq -r '.deployer.address | ascii_downcase' "$release")
version=$(jq -r '.lattice.version' "$release")
owner=$(jq -r '.initialOwner' "$release")
registry=$(jq -r '.contracts[] | select(.kind == "registry") | .address' "$release")
account_args() {
    local record_name=$1 record_kind=$2 record_args=$3 record_artifact=$4
    local binding ep ep_version proxy suffix prefix directory expected_artifact initializer decoded tuples blueprint_hash
    binding=$(jq -cer --arg name "$record_name" --arg kind "$record_kind" '.accounts[] | select(if $kind == "account-init" then .initializer == $name else .factory == $name end)' "$release") || fail "$record_name has no account binding"
    ep=$(jq -r '.entryPoint | ascii_downcase' <<< "$binding")
    ep_version=$(jq -r '.entryPointVersion' <<< "$binding")
    proxy=$(jq -r '.proxyKind' <<< "$binding")
    case "$ep_version" in
        0.7) [ "$ep" = 0x0000000071727de22e5e9d8baf0edac6f37da032 ] || fail 'wrong v0.7 EntryPoint'; suffix=V07 ;;
        0.8) [ "$ep" = 0x4337084d9e255ff0702461cf8895ce9e3b5ff108 ] || fail 'wrong v0.8 EntryPoint'; suffix=V08 ;;
        0.9) [ "$ep" = 0x433709009b8330fda32311df1c2afa402ed8d009 ] || fail 'wrong v0.9 EntryPoint'; suffix=V09 ;;
    esac
    case "$proxy" in
        AccountDiamond) prefix=Account; directory=erc7579 ;;
        ModularAccount6900) prefix=Account; directory=erc6900 ;;
    esac
    if [ "$record_kind" = account-init ]; then prefix=${prefix}Init; else prefix=${prefix}Factory; fi
    if [ "$proxy" = ModularAccount6900 ]; then prefix=${prefix}6900; fi
    [ "$record_name" = "$prefix$suffix" ] || fail "$record_name account label differs"
    expected_artifact="src/accounts/$directory/$prefix.sol:$prefix"
    [ "$record_artifact" = "$expected_artifact" ] || fail "$record_name account artifact differs"
    if [ "$record_kind" = account-init ]; then
        cast abi-encode 'constructor(address)' "$ep"
        return
    fi
    initializer=$(jq -r --arg name "$(jq -r '.initializer' <<< "$binding")" '.contracts[] | select(.name == $name) | .address' "$release")
    decoded=$(cast abi-decode --json 'f()((address,uint8,bytes4[])[],address)' "$record_args") || fail "$record_name malformed factory constructor"
    jq -e --arg init "$initializer" '.success and (.data[1] | ascii_downcase) == ($init | ascii_downcase) and
      (.data[0] | length > 0) and all(.data[0][]; .[1] == 0 and (.[2] | length > 0)) and
      ([.data[0][] | .[0] | ascii_downcase] | length == (unique | length)) and
      ([.data[0][] | .[2][]] | length == (unique | length))' <<< "$decoded" >/dev/null || fail "$record_name constructor init or cuts differ"
    while IFS=$'\t' read -r facet packed; do
        local expected_selectors actual_selectors
        expected_selectors=$(jq -r --arg facet "$facet" '.contracts[] | select(.kind == "facet" and (.address | ascii_downcase) == ($facet | ascii_downcase)) | .selectorsHash' "$release")
        [ -n "$expected_selectors" ] || fail "$record_name blueprint uses an unlisted facet"
        actual_selectors=$(cast keccak "$packed")
        [ "$actual_selectors" = "$expected_selectors" ] || fail "$record_name blueprint selector commitment differs"
    done < <(jq -r '.data[0][] | [.[0], ("0x" + (.[2] | map(ltrimstr("0x")) | join("")))] | @tsv' <<< "$decoded")
    tuples=$(jq -r '.data[0] | "[" + (map("(" + .[0] + "," + (.[1]|tostring) + ",[" + (.[2]|join(",")) + "])") | join(",")) + "]"' <<< "$decoded")
    blueprint_hash=$(cast abi-encode 'blueprint((address,uint8,bytes4[])[])' "$tuples" | cast keccak)
    [ "$blueprint_hash" = "$(jq -r '.blueprintHash' <<< "$binding")" ] || fail "$record_name blueprint hash differs"
    cast abi-encode 'constructor((address,uint8,bytes4[])[],address)' "$tuples" "$initializer"
}
while IFS=$'\t' read -r name kind at salt init_hash args name_hash selectors_hash artifact selectors; do
    digest=$(cast keccak "0xff${deployer#0x}${salt#0x}${init_hash#0x}")
    [ "$at" = "0x${digest:26}" ] || fail "$name CREATE2 prediction differs"
    expected_name_hash="0x$(printf '%064d' 0)"
    case "$kind" in
        registry) expected_salt=$(cast keccak 'lattice.LatticeRegistry'); expected_args=$(cast abi-encode 'constructor(address)' "$owner") ;;
        factory) expected_salt=$(cast keccak 'lattice.LatticeFactory'); expected_args=$(cast abi-encode 'constructor(address,address,address)' "$registry" 0x0000000000000000000000000000000000000000 0x0000000000000000000000000000000000000000) ;;
        library) expected_salt="0x$(printf '%064d' 0)"; expected_args=0x ;;
        facet|init) expected_salt=$(cast keccak "lattice.$name.$version"); expected_args=0x ;;
        account-init|account-factory) expected_salt=$(cast keccak "lattice.$name.$version"); expected_args=$(account_args "$name" "$kind" "$args" "$artifact") ;;
    esac
    if [ "$kind" = facet ]; then
        expected_name_hash=$(cast keccak "lattice.$name")
        [ "$selectors_hash" != "0x$(printf '%064d' 0)" ] || fail "$name missing selector commitment"
        [ "$selectors_hash" = "$(cast keccak "$selectors")" ] || fail "$name selector bytes differ from commitment"
        jq -e --arg name "$name" '
            .contracts[] | select(.name==$name) | .selectors | ascii_downcase | .[2:] | [scan(".{8}")] |
            length>0 and (length == (unique | length))
        ' "$release" >/dev/null || fail "$name empty or duplicate selectors"
    else
        [ "$selectors_hash" = "0x$(printf '%064d' 0)" ] || fail "$name is not a facet"
        [ "$selectors" = 0x ] || fail "$name is not a facet but exports selectors"
    fi
    [ "$salt" = "$expected_salt" ] && [ "$args" = "$expected_args" ] && [ "$name_hash" = "$expected_name_hash" ] || fail "$name salt, constructor arguments or name hash differ"
done < <(jq -r '.contracts[] | [.name,.kind,(.address|ascii_downcase),.salt,.initCodeHash,(.constructorArgs|ascii_downcase),.nameHash,.selectorsHash,.artifact,(.selectors|ascii_downcase)] | @tsv' "$release")
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
    (if has("verificationId") then .verified==false and .codeMatches and .deployed!=null else true end) and
    (if .deployed == null then (.codeMatches == false and .verified == false and .registered == false and .latest == false) else true end) and
    (if .verified or .registered or .latest then .codeMatches else true end) and
    (if .latest then .registered else true end) and
    (if .registered then any($r.contracts[]; .name == $c.name and .kind == "facet") else true end))
' "$chain" >/dev/null || fail 'chain status contradicts release identity or verification evidence'
