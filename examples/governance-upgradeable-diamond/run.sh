#!/usr/bin/env bash
# Shared Makefile entrypoint for deployment and the governance walkthrough on an EVM RPC.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
fail() { echo "grant: $*" >&2; exit 1; }
MODE=${1:-demo}
[[ $# -le 1 && ( "$MODE" == deploy || "$MODE" == demo ) ]] || fail 'usage: run.sh [deploy|demo]'
RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
LOCAL=${LOCAL:-0}
VERIFY=${VERIFY:-1}
POLL_INTERVAL=${POLL_INTERVAL:-5}
WAIT_TIMEOUT=${WAIT_TIMEOUT:-3600}
[[ "$LOCAL" == 0 || "$LOCAL" == 1 ]] || fail 'LOCAL must be 0 or 1'
[[ "$VERIFY" == 0 || "$VERIFY" == 1 ]] || fail 'VERIFY must be 0 or 1'
[[ "$POLL_INTERVAL" =~ ^[1-9][0-9]*$ && ${#POLL_INTERVAL} -le 2 && "$POLL_INTERVAL" -le 60 ]] || fail 'POLL_INTERVAL must be 1..60 seconds'
[[ "$WAIT_TIMEOUT" =~ ^[1-9][0-9]*$ && ${#WAIT_TIMEOUT} -le 5 && "$WAIT_TIMEOUT" -le 86400 ]] || fail 'WAIT_TIMEOUT must be 1..86400 seconds per phase'
AUTH=()
VERIFY_ARGS=()
if [[ "$LOCAL" == 1 ]]; then
  [[ "$RPC_URL" =~ ^http://(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?/?$ ]] || fail 'LOCAL=1 requires a loopback Anvil URL'
  [[ "$(cast chain-id --rpc-url "$RPC_URL")" == 31337 ]] || fail 'LOCAL=1 requires Anvil chain 31337'
  [[ "$(cast rpc --rpc-url "$RPC_URL" web3_clientVersion)" == *[Aa]nvil* ]] || fail 'LOCAL=1 requires Anvil'
  [[ -z "${FORGE_AUTH:-}" ]] || fail 'LOCAL=1 uses the public Anvil account; omit signer options'
  ACCOUNT=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
  AUTH=(--unlocked)
else
  [[ -n "${FORGE_AUTH:-}" ]] || fail 'set KEYSTORE=<name> through make, or supply FORGE_AUTH wallet flags'
  # Existing keychain-auth.sh provides whitespace-delimited flags; never eval or glob them.
  read -r -a AUTH <<< "$FORGE_AUTH"
  ACCOUNT=$(cast wallet address "${AUTH[@]}")
  if [[ "$VERIFY" == 1 ]]; then
    VERIFY_ARGS=(--verify --verifier "${VERIFIER:-etherscan}")
    [[ -z "${VERIFIER_URL:-}" ]] || VERIFY_ARGS+=(--verifier-url "$VERIFIER_URL")
  fi
fi
[[ "$ACCOUNT" =~ ^0x[[:xdigit:]]{40}$ ]] || fail 'could not resolve signer address'
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
number() {
  local value
  value=$(awk 'NR == 1 {print $1}')
  [[ "$value" =~ ^[0-9]+$ ]] || fail 'expected an unsigned on-chain number'
  printf '%s\n' "$value"
}
call() { cast call --rpc-url "$RPC_URL" "$@"; }
send() {
  local receipt
  receipt=$(cast send --rpc-url "$RPC_URL" --from "$ACCOUNT" "${AUTH[@]}" --json "$@")
  jq -e '.status == "0x1" or .status == 1' <<< "$receipt" >/dev/null || fail 'transaction receipt reports failure'
  jq -r '"Confirmed " + .transactionHash' <<< "$receipt" >&2
}
# Optional addresses let deploy-grant and demo-grant be run separately, without another deployment.
if [[ -n "${VAULT:-}${ASSET:-}${PROBE:-}" ]]; then
  [[ "$MODE" == demo ]] || fail 'deploy-grant always creates a fresh example; omit VAULT/ASSET/PROBE'
else
  forge script script/base/defi/GrantExample.s.sol:GrantExample --sig 'run()' \
    --rpc-url "$RPC_URL" --sender "$ACCOUNT" "${AUTH[@]}" --broadcast --slow \
    ${VERIFY_ARGS[@]+"${VERIFY_ARGS[@]}"} | tee "$LOG"
  VAULT=$(awk '$1 == "VAULT" {print $2}' "$LOG")
  ASSET=$(awk '$1 == "ASSET" {print $2}' "$LOG")
  PROBE=$(awk '$1 == "PROBE" {print $2}' "$LOG")
fi
[[ "${VAULT:-}" =~ ^0x[[:xdigit:]]{40}$ && "${ASSET:-}" =~ ^0x[[:xdigit:]]{40}$ && "${PROBE:-}" =~ ^0x[[:xdigit:]]{40}$ ]] || fail 'VAULT, ASSET, and PROBE must all be valid addresses'
printf 'VAULT=%s\nASSET=%s\nPROBE=%s\n' "$VAULT" "$ASSET" "$PROBE"
[[ "$MODE" == demo ]] || exit 0
[[ "$(call "$VAULT" 'asset()(address)' | tr '[:upper:]' '[:lower:]')" == "$(printf '%s' "$ASSET" | tr '[:upper:]' '[:lower:]')" ]] || fail 'ASSET does not match the vault'
[[ "$(call "$PROBE" 'grantVersion()(uint256)' | number)" == 2 ]] || fail 'PROBE is not the example upgrade facet'
SELECTOR=$(cast sig 'grantVersion()')
[[ "$(call "$VAULT" 'facetAddress(bytes4)(address)' "$SELECTOR")" == 0x0000000000000000000000000000000000000000 ]] || fail 'example is already upgraded; use a fresh deployment'
clock_value() {
  if [[ "$1" == vote ]]; then
    call "$VAULT" 'clock()(uint48)' | number
  else
    cast block latest --rpc-url "$RPC_URL" --field timestamp | number
  fi
}
wait_after() {
  local clock=$1 target=$2 now expires=$((SECONDS + WAIT_TIMEOUT))
  [[ "$target" =~ ^[0-9]+$ && ${#target} -le 15 ]] || fail 'invalid on-chain deadline'
  target=$((10#$target + 1))
  echo "Waiting for $clock clock >= $target" >&2
  while true; do
    now=$(clock_value "$clock")
    [[ "$now" =~ ^[0-9]+$ && ${#now} -le 15 ]] || fail 'invalid on-chain clock'
    now=$((10#$now))
    (( now < target )) || return 0
    (( SECONDS < expires )) || fail "timed out waiting for $clock clock; no subsequent transaction sent"
    if [[ "$LOCAL" == 1 ]]; then
      cast rpc --rpc-url "$RPC_URL" evm_setNextBlockTimestamp "$target" >/dev/null
      cast rpc --rpc-url "$RPC_URL" evm_mine >/dev/null
    else
      sleep "$POLL_INTERVAL"
    fi
  done
}
send "$ASSET" 'mint(address,uint256)' "$ACCOUNT" 1000000000000000000000
send "$ASSET" 'approve(address,uint256)' "$VAULT" 1000000000000000000000
send "$VAULT" 'deposit(uint256,address)' 1000000000000000000000 "$ACCOUNT"
send "$VAULT" 'delegate(address)' "$ACCOUNT"
CHECKPOINT=$(clock_value vote)
wait_after vote "$CHECKPOINT"
ASSETS_BEFORE=$(call "$VAULT" 'totalAssets()(uint256)' | number)
SHARES_BEFORE=$(call "$VAULT" 'balanceOf(address)(uint256)' "$ACCOUNT" | number)
CUT=$(cast calldata 'diamondCut((address,uint8,bytes4[])[],address,bytes)' \
  "[($PROBE,0,[$SELECTOR])]" 0x0000000000000000000000000000000000000000 0x)
DESCRIPTION='ENS grant example: add grantVersion'
HASH=$(cast keccak "$DESCRIPTION")
TARGETS="[$VAULT]"
VALUES='[0]'
CALLS="[$CUT]"
ID=$(call "$VAULT" 'hashProposal(address[],uint256[],bytes[],bytes32)(uint256)' "$TARGETS" "$VALUES" "$CALLS" "$HASH" | number)
send "$VAULT" 'propose(address[],uint256[],bytes[],string)' "$TARGETS" "$VALUES" "$CALLS" "$DESCRIPTION"
SNAPSHOT=$(call "$VAULT" 'proposalSnapshot(uint256)(uint256)' "$ID" | number)
wait_after vote "$SNAPSHOT"
send "$VAULT" 'castVote(uint256,uint8)' "$ID" 1
DEADLINE=$(call "$VAULT" 'proposalDeadline(uint256)(uint256)' "$ID" | number)
wait_after vote "$DEADLINE"
send "$VAULT" 'queue(address[],uint256[],bytes[],bytes32)' "$TARGETS" "$VALUES" "$CALLS" "$HASH"
ETA=$(call "$VAULT" 'proposalEta(uint256)(uint256)' "$ID" | number)
wait_after time "$ETA"
send "$VAULT" 'execute(address[],uint256[],bytes[],bytes32)' "$TARGETS" "$VALUES" "$CALLS" "$HASH"
[[ "$(call "$VAULT" 'grantVersion()(uint256)' | number)" == 2 ]] || fail 'upgrade selector did not return version 2'
[[ "$(call "$VAULT" 'totalAssets()(uint256)' | number)" == "$ASSETS_BEFORE" ]] || fail 'vault assets changed during governance'
[[ "$(call "$VAULT" 'balanceOf(address)(uint256)' "$ACCOUNT" | number)" == "$SHARES_BEFORE" ]] || fail 'share balance changed during governance'
echo "Governed upgrade verified at $VAULT; grantVersion() = 2; assets and shares preserved."
