#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cctp-hook-demo.sh
#
# LIVE, one-shot showcase of Lattice's CCTP v2 HOOKS: programmable USDC that
# AUTO-CREDITS a named account on arrival (see CCTPHookDemo + CCTPHookVault). USDC
# is burned on Arc testnet with a Lattice hook envelope, an Iris attestation is
# fetched, then relayMessageWithHook on Base Sepolia MINTS the USDC into a vault
# AND, in the same tx, credits the beneficiary via the diamond's CCTPHookExecutor.
#
# Unlike the plain Arc-hub loop this is LINEAR (setup -> burn -> attest -> relay ->
# verify), because a hook demo runs once. State is journaled to .cctp-demo.hook.env
# (gitignored) so a re-run resumes instead of re-deploying or re-burning.
#
# USAGE
#   script/config/cctp-hook-demo.sh [<actor-address>] [<beneficiary-address>]
#     <actor>       OPTIONAL. Omitted -> derived from the $FORGE_AUTH keystore.
#     <beneficiary> OPTIONAL. Omitted -> the actor (credit yourself).
#
# ENVIRONMENT
#   FORGE_AUTH  Keystore auth forwarded VERBATIM to every broadcast/cast (e.g.
#               "--account daveKey"; add "--password-file <f>" for an unattended
#               run). NEVER echoed. Broadcast-free reads pass --sender instead.
#   AMOUNT      USDC units to bridge (6 decimals; default 1000000 = 1 USDC).
#   IRIS_API / IRIS_POLL_SECONDS / ATTEST_TIMEOUT_SECONDS  Iris polling knobs.
#
# The forks resolve foundry.toml aliases arc-testnet + base-sepolia from the shell
# env OR ./.env (forge auto-loads .env; this shell does not).
#
# REQUIRES: foundry (forge, cast), jq, curl. Run from anywhere (resolves the repo root).
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

SCRIPT_TARGET="script/base/crosschain/CCTPHookDemo.s.sol:CCTPHookDemo"
ARC_USDC="0x3600000000000000000000000000000000000000"
ARC_SRC_DOMAIN=26
ARC_EXPLORER="https://testnet.arcscan.app"
BASE_EXPLORER="https://sepolia.basescan.org"
JOURNAL=".cctp-demo.hook.env"

FORGE_AUTH="${FORGE_AUTH:-}"
AMOUNT="${AMOUNT:-1000000}"
IRIS_API="${IRIS_API:-https://iris-api-sandbox.circle.com}"
IRIS_POLL_SECONDS="${IRIS_POLL_SECONDS:-5}"
ATTEST_TIMEOUT_SECONDS="${ATTEST_TIMEOUT_SECONDS:-300}"

# ---- presentation -------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_INFO=$'\033[0;36m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'; C_OFF=$'\033[0m'
else
    C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_OFF=''
fi
info() { echo "${C_INFO}[hook-demo]${C_OFF} $*"; }
ok()   { echo "${C_OK}[hook-demo]${C_OFF} $*"; }
warn() { echo "${C_WARN}[hook-demo]${C_OFF} $*" >&2; }
err()  { echo "${C_ERR}[hook-demo] ERROR:${C_OFF} $*" >&2; }

# ---- journal (KEY=VALUE lines; values are addresses / tx hashes / hex) ---------
journal_get() { [[ -f "${JOURNAL}" ]] && sed -n "s/^$1=//p" "${JOURNAL}" | tail -1 || true; }
journal_set() {
    local key="$1" val="$2" tmp
    tmp="$(mktemp "${JOURNAL}.XXXXXX")"
    { [[ -f "${JOURNAL}" ]] && grep -vE "^${key}=" "${JOURNAL}" || true; echo "${key}=${val}"; } >"${tmp}"
    mv "${tmp}" "${JOURNAL}"
}

# ---- args ---------------------------------------------------------------------
ACTOR=""; BENEFICIARY=""
for arg in "$@"; do
    [[ "${arg}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "not a 20-byte address: '${arg}'"; exit 2; }
    if [[ -z "${ACTOR}" ]]; then ACTOR="${arg}"; elif [[ -z "${BENEFICIARY}" ]]; then BENEFICIARY="${arg}"; else
        err "too many args; expected [<actor>] [<beneficiary>]"; exit 2
    fi
done

# ---- preflight ----------------------------------------------------------------
for bin in forge cast jq curl; do
    command -v "${bin}" >/dev/null 2>&1 || { err "${bin} not found on PATH"; exit 2; }
done

resolve_rpc() {
    local var="$1" val
    val="${!var:-}"
    if [[ -z "${val}" && -f .env ]]; then
        val="$(grep -E "^${var}=" .env | tail -1 | cut -d= -f2-)"
        val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    fi
    printf '%s' "${val}"
}
for var in ARC_TESTNET_RPC_URL BASE_SEPOLIA_RPC_URL; do
    [[ -n "$(resolve_rpc "${var}")" ]] || { err "${var} is not set (shell env or ./.env); see .env.example."; exit 2; }
done
ARC_RPC="$(resolve_rpc ARC_TESTNET_RPC_URL)"

[[ -n "${FORGE_AUTH}" ]] || { err "set FORGE_AUTH='--account <name> [--password-file <f>]' (needed to sign)."; exit 2; }

# Derive the signer from the keystore if no actor was passed (avoids an actor != signer mismatch).
if [[ -z "${ACTOR}" ]]; then
    # shellcheck disable=SC2086
    ACTOR="$(cast wallet address ${FORGE_AUTH})" || { err "could not derive signer from FORGE_AUTH keystore (add --password-file, or pass the address)."; exit 2; }
    [[ "${ACTOR}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "derived signer is not an address: '${ACTOR}'"; exit 2; }
    info "derived signer ${ACTOR} from the FORGE_AUTH keystore."
fi
[[ -n "${BENEFICIARY}" ]] || BENEFICIARY="${ACTOR}"
info "actor=${ACTOR}  beneficiary=${BENEFICIARY}  amount=${AMOUNT}"

# Scrub API-keyed RPC URLs out of any raw tool output before it reaches a log.
BASE_RPC="$(resolve_rpc BASE_SEPOLIA_RPC_URL)"
scrub() { printf '%s' "$1" | sed -e "s#${ARC_RPC}#<arc-rpc>#g" -e "s#${BASE_RPC}#<base-rpc>#g"; echo; }

# --slow is applied to the multi-tx setup deploy ONLY when the signer is EIP-7702-delegated on Arc (delegated
# accounts are txpool-capped at one in-flight tx, which the ~10-tx deploy would exceed). Detect it; default to
# --slow (safe/serial) when unconfirmable. A plain-EOA signer deploys in parallel.
SLOW="--slow"
_code="$(curl -s --max-time 15 -X POST "${ARC_RPC}" -H 'content-type: application/json' \
    -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getCode\",\"params\":[\"${ACTOR}\",\"latest\"]}" \
    | jq -r '.result // empty' 2>/dev/null || true)"
[[ "${_code}" == "0x" ]] && SLOW=""

# ---- 1. setup (Arc hub + Base diamond + vault) --------------------------------
ARC_HUB="$(journal_get ARC_HUB)"; BASE_DIAMOND="$(journal_get BASE_DIAMOND)"; VAULT="$(journal_get VAULT)"
if [[ -z "${ARC_HUB}" || -z "${BASE_DIAMOND}" || -z "${VAULT}" ]]; then
    info "setup: deploying Arc hub + Base diamond + vault (--verify via Sourcify)..."
    # shellcheck disable=SC2086
    out="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoSetup(uint256,uint32)' 0 2000 ${FORGE_AUTH} --broadcast ${SLOW} --verify 2>&1)" || { scrub "${out}"; err "setup failed."; exit 1; }
    line="$(echo "${out}" | grep -oE 'DEMO-HOOK-SETUP 0x[0-9a-fA-F]{40} 0x[0-9a-fA-F]{40} 0x[0-9a-fA-F]{40}' | tail -1 || true)"
    [[ -n "${line}" ]] || { scrub "${out}"; err "setup did not print DEMO-HOOK-SETUP."; exit 1; }
    read -r _ ARC_HUB BASE_DIAMOND VAULT <<<"${line}"
    journal_set ARC_HUB "${ARC_HUB}"; journal_set BASE_DIAMOND "${BASE_DIAMOND}"; journal_set VAULT "${VAULT}"
    ok "hub=${ARC_HUB}  diamond=${BASE_DIAMOND}  vault=${VAULT}"
else
    info "adopting journaled deployment: hub=${ARC_HUB} diamond=${BASE_DIAMOND} vault=${VAULT}"
fi

# ---- 2/3. burn-with-hook on Arc (cast send; forge cannot simulate Arc USDC moves) ----
# Arc USDC is spent ONLY by the approve+burn, so the fund check is scoped to the not-yet-burned case (a resume
# after a successful burn must not re-demand funds it already spent).
BURN_TX="$(journal_get BURN_TX)"
if [[ -z "${BURN_TX}" ]]; then
    # A prior run set BURN_ATTEMPTED but never recorded a tx hash: the burn MAY have dispatched. Refuse to
    # auto-burn again (never double-burn real USDC); the operator resolves it by inspecting the chain.
    if [[ -n "$(journal_get BURN_ATTEMPTED)" ]]; then
        err "a previous burn was dispatched but its tx hash was not recorded (interrupted run)."
        err "  check ${ARC_EXPLORER}/address/${ACTOR} for a recent depositForBurnWithHook:"
        err "    - if present: add 'BURN_TX=<hash>' to ${JOURNAL} and re-run to resume;"
        err "    - if absent:  remove the 'BURN_ATTEMPTED=1' line from ${JOURNAL} and re-run to retry."
        exit 1
    fi

    # fund check (Arc USDC is the asset AND the gas token). Carries ${FORGE_AUTH} even though this is a
    # read: cast eagerly resolves a wallet whenever ETH_KEYSTORE_ACCOUNT is set (the repo .env sets it), and
    # without credentials it PROMPTS for that unrelated account's password -- on /dev/tty, so neither the
    # 2>/dev/null here nor an `env -u` (cast re-reads .env) suppresses it. Passing the auth we already hold
    # keeps the read on the SAME account as the signing steps and silent under --password-file.
    # shellcheck disable=SC2086
    BAL_HEX="$(cast call "${ARC_USDC}" "balanceOf(address)(uint256)" "${ACTOR}" ${FORGE_AUTH} --rpc-url "${ARC_RPC}" 2>/dev/null | awk '{print $1}' || true)"
    BAL="${BAL_HEX%% *}"
    if [[ -n "${BAL}" ]] && (( BAL < AMOUNT )); then
        err "actor holds ${BAL} of the ${AMOUNT} Arc USDC units needed."
        info "Fund via https://faucet.circle.com : Arc testnet USDC -> ${ACTOR} (asset + gas)."
        exit 1
    fi

    # shellcheck disable=SC2086
    R="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoRecipient(address)' "${VAULT}" --sender "${ACTOR}" 2>&1 | grep -oE 'DEMO-HOOK-RECIPIENT 0x[0-9a-fA-F]+' | awk '{print $2}' || true)"
    # shellcheck disable=SC2086
    E="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoEnvelope(address,address)' "${VAULT}" "${BENEFICIARY}" --sender "${ACTOR}" 2>&1 | grep -oE 'DEMO-HOOK-ENVELOPE 0x[0-9a-fA-F]+' | awk '{print $2}' || true)"
    [[ "${R}" =~ ^0x && "${E}" =~ ^0x ]] || { err "could not encode recipient/envelope."; exit 1; }
    info "approving ${AMOUNT} Arc USDC to the hub..."
    # shellcheck disable=SC2086
    cast send "${ARC_USDC}" "approve(address,uint256)" "${ARC_HUB}" "${AMOUNT}" ${FORGE_AUTH} --rpc-url "${ARC_RPC}" >/dev/null
    info "burning ${AMOUNT} Arc USDC -> Base with hook (target=vault, payload=beneficiary)..."
    journal_set BURN_ATTEMPTED 1 # write-ahead: a crash after this means "check arcscan before re-running"
    rc=0
    # stdout (the --json receipt) and stderr (which may embed the API-keyed RPC URL on a transport error) are
    # kept SEPARATE, so the hash extraction never sees error noise and the error text is scrubbed before echo.
    err_file="$(mktemp "${JOURNAL}.burnerr.XXXXXX")"
    # shellcheck disable=SC2086
    out="$(cast send "${ARC_HUB}" "depositForBurnWithHook(uint256,bytes,bytes)" "${AMOUNT}" "${R}" "${E}" ${FORGE_AUTH} --rpc-url "${ARC_RPC}" --json 2>"${err_file}")" || rc=$?
    err_text="$(cat "${err_file}")"; rm -f "${err_file}"
    hash="$(printf '%s' "${out}" | jq -r '.transactionHash // empty' 2>/dev/null || true)"
    if [[ ! "${hash}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        # A pre-dispatch revert / estimation failure sent NOTHING — never adopt revert calldata as a tx hash.
        if printf '%s\n%s' "${out}" "${err_text}" | grep -qiE 'revert|estimat'; then
            # Nothing was dispatched: clear the write-ahead sentinel so a corrected re-run can burn cleanly.
            journal_set BURN_ATTEMPTED ""
            scrub "${err_text}"; err "burn reverted before dispatch — nothing was sent. Fix the cause and re-run."; exit 1
        fi
        # Tolerant fallback: adopt a STANDALONE 64-hex tx hash echoed on an error line (never a 64-slice of a
        # longer blob) only when no revert marker is present.
        hash="$(printf '%s\n%s' "${out}" "${err_text}" | grep -oE '0x[0-9a-fA-F]{64}[0-9a-fA-F]?' | awk 'length == 66' | head -1 || true)"
    fi
    [[ "${hash}" =~ ^0x[0-9a-fA-F]{64}$ ]] || { scrub "${err_text}"; err "burn produced no tx hash; check ${ARC_EXPLORER}/address/${ACTOR} before re-running (never double-burn)."; exit 1; }
    (( rc == 0 )) || warn "cast exited ${rc} after dispatching the burn; adopting ${hash} (NOT re-burning)."
    journal_set BURN_TX "${hash}"; BURN_TX="${hash}"
    ok "burned: ${ARC_EXPLORER}/tx/${BURN_TX}"
fi

# ---- 4. Iris attestation (source domain 26 = Arc; seconds at Arc finality) -----
MESSAGE="$(journal_get MESSAGE)"; ATTESTATION="$(journal_get ATTESTATION)"
if [[ -z "${MESSAGE}" || -z "${ATTESTATION}" ]]; then
    info "awaiting Iris attestation (poll ${IRIS_POLL_SECONDS}s, cap ${ATTEST_TIMEOUT_SECONDS}s)..."
    deadline=$(( SECONDS + ATTEST_TIMEOUT_SECONDS ))
    while (( SECONDS < deadline )); do
        resp="$(curl -sf --retry 3 --retry-delay 2 "${IRIS_API}/v2/messages/${ARC_SRC_DOMAIN}?transactionHash=${BURN_TX}" 2>/dev/null || true)"
        if [[ -n "${resp}" && "$(echo "${resp}" | jq -r '.messages[0].status // empty')" == "complete" ]]; then
            MESSAGE="$(echo "${resp}" | jq -r '.messages[0].message // empty')"
            ATTESTATION="$(echo "${resp}" | jq -r '.messages[0].attestation // empty')"
            if [[ "${MESSAGE}" =~ ^0x[0-9a-fA-F]+$ && "${ATTESTATION}" =~ ^0x[0-9a-fA-F]+$ ]]; then
                journal_set MESSAGE "${MESSAGE}"; journal_set ATTESTATION "${ATTESTATION}"
                ok "attestation complete."
                break
            fi
        fi
        sleep "${IRIS_POLL_SECONDS}"
    done
    [[ -n "${MESSAGE}" && -n "${ATTESTATION}" ]] || { err "attestation not ready within ${ATTEST_TIMEOUT_SECONDS}s; re-run to resume."; exit 1; }
fi

# ---- 5. relay-with-hook on Base (forge; normal chain) -------------------------
# Journal RELAYED so a resume never replays the message (a consumed CCTP nonce would revert the retry and wedge
# the run). If the relay tx fails THIS run, don't guess from the revert text — fall through: the verify step
# reads the on-chain credit and is the source of truth (a resume after the relay already landed reads it fine).
if [[ -z "$(journal_get RELAYED)" ]]; then
    info "relaying on Base Sepolia (mints to the vault + fires the hook)..."
    rc=0
    # shellcheck disable=SC2086
    out="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoRelay(address,bytes,bytes)' "${BASE_DIAMOND}" "${MESSAGE}" "${ATTESTATION}" ${FORGE_AUTH} --broadcast --rpc-url base-sepolia 2>&1)" || rc=$?
    if (( rc == 0 )); then
        journal_set RELAYED 1
    else
        warn "relay tx did not succeed this run (it may already be relayed from a prior run); verifying credit..."
        scrub "${out}"
    fi
    sleep 6
else
    info "relay already journaled; skipping to verify."
fi

# ---- 6. verify the vault credited the beneficiary (source of truth) ------------
credit_line="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoCredit(address,address)' "${VAULT}" "${BENEFICIARY}" --sender "${ACTOR}" 2>&1 | grep -oE 'DEMO-HOOK-CREDIT [0-9]+ [0-9]+' | tail -1 || true)"
read -r _ CREDIT VAULT_BAL <<<"${credit_line}"
if [[ -z "${CREDIT}" ]]; then err "could not read the vault credit; check ${BASE_EXPLORER}/address/${VAULT}"; exit 1; fi

echo
if (( CREDIT >= AMOUNT )); then
    ok "HOOK DELIVERED: ${BENEFICIARY} auto-credited ${CREDIT} USDC units in the vault (balance ${VAULT_BAL})."
    ok "  burn (Arc):   ${ARC_EXPLORER}/tx/${BURN_TX}"
    ok "  vault (Base): ${BASE_EXPLORER}/address/${VAULT}"
    ok "  hub (Arc):    ${ARC_EXPLORER}/address/${ARC_HUB}"
    rm -f "${JOURNAL}"
else
    warn "relay landed but credit=${CREDIT} < ${AMOUNT}; inspect ${BASE_EXPLORER}/address/${VAULT} (journal kept)."
    exit 1
fi
