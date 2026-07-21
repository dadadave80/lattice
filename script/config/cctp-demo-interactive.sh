#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cctp-demo-interactive.sh — `make demo`: the interactive front door to the
# CCTP demos. Prompts for direction, amount, and auth, then EXECS the hardened
# non-interactive driver with the env/args it already takes — no on-chain
# logic, journaling, or double-burn protection lives here (the children own
# all of it; automation keeps using the non-interactive targets).
#
#   [1] Round trip  Arc -> Base -> Arc   (cctp-roundtrip-demo.sh)
#   [2] One way     Arc -> Base          (cctp-roundtrip-demo.sh --legs out)
#   [3] One way     Base -> Arc          (cctp-roundtrip-demo.sh --legs back)
#   [4] Transfer    Arc -> Sepolia+Base  (cctp-usdc-demo-loop.sh)
#   [5] Hook        Arc -> Base vault    (cctp-hook-demo.sh)
#
# A half-done run's journal is detected BEFORE any prompt and offered for
# resume (direction/stack/amount re-derived from the journal; only auth is
# re-asked — secrets are never journaled). Requires a tty; in scripts use the
# non-interactive targets (demo-cctp-roundtrip / demo-cctp / demo-cctp-hook).
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_INFO=$'\033[0;36m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_BOLD=''; C_OFF=''
fi
info() { echo "${C_INFO}[demo]${C_OFF} $*"; }
ok()   { echo "${C_OK}[demo]${C_OFF} $*"; }
warn() { echo "${C_WARN}[demo]${C_OFF} $*" >&2; }
err()  { echo "${C_ERR}[demo] ERROR:${C_OFF} $*" >&2; }

# DEMO_ASSUME_TTY=1 lets tests drive the prompts through a pipe; real use needs a terminal
# (the prompts read stdin, and the children's progress rendering expects a tty).
if [[ "${DEMO_ASSUME_TTY:-0}" != "1" ]] && ! [[ -t 0 && -t 1 ]]; then
    err "interactive mode needs a terminal. In scripts/CI use the non-interactive targets:"
    err "  make demo-cctp-roundtrip | demo-cctp | demo-cctp-hook   (KEYSTORE=<name> or PRIVATE_KEY=0x…)"
    exit 2
fi

# ask <question> <default> — prints the answer (Enter keeps the default).
ask() {
    local ans
    read -rp "$1${2:+ [$2]}: " ans || true
    printf '%s' "${ans:-${2:-}}"
}
jget() { [[ -f "$1" ]] && sed -n "s/^$2=//p" "$1" | tail -1 || true; }

RT_J=".cctp-demo.roundtrip.env"; HOOK_J=".cctp-demo.hook.env"; LOOP_J=".cctp-demo.arc-hub.env"

echo "${C_BOLD}Lattice CCTP demo — real testnet USDC through diamonds on both ends${C_OFF}"
echo

# ---- resume scan (before any prompt: the children's own errors say 're-run to resume') --------
RESUME=""
for spec in "${RT_J}|round trip (Arc <-> Base)|rt" "${HOOK_J}|hook showcase (auto-credit vault)|hook" "${LOOP_J}|transfer loop (Arc -> Sepolia/Base)|loop"; do
    jfile="${spec%%|*}"; rest="${spec#*|}"; jdesc="${rest%%|*}"; jkind="${rest##*|}"
    [[ -f "${jfile}" ]] || continue
    info "found a half-done ${jdesc} run (${jfile})."
    choice="$(ask "  [r]esume it, [d]elete it, or [i]gnore" "r")"
    case "${choice}" in
        r | R) RESUME="${jkind}"; break ;;
        d | D) rm -f "${jfile}"; ok "  deleted ${jfile}." ;;
        *) warn "  ignoring it — a fresh run against the same stack may be refused by its guards." ;;
    esac
done
[[ -d "${LOOP_J}.lock" ]] && warn "stale transfer-loop lock ${LOOP_J}.lock — if no loop is running: rmdir ${LOOP_J}.lock"

# ---- direction ----------------------------------------------------------------
DIRECTION=""
case "${RESUME}" in
    rt)
        case "$(jget "${RT_J}" LEGS)" in out) DIRECTION=2 ;; back) DIRECTION=3 ;; *) DIRECTION=1 ;; esac
        info "resuming: direction and stack come from the journal."
        ;;
    hook) DIRECTION=5 ;;
    loop) DIRECTION=4 ;;
    *)
        echo
        echo "  ${C_BOLD}Where should the USDC go?${C_OFF}"
        echo "    [1] Round trip   Arc -> Base -> Arc   (out in seconds; return waits ~13-19 min for Base finality)"
        echo "    [2] One way      Arc -> Base"
        echo "    [3] One way      Base -> Arc          (you must already hold Base Sepolia USDC)"
        echo "    [4] Transfer     Arc -> Sepolia + Base (self-cranking loop, both destinations)"
        echo "    [5] Hook         Arc -> Base           (programmable USDC: vault auto-credits a beneficiary)"
        DIRECTION="$(ask "  direction" "1")"
        [[ "${DIRECTION}" =~ ^[1-5]$ ]] || { err "pick 1-5."; exit 2; }
        ;;
esac

# ---- stack --------------------------------------------------------------------
# Resume: re-derive the exact stack from the journal's DEPLOYMENT fingerprint so the child's
# guard sees the same one. Fresh: show what the child WILL resolve and offer an override; the
# child prints the authoritative resolution either way (the chains live there, not here).
if [[ "${RESUME}" == "rt" ]]; then
    dep="$(jget "${RT_J}" DEPLOYMENT)"
    if [[ -n "${dep}" ]]; then
        export DEMO_ARC_HUB="${dep%%:*}" DEMO_BASE_DIAMOND="${dep##*:}"
    fi
elif [[ "${RESUME}" == "hook" ]]; then
    dep="$(jget "${HOOK_J}" DEPLOYMENT)"
    if [[ -n "${dep}" ]]; then
        # hub:diamond:vault — the hook demo's override contract wants all three.
        export DEMO_ARC_HUB="${dep%%:*}" DEMO_VAULT="${dep##*:}"
        mid="${dep#*:}"; export DEMO_BASE_DIAMOND="${mid%%:*}"
    fi
elif [[ "${RESUME}" != "loop" ]]; then
    if [[ -f .cctp-demo.deployment.env ]]; then
        info "stack: your deployment (.cctp-demo.deployment.env, from 'make deploy-cctp')."
    else
        info "stack: the canonical live deployment (README evidence contracts; round-trip-ready)."
    fi
    if [[ "$(ask "  use it? [Y]es / [c]ustom addresses" "Y")" =~ ^[cC]$ ]]; then
        DEMO_ARC_HUB="$(ask "  Arc hub address" "")"
        DEMO_BASE_DIAMOND="$(ask "  Base diamond address" "")"
        for v in DEMO_ARC_HUB DEMO_BASE_DIAMOND; do
            [[ "${!v}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "${v} is not a 20-byte address."; exit 2; }
        done
        export DEMO_ARC_HUB DEMO_BASE_DIAMOND
        if [[ "${DIRECTION}" == "5" ]]; then
            DEMO_VAULT="$(ask "  CCTPHookVault address" "")"
            [[ "${DEMO_VAULT}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "DEMO_VAULT is not a 20-byte address."; exit 2; }
            export DEMO_VAULT
        fi
        if [[ "${DIRECTION}" == "4" ]]; then
            export DIAMOND="${DEMO_ARC_HUB}" BASE_DIAMOND="${DEMO_BASE_DIAMOND}"
        fi
    fi
fi

# ---- auth ---------------------------------------------------------------------
# Never echo FORGE_AUTH. AUTH_MODE: "keychain:<name>" dispatches via keychain-auth.sh (macOS
# unattended); anything else runs the child with the composed FORGE_AUTH in its environment.
AUTH_MODE="env"
ACTOR=""
auth_desc=""
if [[ -n "${FORGE_AUTH:-}" ]]; then
    case "${FORGE_AUTH}" in
        *--private-key*) auth_desc="private key (redacted)" ;;
        *--account*) auth_desc="keystore '$(printf '%s' "${FORGE_AUTH}" | sed -n 's/.*--account \([^ ]*\).*/\1/p')'" ;;
        *) auth_desc="FORGE_AUTH (redacted)" ;;
    esac
    if [[ "$(ask "sign with the ambient ${auth_desc}? [Y]es / [n]o, pick another" "Y")" =~ ^[nN]$ ]]; then
        FORGE_AUTH=""
    fi
fi
if [[ -z "${FORGE_AUTH:-}" ]]; then
    echo
    echo "  ${C_BOLD}How should transactions be signed?${C_OFF} (testnet keys only)"
    echo "    [1] foundry keystore (~/.foundry/keystores)"
    echo "    [2] raw private key (never echoed; visible in local process args while running)"
    case "$(ask "  auth" "1")" in
        1)
            i=0
            ks_names=()
            for f in "${HOME}/.foundry/keystores"/*; do
                [[ -e "${f}" ]] || continue
                i=$(( i + 1 )); ks_names+=("$(basename "${f}")")
                echo "      [${i}] $(basename "${f}")"
            done
            (( i > 0 )) || { err "no keystores in ~/.foundry/keystores — create one: cast wallet import <name> --interactive"; exit 2; }
            pick="$(ask "  keystore #" "1")"
            if [[ ! "${pick}" =~ ^[0-9]+$ ]] || (( pick < 1 || pick > i )); then err "pick 1-${i}."; exit 2; fi
            ks="${ks_names[$(( pick - 1 ))]}"
            # Probe the Keychain BEFORE promising an unattended run (keychain-auth.sh errors late).
            if command -v security >/dev/null 2>&1 && security find-generic-password -s "foundry-${ks}" -w >/dev/null 2>&1; then
                AUTH_MODE="keychain:${ks}"
                auth_desc="keystore '${ks}' (unattended — password from the macOS Keychain)"
            else
                FORGE_AUTH="--account ${ks}"
                auth_desc="keystore '${ks}' (ATTENDED — forge/cast prompt for the password per signing step)"
                info "  tip: store the password once for unattended runs:  security add-generic-password -a \"\$USER\" -s foundry-${ks} -w"
            fi
            ;;
        2)
            IFS= read -rsp "  private key (input hidden): " raw_pk; echo
            [[ "${raw_pk}" =~ ^(0x)?[0-9a-fA-F]{64}$ ]] || { err "not a 32-byte hex key."; exit 2; }
            [[ "${raw_pk}" == 0x* ]] || raw_pk="0x${raw_pk}"
            FORGE_AUTH="--private-key ${raw_pk}"
            ACTOR="$(cast wallet address --private-key "${raw_pk}" 2>/dev/null || true)"
            unset raw_pk
            auth_desc="private key (redacted)${ACTOR:+ — signer ${ACTOR}}"
            ;;
        *) err "pick 1 or 2."; exit 2 ;;
    esac
fi

# ---- amount + extras ----------------------------------------------------------
AMOUNT_UNITS=""
if [[ -n "${RESUME}" ]]; then
    case "${RESUME}" in
        rt) AMOUNT_UNITS="$(jget "${RT_J}" AMOUNT)" ;;
        hook) AMOUNT_UNITS="$(jget "${HOOK_J}" AMOUNT)" ;;
    esac
    [[ -n "${AMOUNT_UNITS}" ]] && info "amount: ${AMOUNT_UNITS} USDC units (journaled — the run is bound to it)."
else
    # Balances are advisory: the children re-check authoritatively before spending, and on Arc the
    # gas IS USDC, so leave headroom. Reading them forks the chain (skipped for the loop — it has
    # its own status/fund gate; and skipped when the signer address is not derivable without a
    # password prompt).
    if [[ "${DIRECTION}" != "4" && -n "${ACTOR}" ]]; then
        info "reading balances (forks the chain; takes a few seconds)..."
        arc_bal="$(forge script script/base/crosschain/CCTPHookDemo.s.sol:CCTPHookDemo --sig 'hookDemoArcBalance(address)' "${ACTOR}" --sender "${ACTOR}" 2>&1 | grep -oE 'DEMO-HOOK-ARCBAL [0-9]+' | awk '{print $2}' || true)"
        base_bal="$(forge script script/base/crosschain/CCTPHookDemo.s.sol:CCTPHookDemo --sig 'hookDemoBaseBalance(address)' "${ACTOR}" --sender "${ACTOR}" 2>&1 | grep -oE 'DEMO-HOOK-BASEBAL [0-9]+' | awk '{print $2}' || true)"
        info "  Arc USDC:  ${arc_bal:-unknown} units   (asset AND Arc gas — https://faucet.circle.com)"
        info "  Base USDC: ${base_bal:-unknown} units   (Base gas is ETH — any Base Sepolia faucet)"
    fi
    amt="$(ask "amount in USDC" "1.0")"
    [[ "${amt}" =~ ^([0-9]+)?(\.[0-9]{1,6})?$ && "${amt}" != "" && "${amt}" != "." ]] || { err "amount must look like 1, 0.5, or 2.25 (max 6 decimals)."; exit 2; }
    int_part="${amt%%.*}"; frac_part=""
    [[ "${amt}" == *.* ]] && frac_part="${amt#*.}"
    frac_part="${frac_part}000000"; frac_part="${frac_part:0:6}"
    # 10# is load-bearing: a fraction like 075000 would otherwise parse as an invalid octal literal.
    AMOUNT_UNITS=$(( 10#${int_part:-0} * 1000000 + 10#${frac_part} ))
    (( AMOUNT_UNITS > 0 )) || { err "amount must be positive."; exit 2; }
    (( AMOUNT_UNITS <= 1000000000000 )) || { err "that is over a million USDC — this is a testnet demo."; exit 2; }
    case "${DIRECTION}" in
        3) rel_bal="${base_bal:-}"; rel_name="Base" ;;
        *) rel_bal="${arc_bal:-}"; rel_name="Arc" ;;
    esac
    if [[ -n "${rel_bal}" ]] && (( AMOUNT_UNITS > rel_bal )); then
        warn "amount exceeds the signer's ${rel_name} USDC (${rel_bal} units) — the run will stop at its fund gate."
    fi
fi

BENEFICIARY=""
if [[ "${DIRECTION}" == "5" && -z "${RESUME}" ]]; then
    BENEFICIARY="$(ask "beneficiary to auto-credit (Enter = credit yourself)" "")"
    [[ -z "${BENEFICIARY}" || "${BENEFICIARY}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "not a 20-byte address."; exit 2; }
fi
DEST_FILTER=""
if [[ "${DIRECTION}" == "4" && -z "${RESUME}" ]]; then
    DEST_FILTER="$(ask "destination (sepolia | base | both)" "both")"
    case "${DEST_FILTER}" in sepolia | base) ;; both) DEST_FILTER="" ;; *) err "pick sepolia, base, or both."; exit 2 ;; esac
fi

# ---- summary + dispatch -------------------------------------------------------
case "${DIRECTION}" in
    1) CHILD="cctp-roundtrip-demo.sh"; CHILD_ARGS=(); flow="round trip Arc -> Base -> Arc" ;;
    2) CHILD="cctp-roundtrip-demo.sh"; CHILD_ARGS=(--legs out); flow="one way Arc -> Base" ;;
    3) CHILD="cctp-roundtrip-demo.sh"; CHILD_ARGS=(--legs back); flow="one way Base -> Arc" ;;
    4) CHILD="cctp-usdc-demo-loop.sh"; CHILD_ARGS=(); [[ -n "${DEST_FILTER}" ]] && CHILD_ARGS=("${DEST_FILTER}"); flow="transfer loop Arc -> ${DEST_FILTER:-sepolia + base}" ;;
    5)
        CHILD="cctp-hook-demo.sh"; CHILD_ARGS=(); flow="hook showcase Arc -> Base vault"
        if [[ -n "${BENEFICIARY}" ]]; then
            # The hook demo takes [actor] [beneficiary] positionally — the actor must come first.
            if [[ -z "${ACTOR}" ]]; then
                info "deriving the signer address to pass the beneficiary (may prompt for the keystore password)..."
                # shellcheck disable=SC2086
                ACTOR="$(cast wallet address ${FORGE_AUTH:-} 2>/dev/null || true)"
                [[ "${ACTOR}" =~ ^0x[0-9a-fA-F]{40}$ ]] || { err "could not derive the signer; re-run and credit yourself, or use PRIVATE_KEY/Keychain auth."; exit 2; }
            fi
            CHILD_ARGS=("${ACTOR}" "${BENEFICIARY}")
        fi
        ;;
esac

echo
echo "  ${C_BOLD}About to run:${C_OFF}"
echo "    flow:    ${flow}${RESUME:+  (RESUMING a half-done run)}"
echo "    amount:  ${AMOUNT_UNITS:-per-journal} USDC units"
echo "    stack:   ${DEMO_ARC_HUB:-auto (deploy journal, else canonical)}${DEMO_BASE_DIAMOND:+ / ${DEMO_BASE_DIAMOND}}"
echo "    auth:    ${auth_desc}"
case "${DIRECTION}" in
    1 | 3) echo "    timing:  the Base -> Arc leg attests after Base Sepolia's L1 finality (~13-19 min; Ctrl-C safe, re-run resumes)." ;;
    4) echo "    timing:  self-cranking; Arc-sourced legs attest in seconds." ;;
    *) echo "    timing:  Arc-sourced; attests in seconds." ;;
esac
if [[ "${auth_desc}" == *ATTENDED* && ( "${DIRECTION}" == "1" || "${DIRECTION}" == "3" ) ]]; then
    warn "attended keystore + a ~15-min wait: a password prompt will fire long after you look away —"
    warn "  consider the Keychain setup or PRIVATE_KEY for this direction."
fi
[[ "$(ask "  proceed? (y/N)" "N")" =~ ^[yY]$ ]] || { info "nothing sent."; exit 0; }
echo

[[ -n "${AMOUNT_UNITS}" ]] && export AMOUNT="${AMOUNT_UNITS}"
case "${AUTH_MODE}" in
    keychain:*)
        exec "script/config/keychain-auth.sh" "${AUTH_MODE#keychain:}" "script/config/${CHILD}" ${CHILD_ARGS[@]+"${CHILD_ARGS[@]}"}
        ;;
    *)
        export FORGE_AUTH
        exec "script/config/${CHILD}" ${CHILD_ARGS[@]+"${CHILD_ARGS[@]}"}
        ;;
esac
