#!/usr/bin/env bash
# forge, pinned for Hedera.
#
# By default, Foundry 1.8 fetches fork state with EIP-1898 block-hash objects, and Hedera's JSON-RPC relay
# (hiero-json-rpc-relay) rejects them with `-32602 Invalid parameter 1 ... [object Object]`, so neither
# `forge script` nor a forking test can reach Hedera. Foundry 1.7.1 sends a block number (or "latest") and
# works. Re-measured 2026-10-08 against hashio (relay/0.79.0): 1.8.1, 1.8.3 and 1.8.5 fail by default and
# 1.7.1 passes. 1.8.5's `--fork-state-by-number` also passes a simulation and the forking test, but no
# broadcast has been made with it yet, so Hedera work still runs on the 1.7.1 binary directly (#227). The
# global `forge` and CI stay on the shared pin. Under [profile.hedera], 1.7.1 and 1.8.5 build identical
# src/ bytecode, metadata included, so this pin does not change what gets deployed.
#
# Usage: script/config/hedera/forge-hedera.sh <forge args...>
#   script/config/hedera/forge-hedera.sh script script/base/tokens/DeployHTSAdapter.s.sol \
#     --sig "run(address)" <ADMIN> --rpc-url hedera-testnet --account <keystore> --broadcast --slow --legacy
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../../.."

version="${HEDERA_FORGE_VERSION:-v1.7.1}"
forge="${FOUNDRY_DIR:-$HOME/.foundry}/versions/foundry-rs/foundry/${version}/forge"

if [[ ! -x "$forge" ]]; then
    echo "error: forge ${version} is not installed (expected ${forge})" >&2
    echo "install it with 'foundryup --install ${version}', then re-select your usual version with" >&2
    echo "'foundryup --use <version>' if foundryup made ${version} the active one" >&2
    exit 1
fi

export FOUNDRY_PROFILE=hedera
exec "$forge" "$@"
