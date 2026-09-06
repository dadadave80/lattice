#!/usr/bin/env bash
# Local Anvil only: unlocked, publicly known development account; never a real wallet.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
ACCOUNT=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
[[ "$(cast chain-id --rpc-url "$RPC_URL")" == 31337 ]] || { echo 'Requires local Anvil chain 31337'; exit 1; }
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
forge script script/base/defi/GrantExample.s.sol:GrantExample --sig 'run()' \
  --rpc-url "$RPC_URL" --sender "$ACCOUNT" --unlocked --broadcast --slow | tee "$LOG"
VAULT=$(awk '$1 == "VAULT" {print $2}' "$LOG")
ASSET=$(awk '$1 == "ASSET" {print $2}' "$LOG")
PROBE=$(awk '$1 == "PROBE" {print $2}' "$LOG")
[[ "$VAULT" =~ ^0x[[:xdigit:]]{40}$ && "$ASSET" =~ ^0x[[:xdigit:]]{40}$ && "$PROBE" =~ ^0x[[:xdigit:]]{40}$ ]]
send() { cast send --rpc-url "$RPC_URL" --from "$ACCOUNT" --unlocked "$@" >/dev/null; }
call() { cast call --rpc-url "$RPC_URL" "$@"; }
number() { awk '{print $1}'; }
advance() {
  cast rpc --rpc-url "$RPC_URL" evm_setNextBlockTimestamp "$1" >/dev/null
  cast rpc --rpc-url "$RPC_URL" evm_mine >/dev/null
}
send "$ASSET" 'mint(address,uint256)' "$ACCOUNT" 1000000000000000000000
send "$ASSET" 'approve(address,uint256)' "$VAULT" 1000000000000000000000
send "$VAULT" 'deposit(uint256,address)' 1000000000000000000000 "$ACCOUNT"
send "$VAULT" 'delegate(address)' "$ACCOUNT"
cast rpc --rpc-url "$RPC_URL" evm_increaseTime 1 >/dev/null
cast rpc --rpc-url "$RPC_URL" evm_mine >/dev/null
SELECTOR=$(cast sig 'grantVersion()')
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
advance "$((SNAPSHOT + 1))"
send "$VAULT" 'castVote(uint256,uint8)' "$ID" 1
DEADLINE=$(call "$VAULT" 'proposalDeadline(uint256)(uint256)' "$ID" | number)
advance "$((DEADLINE + 1))"
send "$VAULT" 'queue(address[],uint256[],bytes[],bytes32)' "$TARGETS" "$VALUES" "$CALLS" "$HASH"
ETA=$(call "$VAULT" 'proposalEta(uint256)(uint256)' "$ID" | number)
advance "$((ETA + 1))"
send "$VAULT" 'execute(address[],uint256[],bytes[],bytes32)' "$TARGETS" "$VALUES" "$CALLS" "$HASH"
[[ "$(call "$VAULT" 'grantVersion()(uint256)' | number)" == 2 ]]
[[ "$(call "$VAULT" 'totalAssets()(uint256)' | number)" == 1000000000000000000000 ]]
echo "Governed upgrade verified at $VAULT; grantVersion() = 2; assets preserved."
