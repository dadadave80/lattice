#!/usr/bin/env bash
# Proves recipe scripts create and initialize Lattice proxies in ONE transaction (through LatticeFactory).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
fail() { echo "atomic-deploy: $*" >&2; exit 1; }
RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
ACCOUNT=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
SCRIPT=script/base/access/DeployAccessControl.s.sol:DeployAccessControl
LOG=broadcast/DeployAccessControl.s.sol/31337/run-latest.json

if grep -rnE 'new Lattice[({]|\.initialize\(' script --include='*.sol'; then
  fail 'create proxies with BaseDeploy._assemble (LatticeFactory), never a separate initialize'
fi

[[ "$(cast chain-id --rpc-url "$RPC_URL")" == 31337 ]] || fail 'requires a local Anvil (chain 31337)'
[[ ! -f .env ]] || ! grep -qE '^(LATTICE_FACTORY|LATTICE_SALT)=' .env || fail 'remove LATTICE_FACTORY/LATTICE_SALT from .env'

deploy() {
  forge script "$SCRIPT" --sig 'run(address)' "$ACCOUNT" \
    --rpc-url "$RPC_URL" --unlocked --sender "$ACCOUNT" --broadcast --slow
}
count() { jq "[.transactions[] | select($1)] | length" "$LOG"; }

deploy > /dev/null
[[ "$(count '(.function // "") | startswith("initialize(")')" == 0 ]] || fail 'broadcast contains a separate initialize transaction'
[[ "$(count '.contractName == "LatticeFactory" and ((.function // "") | startswith("deploy("))')" == 1 ]] || fail 'diamond was not deployed through LatticeFactory.deploy'
DIAMOND=$(jq -r '.returns.accessControl.value' "$LOG")
FACTORY=$(jq -r '[.transactions[] | select(.contractName == "LatticeFactory" and .transactionType == "CREATE")][0].contractAddress' "$LOG")
[[ "$(cast call "$DIAMOND" 'facetAddress(bytes4)(address)' 0x01ffc9a7 --rpc-url "$RPC_URL")" != 0x0000000000000000000000000000000000000000 ]] || fail 'diamond is not initialized'

if OUT=$(LATTICE_FACTORY=$FACTORY deploy 2>&1); then fail 'reused salt did not revert'; fi
grep -q 'set a new LATTICE_SALT' <<< "$OUT" || fail "unexpected failure: $OUT"

LATTICE_FACTORY=$FACTORY LATTICE_SALT=0x0000000000000000000000000000000000000000000000000000000000000001 deploy > /dev/null
[[ "$(count '.contractName == "LatticeFactory" and .transactionType == "CREATE"')" == 0 ]] || fail 'LATTICE_FACTORY was ignored'
echo "Atomic recipe deployment verified: $DIAMOND via $FACTORY"
