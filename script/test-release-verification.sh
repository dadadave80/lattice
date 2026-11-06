#!/usr/bin/env bash
# Sourcify state-machine regressions use executable mocks only; no server or network submission.
# shellcheck disable=SC2016,SC2329 # jq programs and callbacks invoked through sourced helpers.
set -euo pipefail
cd "$(dirname "$0")/.."
export ETHERSCAN_API_KEY='' VERIFIER_API_KEY='' ETH_RPC_JWT_SECRET='' ETH_RPC_HEADERS=''
source script/release/sourcify.sh
source script/release/chain-evidence.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export PATH="$PWD/test/fixtures/release-verification:$PATH"
factory=test/fixtures/release-verification/historical/0x9e49fb5cdbb09ecf65513f7c690909e093170037.json
registry=test/fixtures/release-verification/historical/0x563f372b4E970fe9976cFFeec614d07a2c353684.json
at=$(jq -r .address "$factory")
chain=11155111
job=11111111-1111-4111-8111-111111111111
init_hash=$(cast keccak "$(jq -r .creationBytecode.onchainBytecode "$factory")")
codehash=$(cast keccak "$(jq -r .runtimeBytecode.onchainBytecode "$factory")")
jq '{match:null,creationMatch:null,runtimeMatch:null,chainId,address}' "$factory" > "$tmp/absent.json"
jq --arg job "$job" '{isJobCompleted:true,verificationId:$job,contract:{match,creationMatch,runtimeMatch,chainId,address}}' "$factory" > "$tmp/complete.json"
jq '.contract.match="match"|.contract.creationMatch="match"' "$tmp/complete.json" > "$tmp/partial.json"
jq --arg job "$job" '{isJobCompleted:false,verificationId:$job}' <<< '{}' > "$tmp/pending.json"
jq --arg job "$job" '{verificationId:$job}' <<< '{}' > "$tmp/accepted.json"
printf '{"customCode":"already_verified"}\n' > "$tmp/conflict.json"
printf '{"stdJsonInput":{"language":"Solidity","sources":{"Fixture.sol":{"content":"// fixture source"}},"settings":{"libraries":{}}},"compilerVersion":"0.8.36+commit.8a079791","contractIdentifier":"Fixture.sol:Fixture"}\n' > "$tmp/request.json"
cases=0
check_status() {
    local expected=$1 got; shift
    if "$@"; then got=0; else got=$?; fi
    [ "$got" = "$expected" ] || { echo "verification fixture: expected $expected, got $got ($*)" >&2; exit 1; }
    cases=$((cases + 1))
}
reset_case() {
    export VERIFY_MOCK=$tmp/case-$cases
    mkdir -p "$VERIFY_MOCK/steps"
    printf 0 > "$VERIFY_MOCK/count"
    jq -n '{contracts:[{name:"contract",verified:false,verifier:null}],nonCanonicalFactories:[{name:"preserve"}]}' > "$VERIFY_MOCK/chain.json"
    step_count=0
    verification_can_commit() { return 0; }
}
step() {
    step_count=$((step_count + 1))
    local directory=$VERIFY_MOCK/steps/$step_count
    mkdir -p "$directory"
    printf '%s' "$1" > "$directory/method"
    printf '%s' "$2" > "$directory/url"
    printf '%s' "$3" > "$directory/status"
    cp "$4" "$directory/body.json"
    printf 'HTTP/1.1 %s\r\n' "$3" > "$directory/headers"
    printf '%s' "${5:-0}" > "$directory/exit"
}
run_record() { sourcify_verify_record "$VERIFY_MOCK/chain.json" contract "$at" "$chain" "$init_hash" "$codehash" "$tmp/request.json" "$VERIFY_MOCK"; }
verified() { jq -e '.contracts[0].verified and .contracts[0].verifier=="sourcify" and (.contracts[0]|has("verificationId")|not) and .nonCanonicalFactories[0].name=="preserve"' "$VERIFY_MOCK/chain.json" >/dev/null; }
unknown() { jq -e '.contracts[0].verified==false and .contracts[0].verifier==null' "$VERIFY_MOCK/chain.json" >/dev/null; }

# These are real read-only historical records, not current release goldens. Their creation bytecode includes args.
for historical in "$factory" "$registry"; do
    ctor_args=$(jq -r .creationBytecode.transformationValues.constructorArguments "$historical")
    creation=$(jq -r .creationBytecode.onchainBytecode "$historical")
    check_status 0 jq -e --arg args "$ctor_args" '.creationBytecode.onchainBytecode|endswith($args|ltrimstr("0x"))' "$historical"
    historical_hash=$(cast keccak "$creation")
    runtime_hash=$(cast keccak "$(jq -r .runtimeBytecode.onchainBytecode "$historical")")
    historical_at=$(jq -r .address "$historical")
    check_status 0 sourcify_lookup_exact "$historical" "$chain" "$historical_at" "$historical_hash" "$runtime_hash"
    ctor_free=${creation:0:${#creation}-${#ctor_args}+2}
    check_status 2 sourcify_lookup_exact "$historical" "$chain" "$historical_at" "$(cast keccak "$ctor_free")" "$runtime_hash"
done
# A library's on-chain self-address patch must stay in the hash, unlike the artifact's zero placeholder.
library=0x0000000000000000000000000000000000000042
library_runtime=0x73${library#0x}6000
jq -n --arg at "$library" --arg runtime "$library_runtime" '{match:"exact_match",creationMatch:"exact_match",runtimeMatch:"exact_match",chainId:"31337",address:$at,creationBytecode:{onchainBytecode:"0x60006000"},runtimeBytecode:{onchainBytecode:$runtime}}' > "$tmp/library.json"
check_status 0 sourcify_lookup_exact "$tmp/library.json" 31337 "$library" "$(cast keccak 0x60006000)" "$(cast keccak "$library_runtime")"
check_status 2 sourcify_lookup_exact "$tmp/library.json" 31337 "$library" "$(cast keccak 0x60006000)" "$(cast keccak "0x73$(printf '%040d' 0)6000")"
check_status 1 sourcify_completed_exact "$tmp/partial.json" "$job" "$chain" "$at"
jq 'del(.contract)' "$tmp/complete.json" > "$tmp/missing.json"
check_status 1 sourcify_completed_exact "$tmp/missing.json" "$job" "$chain" "$at"

# Existing exact matches skip all POSTs and bind both bytecodes.
reset_case; step GET /v2/contract/ 200 "$factory"
check_status 0 run_record; verified; [ "$(cat "$VERIFY_MOCK/count")" = 1 ]

# Newly submitted/polled success, with exact archived payload and pending-ticket persistence.
reset_case; step GET /v2/contract/ 404 "$tmp/absent.json"; step POST /v2/verify/ 202 "$tmp/accepted.json"
step GET "/v2/verify/$job" 200 "$tmp/pending.json"; step GET "/v2/verify/$job" 200 "$tmp/complete.json"; step GET /v2/contract/ 200 "$factory"
check_status 0 run_record; verified; cmp "$tmp/request.json" "$VERIFY_MOCK/submitted-2.json"
check_status 0 jq -e '.stdJsonInput.settings.libraries=={}' "$VERIFY_MOCK/submitted-2.json"

# A stale verified flag cannot survive an unknown result.
reset_case; jq '.contracts[0]|={name,verified:true,verifier:"sourcify"}' "$VERIFY_MOCK/chain.json" > "$tmp/stale.json"; cp "$tmp/stale.json" "$VERIFY_MOCK/chain.json"
printf '{broken' > "$tmp/bad.json"; step GET /v2/contract/ 200 "$tmp/bad.json"
check_status 2 run_record; unknown
reset_case; cat "$factory" "$factory" > "$tmp/multiple.json"; step GET /v2/contract/ 200 "$tmp/multiple.json"
check_status 2 run_record; unknown

# Completed partial/missing results and conflicts never imply successful verification.
for completed in "$tmp/partial.json" "$tmp/missing.json"; do
    reset_case; step GET /v2/contract/ 404 "$tmp/absent.json"; step POST /v2/verify/ 202 "$tmp/accepted.json"; step GET "/v2/verify/$job" 200 "$completed"
    check_status 1 run_record; unknown
done
reset_case; step GET /v2/contract/ 404 "$tmp/absent.json"; step POST /v2/verify/ 409 "$tmp/conflict.json"; step GET /v2/contract/ 200 "$factory"
check_status 0 run_record; verified
reset_case; step GET /v2/contract/ 404 "$tmp/absent.json"; step POST /v2/verify/ 409 "$tmp/conflict.json"; step GET /v2/contract/ 200 "$tmp/absent.json"
check_status 1 run_record; unknown

# Resume a pending ticket without another POST; timed-out work keeps that ticket.
reset_case; jq --arg job "$job" '.contracts[0].verificationId=$job' "$VERIFY_MOCK/chain.json" > "$tmp/resume.json"; cp "$tmp/resume.json" "$VERIFY_MOCK/chain.json"
step GET /v2/contract/ 404 "$tmp/absent.json"; step GET "/v2/verify/$job" 200 "$tmp/complete.json"; step GET /v2/contract/ 200 "$factory"
check_status 0 run_record; verified; [ ! -e "$VERIFY_MOCK/submitted-2.json" ]
reset_case; step GET /v2/contract/ 404 "$tmp/absent.json"; step POST /v2/verify/ 202 "$tmp/accepted.json"
for attempt in {1..12}; do step GET "/v2/verify/$job" 200 "$tmp/pending.json"; done
check_status 75 run_record; unknown; jq -e --arg job "$job" '.contracts[0].verificationId==$job' "$VERIFY_MOCK/chain.json" >/dev/null

# Request/address/job identity and bytecode tampering fail closed.
reset_case; jq '.runtimeBytecode.onchainBytecode="0x00"' "$factory" > "$tmp/wrong-code.json"; step GET /v2/contract/ 200 "$tmp/wrong-code.json"
check_status 2 run_record; unknown
reset_case; jq '.address="0x0000000000000000000000000000000000000001"' "$factory" > "$tmp/wrong-address.json"; step GET /v2/contract/ 200 "$tmp/wrong-address.json"
check_status 2 run_record; unknown
reset_case; step GET /v2/contract/ 404 "$tmp/absent.json"; step POST /v2/verify/ 202 "$tmp/multiple.json"
check_status 2 run_record; unknown

# Retries are bounded; Retry-After is respected. Ambiguous POST failures are not retried.
reset_case; step GET /v2/contract/ 429 "$tmp/conflict.json"; printf 'Retry-After: 4\r\n' >> "$VERIFY_MOCK/steps/1/headers"; step GET /v2/contract/ 200 "$factory"
check_status 0 run_record; verified; grep -qx 4 "$VERIFY_MOCK/waits"
reset_case; step GET /v2/contract/ 500 "$tmp/conflict.json"; step GET /v2/contract/ 503 "$tmp/conflict.json"; step GET /v2/contract/ 200 "$factory"
check_status 0 run_record; verified; [ "$(cat "$VERIFY_MOCK/count")" = 3 ]
reset_case; step GET /v2/contract/ 404 "$tmp/absent.json"; step POST /v2/verify/ 500 "$tmp/conflict.json"
check_status 75 run_record; unknown; [ "$(cat "$VERIFY_MOCK/count")" = 2 ]
reset_case; step GET /v2/contract/ 429 "$tmp/conflict.json"; printf 'Retry-After: 120\r\n' >> "$VERIFY_MOCK/steps/1/headers"
check_status 75 run_record; [ ! -e "$VERIFY_MOCK/waits" ]

# A block change before committing authoritative evidence keeps the flag false.
reset_case; step GET /v2/contract/ 200 "$factory"; verification_can_commit() { return 1; }
check_status 75 run_record; unknown

# RPC evidence uses canonical block headers and a direct successful Arachnid salt+initcode transaction.
tx=0x$(printf '%064d' 1)
block_hash=0x$(printf '%064d' 2)
salt=0x$(printf '%064d' 3)
deployer=0x4e59b44847b379578588920cA78FbF26c0B4956C
jq -n --arg tx "$tx" --arg block "$block_hash" '{transactionHash:$tx,status:"0x1",blockNumber:"0xa",blockHash:$block}' > "$tmp/receipt-base.json"
jq -n --arg tx "$tx" --arg block "$block_hash" --arg to "$deployer" --arg input "${salt}6000" '{hash:$tx,blockNumber:"0xa",blockHash:$block,to:$to,input:$input}' > "$tmp/transaction-base.json"
cast() {
    if [ "$1" != rpc ]; then command cast "$@"; return; fi
    case "$4" in
        eth_getTransactionReceipt) cat "$tmp/receipt.json" ;;
        eth_getTransactionByHash) cat "$tmp/transaction.json" ;;
        eth_getBlockByNumber) jq -n --arg hash "$block_hash" '{hash:$hash}' ;;
        *) return 1 ;;
    esac
}
cp "$tmp/receipt-base.json" "$tmp/receipt.json"
cp "$tmp/transaction-base.json" "$tmp/transaction.json"
tx_matches() { verification_transaction_matches mock "$tx" "$deployer" "$salt" "$(command cast keccak 0x6000)" 10 "$tmp/witness"; }
mkdir "$tmp/witness"
check_status 0 tx_matches
for mutation in '.status="0x0"' '.blockNumber="0xb"' 'null'; do
    jq "$mutation" "$tmp/receipt-base.json" > "$tmp/receipt.json"
    check_status 1 tx_matches
done
cp "$tmp/receipt-base.json" "$tmp/receipt.json"
for mutation in '.to="0x0000000000000000000000000000000000000001"' '.input="0x6000"' '.input += "00"' '.blockHash="0x0000000000000000000000000000000000000000000000000000000000000000"'; do
    jq "$mutation" "$tmp/transaction-base.json" > "$tmp/transaction.json"
    check_status 1 tx_matches
done
cat "$tmp/transaction-base.json" "$tmp/transaction-base.json" > "$tmp/transaction.json"
check_status 1 tx_matches
unset -f cast

# Optional tickets remain unknown and require observed matching code; they cannot coexist with success.
release_fixture=test/fixtures/release-manifests/release.json
chain_fixture=test/fixtures/release-manifests/chain.json
jq --arg job "$job" '.contracts[0] |= (.deployed="pre-existing"|.codeMatches=true|.verificationId=$job)' "$chain_fixture" > "$tmp/pending-chain.json"
check_status 0 ./script/release/validate-manifest.sh "$release_fixture" "$tmp/pending-chain.json"
for mutation in '.contracts[0].verified=true|.contracts[0].verifier="sourcify"' '.contracts[0].verificationId="bad-ticket"' '.contracts[0].codeMatches=false'; do
    jq "$mutation" "$tmp/pending-chain.json" > "$tmp/invalid-chain.json"
    check_status 1 ./script/release/validate-manifest.sh "$release_fixture" "$tmp/invalid-chain.json"
done

# Input tampering fails before any source rebuild or verifier request.
printf '[{"input":{"language":"Solidity"}}]\n' > "$tmp/wrong-inputs.json"
if ./script/release-verify.sh --prepare "$release_fixture" "$tmp/wrong-inputs.json" "$tmp/wrong-input-stage" > "$tmp/wrong-input.log" 2>&1; then
    echo 'verification accepted a different input witness' >&2; exit 1
fi
grep -q 'archived compiler-input hash differs' "$tmp/wrong-input.log"
cases=$((cases + 1))

# Test material is never accepted by the operational entry point, before any transport call.
reset_case
if ./script/release-verify.sh test/fixtures/release-manifests/release.json test/fixtures/release-manifests/chain.json missing-input.json mock > "$tmp/fixture-operation.log" 2>&1; then
    echo 'verification accepted operational fixture material' >&2; exit 1
fi
grep -q 'fixture material cannot be submitted' "$tmp/fixture-operation.log"
[ "$(cat "$VERIFY_MOCK/count")" = 0 ]
cases=$((cases + 1))
echo "verification: $cases transport/identity/constructor/library/status/RPC cases passed (no network)"
