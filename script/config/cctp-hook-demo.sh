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
# Blockscout, not basescan: the demo verifies via Sourcify, which Blockscout reads (basescan does not).
BASE_EXPLORER="https://base-sepolia.blockscout.com"
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

# Per-phase wall-clock (narration + the closing timings line). Only phases that ran THIS invocation are
# timed — a resumed run skips journaled phases, and stale timings would misreport them.
T_RUN_START=${SECONDS}
D_SETUP=""; D_BURN=""; D_ATTEST=""; D_RELAY=""

# Scratch files for captured tool output (the streamed setup log; the burn's stderr). Created eagerly in
# TMPDIR (0600) so ONE trap guarantees cleanup even on Ctrl-C mid-deploy — an interrupted run must never
# leave raw forge/cast output on disk: its error text can embed the API-keyed RPC URLs. The journal is
# deliberately NOT trapped — it must survive for resume.
SETUP_LOG="$(mktemp "${TMPDIR:-/tmp}/cctp-hook-demo.setup.XXXXXX")"
ERR_FILE="$(mktemp "${TMPDIR:-/tmp}/cctp-hook-demo.err.XXXXXX")"
trap 'rm -f "${SETUP_LOG}" "${ERR_FILE}"' EXIT INT TERM

# ---- journal (KEY=VALUE lines; values are addresses / tx hashes / hex) ---------
journal_get() { [[ -f "${JOURNAL}" ]] && sed -n "s/^$1=//p" "${JOURNAL}" | tail -1 || true; }
journal_set() {
    local key="$1" val="$2" tmp
    tmp="$(mktemp "${JOURNAL}.XXXXXX")"
    { [[ -f "${JOURNAL}" ]] && grep -vE "^${key}=" "${JOURNAL}" || true; echo "${key}=${val}"; } >"${tmp}"
    mv "${tmp}" "${JOURNAL}"
}

# Decimal for a hex word, safely: bash arithmetic is SIGNED 64-BIT, so only convert when the significant
# digits fit (<= 15 hex digits < 2^60); larger values print as 0x-hex instead of silently wrapping negative.
# Callers must pass pure hex (validated upstream) — a non-hex operand would make `16#` a fatal error.
hex_word_dec() {
    local h
    h="$(printf '%s' "$1" | sed 's/^0*//')"
    if [[ -z "${h}" ]]; then printf '0'; elif (( ${#h} <= 15 )); then printf '%s' "$(( 16#${h} ))"; else printf '0x%s' "${h}"; fi
}

# Stateful renderer for the streamed setup phase: styled chain headers, a live spinner across the
# silent multichain dispatch, and one ✓/✗ line per verification (rewritten in place on a tty;
# piped/CI output degrades to plain sequential lines — no \r rewriting to garble logs). Only
# recognized safe line shapes are printed — forge error text can embed API-keyed RPC URLs;
# everything unmatched stays in ${SETUP_LOG} for the failure-path scrub. MUST consume input to EOF
# (an early exit would SIGPIPE forge mid-broadcast) and MUST NOT let any command fail under set -e
# (all matching happens in if-conditions; body is printf-only). Line shapes pinned empirically
# against forge 1.7.1 (multichain broadcast, via a local two-anvil probe) + Sourcify v2.
render_setup_stream() {
    local tty=0 idx=0 spin_open=0 spin_label="" vname="" vaddr="" line
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    if [[ -t 1 ]]; then tty=1; fi
    # One spinner at a time: spin_label names what we are waiting on (the silent multichain dispatch,
    # or one in-flight verification); the timeout branch redraws it, and _clr erases it before any
    # real line prints. Empirical (local two-anvil probe): multichain forge prints NO per-tx receipts
    # — only '## Setting up N EVMs.', per-chain 'Chain <id>' estimate blocks, then silence until
    # 'ONCHAIN EXECUTION COMPLETE' — so dispatch progress is a spinner, and the per-contract deploy
    # listing is printed by the driver afterwards from the broadcast journal (which has names).
    _clr() { if (( spin_open == 1 )); then printf '\r\033[2K'; spin_open=0; fi; }
    # `read -t` can time out MID-LINE, leaving a partial line in the variable with rc>128 (empirical:
    # ~1-in-3 loss when a write races the 0.15s window) — so partial chunks accumulate in `buf` and
    # are prepended to the next successful read instead of being discarded.
    local buf="" chunk=""
    while true; do
        if IFS= read -r -t 0.15 chunk; then
            line="${buf}${chunk}"; buf=""
            if [[ "${line}" =~ Submitting\ verification\ for\ \[([^]]+)\]\ \"(0x[0-9a-fA-F]{40})\" ]]; then
                _clr
                vname="${BASH_REMATCH[1]##*:}"; vaddr="${BASH_REMATCH[2]}"
                spin_label="verifying ${vname} ${vaddr}"
                if (( tty == 0 )); then printf '    ... verifying %s %s\n' "${vname}" "${vaddr}"; fi
            elif [[ "${line}" == *"Contract source code already fully verified"* ]]; then
                _clr; spin_label=""
                printf '    %s✓%s %s %s verified (already)\n' "${C_OK}" "${C_OFF}" "${vname}" "${vaddr}"
            elif [[ "${line}" == *"Contract successfully verified"* ]]; then
                _clr; spin_label=""
                printf '    %s✓%s %s %s verified\n' "${C_OK}" "${C_OFF}" "${vname}" "${vaddr}"
            elif [[ "${line}" == *"Verification job failed"* ]]; then
                _clr; spin_label=""
                printf '    %s✗%s %s %s verification FAILED (non-fatal; the deploy stands)\n' "${C_ERR}" "${C_OFF}" "${vname}" "${vaddr}"
            elif [[ "${line}" =~ ^(Error\ Code:|Message:) ]]; then
                _clr
                printf '        %s\n' "${line}"
            elif [[ "${line}" == '## Setting up '* ]]; then
                _clr
                spin_label="broadcasting + confirming on both chains (forge is silent here; hold on)"
                if (( tty == 0 )); then printf '    ... broadcasting + confirming on both chains\n'; fi
            elif [[ "${line}" =~ ^Chain\ ([0-9]+) ]]; then
                _clr
                case "${BASH_REMATCH[1]}" in
                    84532) printf '    ── chain 84532 · base-sepolia ──\n' ;;
                    5042002) printf '    ── chain 5042002 · arc-testnet ──\n' ;;
                    *) printf '    ── chain %s ──\n' "${BASH_REMATCH[1]}" ;;
                esac
            elif [[ "${line}" == *"ONCHAIN EXECUTION COMPLETE"* ]]; then
                _clr; spin_label=""
                printf '    %s✓%s all transactions confirmed on both chains\n' "${C_OK}" "${C_OFF}"
            fi
        else
            if (( $? > 128 )); then
                buf+="${chunk}"
                if [[ -n "${spin_label}" ]] && (( tty == 1 )); then
                    idx=$(( (idx + 1) % 10 ))
                    printf '\r\033[2K    %s %s' "${frames[idx]}" "${spin_label}"
                    spin_open=1
                fi
            else
                # EOF. A line torn by a timeout is completed by a later rc=0 read (its tail includes
                # the newline), and forge newline-terminates its final line — so buf+chunk is empty
                # here in practice and there is nothing to flush.
                break
            fi
        fi
    done
    _clr
    return 0
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
    info "setup: deploying Arc hub + Base diamond + vault (~19 contracts across 2 chains; live forge progress):"
    # Verification MUST land on Sourcify (Blockscout/arcscan read it), and two forge behaviors fight that:
    # a set ETHERSCAN_API_KEY makes forge default to the Etherscan verifier EVEN WHEN --verifier sourcify
    # is passed (empirical, forge 1.7.1: "defaulting to Etherscan verifier" despite the flag), and the repo
    # .env sets that key -- so blank it inline (an empty-string env var beats forge's .env auto-load; plain
    # `env -u` does not, forge re-reads .env). Verification is best-effort: success is the DEMO-HOOK-SETUP
    # line + forge's ONCHAIN-EXECUTION marker (precedent: cctp-usdc-demo-loop), NOT the exit code -- a
    # verifier hiccup must not strand a successful deploy un-journaled (a re-run would redeploy everything).
    #
    # The multi-minute deploy+verify STREAMS progress instead of going dark: forge's output is teed to a
    # file for the parsing below while a selective grep passes the per-contract broadcast receipts and
    # verification results through live. The passed-through lines never embed RPC URLs (error text, which
    # can, stays in the file and is scrubbed on the failure path). `|| true` keeps a match-less grep from
    # failing the pipeline; with pipefail, `|| rc=$?` still captures forge's own exit code.
    t0=${SECONDS}
    rc=0
    # Full output tees to ${SETUP_LOG} (for the parsing below + failure-path scrub) while
    # render_setup_stream turns the live stream into per-contract ✓/✗ lines with a verification
    # spinner. The renderer always exits 0, so with pipefail `|| rc=$?` still captures forge's own
    # exit code.
    # shellcheck disable=SC2086
    ETHERSCAN_API_KEY='' forge script "${SCRIPT_TARGET}" --sig 'hookDemoSetup(uint256,uint32)' 0 2000 ${FORGE_AUTH} --broadcast ${SLOW} --verify --verifier sourcify 2>&1 \
        | tee "${SETUP_LOG}" \
        | { render_setup_stream || true; } \
        || rc=$?
    out="$(cat "${SETUP_LOG}")"
    line="$(echo "${out}" | grep -oE 'DEMO-HOOK-SETUP 0x[0-9a-fA-F]{40} 0x[0-9a-fA-F]{40} 0x[0-9a-fA-F]{40}' | tail -1 || true)"
    if [[ -z "${line}" ]] || ! echo "${out}" | grep -q 'ONCHAIN EXECUTION COMPLETE'; then
        scrub "${out}"; err "setup failed."; exit 1
    fi
    verified_note="wired + Sourcify-verified"
    if (( rc != 0 )); then
        warn "setup exited ${rc} after broadcasting (likely a verification hiccup; deploy journaled)."
        verified_note="wired (verification did not complete — see the warning above)"
    fi
    read -r _ ARC_HUB BASE_DIAMOND VAULT <<<"${line}"
    journal_set ARC_HUB "${ARC_HUB}"; journal_set BASE_DIAMOND "${BASE_DIAMOND}"; journal_set VAULT "${VAULT}"
    D_SETUP=$(( SECONDS - t0 ))
    # Per-chain deploy listing, grouped and NAMED, from the broadcast journal forge just wrote:
    # multichain forge prints no per-tx receipts to stdout (empirical), and the journal is richer
    # anyway (contract names). Best-effort — the diamond/vault addresses also appear in the links.
    while IFS= read -r dep_line; do
        info "  ${dep_line/✓/${C_OK}✓${C_OFF}}"
    done < <(jq -r '
        .deployments[]
        | (if .chain == 84532 then "base-sepolia" elif .chain == 5042002 then "arc-testnet" else (.chain|tostring) end) as $c
        | ("deployed on \($c):"),
          (.transactions[] | select(.transactionType == "CREATE") | "  ✓ \(.contractName) \(.contractAddress)")
        ' broadcast/multi/CCTPHookDemo.s.sol-latest/hookDemoSetup.json 2>/dev/null || true)
    ok "setup complete in ${D_SETUP}s: two diamonds + the auto-credit vault, ${verified_note}:"
    ok "  hub (Arc):      ${ARC_EXPLORER}/address/${ARC_HUB}  <- burn goes in here"
    ok "  diamond (Base): ${BASE_EXPLORER}/address/${BASE_DIAMOND}  <- relays + fires the hook"
    ok "  vault (Base):   ${BASE_EXPLORER}/address/${VAULT}  <- receives the mint, credits the beneficiary"
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

    # fund check (Arc USDC is the asset AND the gas token) -- a broadcast-free forge READ with --sender, the
    # driver's own prompt-free idiom, NOT `cast call`: an ambient ETH_KEYSTORE_ACCOUNT (shell or .env --
    # the repo .env no longer sets one) makes cast eagerly unlock that keystore even for a read and
    # prompt mid-run on /dev/tty (2>/dev/null cannot hide it; `env -u` does not stick -- cast re-reads .env). Forking Arc for a READ is fine in revm: only
    # balance-MOVES route through the 0x1800 precompile. A failed read leaves BAL empty and skips the check;
    # an underfunded burn still fails loudly on-chain.
    BAL="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoArcBalance(address)' "${ACTOR}" --sender "${ACTOR}" 2>&1 | grep -oE 'DEMO-HOOK-ARCBAL [0-9]+' | awk '{print $2}' || true)"
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
    # The envelope IS the "programmable USDC" payload — show it annotated. Layout (44 bytes):
    # 4-byte Lattice HOOK_MAGIC ‖ 20-byte hook target (the vault) ‖ payload (the beneficiary to credit).
    info "hook envelope ($(( (${#E} - 2) / 2 )) bytes, rides inside the burn message): ${E}"
    info "  = magic ${E:0:10} ‖ target 0x${E:10:40} (vault) ‖ payload 0x${E:50:40} (beneficiary)"
    t0=${SECONDS}
    info "approving ${AMOUNT} Arc USDC to the hub..."
    # shellcheck disable=SC2086
    cast send "${ARC_USDC}" "approve(address,uint256)" "${ARC_HUB}" "${AMOUNT}" ${FORGE_AUTH} --rpc-url "${ARC_RPC}" >/dev/null
    info "burning ${AMOUNT} Arc USDC -> Base with hook (target=vault, payload=beneficiary)..."
    journal_set BURN_ATTEMPTED 1 # write-ahead: a crash after this means "check arcscan before re-running"
    rc=0
    # stdout (the --json receipt) and stderr (which may embed the API-keyed RPC URL on a transport error) are
    # kept SEPARATE, so the hash extraction never sees error noise and the error text is scrubbed before echo.
    : > "${ERR_FILE}"
    # shellcheck disable=SC2086
    out="$(cast send "${ARC_HUB}" "depositForBurnWithHook(uint256,bytes,bytes)" "${AMOUNT}" "${R}" "${E}" ${FORGE_AUTH} --rpc-url "${ARC_RPC}" --json 2>"${ERR_FILE}")" || rc=$?
    err_text="$(cat "${ERR_FILE}")"
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
    D_BURN=$(( SECONDS - t0 ))
    ok "burned in ${D_BURN}s (approve + depositForBurnWithHook): ${ARC_EXPLORER}/tx/${BURN_TX}"
fi

# ---- 4. Iris attestation (source domain 26 = Arc; seconds at Arc finality) -----
MESSAGE="$(journal_get MESSAGE)"; ATTESTATION="$(journal_get ATTESTATION)"
if [[ -z "${MESSAGE}" || -z "${ATTESTATION}" ]]; then
    # Echo the poll URL only for the default public sandbox: IRIS_API is an env knob, and an override may
    # be a credentialed proxy URL — the exact leak class scrub() exists for (it only masks the RPC URLs).
    iris_display="${IRIS_API}"
    [[ "${IRIS_API}" == "https://iris-api-sandbox.circle.com" ]] || iris_display="<custom IRIS_API>"
    info "awaiting Iris attestation (poll ${IRIS_POLL_SECONDS}s, cap ${ATTEST_TIMEOUT_SECONDS}s); watch it live:"
    info "  ${iris_display}/v2/messages/${ARC_SRC_DOMAIN}?transactionHash=${BURN_TX}"
    t0=${SECONDS}
    deadline=$(( SECONDS + ATTEST_TIMEOUT_SECONDS ))
    last_status=""
    while (( SECONDS < deadline )); do
        resp="$(curl -sf --retry 3 --retry-delay 2 "${IRIS_API}/v2/messages/${ARC_SRC_DOMAIN}?transactionHash=${BURN_TX}" 2>/dev/null || true)"
        # An empty resp covers BOTH curl failure and Iris's pre-index 404 (-f merges them); label it as
        # such rather than piping "" into jq, which exits 0 with NO output (so a `// default` or `|| echo`
        # fallback never fires — both were dead code here).
        if [[ -z "${resp}" ]]; then
            status="not-indexed-yet (or iris unreachable)"
        else
            status="$(echo "${resp}" | jq -r '.messages[0].status // "message-not-indexed-yet"' 2>/dev/null || true)"
            [[ -n "${status}" ]] || status="unparseable-iris-response"
        fi
        if [[ "${status}" != "${last_status}" ]]; then
            info "  iris: ${status} (+$(( SECONDS - t0 ))s)"
            last_status="${status}"
        fi
        if [[ -n "${resp}" && "${status}" == "complete" ]]; then
            MESSAGE="$(echo "${resp}" | jq -r '.messages[0].message // empty')"
            ATTESTATION="$(echo "${resp}" | jq -r '.messages[0].attestation // empty')"
            if [[ "${MESSAGE}" =~ ^0x[0-9a-fA-F]+$ && "${ATTESTATION}" =~ ^0x[0-9a-fA-F]+$ ]]; then
                journal_set MESSAGE "${MESSAGE}"; journal_set ATTESTATION "${ATTESTATION}"
                D_ATTEST=$(( SECONDS - t0 ))
                ok "attested in ${D_ATTEST}s — Arc's sub-second finality means seconds, not the ~15min slower chains need."
                ok "  message: $(( (${#MESSAGE} - 2) / 2 )) bytes (burn + hook envelope) · attestation: $(( (${#ATTESTATION} - 2) / 2 )) bytes (Iris signatures)"
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
    info "relaying on Base Sepolia — ONE tx does both: Circle mints the USDC to the vault, then the"
    info "  diamond's CCTPHookExecutor calls vault.onCCTPHook(...) which credits the beneficiary..."
    t0=${SECONDS}
    rc=0
    # shellcheck disable=SC2086
    out="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoRelay(address,bytes,bytes)' "${BASE_DIAMOND}" "${MESSAGE}" "${ATTESTATION}" ${FORGE_AUTH} --broadcast --rpc-url base-sepolia 2>&1)" || rc=$?
    if (( rc == 0 )); then
        journal_set RELAYED 1
        D_RELAY=$(( SECONDS - t0 ))
        # Surface the relay tx — the demo's money shot (mint + hook in one tx) — from the broadcast log.
        RELAY_TX="$(jq -r '.receipts[0].transactionHash // empty' broadcast/CCTPHookDemo.s.sol/84532/hookDemoRelay-latest.json 2>/dev/null || true)"
        if [[ "${RELAY_TX}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
            journal_set RELAY_TX "${RELAY_TX}"
            ok "relayed in ${D_RELAY}s: ${BASE_EXPLORER}/tx/${RELAY_TX}"
        else
            RELAY_TX=""
        fi
    else
        warn "relay tx did not succeed this run (it may already be relayed from a prior run); verifying credit..."
        scrub "${out}"
    fi
    sleep 6
else
    RELAY_TX="$(journal_get RELAY_TX)"
    info "relay already journaled; skipping to verify."
fi

# Best-effort on-chain proof: decode the vault's Credited event straight from the relay receipt (curl,
# credential-free — cast reads would eagerly unlock the .env keystore). Non-fatal: the credit read below
# is the source of truth.
# topic0 = keccak256("Credited(address,uint256,uint32,bytes32)"), see CCTPHookVault.Credited.
CREDITED_TOPIC="0xc8947ddac936d47e6ab5a0004ed0d2d901b584caf27414a3fa3dd0c7d06f5969"
if [[ "${RELAY_TX:-}" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    rcpt="$(curl -sf -m 15 -X POST "${BASE_RPC}" -H 'content-type: application/json' \
        -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionReceipt\",\"params\":[\"${RELAY_TX}\"]}" 2>/dev/null || true)"
    lg="$(echo "${rcpt}" | jq -c --arg v "$(echo "${VAULT}" | tr '[:upper:]' '[:lower:]')" --arg t "${CREDITED_TOPIC}" \
        '.result.logs[]? | select((.address == $v) and (.topics[0] == $t))' 2>/dev/null | head -1 || true)"
    if [[ -n "${lg}" ]]; then
        ev_benef="0x$(echo "${lg}" | jq -r '.topics[1]' | cut -c27-66)"
        ev_data="$(echo "${lg}" | jq -r '.data')"
        # Decode ONLY a well-formed 3-word data blob: a malformed word would make `16#...` a FATAL
        # arithmetic error under set -e, killing the run before the authoritative credit read below —
        # exactly what this best-effort block must never do.
        if [[ "${ev_data}" =~ ^0x[0-9a-fA-F]{192}$ && "${ev_benef}" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
            ok "hook fired on-chain — the vault emitted:"
            ok "  Credited(beneficiary=${ev_benef}, amount=$(hex_word_dec "${ev_data:2:64}"), sourceDomain=$(hex_word_dec "${ev_data:66:64}") (Arc), sender=0x${ev_data:130:64})"
        fi
    fi
fi

# ---- 6. verify the vault credited the beneficiary (source of truth) ------------
credit_line="$(forge script "${SCRIPT_TARGET}" --sig 'hookDemoCredit(address,address)' "${VAULT}" "${BENEFICIARY}" --sender "${ACTOR}" 2>&1 | grep -oE 'DEMO-HOOK-CREDIT [0-9]+ [0-9]+' | tail -1 || true)"
read -r _ CREDIT VAULT_BAL <<<"${credit_line}"
if [[ -z "${CREDIT}" ]]; then err "could not read the vault credit; check ${BASE_EXPLORER}/address/${VAULT}"; exit 1; fi

echo
if (( CREDIT >= AMOUNT )); then
    ok "HOOK DELIVERED: ${BENEFICIARY} auto-credited ${CREDIT} USDC units in the vault (balance ${VAULT_BAL})."
    ok "  burn (Arc):    ${ARC_EXPLORER}/tx/${BURN_TX}"
    [[ -n "${RELAY_TX:-}" ]] && ok "  relay (Base):  ${BASE_EXPLORER}/tx/${RELAY_TX}  <- mint + hook, one tx"
    ok "  vault (Base):  ${BASE_EXPLORER}/address/${VAULT}"
    ok "  hub (Arc):     ${ARC_EXPLORER}/address/${ARC_HUB}"
    timings=""
    [[ -n "${D_SETUP}" ]] && timings+="setup ${D_SETUP}s · "
    [[ -n "${D_BURN}" ]] && timings+="burn ${D_BURN}s · "
    [[ -n "${D_ATTEST}" ]] && timings+="attest ${D_ATTEST}s · "
    [[ -n "${D_RELAY}" ]] && timings+="relay ${D_RELAY}s · "
    ok "  timings:       ${timings}total $(( SECONDS - T_RUN_START ))s (phases skipped by a resume are untimed)"
    rm -f "${JOURNAL}"
else
    warn "relay landed but credit=${CREDIT} < ${AMOUNT}; inspect ${BASE_EXPLORER}/address/${VAULT} (journal kept)."
    exit 1
fi
