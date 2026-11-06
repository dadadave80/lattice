#!/usr/bin/env bash
# Compiler-declared interface selectors for RecipeGuards (ERC-165 excludes inherited declarations).
set -euo pipefail
shopt -s nullglob
# Keep new recipes in the shared guard suites instead of silently testing only the old inventory.
guards=$(cat test/composability/RecipeUpgradeability*Test.t.sol | tr '\n' ' ')
while IFS= read -r recipe; do
    grep -q 'function buildCuts' "$recipe" || continue
    name="${recipe##*/}"
    name="${name%.s.sol}"
    grep -Eq "new[[:space:]]+${name}[[:space:]]*\(" <<<"$guards" || {
        echo "Missing recipe guard: ${recipe}" >&2
        exit 1
    }
done < <(find script/base -type f -name 'Deploy*.s.sol' | LC_ALL=C sort)
artifacts=()
while IFS= read -r source; do
    artifacts+=(out/"${source##*/}"/*.json)
done < <(find src/interfaces lib/diamond-lib/src/interfaces -type f -name '*.sol' | LC_ALL=C sort)
[[ ${#artifacts[@]} -gt 0 ]] || { echo 'Build the interface artifacts first.' >&2; exit 1; }
tuples=$(jq -sr '
    if any(.[]; .ast == null) then error("Compile interface artifacts with ast = true") else . end
    | [.[] as $a | $a.ast.nodes[]?
      | select(.nodeType == "ContractDefinition" and .contractKind == "interface")
      | select(.name == ($a.metadata.settings.compilationTarget | to_entries[0].value))
      | [($a.ast.absolutePath + ":" + .name),
         [.nodes[]? | select(.nodeType == "FunctionDefinition" and (.functionSelector | length) == 8) | "0x" + .functionSelector]]]
    # Lattice bundles metadata into IERC721/IERC1155; their canonical ERC-165 IDs are separate.
    | . + [.[] | select(.[0] == "src/interfaces/tokens/IERC721.sol:IERC721")
        | . as $i
        | [$i[0] + "(core)", ($i[1] - ["0x06fdde03", "0x95d89b41", "0xc87b56dd"])],
          [$i[0] + "(metadata)", ["0x06fdde03", "0x95d89b41", "0xc87b56dd"]]]
    | . + [.[] | select(.[0] == "src/interfaces/tokens/IERC1155.sol:IERC1155")
        | . as $i
        | [$i[0] + "(core)", ($i[1] - ["0x0e89341c"])],
          [$i[0] + "(metadata)", ["0x0e89341c"]]]
    | sort_by(.[0])
    | "[" + (map("(" + (.[0] | @json) + ",[" + (.[1] | join(",")) + "])") | join(",")) + "]"
' "${artifacts[@]}")
cast abi-encode 'f((string,bytes4[])[])' "$tuples"
