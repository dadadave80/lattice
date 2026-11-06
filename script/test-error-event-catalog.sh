#!/usr/bin/env bash
# Native fixtures for ABI coverage, ambiguous selectors and assembly error encodings.
set -euo pipefail
CHECK="$(cd "$(dirname "$0")" && pwd)/error-event-catalog.sh"
catalog_tmp_dir=$(mktemp -d)
trap 'rm -rf "$catalog_tmp_dir"' EXIT
failures=0
number=0

fixture() {
    mkdir -p "$1/out/Fixture.sol"
    cat >"$1/out/Fixture.sol/Fixture.json" <<'JSON'
{
  "abi": [
    {"type":"error","name":"NotInitializing","inputs":[]},
    {"type":"event","name":"Initialized","anonymous":false,"inputs":[{"name":"version","type":"uint64","indexed":false}]}
  ],
  "ast": {
    "absolutePath":"src/Fixture.sol",
    "nodes":[
      {"nodeType":"ErrorDefinition","name":"NotInitializing","errorSelector":"d7e6bcf8"},
      {"nodeType":"EventDefinition","name":"Initialized","eventSelector":"c7f505b2f371ae2175ee4913f4499e1f2633a7b5936321eed1cdaeb6115181d2","anonymous":false,"parameters":{"parameters":[{"indexed":false}]}},
      {"nodeType":"InlineAssembly","AST":{"nodeType":"YulBlock","statements":[
        {"nodeType":"YulExpressionStatement","expression":{"functionName":{"name":"mstore"},"arguments":[{"nodeType":"YulLiteral","value":"0x00"},{"nodeType":"YulLiteral","value":"0xd7e6bcf8"}]}},
        {"nodeType":"YulExpressionStatement","src":"100:4:0","expression":{"functionName":{"name":"revert"},"arguments":[{"nodeType":"YulLiteral","value":"0x1c"},{"nodeType":"YulLiteral","value":"0x04"}]}}
      ]}}
    ]
  }
}
JSON
}

expect() {
    local want=$1 name=$2 filter=$3 directory result
    number=$((number + 1))
    directory="$catalog_tmp_dir/case$number"
    fixture "$directory"
    jq "$filter" "$directory/out/Fixture.sol/Fixture.json" >"$directory/artifact.tmp"
    mv "$directory/artifact.tmp" "$directory/out/Fixture.sol/Fixture.json"
    if "$CHECK" "$directory/out" "$directory/catalog.json" >"$directory/log" 2>&1; then result=pass; else result=fail; fi
    if [[ "$result" == pass && "$want" == pass ]]; then
        jq -e '.errors["0xd7e6bcf8"].signature == "NotInitializing()" and (.events | length) == 1 and (.assembly | length) == 1' "$directory/catalog.json" >/dev/null || result=fail
    fi
    if [[ "$result" == "$want" ]]; then
        echo "ok   $name"
    else
        echo "FAIL $name (expected $want, got $result)"
        cat "$directory/log"
        failures=$((failures + 1))
    fi
}

expect pass "canonical declarations and assembly site" '.'
expect fail "assembly error declaration missing from every ABI" 'del(.abi[0])'
expect fail "event declaration missing from every ABI" 'del(.abi[1])'
expect fail "unknown literal assembly selector" '.ast.nodes[2].AST.statements[0].expression.arguments[1].value = "0xdeadbeef"'
expect fail "unrecognized four-byte assembly encoding" '.ast.nodes[2].AST.statements[1].expression.arguments[0].value = "0x00"'
expect fail "nonliteral assembly selector" '.ast.nodes[2].AST.statements[0].expression.arguments[1] = {"nodeType":"YulIdentifier","name":"unknown"}'
expect fail "missing compiler AST" 'del(.ast)'
expect fail "multiple JSON documents in one artifact" '., {}'
expect fail "event indexed encoding differs from its ABI" '.ast.nodes[1].parameters.parameters[0].indexed = true'
expect pass "anonymous event with matching ABI encoding" '.abi[1].anonymous = true | .ast.nodes[1].anonymous = true'
expect fail "distinct signatures with one error selector" '
 .abi += [{"type":"error","name":"burn","inputs":[{"name":"amount","type":"uint256"}]},
          {"type":"error","name":"collate_propagate_storage","inputs":[{"name":"value","type":"bytes16"}]}]
 | .ast.nodes += [{"nodeType":"ErrorDefinition","name":"burn","errorSelector":"42966c68"},
                  {"nodeType":"ErrorDefinition","name":"collate_propagate_storage","errorSelector":"42966c68"}]'

[[ "$failures" == 0 ]] || exit 1
echo "$number ABI catalog fixtures passed."
