#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# governance-demo-loop.sh
#
# External autonomous driver for the post-deploy governance demo on a Lattice
# self-governed ENS vault (see DeployGovernedVaultENS.governanceDemo). Each
# proposal phase has a time gate (votingDelay -> votingPeriod -> timelock), so
# the demo can only advance as blocks pass. This loop reads the vault's
# machine-readable status, then either sleeps until the next phase is due or
# sends the next crank transaction -- unattended, until the proposal executes.
#
# HOW IT WORKS
#   Each iteration:
#     1. READ status (no --broadcast, no signing): a dry-run `forge script`
#        call to `governanceDemoStatus(address,string,address)` prints one line
#            DEMO-STATUS <state> <waitSeconds> <done> <attempt>
#        which this script greps + parses.
#     2. DISPATCH:
#          done == 1        -> log success and exit 0.
#          waitSeconds > 0  -> sleep (waitSeconds + pad) until the phase is due.
#          else (actionable)-> send the crank via `governanceDemo(...)` under
#                              $FORGE_AUTH --broadcast, then settle ~2 blocks so
#                              the next read sees mined state.
#   The on-chain crank self-heals across a Defeated attempt (fresh proposal id),
#   so a single missed window never permanently bricks the loop.
#
# USAGE
#   script/config/governance-demo-loop.sh [--once] <vault> <ens-name> <actor-address>
#     --once   Run a single status-driven step (crank if actionable, else print
#              the wait) and exit -- composable with cron/systemd timers.
#
#   IMPORTANT: <actor-address> MUST equal your $FORGE_AUTH --account keystore address. The crank votes
#   as the keystore SIGNER, while status checks whether <actor-address> has voted -- if they differ the
#   vote lands but status never sees it, and the loop cannot observe progress (the stuck-detector aborts).
#
# ENVIRONMENT
#   FORGE_AUTH   Forge keystore auth passed VERBATIM to the crank (broadcast)
#                call, e.g. "--account daveKey". For UNATTENDED runs add a
#                password file:  --account daveKey --password-file .demo.pw
#                where .demo.pw is a GITIGNORED file YOU create holding the
#                KEYSTORE PASSWORD (not a raw private key). This script NEVER
#                creates, writes, reads, or echoes that file -- it only forwards
#                $FORGE_AUTH. Status reads need no auth (read-only).
#   RPC          forge --rpc-url alias/URL (default: "sepolia").
#   MAX_ITERS    Safety cap on loop iterations (default: 50).
#   MAX_WALL_SECONDS  Safety cap on total wall-clock seconds (default: 14400 = 4h).
#   CRANK_SETTLE_SECONDS  Post-crank settle sleep (default: 24 ~= 2 Sepolia blocks).
#   WAIT_PAD_SECONDS      Padding added to a phase wait before re-reading (default: 15).
#   NO_COLOR     Set to disable ANSI color.
#
# REQUIRES: foundry (`forge`). Run from anywhere (resolves the repo root).
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

SCRIPT_TARGET="script/base/defi/DeployGovernedVaultENS.s.sol:DeployGovernedVaultENS"

# ---- presentation -------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_INFO=$'\033[0;36m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'; C_OFF=$'\033[0m'
else
    C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_OFF=''
fi
info() { echo "${C_INFO}[demo-loop]${C_OFF} $*"; }
ok()   { echo "${C_OK}[demo-loop]${C_OFF} $*"; }
warn() { echo "${C_WARN}[demo-loop]${C_OFF} $*" >&2; }
err()  { echo "${C_ERR}[demo-loop] ERROR:${C_OFF} $*" >&2; }

usage() {
    sed -n '2,60p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# ---- argument parsing ---------------------------------------------------------
ONCE=0
if [[ "${1:-}" == "--once" ]]; then ONCE=1; shift; fi
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
if [[ $# -ne 3 ]]; then err "expected <vault> <ens-name> <actor-address> (got $#)"; usage 2; fi

VAULT="$1"; ENS_NAME="$2"; ACTOR="$3"
[[ "${VAULT}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "vault is not a 20-byte address: ${VAULT}"; exit 2; }
[[ "${ACTOR}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "actor is not a 20-byte address: ${ACTOR}"; exit 2; }
[[ -n "${ENS_NAME}" ]] || { err "ens-name is empty"; exit 2; }

RPC="${RPC:-sepolia}"
FORGE_AUTH="${FORGE_AUTH:-}"
MAX_ITERS="${MAX_ITERS:-50}"
MAX_WALL_SECONDS="${MAX_WALL_SECONDS:-14400}"
CRANK_SETTLE_SECONDS="${CRANK_SETTLE_SECONDS:-24}"
WAIT_PAD_SECONDS="${WAIT_PAD_SECONDS:-15}"

command -v forge >/dev/null 2>&1 || { err "forge not found on PATH"; exit 2; }

# Preflight: continuous mode WILL broadcast, so a missing FORGE_AUTH is a config error to catch NOW —
# not after a wasted status read + 3 failed cranks. (--once may run a read-only step without it; a --once
# crank with empty FORGE_AUTH still fails cleanly at crank() below rather than as a raw forge error.)
if (( ! ONCE )) && [[ -z "${FORGE_AUTH}" ]]; then
    err "continuous mode broadcasts and needs FORGE_AUTH set (the keystore auth forwarded to the crank)."
    err "  e.g.  FORGE_AUTH='--account daveKey'   or   FORGE_AUTH='--account daveKey --password-file .pw'"
    err "  (.pw is a GITIGNORED file YOU create holding the KEYSTORE PASSWORD, not a raw private key.)"
    err "  use --once for a read-only status check without broadcasting."
    exit 2
fi

# Parsed status (globals set by read_status).
ST=""; WAIT=""; DONE=""; ATT=""
# Action selected by step(): "crank" | "sleep" | "done" (+ SLEEP_FOR seconds).
DID=""; SLEEP_FOR=0
# Stuck-crank detector: the "state:attempt" signature of the most recent ACTIONABLE crank, and how many
# consecutive actionable cranks have seen that same signature. A successful crank always moves the
# proposal OFF its actionable signature, so a repeat means the last crank made no progress (2 => abort).
LAST_ACTIONABLE_SIG=""; STUCK_COUNT=0

phase_name() {
    case "$1" in
        8) echo "propose" ;;
        0) echo "wait-for-voting-open" ;;
        1) echo "cast-vote" ;;
        4) echo "queue" ;;
        5) echo "execute" ;;
        7) echo "executed" ;;
        *) echo "state-$1" ;;
    esac
}

# READ-ONLY status probe -> ST WAIT DONE ATT. Retries twice, then fails.
read_status() {
    local out line attempt=0
    while (( attempt < 3 )); do
        if out="$(forge script "${SCRIPT_TARGET}" \
                    --sig 'governanceDemoStatus(address,string,address)' \
                    "${VAULT}" "${ENS_NAME}" "${ACTOR}" \
                    --rpc-url "${RPC}" 2>&1)"; then
            line="$(echo "${out}" | grep -oE 'DEMO-STATUS [0-9]+ [0-9]+ [0-9]+ [0-9]+' | tail -1 || true)"
            if [[ -n "${line}" ]]; then
                read -r _ ST WAIT DONE ATT <<<"${line}"
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

# Send the next crank (broadcast + auth). Retries twice, then fails.
crank() {
    if [[ -z "${FORGE_AUTH}" ]]; then
        err "cannot crank: FORGE_AUTH is empty — broadcasting needs keystore auth (e.g. --account daveKey)."
        return 1
    fi
    local attempt=0
    while (( attempt < 3 )); do
        # $FORGE_AUTH is intentionally UNQUOTED so "--account daveKey" splits into
        # two argv words; it is forwarded verbatim and never inspected.
        # shellcheck disable=SC2086
        if forge script "${SCRIPT_TARGET}" \
                --sig 'governanceDemo(address,string)' \
                "${VAULT}" "${ENS_NAME}" \
                ${FORGE_AUTH} --broadcast --rpc-url "${RPC}"; then
            return 0
        fi
        attempt=$(( attempt + 1 ))
        warn "crank failed (attempt ${attempt}/3); retrying in 5s..."
        sleep 5
    done
    err "crank failed after 3 attempts"
    return 1
}

# One status-driven decision. Returns 0 (took a step), 10 (done), or 1 (error).
step() {
    read_status || return 1
    info "status: state=${ST} wait=${WAIT}s done=${DONE} attempt=${ATT} (next: $(phase_name "${ST}"))"
    if [[ "${DONE}" == "1" ]]; then
        ok "governance demo COMPLETE (attempt ${ATT} executed): six selectors frozen + ENS reasserted."
        DID="done"
        return 10
    fi
    if (( WAIT > 0 )); then
        SLEEP_FOR=$(( WAIT + WAIT_PAD_SECONDS ))
        DID="sleep"
        info "phase not due yet; sleeping ${SLEEP_FOR}s until $(phase_name "${ST}")."
        return 0
    fi
    # Stuck-crank guard. A SUCCESSFUL actionable crank always moves the proposal OFF this (state, attempt)
    # actionable signature (propose 8->Pending, vote Active-actionable->Active-waiting, queue
    # Succeeded->Queued, execute Queued->Executed) -- all of which take the sleep/done branch on the next
    # read. So the SAME actionable signature recurring means the previous crank produced NO progress. The
    # most common cause is ACTOR != the keystore signer: the vote lands as the signer, but status keeps
    # seeing ACTOR-not-voted (Active, wait 0) forever. One such crank is suspicious; two identical = abort.
    local sig="${ST}:${ATT}"
    if [[ "${sig}" == "${LAST_ACTIONABLE_SIG}" ]]; then
        STUCK_COUNT=$(( STUCK_COUNT + 1 ))
    else
        LAST_ACTIONABLE_SIG="${sig}"
        STUCK_COUNT=1
    fi
    if (( STUCK_COUNT >= 2 )); then
        err "crank did not advance proposal state after ${STUCK_COUNT} actionable attempts (signature ${sig})."
        err "most likely cause: ACTOR (${ACTOR}) does not match your --account keystore address —"
        err "the vote is cast by the keystore SIGNER, not ACTOR, so status keeps seeing ACTOR-not-voted."
        err "pass your keystore's address as the 3rd argument (it MUST equal the --account address)."
        return 1
    fi
    info "actionable now -> cranking ($(phase_name "${ST}"))."
    crank || return 1
    SLEEP_FOR=${CRANK_SETTLE_SECONDS}
    DID="crank"
    return 0
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
