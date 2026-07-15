#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cctp-usdc-demo-loop.sh
#
# External autonomous driver for the multi-chain Circle CCTP v2 USDC demo
# (see CCTPUSDCDemo). CCTP is BURN-AND-MINT: USDC is burned on Ethereum
# Sepolia, an off-chain Iris attestation is fetched, then the message is
# relayed on the destination which mints the USDC. `forge script` is
# collect-then-dispatch, so ONE run cannot burn -> attest -> relay (the
# attestation only exists once the burn is mined). This loop is therefore a
# CRANK STATE MACHINE across runs: it reads the on-fork status, then advances
# exactly one phase (setup -> fund-check -> burn -> Iris attest -> relay ->
# verify) -- unattended, until the destination is credited.
#
# HOW IT WORKS
#   Each iteration reads a broadcast-free status line
#       DEMO-STATUS <phase> <waitSeconds> <done> <srcBal> <dstBal>
#   (phase: 0 NEEDS-SETUP, 1 NEEDS-FUNDS, 2 READY-TO-BURN,
#           3 AWAITING-DELIVERY, 4 DELIVERED) and dispatches on the phase:
#     0 -> deploy+wire both diamonds (cctpDemoSetup, --verify via Sourcify)
#     1 -> print faucet instructions and exit (funding is never automated)
#     2 -> record the destination baseline, then burn (cctpDemoBurn)
#     3 -> fetch the Iris attestation (poll), then relay (cctpDemoRelay)
#     done==1 -> assert the credited amount and finish.
#   Off-chain state (diamond addresses, burn tx hash, Iris message +
#   attestation) is journaled to .cctp-demo.<lane>.env at the repo root
#   (gitignored), so cranks compose across processes and --once runs.
#
# USAGE
#   script/config/cctp-usdc-demo-loop.sh [--once] <lane:arc|base> <actor-address>
#     --once   Advance a single phase (or report the wait) and exit --
#              composable with cron/systemd timers.
#
#   IMPORTANT: <actor-address> MUST equal your $FORGE_AUTH --account keystore
#   address. The burn pulls USDC from the keystore SIGNER and mints to the
#   SIGNER, while status reads balances of <actor-address> -- if they differ
#   the funds move but status never observes them (the stuck-detector aborts).
#
# ENVIRONMENT
#   FORGE_AUTH   Forge keystore auth passed VERBATIM to every broadcast crank,
#                e.g. "--account daveKey". For UNATTENDED runs add a password
#                file:  --account daveKey --password-file .demo.pw  where
#                .demo.pw is a GITIGNORED file YOU create holding the KEYSTORE
#                PASSWORD (not a raw private key). This script NEVER creates,
#                reads, or echoes that file -- it only forwards $FORGE_AUTH.
#   AMOUNT       USDC units to bridge (6 decimals; default 1000000 = 1 USDC).
#   FAST         0 = free standard transfer (default); 1 = fast (paid) transfer.
#   IRIS_API     Iris attestation API base (default sandbox).
#   IRIS_POLL_SECONDS      Iris poll interval (default 10).
#   ATTEST_TIMEOUT_SECONDS Iris attestation wait cap (default 1800 = 30m).
#   DST_SETTLE_SECONDS     Post-relay settle sleep (default 10).
#   SRC_DIAMOND / DST_DIAMOND  Adopt pre-deployed diamonds (skip the setup crank).
#   MAX_ITERS    Loop iteration cap (default 50).
#   MAX_WALL_SECONDS  Wall-clock cap in seconds (default 14400 = 4h).
#   CRANK_SETTLE_SECONDS  Post-crank settle sleep (default 24 ~= 2 Sepolia blocks).
#   WAIT_PAD_SECONDS      Padding added to a phase wait before re-reading (default 15).
#   NO_COLOR     Set to disable ANSI color.
#
# The status read forks both chains itself (no --rpc-url), so the RPC aliases
# sepolia + base-sepolia/arc-testnet must resolve (foundry auto-loads .env).
#
# REQUIRES: foundry (`forge`), `jq`, `curl`. Run from anywhere (resolves the repo root).
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

SCRIPT_TARGET="script/base/crosschain/CCTPUSDCDemo.s.sol:CCTPUSDCDemo"

# depositForBurn(uint256,bytes) selector — used to pick the burn tx from the broadcast JSON.
BURN_SELECTOR="0x3d8f1160"

# DELIVERED slack (USDC units) on a lane whose destination USDC is the native gas token (arc): the actor signs
# the relay, so its relay gas is debited from the very balance the ERC-20 view reports. Mirrors the contract's
# DST_NATIVE_GAS_ALLOWANCE so the loop's verify bound and the on-fork DELIVERED phase agree.
DST_NATIVE_GAS_ALLOWANCE=50000

# ---- presentation -------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_INFO=$'\033[0;36m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'; C_OFF=$'\033[0m'
else
    C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_OFF=''
fi
info() { echo "${C_INFO}[cctp-loop]${C_OFF} $*"; }
ok()   { echo "${C_OK}[cctp-loop]${C_OFF} $*"; }
warn() { echo "${C_WARN}[cctp-loop]${C_OFF} $*" >&2; }
err()  { echo "${C_ERR}[cctp-loop] ERROR:${C_OFF} $*" >&2; }

usage() {
    sed -n '2,63p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ---- argument parsing ---------------------------------------------------------
ONCE=0
if [[ "${1:-}" == "--once" ]]; then ONCE=1; shift; fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
if [[ $# -ne 2 ]]; then err "expected <lane:arc|base> <actor-address> (got $#)"; usage 2; fi

LANE="$1"; ACTOR="$2"
[[ "${ACTOR}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "actor is not a 20-byte address: ${ACTOR}"; exit 2; }

case "${LANE}" in
    arc)  DST_DOMAIN=26; DST_EXPLORER="https://testnet.arcscan.app";  DST_HUMAN="Arc testnet" ;;
    base) DST_DOMAIN=6;  DST_EXPLORER="https://sepolia.basescan.org"; DST_HUMAN="Base Sepolia" ;;
    *) err "lane must be 'arc' or 'base' (got '${LANE}')"; usage 2 ;;
esac

FORGE_AUTH="${FORGE_AUTH:-}"
AMOUNT="${AMOUNT:-1000000}"
FAST="${FAST:-0}"
IRIS_API="${IRIS_API:-https://iris-api-sandbox.circle.com}"
IRIS_POLL_SECONDS="${IRIS_POLL_SECONDS:-10}"
ATTEST_TIMEOUT_SECONDS="${ATTEST_TIMEOUT_SECONDS:-1800}"
DST_SETTLE_SECONDS="${DST_SETTLE_SECONDS:-10}"
MAX_ITERS="${MAX_ITERS:-50}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-14400}"
CRANK_SETTLE_SECONDS="${CRANK_SETTLE_SECONDS:-24}"
WAIT_PAD_SECONDS="${WAIT_PAD_SECONDS:-15}"

# Pre-deployed diamonds adopted from the environment take precedence over the journal.
ENV_SRC_DIAMOND="${SRC_DIAMOND:-}"
ENV_DST_DIAMOND="${DST_DIAMOND:-}"

# ---- preflight ----------------------------------------------------------------
command -v forge >/dev/null 2>&1 || { err "forge not found on PATH"; exit 2; }
command -v jq >/dev/null 2>&1    || { err "jq not found on PATH (required for the Iris attestation + broadcast JSON)"; exit 2; }
command -v curl >/dev/null 2>&1  || { err "curl not found on PATH (required for the Iris attestation API)"; exit 2; }

# Continuous mode WILL broadcast, so a missing FORGE_AUTH is a config error to catch NOW.
if (( ! ONCE )) && [[ -z "${FORGE_AUTH}" ]]; then
    err "continuous mode broadcasts and needs FORGE_AUTH set (the keystore auth forwarded to every crank)."
    err "  e.g.  FORGE_AUTH='--account daveKey'   or   FORGE_AUTH='--account daveKey --password-file .pw'"
    err "  (.pw is a GITIGNORED file YOU create holding the KEYSTORE PASSWORD, not a raw private key.)"
    err "  use --once for a read-only status check without broadcasting."
    exit 2
fi

# ---- fee policy ---------------------------------------------------------------
# FAST=0: free standard transfer (maxFee 0, finality 2000). FAST=1: fast (paid) transfer -- quote the
# threshold-1000 minimumFee (bps) from Iris and set maxFee = max(ceil(AMOUNT*bps/10000), 500), finality 1000.
# A lane can be re-tuned later by re-running `configureDomain` manually against the journaled diamonds.
if [[ "${FAST}" == "0" ]]; then
    MAXFEE=0; MINFINALITY=2000
else
    FEE_BPS="$(curl -sf --retry 3 --retry-delay 2 "${IRIS_API}/v2/burn/USDC/fees/0/${DST_DOMAIN}" \
        | jq -r '[.[] | select(.finalityThreshold==1000)][0].minimumFee // empty')"
    [[ "${FEE_BPS}" =~ ^[0-9]+$ ]] || { err "could not quote a threshold-1000 fee (bps) from Iris for domain ${DST_DOMAIN}"; exit 2; }
    CEIL_FEE=$(( (AMOUNT * FEE_BPS + 9999) / 10000 ))
    MAXFEE=$(( CEIL_FEE > 500 ? CEIL_FEE : 500 ))
    MINFINALITY=1000
    info "FAST transfer: quoted ${FEE_BPS} bps -> maxFee ${MAXFEE} (finality ${MINFINALITY})"
fi

# ---- journal ------------------------------------------------------------------
JOURNAL="${REPO_ROOT}/.cctp-demo.${LANE}.env"

journal_get() {
    local key="$1"
    [[ -f "${JOURNAL}" ]] || return 0
    grep -E "^${key}=" "${JOURNAL}" 2>/dev/null | tail -1 | cut -d= -f2- || true
}
journal_set() {
    local key="$1" val="$2" tmp
    tmp="$(mktemp)"
    if [[ -f "${JOURNAL}" ]]; then grep -vE "^${key}=" "${JOURNAL}" > "${tmp}" || true; fi
    printf '%s=%s\n' "${key}" "${val}" >> "${tmp}"
    mv "${tmp}" "${JOURNAL}"
}

# ---- parsed status + loop state ----------------------------------------------
ST=""; WAIT=""; DONE=""; SRCBAL=""; DSTBAL=""
DID=""; SLEEP_FOR=0
# Journal-backed off-chain state, refreshed each step().
SRC_DIAMOND=""; DST_DIAMOND=""; DST_BASELINE=0; BURN_TX=""; MESSAGE=""; ATTESTATION=""; RELAYED=""
# Fee policy captured AT BURN TIME so a later default-env --once run verifies against the right bounds.
BURN_AMOUNT=""; BURN_MAXFEE=""; FEE_EXECUTED=""
# Stuck-crank detector: the "phase:burned:dstBal" signature of the most recent ACTIONABLE crank, and how many
# consecutive actionable cranks have shared it. A successful crank always moves the machine off its signature.
LAST_ACTIONABLE_SIG=""; STUCK_COUNT=0

phase_name() {
    case "$1" in
        0) echo "needs-setup" ;;
        1) echo "needs-funds" ;;
        2) echo "ready-to-burn" ;;
        3) echo "awaiting-delivery" ;;
        4) echo "delivered" ;;
        *) echo "phase-$1" ;;
    esac
}

# Refresh journal-backed state (env-adopted diamonds win over the journal).
load_journal() {
    SRC_DIAMOND="${ENV_SRC_DIAMOND:-$(journal_get SRC_DIAMOND)}"
    DST_DIAMOND="${ENV_DST_DIAMOND:-$(journal_get DST_DIAMOND)}"
    DST_BASELINE="$(journal_get DST_BASELINE)"; DST_BASELINE="${DST_BASELINE:-0}"
    BURN_TX="$(journal_get BURN_TX)"
    MESSAGE="$(journal_get MESSAGE)"
    ATTESTATION="$(journal_get ATTESTATION)"
    RELAYED="$(journal_get RELAYED)"
    # Fee policy from the burn (env fallback for adopted/pre-burn journals); FEE_EXECUTED may be empty.
    BURN_AMOUNT="$(journal_get BURN_AMOUNT)"; BURN_AMOUNT="${BURN_AMOUNT:-${AMOUNT}}"
    BURN_MAXFEE="$(journal_get BURN_MAXFEE)"; BURN_MAXFEE="${BURN_MAXFEE:-${MAXFEE}}"
    FEE_EXECUTED="$(journal_get FEE_EXECUTED)"
}

# READ-ONLY status probe (no --broadcast, no --rpc-url; the script forks both chains itself).
# Retries twice, then fails. Sets ST WAIT DONE SRCBAL DSTBAL.
read_status() {
    local src dst burned out line attempt=0
    src="${SRC_DIAMOND:-0x0000000000000000000000000000000000000000}"
    dst="${DST_DIAMOND:-0x0000000000000000000000000000000000000000}"
    burned=0; [[ -n "${BURN_TX}" ]] && burned=1
    while (( attempt < 3 )); do
        if out="$(forge script "${SCRIPT_TARGET}" \
                    --sig 'cctpDemoStatus(string,address,address,address,uint256,uint256,uint256)' \
                    "${LANE}" "${src}" "${dst}" "${ACTOR}" "${AMOUNT}" "${burned}" "${DST_BASELINE}" 2>&1)"; then
            line="$(echo "${out}" | grep -oE 'DEMO-STATUS [0-9]+ [0-9]+ [0-9]+ [0-9]+ [0-9]+' | tail -1 || true)"
            if [[ -n "${line}" ]]; then
                read -r _ ST WAIT DONE SRCBAL DSTBAL <<<"${line}"
                return 0
            fi
        fi
        attempt=$(( attempt + 1 ))
        warn "status read failed (attempt ${attempt}/3); retrying in 5s..."
        sleep 5
    done
    err "could not read a DEMO-STATUS line after 3 attempts"
    return 1
}

# Stuck-crank guard: two identical actionable signatures in a row means the last crank made no progress.
# The most common cause is ACTOR != the keystore signer. Returns 1 (abort) on the second repeat.
guard_stuck() {
    local sig burned
    burned=0; [[ -n "${BURN_TX}" ]] && burned=1
    sig="${ST}:${burned}:${DSTBAL}"
    if [[ "${sig}" == "${LAST_ACTIONABLE_SIG}" ]]; then
        STUCK_COUNT=$(( STUCK_COUNT + 1 ))
    else
        LAST_ACTIONABLE_SIG="${sig}"; STUCK_COUNT=1
    fi
    if (( STUCK_COUNT >= 2 )); then
        err "crank did not advance the demo after ${STUCK_COUNT} actionable attempts (signature ${sig})."
        err "most likely cause: ACTOR (${ACTOR}) does not match your --account keystore address —"
        err "the burn moves the keystore SIGNER's USDC, but status reads ACTOR's balances, so the demo"
        err "never appears to progress. Pass your keystore's address as the 2nd argument (it MUST match)."
        return 1
    fi
    return 0
}

# Fail a crank cleanly (no raw forge wallet errors) when broadcasting auth is absent — relevant to a --once
# actionable crank (continuous mode already preflights FORGE_AUTH before the loop).
require_auth() {
    [[ -n "${FORGE_AUTH}" ]] && return 0
    err "cannot crank: FORGE_AUTH is empty — broadcasting needs keystore auth (e.g. --account daveKey)."
    return 1
}

# Deploy + wire both diamonds (multichain; auto-verify via Sourcify). Journals SRC_DIAMOND/DST_DIAMOND from
# the DEMO-SETUP console line (a multichain run's diamonds are not addressable from a single broadcast JSON).
crank_setup() {
    local attempt=0 out rc line src dst
    require_auth || return 1
    while (( attempt < 3 )); do
        rc=0
        # $FORGE_AUTH is intentionally UNQUOTED so "--account daveKey" splits into words; forwarded verbatim.
        # shellcheck disable=SC2086
        out="$(forge script "${SCRIPT_TARGET}" \
                 --sig 'cctpDemoSetup(string,uint256,uint32)' "${LANE}" "${MAXFEE}" "${MINFINALITY}" \
                 ${FORGE_AUTH} --broadcast --verify 2>&1)" || rc=$?
        echo "${out}"
        line="$(echo "${out}" | grep -oE 'DEMO-SETUP 0x[0-9a-fA-F]{40} 0x[0-9a-fA-F]{40}' | tail -1 || true)"
        if [[ -n "${line}" ]] && echo "${out}" | grep -q 'ONCHAIN EXECUTION COMPLETE'; then
            read -r _ src dst <<<"${line}"
            journal_set SRC_DIAMOND "${src}"
            journal_set DST_DIAMOND "${dst}"
            SRC_DIAMOND="${src}"; DST_DIAMOND="${dst}"
            ok "setup complete: src=${src} dst=${dst} (verification via Sourcify is best-effort)"
            return 0
        fi
        (( rc == 0 )) || warn "setup crank returned ${rc}"
        attempt=$(( attempt + 1 ))
        warn "setup crank did not confirm both diamonds (attempt ${attempt}/3); retrying in 5s..."
        sleep 5
    done
    err "setup crank failed after 3 attempts"
    return 1
}

# Burn AMOUNT of Sepolia USDC toward the actor on the destination (source fork only). Records the destination
# baseline + fee policy first, then broadcasts. IDEMPOTENCY: the retry-stopping predicate is "a burn tx was
# DISPATCHED" (extracted from the broadcast JSON), NOT forge's exit code — so a non-zero exit AFTER the funds-
# moving burn already landed adopts that tx instead of re-burning. A retry happens ONLY when no burn tx was
# dispatched (a pre-dispatch failure, which moved nothing and is safe to repeat).
crank_burn() {
    require_auth || return 1
    local attempt=0 rc json hash
    journal_set DST_BASELINE "${DSTBAL}"; DST_BASELINE="${DSTBAL}"
    journal_set BURN_AMOUNT "${AMOUNT}"; BURN_AMOUNT="${AMOUNT}"
    journal_set BURN_MAXFEE "${MAXFEE}"; BURN_MAXFEE="${MAXFEE}"
    json="broadcast/CCTPUSDCDemo.s.sol/11155111/cctpDemoBurn-latest.json"
    rm -f "${json}" # drop any stale burn from a prior run so a hash here is unambiguously THIS burn
    while (( attempt < 3 )); do
        rc=0
        # shellcheck disable=SC2086
        forge script "${SCRIPT_TARGET}" \
            --sig 'cctpDemoBurn(string,address,uint256)' "${LANE}" "${SRC_DIAMOND}" "${AMOUNT}" \
            ${FORGE_AUTH} --broadcast || rc=$?
        # Extract the dispatched burn tx REGARDLESS of rc — a burn that landed must never be re-broadcast.
        hash=""
        if [[ -f "${json}" ]]; then
            hash="$(jq -r --arg sel "${BURN_SELECTOR}" \
                '[.transactions[] | select(.transactionType=="CALL" and (.transaction.input|startswith($sel)))] | last | .hash // empty' \
                "${json}")"
        fi
        if [[ "${hash}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
            journal_set BURN_TX "${hash}"; BURN_TX="${hash}"
            (( rc == 0 )) || warn "burn crank returned ${rc}, but the burn tx landed (${hash}) — adopting it, NOT re-burning."
            ok "burn broadcast: tx ${hash}"
            return 0
        fi
        if (( rc == 0 )); then
            err "burn crank reported success but no burn tx is in ${json} — refusing to re-burn (inconsistent)."
            return 1
        fi
        attempt=$(( attempt + 1 ))
        warn "burn did not dispatch (attempt ${attempt}/3); retrying in 5s..."
        sleep 5
    done
    err "burn crank failed to dispatch after 3 attempts"
    return 1
}

# Single Iris check for the burn tx. Journals MESSAGE + ATTESTATION (+ FEE_EXECUTED) and returns 0 when the
# attestation is complete; returns 1 while it is still pending. curl retries transient failures 3x.
fetch_attestation() {
    local resp status msg att fee
    resp="$(curl -sf --retry 3 --retry-delay 2 "${IRIS_API}/v2/messages/0?transactionHash=${BURN_TX}" 2>/dev/null || true)"
    [[ -n "${resp}" ]] || return 1
    status="$(echo "${resp}" | jq -r '.messages[0].status // empty')"
    [[ "${status}" == "complete" ]] || return 1
    msg="$(echo "${resp}" | jq -r '.messages[0].message // empty')"
    att="$(echo "${resp}" | jq -r '.messages[0].attestation // empty')"
    fee="$(echo "${resp}" | jq -r '.messages[0].decodedMessageBody.feeExecuted // empty')"
    [[ "${msg}" =~ ^0x[0-9a-fA-F]+$ && "${att}" =~ ^0x[0-9a-fA-F]+$ ]] || return 1
    journal_set MESSAGE "${msg}"; MESSAGE="${msg}"
    journal_set ATTESTATION "${att}"; ATTESTATION="${att}"
    [[ -n "${fee}" ]] && journal_set FEE_EXECUTED "${fee}"
    ok "Iris attestation complete for ${BURN_TX}${fee:+ (feeExecuted ${fee})}"
    return 0
}

# Continuous-mode inner poll: block until the attestation is complete or ATTEST_TIMEOUT_SECONDS elapses.
poll_attestation() {
    local start="${SECONDS}"
    info "awaiting Iris attestation (poll ${IRIS_POLL_SECONDS}s, cap ${ATTEST_TIMEOUT_SECONDS}s)..."
    while (( SECONDS - start < ATTEST_TIMEOUT_SECONDS )); do
        if fetch_attestation; then return 0; fi
        sleep "${IRIS_POLL_SECONDS}"
    done
    err "Iris attestation did not complete within ${ATTEST_TIMEOUT_SECONDS}s for ${BURN_TX}"
    return 1
}

# Relay the attested message on the destination (destination fork only). Retries twice.
crank_relay() {
    require_auth || return 1
    local attempt=0 rc
    while (( attempt < 3 )); do
        rc=0
        # shellcheck disable=SC2086
        forge script "${SCRIPT_TARGET}" \
            --sig 'cctpDemoRelay(string,address,bytes,bytes)' "${LANE}" "${DST_DIAMOND}" "${MESSAGE}" "${ATTESTATION}" \
            ${FORGE_AUTH} --broadcast || rc=$?
        if (( rc == 0 )); then
            journal_set RELAYED 1; RELAYED=1
            ok "relay broadcast on ${DST_HUMAN}"
            return 0
        fi
        attempt=$(( attempt + 1 ))
        warn "relay crank failed (attempt ${attempt}/3); retrying in 5s..."
        sleep 5
    done
    err "relay crank failed after 3 attempts"
    return 1
}

# Assert the credited amount, log the summary + explorer links, delete the journal. Bounds use the fee policy
# CAPTURED AT BURN TIME (BURN_AMOUNT/BURN_MAXFEE) so a later default-env --once run does not false-fail a
# FAST=1 burn; when Iris reported the exact FEE_EXECUTED the check tightens to that exact credit. On a
# native-gas destination (arc) the actor's relay gas is netted from the balance, so the lower bound is relaxed
# by DST_NATIVE_GAS_ALLOWANCE (floor 1) and the exact-fee tightening is skipped.
verify_and_finish() {
    local delta lo hi
    delta=$(( DSTBAL - DST_BASELINE ))
    lo=$(( BURN_AMOUNT - BURN_MAXFEE )); hi=${BURN_AMOUNT}
    if [[ "${LANE}" == "arc" ]]; then
        lo=$(( lo - DST_NATIVE_GAS_ALLOWANCE )); (( lo < 1 )) && lo=1
    elif [[ -n "${FEE_EXECUTED}" ]]; then
        lo=$(( BURN_AMOUNT - FEE_EXECUTED )); hi=${lo}
    fi
    if (( delta < lo || delta > hi )); then
        err "DELIVERED but credited ${delta} is outside [${lo}, ${hi}] (baseline ${DST_BASELINE}, dstBal ${DSTBAL})."
        return 1
    fi
    ok "DELIVERED: ${DST_HUMAN} credited ${delta} USDC units (baseline ${DST_BASELINE} -> ${DSTBAL}, within [${lo}, ${hi}])."
    ok "  lane ${LANE}: src=${SRC_DIAMOND} dst=${DST_DIAMOND}"
    [[ -n "${BURN_TX}" ]] && ok "  burn:  https://sepolia.etherscan.io/tx/${BURN_TX}"
    ok "  mint:  ${DST_EXPLORER}/address/${DST_DIAMOND}"
    rm -f "${JOURNAL}"
    return 0
}

# One status-driven decision. Returns 0 (took a step), 10 (done), or 1 (error). Sets DID + SLEEP_FOR.
step() {
    load_journal
    read_status || return 1
    info "status: phase=${ST} ($(phase_name "${ST}")) wait=${WAIT}s done=${DONE} src=${SRCBAL} dst=${DSTBAL}"
    SLEEP_FOR=0; DID=""

    if [[ "${DONE}" == "1" ]]; then
        verify_and_finish || return 1
        DID="done"
        return 10
    fi

    case "${ST}" in
        0) # NEEDS-SETUP
            if [[ -n "${SRC_DIAMOND}" || -n "${DST_DIAMOND}" ]]; then
                err "status is NEEDS-SETUP but diamonds are already set (src=${SRC_DIAMOND} dst=${DST_DIAMOND})."
                err "the journaled/adopted diamonds are not both wired+registered for lane '${LANE}'."
                err "registration is fail-loud; refusing to re-run setup. Fix them or delete ${JOURNAL} and retry."
                return 1
            fi
            guard_stuck || return 1
            info "actionable now -> setup (deploy + wire both diamonds)."
            crank_setup || return 1
            DID="crank"; SLEEP_FOR=${CRANK_SETTLE_SECONDS}
            return 0
            ;;
        1) # NEEDS-FUNDS — never automate funding.
            warn "NEEDS-FUNDS: actor ${ACTOR} holds ${SRCBAL} of the ${AMOUNT} Sepolia USDC units required."
            info "Fund via https://faucet.circle.com : Ethereum Sepolia USDC -> ${ACTOR} (>= 1 USDC) + Sepolia ETH for gas."
            [[ "${LANE}" == "arc" ]] && info "arc lane also needs Arc testnet USDC (the gas token) on the actor."
            DID="funds"
            return 1
            ;;
        2) # READY-TO-BURN
            guard_stuck || return 1
            info "actionable now -> burn (records the destination baseline, then burns ${AMOUNT})."
            crank_burn || return 1
            DID="crank"; SLEEP_FOR=${CRANK_SETTLE_SECONDS}
            return 0
            ;;
        3) # AWAITING-DELIVERY
            if [[ -z "${BURN_TX}" ]]; then
                err "AWAITING-DELIVERY but no burn tx is journaled — inconsistent state; delete ${JOURNAL} and retry."
                return 1
            fi
            if [[ -z "${ATTESTATION}" ]]; then
                if (( ONCE )); then
                    if fetch_attestation; then
                        info "attestation fetched; re-run to relay."
                        DID="crank"
                    else
                        info "attestation still pending; re-run shortly."
                        DID="sleep"; SLEEP_FOR=${IRIS_POLL_SECONDS}
                    fi
                    return 0
                fi
                poll_attestation || return 1
                DID="crank"; SLEEP_FOR=0
                return 0
            fi
            if [[ -z "${RELAYED}" ]]; then
                guard_stuck || return 1
                info "actionable now -> relay (mint on ${DST_HUMAN})."
                crank_relay || return 1
                DID="crank"; SLEEP_FOR=${DST_SETTLE_SECONDS}
                return 0
            fi
            # Relayed already — wait for the mint to reflect on the destination.
            SLEEP_FOR=$(( WAIT + WAIT_PAD_SECONDS ))
            (( SLEEP_FOR > 0 )) || SLEEP_FOR=${DST_SETTLE_SECONDS}
            DID="sleep"
            info "relay sent; awaiting the destination mint to reflect (sleeping ${SLEEP_FOR}s)."
            return 0
            ;;
        *)
            err "unexpected status phase '${ST}'"
            return 1
            ;;
    esac
}

# ---- --once: single step, no looping -----------------------------------------
if (( ONCE )); then
    rc=0; step || rc=$?
    if (( rc == 10 )); then exit 0; fi
    (( rc == 0 )) || exit 1
    if [[ "${DID}" == "sleep" ]]; then
        info "(--once) would next act in ~${SLEEP_FOR}s; exiting for the caller to reschedule."
    fi
    exit 0
fi

# ---- continuous loop with iteration + wall-clock caps ------------------------
iter=0
while (( iter < MAX_ITERS )); do
    iter=$(( iter + 1 ))
    if (( SECONDS > MAX_WALL_SECONDS )); then
        err "wall-clock cap ${MAX_WALL_SECONDS}s exceeded after ${iter} iterations; aborting."
        exit 1
    fi
    info "iteration ${iter}/${MAX_ITERS} (elapsed ${SECONDS}s)"
    rc=0; step || rc=$?
    if (( rc == 10 )); then exit 0; fi
    (( rc == 0 )) || { err "aborting after a failed step."; exit 1; }
    if (( SLEEP_FOR > 0 )); then sleep "${SLEEP_FOR}"; fi
done

err "iteration cap ${MAX_ITERS} reached without the demo completing; aborting (re-run to continue)."
exit 1
