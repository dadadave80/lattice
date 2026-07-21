#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cctp-roundtrip-demo.sh
#
# LIVE round trip of REAL testnet USDC between Circle's Arc testnet and Base
# Sepolia, through Lattice diamonds on BOTH ends (see CCTPHookDemo):
#
#   OUT:  burn on Arc via the hub (cast send) -> Iris attests in SECONDS (Arc
#         finality) -> relayMessage on Base via the destination diamond (forge)
#         mints the USDC to the actor.
#   BACK: burn on Base via the SAME diamond (forge; Base USDC is a normal
#         ERC-20) -> Iris attests after Base Sepolia's L1 finality (~13-19 min
#         on the free standard tier; be patient) -> cast-send relayMessage on
#         the Arc hub mints the USDC back to the actor (forge cannot simulate
#         Arc's native-USDC mint precompile; the Arc node executes it).
#
# LINEAR with a resume journal (.cctp-demo.roundtrip.env, gitignored): a re-run
# resumes instead of re-burning. Deployment is SEPARATE (`make deploy-cctp`)
# and shared with the other demos; the round trip needs a stack whose Base
# diamond has Arc REGISTERED as a return destination — stacks deployed before
# round-trip support read not-ready, and the script prints the exact admin
# commands that upgrade them.
#
# USAGE
#   script/config/cctp-roundtrip-demo.sh [--legs out|back|both] [<actor-address>]
#     --legs   Which legs to run (default both): `out` = Arc -> Base only (stops
#              after the Base mint is verified); `back` = Base -> Arc only (the
#              actor must already hold the Base USDC); `both` = the round trip.
#     <actor>  OPTIONAL. Omitted -> derived from the $FORGE_AUTH signer. The
#              USDC leaves from and returns to this address (it MUST be the
#              signer — both burns pull from the signer).
#
# RPC: needs ARC_TESTNET_RPC_URL and BASE_SEPOLIA_RPC_URL (shell env or ./.env;
# names match foundry.toml's [rpc_endpoints] — see .env.example).
#
# ENVIRONMENT
#   FORGE_AUTH  Signer auth forwarded VERBATIM to every broadcast/cast: a
#               keystore ("--account <name> [--password-file <f>]") or a raw
#               key ("--private-key 0x<key>", testnet only). NEVER echoed.
#               Prefer `make demo-cctp-roundtrip KEYSTORE=<name>` (any OS) or
#               `PRIVATE_KEY=0x<key>`, which materialize it.
#   AMOUNT      USDC units for the round trip (default 1000000 = 1 USDC).
#   DEMO_ARC_HUB / DEMO_BASE_DIAMOND   Deployment override (set BOTH).
#   IRIS_API / IRIS_POLL_SECONDS       Iris polling knobs.
#   OUT_ATTEST_TIMEOUT_SECONDS   Outbound attestation cap (default 300; Arc
#                                attests in seconds).
#   BACK_ATTEST_TIMEOUT_SECONDS  Return attestation cap (default 1800; the
#                                free tier waits for Base's L1 finality).
#   ARC_GAS_ALLOWANCE  Arc-side gas tolerance (USDC units) on the final check:
#                      Arc's gas IS USDC, so the return relay's own gas nets
#                      out of the returned balance (default 100000 = 0.1 USDC).
#
# REQUIRES: foundry (forge, cast), jq, curl. Run from anywhere.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

SCRIPT_TARGET="script/base/crosschain/CCTPHookDemo.s.sol:CCTPHookDemo"
ARC_USDC="0x3600000000000000000000000000000000000000"
ARC_SRC_DOMAIN=26
BASE_SRC_DOMAIN=6
ARC_EXPLORER="https://testnet.arcscan.app"
BASE_EXPLORER="https://base-sepolia.blockscout.com"
JOURNAL=".cctp-demo.roundtrip.env"
DEPLOY_JOURNAL=".cctp-demo.deployment.env"
# The canonical LIVE deployment (README evidence contracts) — round-trip-ready: its admin registered
# Arc on the Base diamond on 2026-07-21 (registerChainDomain 0xe1f35d97…e561 + configureDomain
# 0x76037c67…1587 on Base Sepolia); the return-ready preflight below verifies it live either way.
CANON_ARC_HUB="0x6ca99B6179eAc891E3aCD4008b610fcE66F63E2d"
CANON_BASE_DIAMOND="0x957259C5AEAa521c9DcFaEb6692C25ae53F349f1"

FORGE_AUTH="${FORGE_AUTH:-}"
AMOUNT="${AMOUNT:-1000000}"
IRIS_API="${IRIS_API:-https://iris-api-sandbox.circle.com}"
IRIS_POLL_SECONDS="${IRIS_POLL_SECONDS:-5}"
OUT_ATTEST_TIMEOUT_SECONDS="${OUT_ATTEST_TIMEOUT_SECONDS:-300}"
BACK_ATTEST_TIMEOUT_SECONDS="${BACK_ATTEST_TIMEOUT_SECONDS:-1800}"
ARC_GAS_ALLOWANCE="${ARC_GAS_ALLOWANCE:-100000}"

# ---- presentation -------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_INFO=$'\033[0;36m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'; C_OFF=$'\033[0m'
else
    C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_OFF=''
fi
info() { echo "${C_INFO}[roundtrip]${C_OFF} $*"; }
ok()   { echo "${C_OK}[roundtrip]${C_OFF} $*"; }
warn() { echo "${C_WARN}[roundtrip]${C_OFF} $*" >&2; }
err()  { echo "${C_ERR}[roundtrip] ERROR:${C_OFF} $*" >&2; }

T_RUN_START=${SECONDS}
D_OUT_BURN=""; D_OUT_ATTEST=""; D_OUT_RELAY=""; D_BACK_BURN=""; D_BACK_ATTEST=""; D_BACK_RELAY=""

# Scratch file for captured cast stderr (may embed API-keyed RPC URLs on transport errors) — trapped
# so an interrupted run never leaves raw tool output on disk. The journal is NOT trapped (resume).
ERR_FILE="$(mktemp "${TMPDIR:-/tmp}/cctp-roundtrip.err.XXXXXX")"
trap 'rm -f "${ERR_FILE}"' EXIT INT TERM

# ---- journals (KEY=VALUE; the run journal resumes, the deploy journal is read-only here) --------
_kv_get() { [[ -f "$1" ]] && sed -n "s/^$2=//p" "$1" | tail -1 || true; }
_kv_set() {
    local file="$1" key="$2" val="$3" tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    { [[ -f "${file}" ]] && grep -vE "^${key}=" "${file}" || true; echo "${key}=${val}"; } >"${tmp}"
    mv "${tmp}" "${file}"
}
journal_get() { _kv_get "${JOURNAL}" "$1"; }
journal_set() { _kv_set "${JOURNAL}" "$1" "$2"; }
deploy_journal_get() { _kv_get "${DEPLOY_JOURNAL}" "$1"; }

# ---- args ---------------------------------------------------------------------
ACTOR=""; LEGS="both"
expect_legs=0
for arg in "$@"; do
    if (( expect_legs == 1 )); then LEGS="${arg}"; expect_legs=0; continue; fi
    case "${arg}" in
        --legs) expect_legs=1; continue ;;
        --legs=*) LEGS="${arg#--legs=}"; continue ;;
    esac
    [[ "${arg}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "unrecognized arg '${arg}'; expected [--legs out|back|both] [<actor>]"; exit 2; }
    [[ -z "${ACTOR}" ]] || { err "too many args; expected [--legs out|back|both] [<actor>]"; exit 2; }
    ACTOR="${arg}"
done
(( expect_legs == 0 )) || { err "--legs needs a value: out | back | both"; exit 2; }
case "${LEGS}" in out | back | both) ;; *) err "invalid --legs '${LEGS}' (out | back | both)"; exit 2 ;; esac

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
BASE_RPC="$(resolve_rpc BASE_SEPOLIA_RPC_URL)"
scrub() { printf '%s' "$1" | sed -e "s#${ARC_RPC}#<arc-rpc>#g" -e "s#${BASE_RPC}#<base-rpc>#g"; echo; }

[[ -n "${FORGE_AUTH}" ]] || {
    err "no signer. Run via 'make demo-cctp-roundtrip KEYSTORE=<name>' (foundry keystore; unattended on"
    err "  macOS, attended prompts elsewhere) or 'make demo-cctp-roundtrip PRIVATE_KEY=0x<testnet-key>',"
    err "  or set FORGE_AUTH='--account <name> [--password-file <f>]' / '--private-key 0x<key>' yourself."
    exit 2
}

if [[ -z "${ACTOR}" ]]; then
    # shellcheck disable=SC2086
    ACTOR="$(cast wallet address ${FORGE_AUTH})" || { err "could not derive signer from FORGE_AUTH (add --password-file, or pass the address)."; exit 2; }
    [[ "${ACTOR}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "derived signer is not an address: '${ACTOR}'"; exit 2; }
    info "derived signer ${ACTOR} from the FORGE_AUTH keystore."
fi
info "actor=${ACTOR}  amount=${AMOUNT} (out AND back)"

# ---- resolve the deployment (never deploys; `make deploy-cctp` does) -----------
if [[ -n "${DEMO_ARC_HUB:-}" || -n "${DEMO_BASE_DIAMOND:-}" ]]; then
    [[ -n "${DEMO_ARC_HUB:-}" && -n "${DEMO_BASE_DIAMOND:-}" ]] \
        || { err "partial deployment override: set BOTH DEMO_ARC_HUB and DEMO_BASE_DIAMOND (or neither)."; exit 2; }
    ARC_HUB="${DEMO_ARC_HUB}"; BASE_DIAMOND="${DEMO_BASE_DIAMOND}"
    dep_src="env override"
else
    ARC_HUB="$(deploy_journal_get ARC_HUB)"; BASE_DIAMOND="$(deploy_journal_get BASE_DIAMOND)"
    if [[ -n "${ARC_HUB}" && -n "${BASE_DIAMOND}" ]]; then
        dep_src="your deployment, ${DEPLOY_JOURNAL}"
    else
        ARC_HUB="${CANON_ARC_HUB}"; BASE_DIAMOND="${CANON_BASE_DIAMOND}"
        dep_src="canonical live deployment; 'make deploy-cctp' deploys your own"
    fi
fi
for v in ARC_HUB BASE_DIAMOND; do
    [[ "${!v}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "${v} is not a 20-byte address: '${!v}'"; exit 2; }
done
info "deployment (${dep_src}):"
info "  hub (Arc):      ${ARC_EXPLORER}/address/${ARC_HUB}"
info "  diamond (Base): ${BASE_EXPLORER}/address/${BASE_DIAMOND}"

# A journaled half-done run is only resumable against the SAME deployment: each burn's mint is bound
# to its stack (the out leg's destinationCaller lock; the back leg's mintRecipient). Stamped at first
# spend, never on a run that got no further than a preflight.
j_dep="$(journal_get DEPLOYMENT)"
cur_dep="${ARC_HUB}:${BASE_DIAMOND}"
if [[ -n "${j_dep}" && "${j_dep}" != "${cur_dep}" ]]; then
    err "the run journal (${JOURNAL}) belongs to a different deployment:"
    err "  journaled: ${j_dep}"
    err "  selected:  ${cur_dep}"
    err "  resume against the journaled stack (DEMO_* env override), or rm ${JOURNAL} to start fresh."
    exit 2
fi

# The journal also pins the run IDENTITY — every journaled artifact (burn txs, baselines, the
# mintRecipient inside the attested messages) is bound to the ORIGINAL legs/actor/amount, and the
# advertised Ctrl-C point is mid-run: a re-parameterized resume must be caught, not absorbed.
if [[ -f "${JOURNAL}" ]]; then
    j_legs="$(journal_get LEGS)"; [[ -n "${j_legs}" ]] || j_legs="both"
    if [[ "${j_legs}" != "${LEGS}" ]]; then
        err "the run journal is a '--legs ${j_legs}' run; resume with that (or rm ${JOURNAL} to start fresh)."
        exit 2
    fi
    j_actor="$(journal_get ACTOR)"
    if [[ -n "${j_actor}" ]] \
        && [[ "$(printf '%s' "${j_actor}" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "${ACTOR}" | tr '[:upper:]' '[:lower:]')" ]]; then
        err "the run journal belongs to actor ${j_actor}; resuming as ${ACTOR} would verify the wrong"
        err "  balances (both mints are locked to the original actor). Re-run with that signer, or rm ${JOURNAL}."
        exit 2
    fi
    j_amount="$(journal_get AMOUNT)"
    if [[ -n "${j_amount}" && "${j_amount}" != "${AMOUNT}" ]]; then
        warn "resuming with the journaled amount ${j_amount} (overrides the requested ${AMOUNT})."
        AMOUNT="${j_amount}"
    fi
fi

# ---- return-ready preflight ----------------------------------------------------
# The BACK leg needs Arc registered as a destination ON the Base diamond. Check BEFORE burning
# anything outbound — a one-way stack must not take the out leg of a round trip. Skipped for an
# explicit '--legs out' (no return planned) and once the back burn exists (a deep resume already
# proved readiness by burning).
if [[ "${LEGS}" != "out" && -z "$(journal_get BACK_BURN_TX)" ]]; then
    ready="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoReturnReady(address)' "${BASE_DIAMOND}" --sender "${ACTOR}" 2>&1 | grep -oE 'DEMO-HOOK-RETURN-READY [01]' | awk '{print $2}' || true)"
    if [[ "${ready}" != "1" ]]; then
        err "this stack cannot return USDC to Arc: the Base diamond has no Arc destination registered"
        err "  (it predates round-trip support, or the read failed). Either run 'make deploy-cctp' for a"
        err "  fresh round-trip-ready stack, or have the stack's admin register the return leg:"
        err "    cast send ${BASE_DIAMOND} 'registerChainDomain(uint256,uint32)' 5042002 26 <auth> --rpc-url base-sepolia"
        err "    cast send ${BASE_DIAMOND} 'configureDomain(uint32,uint256,uint32,bytes32)' 26 0 2000 0x0000000000000000000000000000000000000000000000000000000000000000 <auth> --rpc-url base-sepolia"
        exit 1
    fi
    info "return leg ready: the Base diamond has Arc registered (round trip supported)."
fi

# Adopt a STANDALONE 64-hex tx hash from cast output: the --json receipt's transactionHash, else a
# bare hash on an error line — never a 64-slice of a longer blob, and NEVER when a revert marker is
# present (revert calldata must not be adopted as a hash).
extract_tx_hash() {
    local out="$1" err_text="$2" hash
    hash="$(printf '%s' "${out}" | jq -r '.transactionHash // empty' 2>/dev/null || true)"
    if [[ ! "${hash}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        hash=""
        if ! printf '%s\n%s' "${out}" "${err_text}" | grep -qiE 'revert|estimat'; then
            hash="$(printf '%s\n%s' "${out}" "${err_text}" | grep -oE '0x[0-9a-fA-F]{64}[0-9a-fA-F]?' | awk 'length == 66' | head -1 || true)"
        fi
    fi
    printf '%s' "${hash}"
}

# Poll Iris for a burn's message + attestation. Args: <src-domain> <burn-tx> <timeout-s> <label>.
# Sets IRIS_MESSAGE / IRIS_ATTESTATION on success; returns 1 on timeout.
IRIS_MESSAGE=""; IRIS_ATTESTATION=""
await_attestation() {
    local domain="$1" burn_tx="$2" timeout="$3" label="$4" t0 deadline resp status last_status=""
    local iris_display="${IRIS_API}"
    [[ "${IRIS_API}" == "https://iris-api-sandbox.circle.com" ]] || iris_display="<custom IRIS_API>"
    info "awaiting Iris attestation for the ${label} leg (poll ${IRIS_POLL_SECONDS}s, cap ${timeout}s); watch:"
    info "  ${iris_display}/v2/messages/${domain}?transactionHash=${burn_tx}"
    IRIS_MESSAGE=""; IRIS_ATTESTATION=""
    t0=${SECONDS}
    deadline=$(( SECONDS + timeout ))
    while (( SECONDS < deadline )); do
        resp="$(curl -sf --retry 3 --retry-delay 2 "${IRIS_API}/v2/messages/${domain}?transactionHash=${burn_tx}" 2>/dev/null || true)"
        if [[ -z "${resp}" ]]; then
            status="not-indexed-yet (or iris unreachable)"
        else
            status="$(echo "${resp}" | jq -r '.messages[0].status // "message-not-indexed-yet"' 2>/dev/null || true)"
            [[ -n "${status}" ]] || status="unparseable-iris-response"
        fi
        if [[ "${status}" != "${last_status}" ]]; then
            info "  iris[${label}]: ${status} (+$(( SECONDS - t0 ))s)"
            last_status="${status}"
        fi
        if [[ -n "${resp}" && "${status}" == "complete" ]]; then
            IRIS_MESSAGE="$(echo "${resp}" | jq -r '.messages[0].message // empty')"
            IRIS_ATTESTATION="$(echo "${resp}" | jq -r '.messages[0].attestation // empty')"
            if [[ "${IRIS_MESSAGE}" =~ ^0x[0-9a-fA-F]+$ && "${IRIS_ATTESTATION}" =~ ^0x[0-9a-fA-F]+$ ]]; then
                ok "${label} leg attested in $(( SECONDS - t0 ))s."
                return 0
            fi
        fi
        sleep "${IRIS_POLL_SECONDS}"
    done
    err "${label}-leg attestation not ready within ${timeout}s; re-run to resume (nothing is lost)."
    return 1
}

# Broadcast-free balance read via the demo script (credential-free; --sender avoids any ambient
# keystore unlock). Args: <sig-name> — hookDemoArcBalance | hookDemoBaseBalance. Echoes the balance.
read_balance() {
    forge script "${SCRIPT_TARGET}" --sig "$1(address)" "${ACTOR}" --sender "${ACTOR}" 2>&1 \
        | grep -oE 'DEMO-HOOK-(ARC|BASE)BAL [0-9]+' | tail -1 | awk '{print $2}' || true
}

# ---- OUT leg: Arc -> Base (skipped entirely by --legs back) --------------------
OUT_BURN_TX="$(journal_get OUT_BURN_TX)"
if [[ "${LEGS}" != "back" && -z "${OUT_BURN_TX}" ]]; then
    if [[ -n "$(journal_get OUT_BURN_ATTEMPTED)" ]]; then
        err "a previous OUT burn was dispatched but its tx hash was not recorded (interrupted run)."
        err "  check ${ARC_EXPLORER}/address/${ACTOR} for a recent depositForBurn:"
        err "    - if present: add 'OUT_BURN_TX=<hash>' to ${JOURNAL} and re-run to resume;"
        err "    - if absent:  remove the 'OUT_BURN_ATTEMPTED=1' line from ${JOURNAL} and re-run."
        exit 1
    fi
    BAL="$(read_balance hookDemoArcBalance)"
    if [[ -n "${BAL}" ]] && (( BAL < AMOUNT )); then
        err "actor holds ${BAL} of the ${AMOUNT} Arc USDC units needed (plus gas headroom — Arc gas IS USDC)."
        info "Fund via https://faucet.circle.com : Arc testnet USDC -> ${ACTOR}."
        exit 1
    fi
    # Baselines + stack pin, stamped at first spend: the OUT leg is verified by the actor's BASE
    # balance delta, the BACK leg by the ARC delta over a later pre-relay snapshot.
    BASE_BAL_BEFORE="$(journal_get BASE_BAL_BEFORE)"
    if [[ ! "${BASE_BAL_BEFORE}" =~ ^[0-9]+$ ]]; then
        BASE_BAL_BEFORE="$(read_balance hookDemoBaseBalance)"
        [[ "${BASE_BAL_BEFORE}" =~ ^[0-9]+$ ]] || { err "could not read the actor's Base USDC baseline (nothing spent yet); re-run."; exit 1; }
        journal_set DEPLOYMENT "${cur_dep}"
        journal_set LEGS "${LEGS}"
        journal_set ACTOR "${ACTOR}"
        journal_set AMOUNT "${AMOUNT}"
        journal_set BASE_BAL_BEFORE "${BASE_BAL_BEFORE}"
    fi
    R="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoRecipient(address)' "${ACTOR}" --sender "${ACTOR}" 2>&1 | grep -oE 'DEMO-HOOK-RECIPIENT 0x[0-9a-fA-F]+' | awk '{print $2}' || true)"
    [[ "${R}" =~ ^0x ]] || { err "could not encode the ERC-7930 recipient."; exit 1; }
    t0=${SECONDS}
    info "OUT: approving ${AMOUNT} Arc USDC to the hub..."
    : > "${ERR_FILE}"
    # stderr through the scrub path — a transport error embeds the API-keyed RPC URL.
    # shellcheck disable=SC2086
    cast send "${ARC_USDC}" "approve(address,uint256)" "${ARC_HUB}" "${AMOUNT}" ${FORGE_AUTH} --rpc-url "${ARC_RPC}" >/dev/null 2>"${ERR_FILE}" \
        || { scrub "$(cat "${ERR_FILE}")"; err "OUT approve failed; nothing was burned. Fix the cause and re-run."; exit 1; }
    info "OUT: burning ${AMOUNT} Arc USDC -> Base (mint to the actor; locked to the Base diamond)..."
    journal_set OUT_BURN_ATTEMPTED 1
    rc=0
    : > "${ERR_FILE}"
    # shellcheck disable=SC2086
    out="$(cast send "${ARC_HUB}" "depositForBurn(uint256,bytes)" "${AMOUNT}" "${R}" ${FORGE_AUTH} --rpc-url "${ARC_RPC}" --json 2>"${ERR_FILE}")" || rc=$?
    err_text="$(cat "${ERR_FILE}")"
    hash="$(extract_tx_hash "${out}" "${err_text}")"
    if [[ ! "${hash}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        if printf '%s\n%s' "${out}" "${err_text}" | grep -qiE 'revert|estimat'; then
            journal_set OUT_BURN_ATTEMPTED ""
            scrub "${err_text}"; err "OUT burn reverted before dispatch — nothing was sent. Fix the cause and re-run."; exit 1
        fi
        scrub "${err_text}"; err "OUT burn produced no tx hash; check ${ARC_EXPLORER}/address/${ACTOR} before re-running (never double-burn)."; exit 1
    fi
    # A dispatched-but-REVERTED burn has a hash but burned NOTHING — journaling it would wedge the
    # attestation poll forever. cast's --json receipt carries the status; trust it when present.
    tx_status="$(printf '%s' "${out}" | jq -r '.status // empty' 2>/dev/null || true)"
    if [[ "${tx_status}" == "0x0" ]]; then
        journal_set OUT_BURN_ATTEMPTED ""
        err "OUT burn tx REVERTED on-chain (nothing burned): ${ARC_EXPLORER}/tx/${hash}"
        err "  fix the cause and re-run."
        exit 1
    fi
    (( rc == 0 )) || warn "cast exited ${rc} after dispatching the OUT burn; adopting ${hash} (NOT re-burning)."
    journal_set OUT_BURN_TX "${hash}"; OUT_BURN_TX="${hash}"
    D_OUT_BURN=$(( SECONDS - t0 ))
    ok "OUT burned in ${D_OUT_BURN}s: ${ARC_EXPLORER}/tx/${OUT_BURN_TX}"
fi

OUT_MESSAGE="$(journal_get OUT_MESSAGE)"; OUT_ATTESTATION="$(journal_get OUT_ATTESTATION)"
if [[ "${LEGS}" != "back" ]] && [[ -z "${OUT_MESSAGE}" || -z "${OUT_ATTESTATION}" ]]; then
    t0=${SECONDS}
    await_attestation "${ARC_SRC_DOMAIN}" "${OUT_BURN_TX}" "${OUT_ATTEST_TIMEOUT_SECONDS}" "OUT" || exit 1
    OUT_MESSAGE="${IRIS_MESSAGE}"; OUT_ATTESTATION="${IRIS_ATTESTATION}"
    journal_set OUT_MESSAGE "${OUT_MESSAGE}"; journal_set OUT_ATTESTATION "${OUT_ATTESTATION}"
    D_OUT_ATTEST=$(( SECONDS - t0 ))
fi

if [[ "${LEGS}" != "back" && -z "$(journal_get OUT_RELAYED)" ]]; then
    info "OUT: relaying on Base — the diamond's relayMessage mints the USDC to the actor..."
    t0=${SECONDS}
    rc=0
    # shellcheck disable=SC2086
    out="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoRelayPlain(address,bytes,bytes)' "${BASE_DIAMOND}" "${OUT_MESSAGE}" "${OUT_ATTESTATION}" ${FORGE_AUTH} --broadcast --rpc-url base-sepolia 2>&1)" || rc=$?
    if (( rc == 0 )); then
        journal_set OUT_RELAYED 1
        D_OUT_RELAY=$(( SECONDS - t0 ))
        OUT_RELAY_TX="$(jq -r '.receipts[0].transactionHash // empty' broadcast/CCTPHookDemo.s.sol/84532/hookDemoRelayPlain-latest.json 2>/dev/null || true)"
        [[ "${OUT_RELAY_TX}" =~ ^0x[0-9a-fA-F]{64}$ ]] && journal_set OUT_RELAY_TX "${OUT_RELAY_TX}"
        ok "OUT relayed in ${D_OUT_RELAY}s${OUT_RELAY_TX:+: ${BASE_EXPLORER}/tx/${OUT_RELAY_TX}}"
    else
        warn "OUT relay did not succeed this run (it may already be relayed); verifying the balance..."
        scrub "${out}"
    fi
    sleep 6
fi

# OUT verify: the actor's Base balance must have grown by AMOUNT (fee 0 on the standard tier).
if [[ "${LEGS}" != "back" && -z "$(journal_get OUT_DELIVERED)" ]]; then
    BASE_BAL_BEFORE="$(journal_get BASE_BAL_BEFORE)"; [[ "${BASE_BAL_BEFORE}" =~ ^[0-9]+$ ]] || BASE_BAL_BEFORE=0
    base_bal="$(read_balance hookDemoBaseBalance)"
    [[ "${base_bal}" =~ ^[0-9]+$ ]] || { err "could not read the actor's Base USDC balance; re-run to resume."; exit 1; }
    if (( base_bal - BASE_BAL_BEFORE < AMOUNT )); then
        err "OUT leg not delivered yet: Base balance delta $(( base_bal - BASE_BAL_BEFORE )) < ${AMOUNT}; re-run to resume."
        exit 1
    fi
    journal_set OUT_DELIVERED 1
    ok "OUT leg DELIVERED: actor's Base USDC +$(( base_bal - BASE_BAL_BEFORE )) (Arc -> Base complete)."
fi

# --legs out stops here: the USDC now lives on Base, deliberately one-way.
if [[ "${LEGS}" == "out" ]]; then
    echo
    ok "ONE-WAY COMPLETE (--legs out): ${AMOUNT} USDC units moved Arc -> Base to ${ACTOR}."
    ok "  burn (Arc):   ${ARC_EXPLORER}/tx/${OUT_BURN_TX}"
    OUT_RELAY_TX="$(journal_get OUT_RELAY_TX)"
    [[ -n "${OUT_RELAY_TX}" ]] && ok "  relay (Base): ${BASE_EXPLORER}/tx/${OUT_RELAY_TX}"
    ok "  bring it home later with:  make demo-cctp-roundtrip ARGS='--legs back'"
    rm -f "${JOURNAL}"
    exit 0
fi

# ---- BACK leg: Base -> Arc -----------------------------------------------------
BACK_BURN_TX="$(journal_get BACK_BURN_TX)"
if [[ -z "${BACK_BURN_TX}" ]]; then
    if [[ -n "$(journal_get BACK_BURN_ATTEMPTED)" ]]; then
        err "a previous BACK burn may have been dispatched but was never recorded (interrupted run)."
        err "  check ${BASE_EXPLORER}/address/${ACTOR} for a recent depositForBurn:"
        err "    - if present: add 'BACK_BURN_TX=<hash>' to ${JOURNAL} and re-run to resume;"
        err "    - if absent:  remove the 'BACK_BURN_ATTEMPTED=1' line from ${JOURNAL} and re-run."
        exit 1
    fi
    # A back-only run spends FIRST here: fund-gate the Base USDC and stamp the run identity that
    # out/both runs stamp at the OUT burn (the DEPLOYMENT/ACTOR/AMOUNT guards need it on resume).
    if [[ "${LEGS}" == "back" ]]; then
        bb="$(read_balance hookDemoBaseBalance)"
        if [[ -n "${bb}" ]] && (( bb < AMOUNT )); then
            err "actor holds ${bb} of the ${AMOUNT} Base USDC units needed for the return burn."
            info "Bridge some out first (make demo-cctp-roundtrip, or ARGS='--legs out'), or fund ${ACTOR} on Base Sepolia."
            exit 1
        fi
        if [[ -z "$(journal_get DEPLOYMENT)" ]]; then
            journal_set DEPLOYMENT "${cur_dep}"
            journal_set LEGS "${LEGS}"
            journal_set ACTOR "${ACTOR}"
            journal_set AMOUNT "${AMOUNT}"
        fi
    fi
    info "BACK: burning ${AMOUNT} Base USDC -> Arc through the same diamond (forge; approve + burn, --slow)..."
    t0=${SECONDS}
    journal_set BACK_BURN_ATTEMPTED 1
    rc=0
    # shellcheck disable=SC2086
    out="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoReturnBurn(address,uint256)' "${BASE_DIAMOND}" "${AMOUNT}" ${FORGE_AUTH} --broadcast --slow --rpc-url base-sepolia 2>&1)" || rc=$?
    if (( rc != 0 )); then
        # forge is collect-then-dispatch: a body/simulation revert dispatches NOTHING — but a dispatch
        # failure mid-broadcast may have sent the approve and/or burn. Only clear the sentinel when the
        # broadcast journal shows no receipts for this run.
        scrub "${out}"
        err "BACK burn run failed. If a depositForBurn landed on ${BASE_EXPLORER}/address/${ACTOR}, journal it as"
        err "  BACK_BURN_TX=<hash>; if nothing landed, remove BACK_BURN_ATTEMPTED from ${JOURNAL} and re-run."
        exit 1
    fi
    BACK_BURN_TX="$(jq -r '.receipts | last | .transactionHash // empty' broadcast/CCTPHookDemo.s.sol/84532/hookDemoReturnBurn-latest.json 2>/dev/null || true)"
    [[ "${BACK_BURN_TX}" =~ ^0x[0-9a-fA-F]{64}$ ]] || { err "BACK burn broadcast but no receipt hash found; reconcile via ${BASE_EXPLORER}/address/${ACTOR} (journal BACK_BURN_TX=<hash>)."; exit 1; }
    journal_set BACK_BURN_TX "${BACK_BURN_TX}"
    D_BACK_BURN=$(( SECONDS - t0 ))
    ok "BACK burned in ${D_BACK_BURN}s: ${BASE_EXPLORER}/tx/${BACK_BURN_TX}"
fi

BACK_MESSAGE="$(journal_get BACK_MESSAGE)"; BACK_ATTESTATION="$(journal_get BACK_ATTESTATION)"
if [[ -z "${BACK_MESSAGE}" || -z "${BACK_ATTESTATION}" ]]; then
    info "the return leg attests after Base Sepolia's L1 finality (~13-19 min on the free tier) — the run"
    info "  resumes from here if interrupted (Ctrl-C is safe; re-run later to continue)."
    t0=${SECONDS}
    await_attestation "${BASE_SRC_DOMAIN}" "${BACK_BURN_TX}" "${BACK_ATTEST_TIMEOUT_SECONDS}" "BACK" || exit 1
    BACK_MESSAGE="${IRIS_MESSAGE}"; BACK_ATTESTATION="${IRIS_ATTESTATION}"
    journal_set BACK_MESSAGE "${BACK_MESSAGE}"; journal_set BACK_ATTESTATION "${BACK_ATTESTATION}"
    D_BACK_ATTEST=$(( SECONDS - t0 ))
fi

if [[ -z "$(journal_get BACK_RELAYED)" ]]; then
    # Snapshot the Arc balance IMMEDIATELY before the relay (journaled once): the final check is the
    # delta across this one tx — Arc gas is USDC, so the relay's own cost nets out of the mint.
    ARC_BAL_BEFORE="$(journal_get ARC_BAL_BEFORE)"
    if [[ ! "${ARC_BAL_BEFORE}" =~ ^[0-9]+$ ]]; then
        ARC_BAL_BEFORE="$(read_balance hookDemoArcBalance)"
        [[ "${ARC_BAL_BEFORE}" =~ ^[0-9]+$ ]] || { err "could not read the actor's Arc USDC baseline; re-run to resume."; exit 1; }
        journal_set ARC_BAL_BEFORE "${ARC_BAL_BEFORE}"
    fi
    info "BACK: relaying into Arc via the hub's relayMessage (cast send — the Arc NODE executes the"
    info "  native-USDC mint precompile that forge's revm cannot simulate)..."
    t0=${SECONDS}
    rc=0
    : > "${ERR_FILE}"
    # shellcheck disable=SC2086
    out="$(cast send "${ARC_HUB}" "relayMessage(bytes,bytes)" "${BACK_MESSAGE}" "${BACK_ATTESTATION}" ${FORGE_AUTH} --rpc-url "${ARC_RPC}" --json 2>"${ERR_FILE}")" || rc=$?
    err_text="$(cat "${ERR_FILE}")"
    hash="$(extract_tx_hash "${out}" "${err_text}")"
    tx_status="$(printf '%s' "${out}" | jq -r '.status // empty' 2>/dev/null || true)"
    if [[ "${hash}" =~ ^0x[0-9a-fA-F]{64}$ && "${tx_status}" == "0x0" ]]; then
        # A REVERTED relay must NOT set BACK_RELAYED — that would permanently disable the retry
        # path while the burned USDC waits attested. Keep the journal as-is and fail loudly.
        err "BACK relay tx REVERTED: ${ARC_EXPLORER}/tx/${hash} — the message is still relayable; re-run to retry."
        exit 1
    fi
    if [[ "${hash}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
        journal_set BACK_RELAYED 1
        journal_set BACK_RELAY_TX "${hash}"
        D_BACK_RELAY=$(( SECONDS - t0 ))
        ok "BACK relayed in ${D_BACK_RELAY}s: ${ARC_EXPLORER}/tx/${hash}"
    else
        warn "BACK relay did not confirm this run (a consumed nonce means it already landed); verifying the balance..."
        scrub "${err_text}"
    fi
    sleep 6
fi

# ---- final verify: the USDC is back on Arc -------------------------------------
ARC_BAL_BEFORE="$(journal_get ARC_BAL_BEFORE)"
[[ "${ARC_BAL_BEFORE}" =~ ^[0-9]+$ ]] || { err "no Arc baseline journaled; re-run to resume."; exit 1; }
arc_bal="$(read_balance hookDemoArcBalance)"
[[ "${arc_bal}" =~ ^[0-9]+$ ]] || { err "could not read the actor's Arc USDC balance; re-run to resume."; exit 1; }
delta=$(( arc_bal - ARC_BAL_BEFORE ))

echo
if (( delta > 0 && delta + ARC_GAS_ALLOWANCE >= AMOUNT )); then
    ok "ROUND TRIP COMPLETE: ${AMOUNT} USDC left Arc and came back (Arc delta +${delta}; the relay's own"
    ok "  gas nets out of the mint — Arc gas IS USDC)."
    ok "  out:  burn ${ARC_EXPLORER}/tx/${OUT_BURN_TX}"
    OUT_RELAY_TX="$(journal_get OUT_RELAY_TX)"
    [[ -n "${OUT_RELAY_TX}" ]] && ok "        relay ${BASE_EXPLORER}/tx/${OUT_RELAY_TX}"
    ok "  back: burn ${BASE_EXPLORER}/tx/${BACK_BURN_TX}"
    BACK_RELAY_TX="$(journal_get BACK_RELAY_TX)"
    [[ -n "${BACK_RELAY_TX}" ]] && ok "        relay ${ARC_EXPLORER}/tx/${BACK_RELAY_TX}"
    timings=""
    [[ -n "${D_OUT_BURN}" ]] && timings+="out-burn ${D_OUT_BURN}s · "
    [[ -n "${D_OUT_ATTEST}" ]] && timings+="out-attest ${D_OUT_ATTEST}s · "
    [[ -n "${D_OUT_RELAY}" ]] && timings+="out-relay ${D_OUT_RELAY}s · "
    [[ -n "${D_BACK_BURN}" ]] && timings+="back-burn ${D_BACK_BURN}s · "
    [[ -n "${D_BACK_ATTEST}" ]] && timings+="back-attest ${D_BACK_ATTEST}s · "
    [[ -n "${D_BACK_RELAY}" ]] && timings+="back-relay ${D_BACK_RELAY}s · "
    ok "  timings: ${timings}total $(( SECONDS - T_RUN_START ))s (resumed phases untimed)"
    rm -f "${JOURNAL}"
else
    warn "Arc balance delta ${delta} is below ${AMOUNT} - ${ARC_GAS_ALLOWANCE} (gas allowance); the relay may"
    warn "  still be settling — re-run shortly to re-verify (journal kept)."
    exit 1
fi
