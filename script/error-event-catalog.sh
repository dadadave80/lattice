#!/usr/bin/env bash
# Generate a checked custom-error/event catalog from one clean Foundry artifact build.
# Usage: script/error-event-catalog.sh [artifact-directory] [output-json]
set -euo pipefail
artifact_dir=${1:-out}
output=${2:-out/errors.json}
catalog_tmp_dir=$(mktemp -d)
trap 'rm -rf "$catalog_tmp_dir"' EXIT
shopt -s nullglob
artifacts=("$artifact_dir"/*.sol/*.json)
[[ ${#artifacts[@]} -gt 0 ]] || { echo 'ABI catalog: build artifacts first.' >&2; exit 1; }

# Summarize one artifact at a time: slurping complete AST artifacts exhausts CI memory.
# shortcut: assembly reverts must match the local error, Panic, empty or returndata
# shapes below; extend this allowlist when introducing another encoding.
for artifact in "${artifacts[@]}"; do
jq -sc '
  def canonical:
    if (.type | startswith("tuple")) then
      "(" + ([.components[] | canonical] | join(",")) + ")" + .type[5:]
    else .type end;
  def signature: .name + "(" + ([.inputs[]? | canonical] | join(",")) + ")";
  def literal($pattern):
    .nodeType == "YulLiteral" and ((.value // "") | test($pattern; "i"));
  def type_node:
    if .nodeType == "ElementaryTypeName" then {kind:"elementary",name}
    elif .nodeType == "ArrayTypeName" then
      {kind:"array",base:(.baseType | type_node),
       suffix:(.typeDescriptions.typeString | capture("\\[(?<length>[0-9]*)\\](?: .*)?$").length)}
    elif .nodeType == "UserDefinedTypeName" then {kind:"defined",reference:.referencedDeclaration}
    elif .nodeType == "FunctionTypeName" and .visibility == "external" then {kind:"function"}
    else {kind:"unsupported",node:.nodeType} end;
  def call($name): .nodeType == "YulFunctionCall" and .functionName.name == $name;
  def identifier: .nodeType == "YulIdentifier";
  def buffer_pointer:
    if call("add") then
      if (.arguments[0] | literal("^(0*32|0x0*20)$")) and (.arguments[1] | identifier)
      then .arguments[1].name
      elif (.arguments[1] | literal("^(0*32|0x0*20)$")) and (.arguments[0] | identifier)
      then .arguments[0].name else null end
    else null end;
  def buffer_length($buffer): call("mload") and .arguments[0].name == $buffer;
  def bubble($prefix; $previous):
    .arguments[0] as $offset | .arguments[1] as $size
    | ($offset | buffer_pointer) as $buffer
    | (($offset | literal("^(0+|0x0+)$")) and ($size | call("returndatasize")))
      or ($buffer != null and
        (($size | buffer_length($buffer)) or (($size | identifier) and
          any($prefix[]; .nodeType == "YulVariableDeclaration"
            and (.variables | length) == 1 and .variables[0].name == $size.name
            and (.value | buffer_length($buffer))) and
          (any($prefix[] | .. | objects;
            .nodeType? == "YulAssignment" and any(.variableNames[]?; .name == $size.name)) | not))))
      or (($offset | identifier) and ($size | identifier)
        and ($previous | call("returndatacopy"))
        and $previous.arguments[0].name == $offset.name
        and ($previous.arguments[1] | literal("^(0+|0x0+)$"))
        and $previous.arguments[2].name == $size.name);
  if length != 1 or (.[0] | type) != "object" then
    error("Expected one artifact object: " + input_filename)
  else .[0] end
  | (.ast.absolutePath // ((.metadata.settings.compilationTarget // {}) | keys[0]) // "") as $source
  | select(($source | startswith("src/")) or ($source | startswith("lib/diamond-lib/src/")))
  | if .ast == null then error("Compile with ast = true: " + $source) else . end
  | {
      source:$source,
      types:[.ast | .. | objects |
        if .nodeType? == "StructDefinition" then
          {id,name,source:$source,kind:"struct",members:[.members[].typeName | type_node]}
        elif .nodeType? == "EnumDefinition" then {id,name,source:$source,kind:"enum"}
        elif .nodeType? == "UserDefinedValueTypeDefinition" then
          {id,name,source:$source,kind:"value",underlying:(.underlyingType | type_node)}
        elif .nodeType? == "ContractDefinition" then {id,name,source:$source,kind:"contract"}
        else empty end],
      abis: [.abi[]? | select(.type == "error" or .type == "event") |
        {kind:.type, signature:signature, anonymous:(.anonymous // false),
         indexed:[.inputs[]? | .indexed // false]}],
      declarations: [.ast | .. | objects |
        select(.nodeType? == "ErrorDefinition" or .nodeType? == "EventDefinition") |
        {kind:(if .nodeType == "ErrorDefinition" then "error" else "event" end),
         name, selector:("0x" + (.errorSelector // .eventSelector |
           if . == null then error("Missing compiler selector: " + $source) else ascii_downcase end)),
         source:$source, anonymous:(.anonymous // false),
         parameters:[.parameters.parameters[]? | .typeName | type_node],
         indexed:[.parameters.parameters[]? | .indexed // false]}],
      assembly: [.ast | .. | objects | select(.nodeType? == "YulBlock") |
        .statements as $statements | range(0; $statements | length) as $i |
        $statements[$i] as $statement |
        select($statement.nodeType == "YulExpressionStatement"
          and $statement.expression.functionName.name == "revert") |
        $statement.expression as $revert |
        $statements[$i - 1].expression as $store |
        if ($revert.arguments[0] | literal("^(0+|0x0+)$"))
          and ($revert.arguments[1] | literal("^(0+|0x0+)$")) then empty
        elif ($revert | bubble($statements[:$i]; $store)) then empty
        elif $i >= 2 and ($revert.arguments[0] | literal("^(0*28|0x0*1c)$"))
          and ($revert.arguments[1] | literal("^(0*36|0x0*24)$"))
          and ($store | call("mstore")) and ($store.arguments[0] | literal("^(0*32|0x0*20)$"))
          and ($statements[$i - 2].expression | call("mstore"))
          and ($statements[$i - 2].expression.arguments[0] | literal("^(0+|0x0+)$"))
          and ($statements[$i - 2].expression.arguments[1] | literal("^0x4e487b71$")) then empty
        elif $i == 0 or ($store | call("mstore") | not)
          or ($store.arguments[0] | literal("^(0+|0x0+)$") | not)
          or ($revert.arguments[0] | literal("^(0*28|0x0*1c)$") | not)
          or ($revert.arguments[1] | literal("^(0*4|0x0*4)$") | not)
          or ($store.arguments[1].nodeType != "YulLiteral")
          or (($store.arguments[1].value // "") | test("^0x[0-9a-f]{8}$"; "i") | not)
        then error("Unsupported assembly revert: " + $source + ":" + ($statement.src // "?"))
        else {selector:($store.arguments[1].value | ascii_downcase),
              source:$source, position:(($statement.src // "?") | split(":")[:2] | join(":"))} end]
    }
' "$artifact"
done >"$catalog_tmp_dir/summary.ndjson"

find src lib/diamond-lib/src -type f -name '*.sol' -print | LC_ALL=C sort >"$catalog_tmp_dir/sources.txt"
jq -r '.source' "$catalog_tmp_dir/summary.ndjson" | LC_ALL=C sort -u >"$catalog_tmp_dir/compiled.txt"
LC_ALL=C comm -23 "$catalog_tmp_dir/sources.txt" "$catalog_tmp_dir/compiled.txt" >"$catalog_tmp_dir/missing.txt"
if [[ -s "$catalog_tmp_dir/missing.txt" ]]; then
    echo 'ABI catalog: source units absent from compiler artifacts:' >&2
    cat "$catalog_tmp_dir/missing.txt" >&2
    exit 1
fi

jq -s '
  if length == 0 then error("No source artifacts in ABI catalog") else . end
  | {abis:([.[].abis[]] | unique),
     types:([.[].types[]] | unique),
     declarations:([.[].declarations[]] | unique),
     assembly:([.[].assembly[]] | unique)}
' "$catalog_tmp_dir/summary.ndjson" >"$catalog_tmp_dir/summary.json"

jq -r '.abis | unique_by(.kind, .signature) | .[] | [.kind, .signature] | @tsv' \
  "$catalog_tmp_dir/summary.json" >"$catalog_tmp_dir/signatures.tsv"
while IFS=$'\t' read -r kind signature; do
    digest=$(cast keccak "$signature")
    if [[ "$kind" == error ]]; then selector=${digest:0:10}; else selector=$digest; fi
    printf '%s\t%s\t%s\n' "$kind" "$signature" "$selector"
done <"$catalog_tmp_dir/signatures.tsv" >"$catalog_tmp_dir/hashes.tsv"
jq -Rn '[inputs | split("\t") | {kind:.[0], signature:.[1], selector:.[2]}]' \
  <"$catalog_tmp_dir/hashes.tsv" >"$catalog_tmp_dir/hashes.json"

jq -n --slurpfile summary "$catalog_tmp_dir/summary.json" --slurpfile hashes "$catalog_tmp_dir/hashes.json" '
  $summary[0] as $s | $hashes[0] as $hashes
  | ($s.types | group_by(.id) | map(
      if length != 1 then error("Mixed compiler AST IDs; run make abi-catalog")
      else {key:(.[0].id | tostring),value:.[0]} end) | from_entries) as $types
  | def canonical_type:
      if .kind == "elementary" then
        if .name == "uint" then "uint256" elif .name == "int" then "int256"
        elif .name == "byte" then "bytes1" elif .name == "address payable" then "address"
        else .name end
      elif .kind == "array" then (.base | canonical_type) + "[" + .suffix + "]"
      elif .kind == "function" then "function"
      elif .kind == "defined" then $types[.reference | tostring] as $type |
        if $type.kind == "struct" then "(" + ([$type.members[] | canonical_type] | join(",")) + ")"
        elif $type.kind == "enum" then "uint8"
        elif $type.kind == "contract" then "address"
        elif $type.kind == "value" then $type.underlying | canonical_type
        else error("Unresolved ABI type; run make abi-catalog") end
      else error("Unsupported ABI type") end;
    ($hashes | group_by([.kind,.selector]) |
      map(if ([.[].signature] | unique | length) != 1 then
        error("ABI selector collision: " + (map(.signature) | join(", ")))
      else {key:(.[0].kind + ":" + .[0].selector), value:.[0].signature} end) |
      from_entries) as $signatures
  | [$s.declarations[] |
      . + {signature:(.name + "(" + ([.parameters[] | canonical_type] | join(",")) + ")")}] as $declared
  | if any($declared | group_by([.kind,.selector])[]; ([.[].signature] | unique | length) != 1)
    then error("AST declaration selector collision") else . end
  | [$declared[] | . as $d |
      $signatures[.kind + ":" + .selector] as $signature |
      if $signature == null or $signature != .signature then
        error("Declaration missing from every ABI: " + .source + ":" + .name)
      elif .kind == "event" and (any($s.abis[];
        .kind == "event" and .signature == $signature
          and .anonymous == $d.anonymous and .indexed == $d.indexed) | not) then
        error("Event encoding missing from every ABI: " + .source + ":" + .name)
      else . + {signature:$signature} end] as $declarations
  | ($declarations | map(select(.kind == "error")) | group_by(.selector) |
      map({key:.[0].selector, value:{signature:.[0].signature,
        sources:(map(.source) | unique)}}) | from_entries) as $errors
  | ($declarations | map(select(.kind == "event")) | group_by(.selector) |
      map({key:.[0].selector, value:{signature:.[0].signature,
        definitions:(map({source,anonymous,indexed}) | unique)}}) | from_entries) as $events
  | if any($s.assembly[]; $errors[.selector] == null) then
      error("Assembly error selector missing from the catalog")
    else {schemaVersion:1, errors:$errors, events:$events, assembly:$s.assembly} end
' >"$catalog_tmp_dir/catalog.json"

mkdir -p "$(dirname "$output")"
mv "$catalog_tmp_dir/catalog.json" "$output"
echo "ABI catalog written: $output"
