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
# shortcut: four-byte assembly reverts use adjacent literal mstore/revert statements;
# extend this validation when introducing another local error encoding.
for artifact in "${artifacts[@]}"; do
jq -sc '
  def canonical:
    if (.type | startswith("tuple")) then
      "(" + ([.components[] | canonical] | join(",")) + ")" + .type[5:]
    else .type end;
  def signature: .name + "(" + ([.inputs[]? | canonical] | join(",")) + ")";
  def literal($pattern):
    .nodeType == "YulLiteral" and ((.value // "") | test($pattern; "i"));
  if length != 1 or (.[0] | type) != "object" then
    error("Expected one artifact object: " + input_filename)
  else .[0] end
  | (.ast.absolutePath // ((.metadata.settings.compilationTarget // {}) | keys[0]) // "") as $source
  | select(($source | startswith("src/")) or ($source | startswith("lib/diamond-lib/src/")))
  | if .ast == null then error("Compile with ast = true: " + $source) else . end
  | {
      abis: [.abi[]? | select(.type == "error" or .type == "event") |
        {kind:.type, signature:signature, anonymous:(.anonymous // false),
         indexed:[.inputs[]? | .indexed // false]}],
      declarations: [.ast | .. | objects |
        select(.nodeType? == "ErrorDefinition" or .nodeType? == "EventDefinition") |
        {kind:(if .nodeType == "ErrorDefinition" then "error" else "event" end),
         name, selector:("0x" + (.errorSelector // .eventSelector |
           if . == null then error("Missing compiler selector: " + $source) else ascii_downcase end)),
         source:$source, anonymous:(.anonymous // false),
         indexed:[.parameters.parameters[]? | .indexed // false]}],
      assembly: [.ast | .. | objects | select(.nodeType? == "YulBlock") |
        .statements as $statements | range(0; $statements | length) as $i |
        $statements[$i] as $statement |
        select($statement.nodeType == "YulExpressionStatement"
          and $statement.expression.functionName.name == "revert"
          and ($statement.expression.arguments[1] | literal("^(0*4|0x0*4)$"))) |
        $statements[$i - 1].expression as $store |
        if $i == 0 or $store.functionName.name != "mstore"
          or ($store.arguments[0] | literal("^(0+|0x0+)$") | not)
          or ($statement.expression.arguments[0] | literal("^(0*28|0x0*1c)$") | not)
          or ($store.arguments[1].nodeType != "YulLiteral")
          or (($store.arguments[1].value // "") | test("^0x[0-9a-f]{8}$"; "i") | not)
        then error("Unsupported four-byte assembly revert: " + $source + ":" + ($statement.src // "?"))
        else {selector:($store.arguments[1].value | ascii_downcase),
              source:$source, position:(($statement.src // "?") | split(":")[:2] | join(":"))} end]
    }
' "$artifact"
done >"$catalog_tmp_dir/summary.ndjson"

jq -s '
  if length == 0 then error("No source artifacts in ABI catalog") else . end
  | {abis:([.[].abis[]] | unique),
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
  | ($hashes | group_by([.kind,.selector]) |
      map(if ([.[].signature] | unique | length) != 1 then
        error("ABI selector collision: " + (map(.signature) | join(", ")))
      else {key:(.[0].kind + ":" + .[0].selector), value:.[0].signature} end) |
      from_entries) as $signatures
  | [$s.declarations[] | . as $d |
      $signatures[.kind + ":" + .selector] as $signature |
      if $signature == null or ($signature | split("(")[0]) != .name then
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
