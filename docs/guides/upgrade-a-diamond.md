# Upgrade a diamond

A governed upgrade changes routes and initializes new state in the same transaction. This walkthrough
adds the independent RateLimiter utility to a live self-governed vault through its real
proposal → vote → queue → timelock → execution path. It does not change how vault transfers work.

Use the pinned Foundry **1.9.0**, Solidity **0.8.36** and **Cancun** configuration, Git and jq.
Run the Bash blocks in order from a Lattice checkout. This example creates a fresh, private Anvil
fixture. Its addresses and open-faucet asset are **not canonical release or public chain evidence**.
For an existing application, select reviewed frozen release addresses and verify their code hashes;
see [release integration](integrate-lattice.md).

## 1. Classify the cut and its initialization

Record every selector as Add, Replace or Remove, its previous and intended owner, any new storage
namespace, and the required initialization. Replace must preserve the old state; Remove does not erase it.
Check selector seams and [movement-policy compatibility](selector-compatibility.md) before composing modules.

Here all four RateLimiter selectors are **Add**, its ERC-7201 namespace is new to this vault, and
RateLimiterInit registers the interface. A following configuration step fills one bucket. Both execute
inside ReinitMultiInit's window. The vault's original AccessControl bootstrap identity is the vault
itself; the new init must preserve that identity.

Start a node that this shell owns. The guard requires a loopback Anvil endpoint on chain31337 before
every transaction or time change:

```bash
set -euo pipefail
export FOUNDRY_PROFILE=ci
RPC_URL=http://127.0.0.1:18561
ACCOUNT=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
LAB=$(mktemp -d)
if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
  echo 'Port18561 is occupied; choose another unused port.' >&2
  exit 1
fi
anvil --host 127.0.0.1 --port 18561 --hardfork cancun > "$LAB/anvil.log" 2>&1 &
ANVIL_PID=$!
trap 'kill "$ANVIL_PID" 2>/dev/null || true; wait "$ANVIL_PID" 2>/dev/null || true; rm -rf "$LAB"' EXIT
for _ in {1..50}; do
  kill -0 "$ANVIL_PID"
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
local_rpc() {
  [[ "$RPC_URL" =~ ^http://(localhost|127\.0\.0\.1|\[::1\])(:[0-9]+)?/?$ ]] || return 1
  test "$(cast chain-id --rpc-url "$RPC_URL")" = 31337 || return 1
  [[ "$(cast rpc --rpc-url "$RPC_URL" web3_clientVersion)" == *[Aa]nvil* ]] || return 1
}
local_rpc
git submodule update --init --recursive
make example-ens-grant-m2 LOCAL=1 VERIFY=0 WAIT_TIMEOUT=60 RPC="$RPC_URL" | tee "$LAB/baseline.log"
VAULT=$(awk '$1=="VAULT" {print $2}' "$LAB/baseline.log" | tail -1)
[[ "$VAULT" =~ ^0x[[:xdigit:]]{40}$ ]]
```

The existing example runner atomically deploys the vault, funds/delegates its voter and performs its
probe upgrade without an init. The vault is now live, its initialized version is still1, and its cut
registry contains one successful upgrade. Governance and the co-located timelock are the existing
upgrade authority; neither this procedure nor ReinitMultiInit grants a new executor.

## 2. Check storage against a trusted baseline

Review the candidate layouts against the deployed build's reviewed baseline. For a state-preserving
upgrade, retain each live namespace and interface ID and use compatible, normally append-only storage.
A deliberately incompatible layout needs a tested migration or a fresh deployment; passing a source
check against an unrelated branch does not establish compatibility with your instance.

The local checkout check and the governed regression run with these existing commands:

```bash
make storage-check BASE_REF=origin/dev
forge test --match-contract 'GovernedVaultUpgradeTest|ReinitMultiInitTest'
```

The test uses the real vault lifecycle, adds/configures the module, rejects equal/lower versions
through distinct proposals, and proves that a later failing step rolls back the cut, interface,
bucket, version and governance/timelock execution writes. It then retries the same next version successfully.
For your deployment, replace origin/dev with the trusted source baseline in the storage comparison,
and review custom storage and migrations separately. The live-layout policy is in
[project guidance](../../AGENTS.md#solidity-architecture-and-storage).

## 3. Read the current version and select a greater one

The stable slot is `0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132`:
bit0 is the initializing flag and bits1–64 are the uint64 version.
Read at a recorded block. These native commands mask the shifted value to64 bits and print its
full decimal value, avoiding signed64 Bash arithmetic:

```bash
INIT_SLOT=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132
BLOCK=$(cast block-number --rpc-url "$RPC_URL")
INIT_WORD=$(cast storage "$VAULT" "$INIT_SLOT" --block "$BLOCK" --rpc-url "$RPC_URL")
case "${INIT_WORD: -1}" in
  [13579bBdDfF]) echo 'Initialization window is open; stop.' >&2; exit 1 ;;
esac
SHIFTED=$(cast shr "$INIT_WORD" 1)
LOW64="0000000000000000${SHIFTED#0x}"
CURRENT=$(cast to-dec "0x${LOW64: -16}")
printf 'At block%s, initialized version is%s\n' "$BLOCK" "$CURRENT"
test "$CURRENT" = 1
VERSION=2
```

Version2 is the explicit choice for this version1 fixture. In an application, choose a reviewed
uint64 strictly greater than the observed version; never truncate through floating-point JSON or
automatically assume the next integer is available. uint64 maximum is terminal.
Even an empty successful batch or a zero-address terminator advances the version.
See the [stable read contract](../../STORAGE_REGISTRY.md#initialization-version-read).

## 4. Propose, vote, queue and execute the initialized cut

Deploy three **local fixture implementations** with the existing Forge command. For a real release,
use the matching frozen-manifest identities instead. The fixture deployment checks each runtime
against this build's artifact:

```bash
deploy_fixture() {
  local artifact="$1" name="$2" at expected
  local_rpc || return 1
  forge create "$artifact" --rpc-url "$RPC_URL" --from "$ACCOUNT" --unlocked --broadcast --json > "$LAB/deploy.json" || return 1
  at=$(jq -er .deployedTo "$LAB/deploy.json") || return 1
  expected=$(jq -r '.deployedBytecode.object' "out/$name.sol/$name.json" | cast keccak) || return 1
  test "$(cast code "$at" --rpc-url "$RPC_URL" | cast keccak)" = "$expected" || return 1
  printf '%s\n' "$at"
}
LIMITER=$(deploy_fixture src/security/RateLimiter.sol:RateLimiter RateLimiter)
MODULE_INIT=$(deploy_fixture src/security/RateLimiterInit.sol:RateLimiterInit RateLimiterInit)
BATCH=$(deploy_fixture src/utils/ReinitMultiInit.sol:ReinitMultiInit ReinitMultiInit)

number() { awk 'NR==1 {print $1}'; }
send() {
  local receipt
  local_rpc || return 1
  receipt=$(cast send "$@" --rpc-url "$RPC_URL" --from "$ACCOUNT" --unlocked --json) || return 1
  jq -e '.status=="0x1" or .status==1' <<< "$receipt" >/dev/null
}
advance_after() {
  local target="$1" now
  [[ "$target" =~ ^[0-9]+$ && ${#target} -le 15 ]] || return 1
  target=$((10#$target + 1))
  local_rpc || return 1
  now=$(cast block latest --rpc-url "$RPC_URL" --field timestamp | number)
  if (( now < target )); then
    local_rpc || return 1
    cast rpc --rpc-url "$RPC_URL" evm_setNextBlockTimestamp "$target" >/dev/null || return 1
    cast rpc --rpc-url "$RPC_URL" evm_mine >/dev/null || return 1
  fi
}
PACKED=$(cast call "$LIMITER" 'exportSelectors()(bytes)' --rpc-url "$RPC_URL")
SELECTORS=$(jq -nr --arg packed "$PACKED" '$packed[2:] | "["+([scan(".{8}")|"0x"+.]|join(","))+"]"')
KEY=$(cast keccak governed-upgrade-example)
STEP_INIT=$(cast calldata 'init(address)' "$VAULT")
STEP_CONFIG=$(cast calldata 'configure(bytes32,uint256,uint256)' "$KEY" 100 1)
INIT_DATA=$(cast calldata 'reinitMulti(uint64,address[],bytes[])' "$VERSION" "[$MODULE_INIT,$LIMITER]" "[$STEP_INIT,$STEP_CONFIG]")
CUT=$(cast calldata 'diamondCut((address,uint8,bytes4[])[],address,bytes)' "[($LIMITER,0,$SELECTORS)]" "$BATCH" "$INIT_DATA")
TARGETS="[$VAULT]"
VALUES='[0]'
CALLS="[$CUT]"
DESCRIPTION='Guide: add and initialize RateLimiter at version2'
HASH=$(cast keccak "$DESCRIPTION")
ID=$(cast call "$VAULT" 'hashProposal(address[],uint256[],bytes[],bytes32)(uint256)' "$TARGETS" "$VALUES" "$CALLS" "$HASH" --rpc-url "$RPC_URL" | number)
SHARES=$(cast call "$VAULT" 'balanceOf(address)(uint256)' "$ACCOUNT" --rpc-url "$RPC_URL" | number)
ASSETS=$(cast call "$VAULT" 'totalAssets()(uint256)' --rpc-url "$RPC_URL" | number)
test "$(cast call "$VAULT" 'cutCount()(uint256)' --rpc-url "$RPC_URL" | number)" = 1

send "$VAULT" 'propose(address[],uint256[],bytes[],string)' "$TARGETS" "$VALUES" "$CALLS" "$DESCRIPTION"
SNAPSHOT=$(cast call "$VAULT" 'proposalSnapshot(uint256)(uint256)' "$ID" --rpc-url "$RPC_URL" | number)
advance_after "$SNAPSHOT"
send "$VAULT" 'castVote(uint256,uint8)' "$ID" 1
DEADLINE=$(cast call "$VAULT" 'proposalDeadline(uint256)(uint256)' "$ID" --rpc-url "$RPC_URL" | number)
advance_after "$DEADLINE"
send "$VAULT" 'queue(address[],uint256[],bytes[],bytes32)' "$TARGETS" "$VALUES" "$CALLS" "$HASH"
if cast call "$VAULT" 'execute(address[],uint256[],bytes[],bytes32)' "$TARGETS" "$VALUES" "$CALLS" "$HASH" --from "$ACCOUNT" --rpc-url "$RPC_URL" > "$LAB/early.log" 2>&1; then
  echo 'Expected the timelock delay to prevent early execution.' >&2; exit 1
fi
ETA=$(cast call "$VAULT" 'proposalEta(uint256)(uint256)' "$ID" --rpc-url "$RPC_URL" | number)
advance_after "$ETA"
send "$VAULT" 'execute(address[],uint256[],bytes[],bytes32)' "$TARGETS" "$VALUES" "$CALLS" "$HASH"
```

The timelock's external self-call makes the cut and both delegate steps see the vault as caller.
RateLimiterInit preserves that original admin; the second step uses the newly initialized module's
configure function under the same existing authority. Never route reinitMulti as a facet, invoke
the helper directly to initialize a diamond, or split initial proxy deployment from initialization.
Order any real dependencies deliberately. An unrelated configuration function is not automatically
safe merely because it fits in the batch.

## 5. Verify routes, discovery, state and replay protection

Verify every selected route, inspect the facet selector list, read the registered interface and bucket,
then confirm the version/window and original vault state:

```bash
for selector in $(jq -nr --arg packed "$PACKED" '$packed[2:]|scan(".{8}")|"0x"+.'); do
  routed=$(cast call "$VAULT" 'facetAddress(bytes4)(address)' "$selector" --rpc-url "$RPC_URL")
  test "$(printf '%s' "$routed" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$LIMITER" | tr '[:upper:]' '[:lower:]')"
done
cast call "$VAULT" 'facetFunctionSelectors(address)(bytes4[])' "$LIMITER" --rpc-url "$RPC_URL"
test "$(cast call "$VAULT" 'supportsInterface(bytes4)(bool)' 0x9afe0493 --rpc-url "$RPC_URL")" = true
cast call "$VAULT" 'getConfig(bytes32)(uint256,uint256)' "$KEY" --rpc-url "$RPC_URL"
test "$(cast call "$VAULT" 'getAvailable(bytes32)(uint256)' "$KEY" --rpc-url "$RPC_URL" | number)" = 100
test "$(cast to-dec "$(cast storage "$VAULT" "$INIT_SLOT" --rpc-url "$RPC_URL")")" = 4
test "$(cast call "$VAULT" 'state(uint256)(uint8)' "$ID" --rpc-url "$RPC_URL" | number)" = 7
test "$(cast call "$VAULT" 'cutCount()(uint256)' --rpc-url "$RPC_URL" | number)" = 2
test "$(cast call "$VAULT" 'balanceOf(address)(uint256)' "$ACCOUNT" --rpc-url "$RPC_URL" | number)" = "$SHARES"
test "$(cast call "$VAULT" 'totalAssets()(uint256)' --rpc-url "$RPC_URL" | number)" = "$ASSETS"

for rejected_version in 2 1; do
  REPLAY_DATA=$(cast calldata 'reinitMulti(uint64,address[],bytes[])' "$rejected_version" "[$MODULE_INIT,$LIMITER]" "[$STEP_INIT,$STEP_CONFIG]")
  if cast call "$VAULT" 'diamondCut((address,uint8,bytes4[])[],address,bytes)' '[]' "$BATCH" "$REPLAY_DATA" --from "$VAULT" --rpc-url "$RPC_URL" > "$LAB/replay.log" 2>&1; then
    echo 'Expected the non-increasing version to revert.' >&2; exit 1
  fi
  ERROR=$(cast sig 'InvalidInitialization()')
  grep -q "${ERROR#0x}" "$LAB/replay.log"
done
```

The last calls are read-only simulations with the timelock's self-call sender. They grant no
transaction authority. The governed tests in step2 additionally vote and queue distinct proposals for
equal/lower versions, proving rejection reaches the reinitializer rather than a reused proposal ID.
Successful governance execution consumes a proposal; it cannot be executed again.

Keep the transaction receipt, observed block, cut/init calldata and verification results with your
deployment records. [Release chain observations](integrate-lattice.md#errors-and-chain-observations)
track shared implementations separately from application upgrade evidence. These local checks do
not certify external dependencies or storage migrations.

Stop the node and remove only this shell's temporary files:

```bash
kill "$ANVIL_PID"
wait "$ANVIL_PID" 2>/dev/null || true
rm -rf "$LAB"
trap - EXIT
```

