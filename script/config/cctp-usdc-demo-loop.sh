#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cctp-usdc-demo-loop.sh
#
# External autonomous driver for the ARC-HUB Circle CCTP v2 USDC demo (see
# CCTPUSDCDemo). ONE Lattice diamond lives on Circle's Arc testnet (the SOURCE)
# and bridges REAL testnet USDC OUT to BOTH Ethereum Sepolia AND Base Sepolia.
# CCTP is BURN-AND-MINT: USDC is burned on Arc, an off-chain Iris attestation is
# fetched, then the message is relayed on the DESTINATION which mints the USDC.
# `forge script` is collect-then-dispatch, so ONE run cannot burn -> attest ->
# relay (the attestation only exists once the burn is mined). This loop is a
# CRANK STATE MACHINE across runs: it reads the on-fork status, then advances
# exactly one phase (setup -> fund-check -> burn -> Iris attest -> relay ->
# verify) -- unattended, until each destination is credited.
#
# WHY ARC AS THE SOURCE HUB
#   Standard (free) CCTP attests only after SOURCE-chain hard finality. Sepolia
#   finality is ~13-19 min; Arc has sub-second finality, so an Arc-sourced free
#   burn attests in SECONDS. Relays run on the plain-EOA destinations (Sepolia /
#   Base Sepolia) via Circle's MessageTransmitterV2 directly -- never into Arc,
#   where the native-USDC mint path routes through a node precompile that forge's
#   revm cannot simulate (see the note in crank_burn).
#
# HOW IT WORKS
#   Each iteration reads a broadcast-free status line
#       DEMO-STATUS <phase> <waitSeconds> <done> <srcBal> <dstBal>
#   (phase: 0 NEEDS-SETUP, 1 NEEDS-FUNDS, 2 READY-TO-BURN,
#           3 AWAITING-DELIVERY, 4 DELIVERED) and dispatches on the phase:
#     0 -> deploy+wire the ONE Arc hub (cctpDemoSetup, --verify via Sourcify)
#     1 -> print faucet instructions and exit (funding is never automated)
#     2 -> record the destination baseline, then burn on Arc via `cast send`
#          (approve + depositForBurn; NOT forge script — see crank_burn for why)
#     3 -> fetch the Iris attestation (poll), then relay on the dest (cctpDemoRelay)
#     done==1 -> assert the credited amount and finish that destination.
#   With no destination argument the loop drives BOTH destinations sequentially
#   (sepolia to DELIVERED, then base) in ONE invocation; an optional 2nd arg
#   (sepolia|base) filters to one. Off-chain state (hub address, per-destination
#   burn tx hash, Iris message + attestation) is journaled to
#   .cctp-demo.arc-hub.env at the repo root (gitignored), so cranks compose
#   across processes and --once runs.
#
# USAGE
#   script/config/cctp-usdc-demo-loop.sh [--once] <actor-address> [dest: sepolia|base]
#     --once   Advance a single phase of the CURRENT destination (or report the
#              wait) and exit -- composable with cron/systemd timers.
#
#   IMPORTANT: <actor-address> MUST equal your $FORGE_AUTH --account keystore
#   address. The burn pulls Arc USDC from the keystore SIGNER and mints to the
#   SIGNER on the destination, while status reads balances of <actor-address> --
#   if they differ the funds move but status never observes them (the
#   stuck-detector aborts).
#
# ENVIRONMENT
#   FORGE_AUTH   Forge keystore auth passed VERBATIM to every broadcast crank,
#                e.g. "--account daveKey". For UNATTENDED runs add a password
#                file:  --account daveKey --password-file .demo.pw  where
#                .demo.pw is a GITIGNORED file YOU create holding the KEYSTORE
#                PASSWORD (not a raw private key). This script NEVER creates,
#                reads, or echoes that file -- it only forwards $FORGE_AUTH.
#                NOTE: broadcast-free status reads pass an explicit --sender so an
#                ETH_KEYSTORE_ACCOUNT default (shell env or .env) never triggers a
#                keystore unlock; only the broadcast cranks authenticate, via $FORGE_AUTH.
#   AMOUNT       USDC units to bridge (6 decimals; default 1000000 = 1 USDC).
#   FAST         0 = free standard transfer (default); 1 = fast (paid) transfer.
#   IRIS_API     Iris attestation API base (default sandbox).
#   IRIS_POLL_SECONDS      Iris poll interval (default 5; Arc attests in seconds).
#   ATTEST_TIMEOUT_SECONDS Iris attestation wait cap (default 300 = 5m).
#   DST_SETTLE_SECONDS     Post-relay settle sleep (default 10).
#   DIAMOND      Adopt a pre-deployed Arc hub (skips the setup crank).
#   MAX_ITERS    Loop iteration cap across all driven destinations (default 50).
#   MAX_WALL_SECONDS  Wall-clock cap in seconds (default 14400 = 4h).
#   CRANK_SETTLE_SECONDS  Post-crank settle sleep (default 8; Arc mines fast).
#   WAIT_PAD_SECONDS      Padding added to a phase wait before re-reading (default 15).
#   NO_COLOR     Set to disable ANSI color.
#
# The status read forks both chains itself (no --rpc-url), so the RPC aliases
# arc-testnet + sepolia/base-sepolia must resolve (foundry auto-loads .env).
#
# REQUIRES: foundry (`forge`, `cast`), `jq`, `curl`. Run from anywhere (resolves the repo root).
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

SCRIPT_TARGET="script/base/crosschain/CCTPUSDCDemo.s.sol:CCTPUSDCDemo"

# Arc native USDC (the gas token) — approved before the cast-send burn. Same address on every Arc deployment.
ARC_USDC="0x3600000000000000000000000000000000000000"

# Arc is the Iris SOURCE domain now (every burn originates on Arc).
ARC_SRC_DOMAIN=26
ARC_EXPLORER="https://testnet.arcscan.app"

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
    sed -n '2,80p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ---- destination metadata -----------------------------------------------------
# Sets DEST_DOMAIN / DEST_EXPLORER / DEST_HUMAN / DEST_RPC_VAR / DEST_PREFIX for a destination key.
DEST_DOMAIN=""; DEST_EXPLORER=""; DEST_HUMAN=""; DEST_RPC_VAR=""; DEST_PREFIX=""
dest_meta() {
    case "$1" in
        sepolia)
            DEST_DOMAIN=0; DEST_EXPLORER="https://sepolia.etherscan.io"; DEST_HUMAN="Ethereum Sepolia"
            DEST_RPC_VAR="SEPOLIA_RPC_URL"; DEST_PREFIX="SEPOLIA" ;;
        base)
            DEST_DOMAIN=6; DEST_EXPLORER="https://sepolia.basescan.org"; DEST_HUMAN="Base Sepolia"
            DEST_RPC_VAR="BASE_SEPOLIA_RPC_URL"; DEST_PREFIX="BASE" ;;
        *) err "internal: unknown destination '$1'"; exit 2 ;;
    esac
}

# ---- argument parsing ---------------------------------------------------------
ONCE=0
if [[ "${1:-}" == "--once" ]]; then ONCE=1; shift; fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
if [[ $# -lt 1 || $# -gt 2 ]]; then err "expected <actor-address> [dest: sepolia|base] (got $#)"; usage 2; fi

ACTOR="$1"
[[ "${ACTOR}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "actor is not a 20-byte address: ${ACTOR}"; exit 2; }

DEST_FILTER="${2:-}"
if [[ -n "${DEST_FILTER}" ]]; then
    case "${DEST_FILTER}" in
        sepolia|base) ;;
        *) err "dest must be 'sepolia' or 'base' (got '${DEST_FILTER}')"; usage 2 ;;
    esac
    DESTS=("${DEST_FILTER}")
else
    DESTS=(sepolia base)
fi

FORGE_AUTH="${FORGE_AUTH:-}"
AMOUNT="${AMOUNT:-1000000}"
FAST="${FAST:-0}"
IRIS_API="${IRIS_API:-https://iris-api-sandbox.circle.com}"
IRIS_POLL_SECONDS="${IRIS_POLL_SECONDS:-5}"
ATTEST_TIMEOUT_SECONDS="${ATTEST_TIMEOUT_SECONDS:-300}"
DST_SETTLE_SECONDS="${DST_SETTLE_SECONDS:-10}"
MAX_ITERS="${MAX_ITERS:-50}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-14400}"
CRANK_SETTLE_SECONDS="${CRANK_SETTLE_SECONDS:-8}"
WAIT_PAD_SECONDS="${WAIT_PAD_SECONDS:-15}"

# A pre-deployed hub adopted from the environment takes precedence over the journal.
ENV_DIAMOND="${DIAMOND:-}"

# ---- preflight ----------------------------------------------------------------
command -v forge >/dev/null 2>&1 || { err "forge not found on PATH"; exit 2; }
command -v cast >/dev/null 2>&1  || { err "cast not found on PATH (the Arc burn uses cast send for approve + depositForBurn)"; exit 2; }
command -v jq >/dev/null 2>&1    || { err "jq not found on PATH (required for the Iris attestation + cast-send JSON output)"; exit 2; }
command -v curl >/dev/null 2>&1  || { err "curl not found on PATH (required for the Iris attestation API)"; exit 2; }

# The script's forks resolve foundry.toml aliases like ${ARC_TESTNET_RPC_URL} from the shell env OR the repo
# .env (forge auto-loads it; this shell does not). A missing var otherwise fails DEEP inside fork setup
# ("environment variable `X` not found") behind 3 opaque status retries -- so check both sources NOW and name
# the exact var needed. Arc is always required (the source); each driven destination adds its own.
rpc_var_available() {
    [[ -n "${!1:-}" ]] && return 0
    [[ -f .env ]] && grep -qE "^${1}=" .env
}
# Echo the resolved URL for an RPC var (shell env, else the repo .env), stripping surrounding quotes. Used to
# give `cast send` an explicit --rpc-url (the URL var is expanded by this shell, which does not load .env). The
# returned URL is stored in a variable and NEVER echoed to the log.
resolve_rpc() {
    local var="$1" val
    val="${!var:-}"
    if [[ -z "${val}" && -f .env ]]; then
        val="$(grep -E "^${var}=" .env | tail -1 | cut -d= -f2-)"
        val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    fi
    printf '%s' "${val}"
}
NEED_RPC=(ARC_TESTNET_RPC_URL)
for _d in "${DESTS[@]}"; do
    dest_meta "${_d}"
    NEED_RPC+=("${DEST_RPC_VAR}")
done
for _v in "${NEED_RPC[@]}"; do
    if ! rpc_var_available "${_v}"; then
        err "RPC env var ${_v} is not set (checked the shell env and ./.env) — the driven destination(s) need it."
        err "  add ${_v}=<url> to .env (names must match foundry.toml's [rpc_endpoints]; see .env.example)."
        exit 2
    fi
done

# Explicit Arc RPC URL for the cast-send burn (see crank_burn). Resolved once; never echoed.
ARC_RPC="$(resolve_rpc ARC_TESTNET_RPC_URL)"
[[ -n "${ARC_RPC}" ]] || { err "could not resolve ARC_TESTNET_RPC_URL to a URL (shell env or ./.env)."; exit 2; }

# Continuous mode WILL broadcast, so a missing FORGE_AUTH is a config error to catch NOW.
if (( ! ONCE )) && [[ -z "${FORGE_AUTH}" ]]; then
    err "continuous mode broadcasts and needs FORGE_AUTH set (the keystore auth forwarded to every crank)."
    err "  e.g.  FORGE_AUTH='--account daveKey'   or   FORGE_AUTH='--account daveKey --password-file .pw'"
    err "  (.pw is a GITIGNORED file YOU create holding the KEYSTORE PASSWORD, not a raw private key.)"
    err "  use --once for a read-only status check without broadcasting."
    exit 2
fi

# ---- journal ------------------------------------------------------------------
# Single journal for the shared Arc hub + per-destination namespaced keys (SEPOLIA_* / BASE_*).
JOURNAL="${REPO_ROOT}/.cctp-demo.arc-hub.env"

# Exclusive whole-invocation lock over the shared journal: two concurrent invocations (the header advertises
# cron/systemd-composable --once runs) could each observe an empty BURN_TX and double-burn, or race journal_set
# whole-file rewrites and drop keys. `mkdir` is atomic on POSIX filesystems (flock(1) does not exist on macOS);
# the EXIT trap releases it on every exit path. Derived from ${JOURNAL} so finalize_all's `rm -f` leaves the
# lock lifecycle untouched.
LOCK_DIR="${JOURNAL}.lock"
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    err "another cctp-usdc-demo-loop invocation holds ${LOCK_DIR}; refusing to run concurrently (a parallel crank could double-burn)."
    err "  if no other instance is running, remove the stale lock: rmdir ${LOCK_DIR}"
    exit 1
fi
trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

journal_get() {
    local key="$1"
    [[ -f "${JOURNAL}" ]] || return 0
    grep -E "^${key}=" "${JOURNAL}" 2>/dev/null | tail -1 | cut -d= -f2- || true
}
journal_set() {
    local key="$1" val="$2" tmp
    # mktemp a SIBLING of the journal so `mv` is always an atomic same-filesystem rename(2) (a $TMPDIR temp on a
    # different filesystem degrades to a non-atomic copy, and every journal_set rewrites the WHOLE file).
    tmp="$(mktemp "${JOURNAL}.XXXXXX")"
    if [[ -f "${JOURNAL}" ]]; then grep -vE "^${key}=" "${JOURNAL}" > "${tmp}" || true; fi
    printf '%s=%s\n' "${key}" "${val}" >> "${tmp}"
    mv "${tmp}" "${JOURNAL}"
}

# ---- parsed status + loop state ----------------------------------------------
ST=""; WAIT=""; DONE=""; SRCBAL=""; DSTBAL=""
DID=""; SLEEP_FOR=0
# Shared hub (env-adopted wins over the journal), plus per-destination off-chain state refreshed each step().
DIAMOND=""; DST_BASELINE=0; BURN_TX=""; BURN_ATTEMPTED=""; MESSAGE=""; ATTESTATION=""; RELAYED=""
# Fee policy captured AT BURN TIME so a later default-env --once run verifies against the right bounds.
BURN_AMOUNT=""; BURN_MAXFEE=""; FEE_EXECUTED=""
# Current fee policy (recomputed per destination before an actionable setup/burn crank).
MAXFEE=0; MINFINALITY=2000
# ERC-7930 recipient bytes for the current burn (resolved by the broadcast-free encoding helper).
RECIPIENT=""
# Current destination being driven (set before every step()).
DEST=""
# Stuck-crank detector: "<dest>:<phase>:<burned>:<dstBal>" signature of the most recent ACTIONABLE crank, and
# how many consecutive actionable cranks have shared it. A successful crank always moves off its signature.
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

# Refresh the shared hub (env-adopted wins over the journal).
load_diamond() {
    DIAMOND="${ENV_DIAMOND:-$(journal_get DIAMOND)}"
}

# Refresh per-destination journal state for prefix $1 (SEPOLIA | BASE).
load_dest_journal() {
    local p="$1"
    DST_BASELINE="$(journal_get "${p}_DST_BASELINE")"; DST_BASELINE="${DST_BASELINE:-0}"
    BURN_TX="$(journal_get "${p}_BURN_TX")"
    BURN_ATTEMPTED="$(journal_get "${p}_BURN_ATTEMPTED")"
    MESSAGE="$(journal_get "${p}_MESSAGE")"
    ATTESTATION="$(journal_get "${p}_ATTESTATION")"
    RELAYED="$(journal_get "${p}_RELAYED")"
    BURN_AMOUNT="$(journal_get "${p}_BURN_AMOUNT")"; BURN_AMOUNT="${BURN_AMOUNT:-${AMOUNT}}"
    BURN_MAXFEE="$(journal_get "${p}_BURN_MAXFEE")"; BURN_MAXFEE="${BURN_MAXFEE:-${MAXFEE}}"
    FEE_EXECUTED="$(journal_get "${p}_FEE_EXECUTED")"
}

# True when destination prefix $1 is journaled as DELIVERED.
dest_delivered() {
    [[ "$(journal_get "${1}_DELIVERED")" == "1" ]]
}

# Echo the first driven destination not yet DELIVERED (empty when all are done).
pick_current_dest() {
    local d
    for d in "${DESTS[@]}"; do
        dest_meta "${d}"
        dest_delivered "${DEST_PREFIX}" || { echo "${d}"; return 0; }
    done
}

# Fee policy for the CURRENT destination. FAST=0: free standard transfer (maxFee 0, finality 2000). FAST=1:
# fast (paid) transfer -- quote the threshold-1000 minimumFee (bps) from Iris (source domain 26) and set
# maxFee = max(ceil(AMOUNT*bps/10000), 500), finality 1000.
compute_fee_policy() {
    if [[ "${FAST}" == "0" ]]; then
        MAXFEE=0; MINFINALITY=2000
        return 0
    fi
    local fee_bps ceil_fee
    fee_bps="$(curl -sf --retry 3 --retry-delay 2 "${IRIS_API}/v2/burn/USDC/fees/${ARC_SRC_DOMAIN}/${DEST_DOMAIN}" \
        | jq -r '[.[] | select(.finalityThreshold==1000)][0].minimumFee // empty')"
    [[ "${fee_bps}" =~ ^[0-9]+$ ]] || { err "could not quote a threshold-1000 fee (bps) from Iris for domain ${DEST_DOMAIN}"; exit 2; }
    ceil_fee=$(( (AMOUNT * fee_bps + 9999) / 10000 ))
    MAXFEE=$(( ceil_fee > 500 ? ceil_fee : 500 ))
    MINFINALITY=1000
    info "FAST transfer: quoted ${fee_bps} bps -> maxFee ${MAXFEE} (finality ${MINFINALITY}) for ${DEST_HUMAN}"
}

# READ-ONLY status probe (no --broadcast, no --rpc-url; the script forks Arc + the current dest itself).
# Retries twice, then fails. Sets ST WAIT DONE SRCBAL DSTBAL.
read_status() {
    local diamond burned amount out line attempt=0
    diamond="${DIAMOND:-0x0000000000000000000000000000000000000000}"
    # Pre-burn the NEEDS-FUNDS check uses the LIVE amount; once burned, use the journaled BURN_AMOUNT so a later
    # env-drifted --once run computes the delivery phase against the amount the burn actually used (mirrors
    # verify_and_finish's burn-time bounds). BURN_AMOUNT is loaded by load_dest_journal (defaults to AMOUNT).
    amount="${AMOUNT}"
    burned=0; [[ -n "${BURN_TX}" ]] && { burned=1; amount="${BURN_AMOUNT}"; }
    while (( attempt < 3 )); do
        # Status is a broadcast-free dry run that reads ACTOR's balances (never msg.sender), so it needs NO
        # keystore. But forge auto-loads the repo .env, and an ETH_KEYSTORE_ACCOUNT entry there (or an exported
        # one) is the env fallback for --account: forge then EAGERLY unlocks that keystore -- a password prompt
        # on every poll. Forge only unlocks a wallet to DERIVE the sender, so passing --sender explicitly
        # removes the need and no unlock ever happens. ACTOR is the natural sender for a status dry run; the
        # broadcast cranks still authenticate via $FORGE_AUTH's --account.
        if out="$(forge script "${SCRIPT_TARGET}" \
                    --sig 'cctpDemoStatus(address,address,uint256,string,uint256,uint256)' \
                    --sender "${ACTOR}" \
                    "${diamond}" "${ACTOR}" "${amount}" "${DEST}" "${burned}" "${DST_BASELINE}" 2>&1)"; then
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

# READ-ONLY encoding helper: resolves the ERC-7930 recipient bytes for the CURRENT destination via the
# broadcast-free, fork-free cctpDemoRecipient entrypoint (never re-encoded in shell). Passes --sender for the
# same reason as the status read (an ETH_KEYSTORE_ACCOUNT default must not trigger an eager keystore unlock on
# a read-only call). Retries twice, then fails. Sets RECIPIENT.
fetch_recipient() {
    local out line attempt=0
    RECIPIENT=""
    while (( attempt < 3 )); do
        if out="$(forge script "${SCRIPT_TARGET}" \
                    --sig 'cctpDemoRecipient(string,address)' \
                    --sender "${ACTOR}" \
                    "${DEST}" "${ACTOR}" 2>&1)"; then
            line="$(echo "${out}" | grep -oE 'DEMO-RECIPIENT 0x[0-9a-fA-F]+' | tail -1 || true)"
            if [[ -n "${line}" ]]; then
                RECIPIENT="${line#DEMO-RECIPIENT }"
                return 0
            fi
        fi
        attempt=$(( attempt + 1 ))
        warn "recipient encode failed (attempt ${attempt}/3); retrying in 5s..."
        sleep 5
    done
    err "could not read a DEMO-RECIPIENT line after 3 attempts"
    return 1
}

# Stuck-crank guard: two identical actionable signatures in a row means the last crank made no progress. The
# most common cause is ACTOR != the keystore signer. Returns 1 (abort) on the second repeat.
guard_stuck() {
    local sig burned
    burned=0; [[ -n "${BURN_TX}" ]] && burned=1
    sig="${DEST}:${ST}:${burned}:${DSTBAL}"
    if [[ "${sig}" == "${LAST_ACTIONABLE_SIG}" ]]; then
        STUCK_COUNT=$(( STUCK_COUNT + 1 ))
    else
        LAST_ACTIONABLE_SIG="${sig}"; STUCK_COUNT=1
    fi
    if (( STUCK_COUNT >= 2 )); then
        err "crank did not advance the demo after ${STUCK_COUNT} actionable attempts (signature ${sig})."
        err "most likely cause: ACTOR (${ACTOR}) does not match your --account keystore address —"
        err "the burn moves the keystore SIGNER's Arc USDC, but status reads ACTOR's balances, so the demo"
        err "never appears to progress. Pass your keystore's address as the 1st argument (it MUST match)."
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

# Deploy + wire the ONE Arc hub (auto-verify via Sourcify). Journals DIAMOND from the DEMO-SETUP console line.
# Runs at most once — the hub is shared by both destinations (it registers BOTH at deploy).
crank_setup() {
    local attempt=0 out rc line diamond
    require_auth || return 1
    while (( attempt < 3 )); do
        rc=0
        # $FORGE_AUTH is intentionally UNQUOTED so "--account daveKey" splits into words; forwarded verbatim.
        # --slow sends each tx only after the previous one confirms. REQUIRED when the SIGNER is an
        # EIP-7702-delegated account (the txpool caps such accounts at ONE in-flight tx), which fires
        # "in-flight transaction limit reached for delegated accounts" on this multi-contract deploy otherwise.
        # A signer becomes delegated via a smart-account / 7702 setup -- it is NOT an Arc chain default; --slow
        # is harmless (and cheap, given Arc's sub-second finality) for a plain-EOA signer too, so it stays on.
        # --verify best-effort verifies via Sourcify (bare --verify); a chain Sourcify does not cover fails
        # that one contract non-fatally, so success is detected by the DEMO-SETUP + ONCHAIN-EXECUTION greps.
        # shellcheck disable=SC2086
        out="$(forge script "${SCRIPT_TARGET}" \
                 --sig 'cctpDemoSetup(uint256,uint32)' "${MAXFEE}" "${MINFINALITY}" \
                 ${FORGE_AUTH} --broadcast --slow --verify 2>&1)" || rc=$?
        echo "${out}"
        line="$(echo "${out}" | grep -oE 'DEMO-SETUP 0x[0-9a-fA-F]{40}' | tail -1 || true)"
        if [[ -n "${line}" ]] && echo "${out}" | grep -q 'ONCHAIN EXECUTION COMPLETE'; then
            read -r _ diamond <<<"${line}"
            journal_set DIAMOND "${diamond}"
            DIAMOND="${diamond}"
            ok "setup complete: hub=${diamond} (verification via Sourcify is best-effort)"
            return 0
        fi
        (( rc == 0 )) || warn "setup crank returned ${rc}"
        attempt=$(( attempt + 1 ))
        warn "setup crank did not confirm the hub (attempt ${attempt}/3); retrying in 5s..."
        sleep 5
    done
    err "setup crank failed after 3 attempts"
    return 1
}

# Burn AMOUNT of Arc USDC toward the actor on the CURRENT destination, via `cast send` (NOT `forge script`).
# Records the destination baseline + fee policy first, then: (1) resolves the ERC-7930 recipient bytes,
# (2) approves the hub for EXACTLY AMOUNT, (3) burns. Returns 0 once a burn tx hash is journaled.
#
# WHY cast send, not forge script: on Arc, USDC is the native gas token and EVERY balance-move routes through a
# node-level precompile (0x1800…) that revm does NOT implement. `forge script` executes the burn body during
# its collect phase, so a scripted burn reverts LOCALLY before any tx is dispatched. `cast send` performs NO
# local simulation — gas is estimated by, and the tx executed on, the real Arc NODE, which runs the precompile
# natively (the same mechanism that proved mint-into-Arc works live). Setup, status, and the destination relays
# are unaffected (they never move Arc USDC under revm).
#
# NEVER auto-retry the burn: a re-run must never double-burn. The approve IS retried (re-approving is
# idempotent) and is SYNCHRONOUS (cast send waits for the receipt), which both satisfies the EIP-7702
# one-in-flight cap on a delegated signer and guarantees the allowance exists before the burn.
crank_burn() {
    require_auth || return 1
    local rc out hash a_attempt=0 approve_rc err_file err_text
    journal_set "${DEST_PREFIX}_DST_BASELINE" "${DSTBAL}"; DST_BASELINE="${DSTBAL}"
    journal_set "${DEST_PREFIX}_BURN_AMOUNT" "${AMOUNT}"; BURN_AMOUNT="${AMOUNT}"
    journal_set "${DEST_PREFIX}_BURN_MAXFEE" "${MAXFEE}"; BURN_MAXFEE="${MAXFEE}"

    # 1. ERC-7930 recipient bytes (broadcast-free helper; never re-encoded in shell).
    fetch_recipient || return 1

    # 2. Approve the hub for EXACTLY AMOUNT of Arc USDC. $FORGE_AUTH forwards to cast VERBATIM (unquoted, never
    #    echoed) — cast accepts --account/--password-file identically to forge. Idempotent, so retry-3x is safe.
    while (( a_attempt < 3 )); do
        approve_rc=0
        # shellcheck disable=SC2086
        cast send "${ARC_USDC}" "approve(address,uint256)" "${DIAMOND}" "${AMOUNT}" \
            ${FORGE_AUTH} --rpc-url "${ARC_RPC}" --json >/dev/null 2>&1 || approve_rc=$?
        (( approve_rc == 0 )) && break
        a_attempt=$(( a_attempt + 1 ))
        warn "approve did not confirm (attempt ${a_attempt}/3); retrying in 5s..."
        sleep 5
    done
    (( approve_rc == 0 )) || { err "approve failed after 3 attempts — cannot burn."; return 1; }

    # 3. Write-ahead intent sentinel — set AFTER the approve succeeds and IMMEDIATELY before the burn cast send.
    #    It guards the kill window between submitting the burn and journaling BURN_TX: a crash there would leave
    #    burned=0, and the READY-TO-BURN guard in step() refuses to re-burn while this is set without a BURN_TX
    #    (the operator must reconcile via arcscan). Placed after approve so a mere approve failure never strands
    #    a stale sentinel. journal_set is atomic (mktemp+rename), so the sentinel write is crash-safe.
    journal_set "${DEST_PREFIX}_BURN_ATTEMPTED" 1; BURN_ATTEMPTED=1

    # 4. Burn (NO retry — a re-run must never double-burn). Separate stdout (the --json receipt) from stderr
    #    (errors) so a stderr warning cannot corrupt the receipt's jq parse, and so revert calldata on a failed
    #    submit is never mistaken for a tx hash. A hash is adopted even on a non-zero exit (submitted but the
    #    receipt wait failed) — that tx must NOT be re-sent.
    err_file="$(mktemp "${JOURNAL}.burnerr.XXXXXX")"
    rc=0
    # shellcheck disable=SC2086
    out="$(cast send "${DIAMOND}" "depositForBurn(uint256,bytes)" "${AMOUNT}" "${RECIPIENT}" \
        ${FORGE_AUTH} --rpc-url "${ARC_RPC}" --json 2>"${err_file}")" || rc=$?
    err_text="$(cat "${err_file}" 2>/dev/null || true)"; rm -f "${err_file}"

    # Primary: the transactionHash field of the stdout JSON receipt.
    hash="$(printf '%s' "${out}" | jq -r '.transactionHash // empty' 2>/dev/null || true)"
    if [[ ! "${hash}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        hash=""
        # Fallback ONLY when nothing was reverted / estimation-failed. A pre-broadcast node-side revert sent
        # NOTHING; its revert calldata (a selector+args blob) must never be adopted as a tx hash.
        if ! printf '%s\n%s' "${out}" "${err_text}" | grep -qiE 'revert|estimat'; then
            # Tier 1: the receipt's transactionHash FIELD, matched textually (tolerant of stderr noise that
            # broke the full-document jq above).
            hash="$(printf '%s' "${out}" | grep -oE '"transactionHash" *: *"0x[0-9a-fA-F]{64}"' \
                | grep -oE '0x[0-9a-fA-F]{64}' | head -1 || true)"
            # Tier 2: a STANDALONE 64-hex token echoed in an error line — never a 64-char slice of a longer
            # blob. BSD grep on macOS lacks a reliable \b, so grab one OPTIONAL trailing hex char and keep only
            # exact-length-66 hits: grep's leftmost-longest match over a longer blob captures 65 hex (length 67
            # -> filtered), while a bare hash captures exactly 64 (length 66 -> kept).
            [[ "${hash}" =~ ^0x[0-9a-fA-F]{64}$ ]] || hash="$(printf '%s\n%s' "${out}" "${err_text}" \
                | grep -oE '0x[0-9a-fA-F]{64}[0-9a-fA-F]?' | awk 'length == 66' | head -1 || true)"
        fi
    fi
    if [[ "${hash}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        journal_set "${DEST_PREFIX}_BURN_TX" "${hash}"; BURN_TX="${hash}"
        if (( rc == 0 )); then
            ok "burn broadcast via cast send: tx ${hash}"
        else
            warn "burn submitted despite non-zero exit; adopting ${hash}, NOT re-burning."
        fi
        return 0
    fi
    err "burn did not submit (cast send rc=${rc}) and no tx hash was found in its output."
    err "  DO NOT blindly re-run: a depositForBurn that landed must not be repeated (it would double-burn)."
    err "  check ${ACTOR}'s recent txs on ${ARC_EXPLORER}/address/${ACTOR} before re-running (the BURN_ATTEMPTED"
    err "  sentinel now blocks an automatic re-burn until you reconcile — see the READY-TO-BURN guard)."
    return 1
}

# Single Iris check for the burn tx (SOURCE domain 26 = Arc). Journals MESSAGE + ATTESTATION (+ FEE_EXECUTED)
# and returns 0 when the attestation is complete; returns 1 while it is still pending. curl retries transient
# failures 3x.
fetch_attestation() {
    local resp status msg att fee
    resp="$(curl -sf --retry 3 --retry-delay 2 "${IRIS_API}/v2/messages/${ARC_SRC_DOMAIN}?transactionHash=${BURN_TX}" 2>/dev/null || true)"
    [[ -n "${resp}" ]] || return 1
    status="$(echo "${resp}" | jq -r '.messages[0].status // empty')"
    [[ "${status}" == "complete" ]] || return 1
    msg="$(echo "${resp}" | jq -r '.messages[0].message // empty')"
    att="$(echo "${resp}" | jq -r '.messages[0].attestation // empty')"
    fee="$(echo "${resp}" | jq -r '.messages[0].decodedMessageBody.feeExecuted // empty')"
    [[ "${msg}" =~ ^0x[0-9a-fA-F]+$ && "${att}" =~ ^0x[0-9a-fA-F]+$ ]] || return 1
    journal_set "${DEST_PREFIX}_MESSAGE" "${msg}"; MESSAGE="${msg}"
    journal_set "${DEST_PREFIX}_ATTESTATION" "${att}"; ATTESTATION="${att}"
    [[ -n "${fee}" ]] && journal_set "${DEST_PREFIX}_FEE_EXECUTED" "${fee}"
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

# Relay the attested message on the CURRENT destination (destination fork only). Calls Circle's
# MessageTransmitterV2.receiveMessage DIRECTLY (the destinations carry no diamond). Retries twice.
crank_relay() {
    require_auth || return 1
    local attempt=0 rc
    while (( attempt < 3 )); do
        rc=0
        # shellcheck disable=SC2086
        forge script "${SCRIPT_TARGET}" \
            --sig 'cctpDemoRelay(string,bytes,bytes)' "${DEST}" "${MESSAGE}" "${ATTESTATION}" \
            ${FORGE_AUTH} --broadcast --slow || rc=$?
        if (( rc == 0 )); then
            journal_set "${DEST_PREFIX}_RELAYED" 1; RELAYED=1
            ok "relay broadcast on ${DEST_HUMAN}"
            return 0
        fi
        attempt=$(( attempt + 1 ))
        warn "relay crank failed (attempt ${attempt}/3); retrying in 5s..."
        sleep 5
    done
    err "relay crank failed after 3 attempts"
    return 1
}

# Assert the credited amount for the CURRENT destination and mark it DELIVERED. Bounds use the fee policy
# CAPTURED AT BURN TIME (BURN_AMOUNT/BURN_MAXFEE) so a later default-env --once run does not false-fail a
# FAST=1 burn; when Iris reported the exact FEE_EXECUTED the check tightens to that exact credit. Destination
# gas is ETH (never netted from the credit) — there is NO native-gas allowance.
verify_and_finish() {
    local delta lo hi
    delta=$(( DSTBAL - DST_BASELINE ))
    lo=$(( BURN_AMOUNT - BURN_MAXFEE )); hi=${BURN_AMOUNT}
    if [[ -n "${FEE_EXECUTED}" ]]; then
        lo=$(( BURN_AMOUNT - FEE_EXECUTED )); hi=${lo}
    fi
    if (( delta < lo || delta > hi )); then
        err "DELIVERED but credited ${delta} is outside [${lo}, ${hi}] (baseline ${DST_BASELINE}, dstBal ${DSTBAL})."
        return 1
    fi
    ok "DELIVERED: ${DEST_HUMAN} credited ${delta} USDC units (baseline ${DST_BASELINE} -> ${DSTBAL}, within [${lo}, ${hi}])."
    journal_set "${DEST_PREFIX}_DELIVERED" 1
    return 0
}

# Print the combined summary + explorer links and delete the journal — ONLY once EVERY KNOWN destination is
# DELIVERED. The journal is SHARED (one hub + both destinations), so a FILTERED run (loop <actor> base) must
# never erase the other destination's in-flight state or the hub record: gate on `sepolia base`, not the
# filtered ${DESTS[@]}. load_diamond before printing the hub link (the --once early-exit path may not have).
finalize_all() {
    local d btx
    for d in sepolia base; do
        dest_meta "${d}"
        dest_delivered "${DEST_PREFIX}" || { info "journal kept: ${d} is not yet DELIVERED (run the loop for it to finish)."; return 0; }
    done
    load_diamond
    ok "ALL destinations DELIVERED — Arc-hub demo complete."
    ok "  hub (Arc source): ${ARC_EXPLORER}/address/${DIAMOND}"
    for d in sepolia base; do
        dest_meta "${d}"
        btx="$(journal_get "${DEST_PREFIX}_BURN_TX")"
        [[ -n "${btx}" ]] && ok "  ${DEST_HUMAN} burn (Arc): ${ARC_EXPLORER}/tx/${btx}"
        ok "  ${DEST_HUMAN} mint: ${DEST_EXPLORER}/address/${ACTOR}"
    done
    rm -f "${JOURNAL}"
}

# One status-driven decision for the CURRENT destination (${DEST}). Returns 0 (took a step), 10 (this dest
# done), or 1 (error). Sets DID + SLEEP_FOR.
step() {
    load_diamond
    load_dest_journal "${DEST_PREFIX}"
    read_status || return 1
    info "status[${DEST}]: phase=${ST} ($(phase_name "${ST}")) wait=${WAIT}s done=${DONE} src=${SRCBAL} dst=${DSTBAL}"
    SLEEP_FOR=0; DID=""

    if [[ "${DONE}" == "1" ]]; then
        verify_and_finish || return 1
        DID="done"
        return 10
    fi

    case "${ST}" in
        0) # NEEDS-SETUP
            if [[ -n "${DIAMOND}" ]]; then
                err "status is NEEDS-SETUP but a hub is already set (${DIAMOND})."
                err "the journaled/adopted hub is not wired+registered for BOTH destinations."
                err "registration is fail-loud; refusing to re-run setup. Fix it or delete ${JOURNAL} and retry."
                return 1
            fi
            guard_stuck || return 1
            compute_fee_policy
            info "actionable now -> setup (deploy the Arc hub + wire BOTH destinations)."
            crank_setup || return 1
            DID="crank"; SLEEP_FOR=${CRANK_SETTLE_SECONDS}
            return 0
            ;;
        1) # NEEDS-FUNDS — never automate funding.
            warn "NEEDS-FUNDS: actor ${ACTOR} holds ${SRCBAL} of the ${AMOUNT} Arc USDC units required."
            info "Fund via https://faucet.circle.com : Arc testnet USDC -> ${ACTOR} (>= 1 USDC; also the Arc gas token)."
            info "  destinations also need relay gas: Sepolia ETH and/or Base Sepolia ETH on ${ACTOR}."
            DID="funds"
            return 1
            ;;
        2) # READY-TO-BURN
            if [[ -z "${BURN_TX}" && "${BURN_ATTEMPTED}" == "1" ]]; then
                err "a previous burn attempt for ${DEST} may have been submitted but never journaled (interrupted run)."
                err "  check ${ACTOR}'s recent txs on ${ARC_EXPLORER}/address/${ACTOR}:"
                err "  - if a depositForBurn landed, journal it:  echo '${DEST_PREFIX}_BURN_TX=<hash>' >> ${JOURNAL}"
                err "  - if nothing landed, remove the ${DEST_PREFIX}_BURN_ATTEMPTED line from ${JOURNAL} and re-run."
                return 1
            fi
            guard_stuck || return 1
            compute_fee_policy
            info "actionable now -> burn toward ${DEST_HUMAN} (records the destination baseline, then burns ${AMOUNT})."
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
                info "actionable now -> relay (mint on ${DEST_HUMAN})."
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

# ---- --once: single step of the current destination, no looping --------------
if (( ONCE )); then
    CUR="$(pick_current_dest)"
    if [[ -z "${CUR}" ]]; then
        info "all driven destinations already DELIVERED."
        finalize_all
        exit 0
    fi
    DEST="${CUR}"; dest_meta "${DEST}"
    rc=0; step || rc=$?
    if (( rc == 10 )); then
        finalize_all
        exit 0
    fi
    (( rc == 0 )) || exit 1
    if [[ "${DID}" == "sleep" ]]; then
        info "(--once) would next act on ${DEST} in ~${SLEEP_FOR}s; exiting for the caller to reschedule."
    fi
    exit 0
fi

# ---- continuous loop: drive each destination to DELIVERED, then the next -----
iter=0
for DEST in "${DESTS[@]}"; do
    dest_meta "${DEST}"
    if dest_delivered "${DEST_PREFIX}"; then
        info "${DEST} (${DEST_HUMAN}) already DELIVERED (journal); skipping."
        continue
    fi
    info "=== driving destination ${DEST} (${DEST_HUMAN}) ==="
    while (( iter < MAX_ITERS )); do
        iter=$(( iter + 1 ))
        if (( SECONDS > MAX_WALL_SECONDS )); then
            err "wall-clock cap ${MAX_WALL_SECONDS}s exceeded after ${iter} iterations; aborting."
            exit 1
        fi
        info "iteration ${iter}/${MAX_ITERS} (elapsed ${SECONDS}s, dest ${DEST})"
        rc=0; step || rc=$?
        if (( rc == 10 )); then break; fi
        (( rc == 0 )) || { err "aborting after a failed step."; exit 1; }
        if (( SLEEP_FOR > 0 )); then sleep "${SLEEP_FOR}"; fi
    done
    if ! dest_delivered "${DEST_PREFIX}"; then
        err "iteration cap ${MAX_ITERS} reached without ${DEST} delivering; aborting (re-run to continue)."
        exit 1
    fi
done

finalize_all
exit 0
