#!/usr/bin/env bash
# forge, pinned for Hedera.
#
# `forge script` on Foundry >= 1.8 cannot reach Hedera: its fork backend asks the relay for account state
# with EIP-1898 block-hash objects, and Hedera's JSON-RPC relay (hiero-json-rpc-relay) rejects them with
# `-32602 Invalid parameter 1 ... [object Object]`. Foundry 1.7.1 sends plain "latest" and works. Whether
# the fix belongs in Foundry or in the relay is still open, so until it is resolved Hedera work runs on the
# 1.7.1 binary directly — the global `forge` and CI stay on the shared pin.
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
