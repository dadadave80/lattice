#!/usr/bin/env bash
# Collect compiler-backed pure recipe data in bounded local frames; never use an RPC or broadcast.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "recipes: $*" >&2; exit 1; }
[ "$#" = 0 ] || fail 'usage: script/recipes.sh (writes out/recipes.json)'

# Capture provenance before a build or temporary output can affect the working-tree observation.
source_commit=$(git rev-parse HEAD)
[[ "$source_commit" =~ ^[0-9a-f]{40}$ ]] || fail 'expected a full source commit'
source_status=$(git status --porcelain --untracked-files=all)
source_dirty=false
[ -z "$source_status" ] || source_dirty=true
export FOUNDRY_PROFILE=ci
./script/check-release-build.sh
forge build --locked --skip test

interface=out/RecipeSpec.sol/IRecipeSpec.json
[ -f "$interface" ] || fail 'missing IRecipeSpec compiler ABI; build the recipe inventory first'
jq -e -s '
    length==1 and (.[0].abi|type)=="array" and
    ([.[0].abi[]|select(.type=="function" and .name=="recipeSpec" and .inputs==[])] as $methods |
      ($methods|length)==1 and $methods[0].stateMutability=="pure" and
      ($methods[0].outputs|length)==1 and $methods[0].outputs[0].type=="tuple")
' "$interface" >/dev/null || fail 'IRecipeSpec must declare one pure recipeSpec() tuple output'
type_description=$(jq -erf script/recipes/type-description.jq "$interface")
[ -n "$type_description" ] || fail 'empty native recipe type description'

mkdir -p deployments
temporary=$(mktemp -d deployments/.recipes-export.XXXXXX)
cleanup() { rm -rf "$temporary"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
inventory=$temporary/inventory.json
forge script script/recipes/GenerateRecipes.s.sol:GenerateRecipes \
    --sig 'inventory(string,string)' "$type_description" "$inventory" --non-interactive
[ -f "$inventory" ] || fail 'native inventory did not write its output'
jq -e -s --arg description "$type_description" '
    length==1 and (.[0]|type)=="object" and (.[0] |
      .schemaVersion==1 and (.latticeVersion|type)=="string" and
      (.latticeVersion|test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")) and
      .typeDescription==$description and
      (.names|type)=="array" and (.artifacts|type)=="array" and (.names|length)>0 and
      (.names|length)==(.artifacts|length) and
      (.names|unique|length)==(.names|length) and (.artifacts|unique|length)==(.artifacts|length) and
      all(.names[]; type=="string" and test("^[A-Za-z_][A-Za-z0-9_]*$")) and
      all(.artifacts[]; type=="string" and test("^script/base/([A-Za-z0-9_]+/)+[A-Za-z0-9_]+\\.s\\.sol:[A-Za-z_][A-Za-z0-9_]*$")) and
      (. as $inventory | all(range(.names|length); . as $index |
        ($inventory.artifacts[$index]|split(":")|last)==$inventory.names[$index])))
' "$inventory" >/dev/null || fail 'invalid native recipe inventory: metadata, names, FQNs or counts differ'
jq -r '. as $inventory | range(.names|length) | [. as $index|$inventory.names[$index],$inventory.artifacts[$index]] | @tsv' \
    "$inventory" > "$temporary/entries.tsv"
records=()
while IFS=$'\t' read -r name artifact; do
    source_file=${artifact%:*}
    contract=${artifact##*:}
    compiler_artifact=out/$(basename "$source_file")/$contract.json
    [ -f "$compiler_artifact" ] || fail "$name: missing compiler artifact $compiler_artifact"
    # Return-variable spelling is irrelevant; all tuple components, names, types and internal types must match.
    jq -e -s --slurpfile interface "$interface" '
        length==1 and (.[0].abi|type)=="array" and
        ([.[0].abi[]|select(.type=="function" and .name=="recipeSpec" and .inputs==[])] as $methods |
          ($methods|length)==1 and $methods[0].stateMutability=="pure" and
          ($methods[0].outputs|length)==1 and
          ($methods[0].outputs[0]|del(.name))==
            ($interface[0].abi[]|select(.type=="function" and .name=="recipeSpec" and .inputs==[])|.outputs[0]|del(.name)))
    ' "$compiler_artifact" >/dev/null || fail "$name: implement pure recipeSpec() with the exact IRecipeSpec output ABI"
    record=$temporary/record-${#records[@]}.json
    forge script script/recipes/GenerateRecipes.s.sol:GenerateRecipes \
        --sig 'generate(string,string,string,string)' "$name" "$artifact" "$type_description" "$record" --non-interactive
    [ -f "$record" ] || fail "$name: native collection did not write a record"
    jq -e -s --arg name "$name" --arg source "$source_file" '
        length==1 and (.[0]|type)=="object" and (.[0] |
          .name==$name and .source==$source and
          (.variants|type)=="array" and (.variants|length)>0 and
          (.deploymentContexts|type)=="array" and (.deploymentContexts|length)>0)
    ' "$record" >/dev/null || fail "$name: invalid, incomplete or mismatched native recipe record"
    records+=("$record")
done < "$temporary/entries.tsv"
[ "${#records[@]}" = "$(jq '.names|length' "$inventory")" ] || fail 'collected recipe count differs from inventory'
jq -S -s --slurpfile inventory "$inventory" --arg commit "$source_commit" --argjson dirty "$source_dirty" '
    if length!=($inventory[0].names|length) or map(.name)!=$inventory[0].names then
      error("collected recipe names/count/order differ from inventory")
    else . as $recipes | ($inventory[0]|del(.names,.artifacts)) +
      {recipes:$recipes,sourceCommit:$commit,sourceDirty:$dirty} end
' "${records[@]}" > "$temporary/catalog.json"
[ ! -d out/recipes.json ] || fail 'out/recipes.json must be a file, not a directory'
./script/recipes/check-catalog.sh "$temporary/catalog.json"
mv "$temporary/catalog.json" out/recipes.json
echo "recipes: wrote out/recipes.json (${#records[@]} recipes; source $source_commit; dirty=$source_dirty)"
