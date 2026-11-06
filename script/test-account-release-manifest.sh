#!/usr/bin/env bash
# Account mutations derive from the actual generated constructor identities, not a copied cut catalog.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" = 1 ] || { echo 'usage: test-account-release-manifest.sh <generated-fixture-release.json>' >&2; exit 1; }
source_manifest=$1
temporary=$(mktemp -d "${TMPDIR:-/tmp}/lattice-account-manifest.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
factory_name=$(jq -r '.accounts[0].factory' "$source_manifest")
initializer_name=$(jq -r '.accounts[0].initializer' "$source_manifest")
args=$(jq -r --arg name "$factory_name" '.contracts[] | select(.name == $name) | .constructorArgs' "$source_manifest")
decoded=$(cast abi-decode --json 'f()((address,uint8,bytes4[])[],address)' "$args")
facet_addresses=$(jq -c '.data[0] | map(.[0] | ascii_downcase)' <<< "$decoded")
# Keep one real pair plus exactly its referenced facets and the two core identity records. This is fixture
# evidence, explicitly not a complete release; current release publication still requires all six pairs.
jq --arg factory "$factory_name" --arg init "$initializer_name" --argjson facets "$facet_addresses" '
  .publication = "fixture" | .lattice.tag = "fixture/account-manifest" |
  .accounts = [.accounts[0]] |
  .contracts |= map(. as $c | select(.kind == "registry" or .kind == "factory" or .name == $factory or .name == $init or
    (.kind == "facet" and (($facets | index($c.address | ascii_downcase)) != null))))
' "$source_manifest" > "$temporary/release.json"
baseline=$temporary/release.json
check() { ./script/release/validate-manifest.sh "$1" > "$temporary/check.log" 2>&1; }
check "$baseline" || { cat "$temporary/check.log" >&2; echo 'account fixture baseline failed' >&2; exit 1; }
reject() {
    jq "$2" "$baseline" > "$temporary/mutated.json"
    if check "$temporary/mutated.json"; then echo "account fixture accepted: $1" >&2; exit 1; fi
}
reject missing-bindings 'del(.accounts)'
reject duplicate-bindings '.accounts += .accounts'
reject dangling-init '.accounts[0].initializer = "MissingInit"'
reject dangling-factory '.accounts[0].factory = "MissingFactory"'
reject wrong-entrypoint '.accounts[0].entryPoint = "0x0000000000000000000000000000000000000001"'
reject wrong-entrypoint-version '.accounts[0].entryPointVersion = "0.8"'
reject wrong-proxy-kind '.accounts[0].proxyKind = "ModularAccount6900"'
reject wrong-blueprint-hash '.accounts[0].blueprintHash = ("0x" + ("1" * 64))'
reject missing-pair '.contracts |= map(select(.kind != "account-init"))'
reject stateless-init-confusion '.contracts |= map(if .kind == "account-init" then .kind = "init" else . end)'
reject missing-init-constructor '.contracts |= map(if .kind == "account-init" then .constructorArgs = "0x" else . end)'
reject wrong-account-salt '.contracts |= map(if .kind == "account-factory" then .salt = ("0x" + ("1" * 64)) else . end)'
reject wrong-account-artifact '.contracts |= map(if .kind == "account-factory" then .artifact = "src/LatticeFactory.sol:LatticeFactory" else . end)'
reject fabricated-complete-release '.publication = "release" | .lattice.tag = ("v" + .lattice.version)'
# These are valid ABI encodings, so their rejection exercises constructor semantics rather than a decoder error.
tuples=$(jq -r '.data[0] | "[" + (map("(" + .[0] + "," + (.[1]|tostring) + ",[" + (.[2]|join(",")) + "])") | join(",")) + "]"' <<< "$decoded")
wrong_init_args=$(cast abi-encode 'constructor((address,uint8,bytes4[])[],address)' "$tuples" 0x0000000000000000000000000000000000000001)
jq --arg args "$wrong_init_args" '.contracts |= map(if .kind == "account-factory" then .constructorArgs = $args else . end)' "$baseline" > "$temporary/mutated.json"
if check "$temporary/mutated.json"; then echo 'account fixture accepted: wrong constructor init' >&2; exit 1; fi
grep -q 'constructor init or cuts differ' "$temporary/check.log"
wrong_cuts=$(jq '.data[0][0][0] = .data[0][1][0]' <<< "$decoded")
tuples=$(jq -r '.data[0] | "[" + (map("(" + .[0] + "," + (.[1]|tostring) + ",[" + (.[2]|join(",")) + "])") | join(",")) + "]"' <<< "$wrong_cuts")
wrong_facet_args=$(cast abi-encode 'constructor((address,uint8,bytes4[])[],address)' "$tuples" "$(jq -r '.data[1]' <<< "$decoded")")
jq --arg args "$wrong_facet_args" '.contracts |= map(if .kind == "account-factory" then .constructorArgs = $args else . end)' "$baseline" > "$temporary/mutated.json"
if check "$temporary/mutated.json"; then echo 'account fixture accepted: wrong blueprint facet' >&2; exit 1; fi
grep -q 'constructor init or cuts differ' "$temporary/check.log"
echo 'account manifest fixtures: 16 missing, dangling, conflicting and valid-ABI constructor mutations rejected'
