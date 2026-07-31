#!/usr/bin/env bash
# CCTP receipt demo: Arc -> Base USDC delivered directly to a recipient, plus an on-chain receipt NFT.
# Usage:
#   script/config/cctp-hook-receipt-demo.sh [--deploy-only] [actor] [recipient]
#   make demo-cctp-receipt KEYSTORE=<name> | PRIVATE_KEY=0x<testnet-key>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

SCRIPT_TARGET="script/base/crosschain/CCTPHookReceiptDemo.s.sol:CCTPHookReceiptDemo"
ARC_DOMAIN=26
BASE_DOMAIN=6
ARC_USDC="0x3600000000000000000000000000000000000000"
ARC_EXPLORER="https://testnet.arcscan.app"
BASE_EXPLORER="https://base-sepolia.blockscout.com"
CANON_ARC_HUB="0x6ca99B6179eAc891E3aCD4008b610fcE66F63E2d"
CANON_BASE_DIAMOND="0x957259C5AEAa521c9DcFaEb6692C25ae53F349f1"

JOURNAL=".cctp-demo.receipt.env"
STACK_JOURNAL=".cctp-demo.deployment.env"
DEPLOY_JOURNAL=".cctp-demo.receipt-deployment.env"
IRIS_API="${IRIS_API:-https://iris-api-sandbox.circle.com}"
IRIS_POLL_SECONDS="${IRIS_POLL_SECONDS:-5}"
ATTEST_TIMEOUT_SECONDS="${ATTEST_TIMEOUT_SECONDS:-300}"
AMOUNT="${AMOUNT:-1000000}"
FORGE_AUTH="${FORGE_AUTH:-}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_INFO=$'\033[0;36m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'; C_OFF=$'\033[0m'
else
    C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_OFF=''
fi
info() { echo "${C_INFO}[receipt-demo]${C_OFF} $*"; }
ok() { echo "${C_OK}[receipt-demo]${C_OFF} $*"; }
warn() { echo "${C_WARN}[receipt-demo]${C_OFF} $*" >&2; }
err() { echo "${C_ERR}[receipt-demo] ERROR:${C_OFF} $*" >&2; }

is_addr() { [[ "$1" =~ ^0x[0-9a-fA-F]{40}$ ]]; }
lower() { tr '[:upper:]' '[:lower:]' <<<"$1"; }

kv_get() {
    local file="$1" key="$2" line value=""
    [[ -f "${file}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == "${key}="* ]] && value="${line#*=}"
    done <"${file}"
    printf '%s' "${value}"
}
kv_set() {
    local file="$1" key="$2" value="$3" tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    { [[ -f "${file}" ]] && grep -vE "^${key}=" "${file}" || true; echo "${key}=${value}"; } >"${tmp}"
    mv "${tmp}" "${file}"
}
jget() { kv_get "${JOURNAL}" "$1"; }
jset() { kv_set "${JOURNAL}" "$1" "$2"; }

resolve_rpc() {
    local var="$1" value="${!1:-}"
    if [[ -z "${value}" && -f .env ]]; then
        value="$(sed -n "s/^${var}=//p" .env | tail -1)"
        value="${value%\"}"; value="${value#\"}"; value="${value%\'}"; value="${value#\'}"
    fi
    printf '%s' "${value}"
}

for bin in forge cast jq curl; do
    command -v "${bin}" >/dev/null 2>&1 || { err "${bin} not found on PATH"; exit 2; }
done

BASE_RPC="$(resolve_rpc BASE_SEPOLIA_RPC_URL)"
ARC_RPC="$(resolve_rpc ARC_TESTNET_RPC_URL)"
[[ -n "${BASE_RPC}" ]] || { err "BASE_SEPOLIA_RPC_URL is not set (shell or .env)."; exit 2; }

DEPLOY_ONLY=0
ACTOR=""
RECIPIENT=""
for arg in "$@"; do
    if [[ "${arg}" == "--deploy-only" ]]; then DEPLOY_ONLY=1; continue; fi
    is_addr "${arg}" || { err "not a 20-byte address: ${arg}"; exit 2; }
    if [[ -z "${ACTOR}" ]]; then ACTOR="${arg}"; elif [[ -z "${RECIPIENT}" ]]; then RECIPIENT="${arg}"; else
        err "expected [--deploy-only] [actor] [recipient]"; exit 2
    fi
done

BASE_DIAMOND="${DEMO_BASE_DIAMOND:-$(kv_get "${STACK_JOURNAL}" BASE_DIAMOND)}"
[[ -n "${BASE_DIAMOND}" ]] || BASE_DIAMOND="${CANON_BASE_DIAMOND}"
is_addr "${BASE_DIAMOND}" || { err "invalid Base diamond: ${BASE_DIAMOND}"; exit 2; }

[[ -n "${FORGE_AUTH}" ]] || {
    err "no signer. Use KEYSTORE=<name>, PRIVATE_KEY=0x<testnet-key>, or FORGE_AUTH."
    exit 2
}
if [[ -z "${ACTOR}" ]]; then
    # shellcheck disable=SC2086
    ACTOR="$(cast wallet address ${FORGE_AUTH} 2>/dev/null || true)"
fi
is_addr "${ACTOR}" || { err "could not derive a signer address; pass actor explicitly."; exit 2; }

if (( DEPLOY_ONLY == 1 )); then
    [[ ! -f "${DEPLOY_JOURNAL}" ]] || {
        err "${DEPLOY_JOURNAL} already exists; refusing to overwrite it."
        err "remove it only when you intentionally want a different receipt deployment."
        exit 2
    }
    info "deploying one CCTPHookReceipt against Base diamond ${BASE_DIAMOND}..."
    rc=0
    # shellcheck disable=SC2086
    output="$(ETHERSCAN_API_KEY='' forge script "${SCRIPT_TARGET}" --sig 'receiptDemoSetup(address)' "${BASE_DIAMOND}" \
        ${FORGE_AUTH} --broadcast --verify --verifier sourcify 2>&1)" || rc=$?
    (( rc == 0 )) || { err "receipt deployment failed."; exit "${rc}"; }
    setup="$(grep -oE 'DEMO-RECEIPT-SETUP 0x[0-9a-fA-F]{40} 0x[0-9a-fA-F]{40}' <<<"${output}" | tail -1)"
    read -r _ RECEIPT EXECUTOR <<<"${setup}"
    if ! is_addr "${RECEIPT:-}" || ! is_addr "${EXECUTOR:-}"; then
        err "deployment succeeded but addresses were not parsed."; exit 1
    fi
    kv_set "${DEPLOY_JOURNAL}" BASE_DIAMOND "${BASE_DIAMOND}"
    kv_set "${DEPLOY_JOURNAL}" RECEIPT "${RECEIPT}"
    kv_set "${DEPLOY_JOURNAL}" EXECUTOR "${EXECUTOR}"
    ok "receipt deployed: ${BASE_EXPLORER}/address/${RECEIPT}"
    exit 0
fi

[[ -n "${ARC_RPC}" ]] || { err "ARC_TESTNET_RPC_URL is not set (shell or .env)."; exit 2; }
[[ -n "${RECIPIENT}" ]] || RECIPIENT="${ACTOR}"

ARC_HUB="${DEMO_ARC_HUB:-$(kv_get "${STACK_JOURNAL}" ARC_HUB)}"
[[ -n "${ARC_HUB}" ]] || ARC_HUB="${CANON_ARC_HUB}"
RECEIPT="${DEMO_RECEIPT:-$(kv_get "${DEPLOY_JOURNAL}" RECEIPT)}"
DEPLOY_BASE="$(kv_get "${DEPLOY_JOURNAL}" BASE_DIAMOND)"

is_addr "${ARC_HUB}" || { err "invalid Arc hub: ${ARC_HUB}"; exit 2; }
is_addr "${RECEIPT}" || {
    err "no CCTPHookReceipt deployment found."
    err "run make deploy-cctp-receipt ... or set DEMO_RECEIPT."
    exit 2
}
if [[ -n "${DEPLOY_BASE}" && "$(lower "${DEPLOY_BASE}")" != "$(lower "${BASE_DIAMOND}")" ]]; then
    err "receipt journal is bound to ${DEPLOY_BASE}, not selected Base diamond ${BASE_DIAMOND}."
    exit 2
fi
if [[ ! "${AMOUNT}" =~ ^[0-9]+$ ]] || (( AMOUNT == 0 || AMOUNT > 1000000000000 )); then
    err "AMOUNT must be 1..1000000000000 raw USDC units."; exit 2
fi

# A resumed run is bound to its original value-moving inputs.
if [[ -n "$(jget DEPLOYMENT)" ]]; then
    IFS=: read -r ARC_HUB BASE_DIAMOND RECEIPT <<<"$(jget DEPLOYMENT)"
    ACTOR="$(jget ACTOR)"; RECIPIENT="$(jget RECIPIENT)"; AMOUNT="$(jget AMOUNT)"
    info "resuming journaled run."
fi

# Pre-burn trust/routing checks.
receipt_executor="$(cast call "${RECEIPT}" "executor()(address)" --rpc-url "${BASE_RPC}" 2>/dev/null | tail -1 || true)"
diamond_executor="$(cast call "${BASE_DIAMOND}" "hookExecutor()(address)" --rpc-url "${BASE_RPC}" 2>/dev/null | tail -1 || true)"
if ! is_addr "${receipt_executor}" || ! is_addr "${diamond_executor}"; then
    err "could not read hook executors."; exit 1
fi
[[ "$(lower "${receipt_executor}")" == "$(lower "${diamond_executor}")" ]] || {
    err "receipt executor ${receipt_executor} does not match diamond executor ${diamond_executor}."; exit 1;
}
domain_config="$(cast call "${ARC_HUB}" "getDomainConfig(uint32)(uint256,uint32,bytes32)" "${BASE_DOMAIN}" --rpc-url "${ARC_RPC}" 2>/dev/null || true)"
destination_caller="$(tail -1 <<<"${domain_config}")"
[[ "${destination_caller}" =~ ^0x[0-9a-fA-F]{64}$ ]] || { err "could not read Arc hub Base-domain config."; exit 1; }
[[ "$(lower "0x${destination_caller:26}")" == "$(lower "${BASE_DIAMOND}")" ]] || {
    err "Arc hub destinationCaller is not the selected Base diamond; refusing to burn."; exit 1;
}

info "actor=${ACTOR} recipient=${RECIPIENT} amount=${AMOUNT}"
info "hub=${ARC_HUB} diamond=${BASE_DIAMOND} receipt=${RECEIPT}"

BURN_TX="$(jget BURN_TX)"
if [[ -z "${BURN_TX}" ]]; then
    [[ -z "$(jget BURN_ATTEMPTED)" ]] || {
        err "a burn may have dispatched without a recorded hash."
        err "inspect ${ARC_EXPLORER}/address/${ACTOR}; then add BURN_TX or remove BURN_ATTEMPTED only if absent."
        exit 1
    }

    arc_line="$(forge script "${SCRIPT_TARGET}" --sig 'receiptDemoArcBalance(address)' "${ACTOR}" --sender "${ACTOR}" 2>&1 \
        | grep -oE 'DEMO-RECEIPT-ARCBAL [0-9]+' | tail -1 || true)"
    ARC_BAL="${arc_line##* }"
    [[ "${ARC_BAL}" =~ ^[0-9]+$ ]] || { err "could not read Arc USDC balance."; exit 1; }
    (( ARC_BAL > AMOUNT )) || {
        err "Arc balance ${ARC_BAL} must exceed amount ${AMOUNT}; Arc USDC also pays gas."; exit 1;
    }

    base_line="$(forge script "${SCRIPT_TARGET}" --sig 'receiptDemoBaseBalance(address)' "${RECIPIENT}" --sender "${ACTOR}" 2>&1 \
        | grep -oE 'DEMO-RECEIPT-BASEBAL [0-9]+' | tail -1 || true)"
    nft_line="$(forge script "${SCRIPT_TARGET}" --sig 'receiptDemoNftBalance(address,address)' "${RECEIPT}" "${RECIPIENT}" --sender "${ACTOR}" 2>&1 \
        | grep -oE 'DEMO-RECEIPT-NFTBAL [0-9]+' | tail -1 || true)"
    BASE_BEFORE="${base_line##* }"; NFT_BEFORE="${nft_line##* }"
    [[ "${BASE_BEFORE}" =~ ^[0-9]+$ && "${NFT_BEFORE}" =~ ^[0-9]+$ ]] || { err "could not read Base baselines."; exit 1; }

    recipient_line="$(forge script "${SCRIPT_TARGET}" --sig 'receiptDemoRecipient(address)' "${RECIPIENT}" --sender "${ACTOR}" 2>&1 \
        | grep -oE 'DEMO-RECEIPT-RECIPIENT 0x[0-9a-fA-F]+' | tail -1 || true)"
    envelope_line="$(forge script "${SCRIPT_TARGET}" --sig 'receiptDemoEnvelope(address)' "${RECEIPT}" --sender "${ACTOR}" 2>&1 \
        | grep -oE 'DEMO-RECEIPT-ENVELOPE 0x[0-9a-fA-F]+' | tail -1 || true)"
    CCTP_RECIPIENT="${recipient_line##* }"; ENVELOPE="${envelope_line##* }"
    [[ "${CCTP_RECIPIENT}" =~ ^0x[0-9a-fA-F]+$ && "${ENVELOPE}" =~ ^0x[0-9a-fA-F]{48}$ ]] || {
        err "could not encode recipient or 24-byte hook envelope."; exit 1;
    }

    jset DEPLOYMENT "${ARC_HUB}:${BASE_DIAMOND}:${RECEIPT}"
    jset ACTOR "${ACTOR}"; jset RECIPIENT "${RECIPIENT}"; jset AMOUNT "${AMOUNT}"
    jset BASE_USDC_BEFORE "${BASE_BEFORE}"; jset NFT_BALANCE_BEFORE "${NFT_BEFORE}"

    info "approving ${AMOUNT} Arc USDC..."
    # shellcheck disable=SC2086
    cast send "${ARC_USDC}" "approve(address,uint256)" "${ARC_HUB}" "${AMOUNT}" ${FORGE_AUTH} --rpc-url "${ARC_RPC}" >/dev/null
    jset BURN_ATTEMPTED 1
    info "burning toward Base recipient with receipt hook..."
    rc=0
    # shellcheck disable=SC2086
    burn_output="$(cast send "${ARC_HUB}" "depositForBurnWithHook(uint256,bytes,bytes)" "${AMOUNT}" "${CCTP_RECIPIENT}" \
        "${ENVELOPE}" ${FORGE_AUTH} --rpc-url "${ARC_RPC}" --json 2>/dev/null)" || rc=$?
    BURN_TX="$(jq -r '.transactionHash // empty' <<<"${burn_output}" 2>/dev/null || true)"
    [[ "${BURN_TX}" =~ ^0x[0-9a-fA-F]{64}$ ]] || {
        err "burn returned no transaction hash; inspect Arc before retrying."; exit 1;
    }
    (( rc == 0 )) || warn "cast exited ${rc} after returning ${BURN_TX}; adopting the hash."
    jset BURN_TX "${BURN_TX}"
    ok "burn: ${ARC_EXPLORER}/tx/${BURN_TX}"
fi

MESSAGE="$(jget MESSAGE)"
ATTESTATION="$(jget ATTESTATION)"
if [[ -z "${MESSAGE}" || -z "${ATTESTATION}" ]]; then
    info "waiting for Circle Iris attestation..."
    deadline=$(( SECONDS + ATTEST_TIMEOUT_SECONDS ))
    while (( SECONDS < deadline )); do
        response="$(curl -sf --retry 3 --retry-delay 2 \
            "${IRIS_API}/v2/messages/${ARC_DOMAIN}?transactionHash=${BURN_TX}" 2>/dev/null || true)"
        status="$(jq -r '.messages[0].status // empty' <<<"${response}" 2>/dev/null || true)"
        if [[ "${status}" == "complete" ]]; then
            MESSAGE="$(jq -r '.messages[0].message // empty' <<<"${response}")"
            ATTESTATION="$(jq -r '.messages[0].attestation // empty' <<<"${response}")"
            [[ "${MESSAGE}" =~ ^0x[0-9a-fA-F]+$ && "${ATTESTATION}" =~ ^0x[0-9a-fA-F]+$ ]] && break
        fi
        sleep "${IRIS_POLL_SECONDS}"
    done
    [[ -n "${MESSAGE}" && -n "${ATTESTATION}" ]] || { err "attestation timed out; re-run to resume."; exit 1; }
    jset MESSAGE "${MESSAGE}"; jset ATTESTATION "${ATTESTATION}"
fi

message_line="$(forge script "${SCRIPT_TARGET}" --sig 'receiptDemoMessage(bytes)' "${MESSAGE}" --sender "${ACTOR}" 2>&1 \
    | grep -oE 'DEMO-RECEIPT-MESSAGE .*' | tail -1 || true)"
read -r _ MSG_DOMAIN MSG_SENDER MSG_RECIPIENT MSG_GROSS MSG_FEE NET MSG_TARGET <<<"${message_line}"
if ! {
    [[ "${MSG_DOMAIN}" == "${ARC_DOMAIN}" && "$(lower "${MSG_RECIPIENT}")" == "$(lower "${RECIPIENT}")" \
        && "$(lower "${MSG_TARGET}")" == "$(lower "${RECEIPT}")" && "${NET}" =~ ^[0-9]+$ \
        && "${MSG_GROSS}" =~ ^[0-9]+$ && "${MSG_FEE}" =~ ^[0-9]+$ ]] \
        && (( MSG_GROSS - MSG_FEE == NET ))
}; then
    err "attested message does not match the selected route/recipient/receipt."; exit 1
fi

RELAY_TX="$(jget RELAY_TX)"
if [[ -z "${RELAY_TX}" ]]; then
    [[ -z "$(jget RELAY_ATTEMPTED)" ]] || {
        err "a relay may have dispatched without a recorded hash."
        err "inspect the receipt contract and Base diamond before editing ${JOURNAL}; the USDC mint may already stand."
        exit 1
    }
    info "relaying on Base: Circle mint + receipt NFT in one transaction..."
    jset RELAY_ATTEMPTED 1
    # shellcheck disable=SC2086
    forge script "${SCRIPT_TARGET}" --sig 'receiptDemoRelay(address,bytes,bytes)' "${BASE_DIAMOND}" "${MESSAGE}" \
        "${ATTESTATION}" ${FORGE_AUTH} --broadcast --rpc-url base-sepolia >/dev/null
    RELAY_TX="$(jq -r '.receipts[0].transactionHash // empty' \
        broadcast/CCTPHookReceiptDemo.s.sol/84532/receiptDemoRelay-latest.json 2>/dev/null || true)"
    [[ "${RELAY_TX}" =~ ^0x[0-9a-fA-F]{64}$ ]] || { err "relay succeeded but transaction hash was not found."; exit 1; }
    jset RELAY_TX "${RELAY_TX}"
fi

rpc_receipt="$(curl -sf -m 15 -X POST "${BASE_RPC}" -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionReceipt\",\"params\":[\"${RELAY_TX}\"]}" 2>/dev/null || true)"
event_topic="$(cast keccak 'ReceiptMinted(uint256,address,uint32,bytes32,uint256,uint64)')"
log="$(jq -c --arg a "$(lower "${RECEIPT}")" --arg t "$(lower "${event_topic}")" \
    '.result.logs[]? | select((.address | ascii_downcase) == $a and (.topics[0] | ascii_downcase) == $t)' \
    <<<"${rpc_receipt}" | head -1 || true)"
[[ -n "${log}" ]] || { err "ReceiptMinted event not found in relay transaction."; exit 1; }

TOKEN_HEX="$(jq -r '.topics[1]' <<<"${log}")"
EVENT_RECIPIENT="0x$(jq -r '.topics[2]' <<<"${log}" | cut -c27-66)"
EVENT_DOMAIN="$(cast to-dec "$(jq -r '.topics[3]' <<<"${log}")")"
EVENT_DATA="$(jq -r '.data' <<<"${log}")"
[[ "${EVENT_DATA}" =~ ^0x[0-9a-fA-F]{192}$ ]] || { err "malformed ReceiptMinted data."; exit 1; }
EVENT_SENDER="0x${EVENT_DATA:2:64}"
EVENT_AMOUNT="$(cast to-dec "0x${EVENT_DATA:66:64}")"
EVENT_RECORDED_AT="$(cast to-dec "0x${EVENT_DATA:130:64}")"
TOKEN_ID="$(cast to-dec "${TOKEN_HEX}")"

[[ "$(lower "${EVENT_RECIPIENT}")" == "$(lower "${RECIPIENT}")" && "${EVENT_DOMAIN}" == "${MSG_DOMAIN}" \
    && "$(lower "${EVENT_SENDER}")" == "$(lower "${MSG_SENDER}")" && "${EVENT_AMOUNT}" == "${NET}" ]] || {
    err "ReceiptMinted facts do not match the attested message."; exit 1;
}

OWNER="$(cast call "${RECEIPT}" "ownerOf(uint256)(address)" "${TOKEN_ID}" --rpc-url "${BASE_RPC}" | tail -1)"
URI="$(cast call "${RECEIPT}" "tokenURI(uint256)(string)" "${TOKEN_ID}" --rpc-url "${BASE_RPC}" | tail -1)"
URI="${URI%\"}"; URI="${URI#\"}"
data_line="$(forge script "${SCRIPT_TARGET}" --sig 'receiptDemoData(address,uint256)' "${RECEIPT}" "${TOKEN_ID}" --sender "${ACTOR}" 2>&1 \
    | grep -oE 'DEMO-RECEIPT-DATA .*' | tail -1 || true)"
read -r _ DATA_TOKEN DATA_DOMAIN DATA_SENDER DATA_RECIPIENT DATA_AMOUNT DATA_RECORDED_AT <<<"${data_line}"
base_line="$(forge script "${SCRIPT_TARGET}" --sig 'receiptDemoBaseBalance(address)' "${RECIPIENT}" --sender "${ACTOR}" 2>&1 \
    | grep -oE 'DEMO-RECEIPT-BASEBAL [0-9]+' | tail -1 || true)"
nft_line="$(forge script "${SCRIPT_TARGET}" --sig 'receiptDemoNftBalance(address,address)' "${RECEIPT}" "${RECIPIENT}" --sender "${ACTOR}" 2>&1 \
    | grep -oE 'DEMO-RECEIPT-NFTBAL [0-9]+' | tail -1 || true)"
BASE_AFTER="${base_line##* }"; NFT_AFTER="${nft_line##* }"
BASE_BEFORE="$(jget BASE_USDC_BEFORE)"; NFT_BEFORE="$(jget NFT_BALANCE_BEFORE)"

[[ "$(lower "${OWNER}")" == "$(lower "${RECIPIENT}")" ]] || { err "receipt owner mismatch."; exit 1; }
[[ "${DATA_TOKEN}" == "${TOKEN_ID}" && "${DATA_DOMAIN}" == "${MSG_DOMAIN}" \
    && "$(lower "${DATA_SENDER}")" == "$(lower "${MSG_SENDER}")" \
    && "$(lower "${DATA_RECIPIENT}")" == "$(lower "${RECIPIENT}")" \
    && "${DATA_AMOUNT}" == "${NET}" && "${DATA_RECORDED_AT}" == "${EVENT_RECORDED_AT}" ]] || {
    err "stored receipt facts do not match ReceiptMinted."; exit 1;
}
[[ "${URI}" == data:application/json\;base64,* ]] || { err "receipt tokenURI is not fully on-chain."; exit 1; }
(( BASE_AFTER - BASE_BEFORE == NET )) || { err "recipient USDC delta does not equal ${NET}."; exit 1; }
(( NFT_AFTER - NFT_BEFORE == 1 )) || { err "recipient NFT balance did not increase by one."; exit 1; }

jset TOKEN_ID "${TOKEN_ID}"
ok "Circle minted $(awk "BEGIN { printf \"%.6f\", ${NET}/1000000 }") USDC directly to ${RECIPIENT}"
ok "Lattice minted CCTP Receipt #${TOKEN_ID} to the same recipient"
ok "  route: Arc (domain ${ARC_DOMAIN}) -> Base Sepolia"
ok "  source contract: ${MSG_SENDER}"
ok "  burn:  ${ARC_EXPLORER}/tx/${BURN_TX}"
ok "  relay: ${BASE_EXPLORER}/tx/${RELAY_TX}"
ok "  NFT:   ${BASE_EXPLORER}/address/${RECEIPT} (token #${TOKEN_ID})"
rm -f "${JOURNAL}"
