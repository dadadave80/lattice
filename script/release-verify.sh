#!/usr/bin/env bash
# Verify a complete frozen release on Sourcify. An explicit operational invocation publishes source.
set -euo pipefail
cd "$(dirname "$0")/.."
unset ETHERSCAN_API_KEY VERIFIER_API_KEY
source script/release/sourcify.sh
source script/release/chain-evidence.sh
fail() { echo "release-verify: $*" >&2; exit 1; }
if [ "${1:-}" = --prepare ]; then
    [ "$#" = 4 ] || fail 'usage: release-verify.sh --prepare <release> <inputs> <stage>'
    exec ./script/release/prepare-verification.sh "$2" "$3" "$4"
fi
[ "$#" = 4 ] || fail 'usage: release-verify.sh <release> <chain-status> <inputs> <rpc-url-or-alias>'
release=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
chain_file=$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")
inputs=$3 rpc=$4
./script/release/validate-manifest.sh "$release" "$chain_file"
[ "$(jq -r '.publication' "$release")" = release ] || fail 'fixture material cannot be submitted'
lock=${chain_file}.verify.lock
mkdir "$lock" 2>/dev/null || fail 'verification already locked; check the existing process before removing a stale lock'
printf '%s\n' "$$" > "$lock/pid"
stage=$(mktemp -d "${TMPDIR:-/tmp}/lattice-source-verification.XXXXXX")
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() { rm -rf "$stage"; rm -f "$lock/pid"; rmdir "$lock"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
./script/release/prepare-verification.sh "$release" "$inputs" "$stage" "$chain_file" "$rpc"
# Re-observation resets positive flags; only fresh exact Sourcify evidence can promote each record again.
# Preserve existing transaction hints and pending IDs for this already-validated release/address set.
jq -S --slurpfile old "$chain_file" '
    .nonCanonicalFactories=$old[0].nonCanonicalFactories |
    .contracts |= map(. as $record | ($old[0].contracts[]|select(.name==$record.name)) as $previous |
      if $previous.deployed!=null then .deployed=$previous.deployed else . end |
      if $previous|has("verificationId") then .verificationId=$previous.verificationId else . end)
' "$stage/observed.json" > "$stage/current.json"
./script/release/validate-manifest.sh "$release" "$stage/current.json"
next=$(mktemp "${chain_file}.tmp.XXXXXX")
cp "$stage/current.json" "$next"
mv "$next" "$chain_file"
chain=$(jq -r '.chain.id' "$chain_file")
number=$(jq -r '.chain.blockNumber' "$chain_file")
block_hash=$(jq -r '.chain.blockHash' "$chain_file")
verification_can_commit() {
    verification_block_matches "$rpc" "$chain" "$number" "$block_hash"
}
result=0
while IFS=$'\t' read -r name at identifier compiler input_index init_hash codehash; do
    verification_can_commit || { result=1; break; }
    tx=$(jq -r --arg name "$name" '.contracts[]|select(.name==$name)|.deployed' "$chain_file")
    jq -n --slurpfile inputs "$stage/inputs.json" --argjson index "$input_index" --arg identifier "$identifier" --arg compiler "$compiler" --arg tx "$tx" '
      {stdJsonInput:$inputs[0][$index].input,compilerVersion:$compiler,contractIdentifier:$identifier} +
      (if $tx=="pre-existing" then {} else {creationTransactionHash:$tx} end)
    ' > "$stage/request.json"
    printf 'release-verify: %s\n' "$name"
    if sourcify_verify_record "$chain_file" "$name" "$at" "$chain" "$init_hash" "$codehash" "$stage/request.json" "$stage"; then
        printf 'release-verify: %s exact source and bytecodes verified\n' "$name"
    else
        status=$?
        result=1
        printf 'release-verify: %s remains unverified (status %s)\n' "$name" "$status" >&2
        # Pending/rate-limited work is saved; avoid flooding the verifier with additional submissions.
        [ "$status" != 75 ] || break
    fi
done < <(jq -r '.[]|[.name,.address,.identifier,.compilerVersion,.inputIndex,.initCodeHash,.codehash]|@tsv' "$stage/catalog.json")
if ! verification_can_commit; then
    next=$(mktemp "${chain_file}.tmp.XXXXXX")
    jq -S '.contracts |= map(.verified=false|.verifier=null)' "$chain_file" > "$next"
    mv "$next" "$chain_file"
    result=1
fi
./script/release/validate-manifest.sh "$release" "$chain_file"
jq -e 'all(.contracts[]; .verified and .verifier=="sourcify")' "$chain_file" >/dev/null || result=1
exit "$result"
