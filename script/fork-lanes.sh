#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# fork-lanes.sh
#
# Assigns every fork suite (test/fork/*.t.sol) to one lane of the weekly fork job in
# .github/workflows/scheduled.yml. A lane needs only its own RPC secrets, so one missing
# or failing endpoint fails one lane instead of hiding the others. Suites that span
# chains stay together (cctp-testnet forks Sepolia, Base Sepolia and Arc testnet).
#
# Usage:
#   ./script/fork-lanes.sh glob <lane>      # the lane's `forge test --match-path` glob
#   ./script/fork-lanes.sh secrets <lane>   # the RPC secrets the lane requires
#   ./script/fork-lanes.sh require <lane>   # fail unless every one of those secrets is set
#   ./script/fork-lanes.sh run <lane>       # run the lane's suites; rerun the whole lane once
#                                           # when a failed run's log shows an RPC error
#   ./script/fork-lanes.sh check            # every suite in exactly one lane (or UNSCHEDULED),
#                                           # each suite reads only its lane's *_RPC_URL, and the
#                                           # scheduled.yml matrix lists exactly the lanes below
#                                           # (`make scripts-check`)
#
# FORK_LANES_WORKFLOW overrides the workflow `check` reads (script/test-fork-lanes.sh uses it).
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORK_DIR=test/fork
WORKFLOW=${FORK_LANES_WORKFLOW:-.github/workflows/scheduled.yml}

# Output that marks a failed run as an RPC failure worth one retry.
RPC_ERROR='database error|server returned an error response|HTTP error|error sending request|timed out|Too Many Requests|rate limit'

LANES="mainnet sepolia base-sepolia cctp-testnet"

# Suites no lane runs. The Hedera suites need HEDERA_TEST_* values and the Foundry 1.7.1
# wrapper (script/config/hedera/forge-hedera.sh), so they stay a manual opt-in.
UNSCHEDULED="HASSignatureVerifierFork HTSAdapterFork"

suites() {
    case "$1" in
        mainnet)
            echo "AaveV3AdapterFork AcrossBridgeAdapterFork API3AdapterFork API3QRNGAdapterFork BandAdapterFork" \
                "CCTPBridgeAdapterFork ChainlinkAdapterFork ChainlinkAutomationAdapterFork ChainlinkCREAdapterFork" \
                "ChronicleAdapterFork ConstantProductFork DIAAdapterFork EntryPoint7702Fork EntryPointFork" \
                "GelatoAutomateAdapterFork GelatoVRFAdapterFork LayerZeroGatewayAdapterFork PythAdapterFork" \
                "RedStoneAdapterFork StarknetGatewayAdapterFork TellorAdapterFork TWAPOracleFork"
            ;;
        sepolia) echo "GovernanceDemoFork GovernedVaultENSFork LatticeFactoryENSFork" ;;
        base-sepolia) echo "CCTPHookDemoFork CCTPHookReceiptDemoFork PythEntropyAdapterFork" ;;
        cctp-testnet) echo "CCTPBridgeAdapterTestnetFork CCTPUSDCDemoFork" ;;
        *) echo "unknown lane: $1 (lanes: $LANES)" >&2; return 1 ;;
    esac
}

secrets() {
    case "$1" in
        mainnet) echo "MAINNET_RPC_URL" ;;
        sepolia) echo "SEPOLIA_RPC_URL" ;;
        base-sepolia) echo "BASE_SEPOLIA_RPC_URL" ;;
        cctp-testnet) echo "SEPOLIA_RPC_URL BASE_SEPOLIA_RPC_URL ARC_TESTNET_RPC_URL" ;;
        *) echo "unknown lane: $1 (lanes: $LANES)" >&2; return 1 ;;
    esac
}

glob() {
    local list
    list=$(suites "$1") || return 1
    echo "$FORK_DIR/{${list// /,}}.t.sol"
}

# A lane without its secret would skip every suite and still pass, so a missing secret fails the lane.
require() {
    local names name missing=()
    names=$(secrets "$1") || return 1
    for name in $names; do
        [ -n "${!name:-}" ] || missing+=("$name")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        echo "::error::Lane $1 is missing repository secrets: ${missing[*]} (archive-capable RPC URLs; see .env.example)."
        return 1
    fi
    echo "lane $1: secrets set ($names)"
}

# Runs the lane, and once more when a failed run's log shows an RPC error. The retry reruns the whole
# lane, not `forge test --rerun`: cache/test-failures records only failed test functions, never a failed
# setUp(), so `--rerun` would drop a suite whose setUp failed and could pass the lane with it still broken.
run() {
    local path log status
    path=$(glob "$1") || return 1
    log=$(mktemp)
    set +e
    forge test --match-path "$path" --summary 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    set -e
    if [ "$status" -ne 0 ] && grep -qE "$RPC_ERROR" "$log"; then
        echo "::warning::Lane $1 failed with an RPC error; rerunning the whole lane once."
        set +e
        forge test --match-path "$path" --summary
        status=$?
        set -e
    fi
    rm -f "$log"
    return "$status"
}

check() {
    cd "$ROOT"
    local failures=0 lane suite owner file var
    local assigned=" $UNSCHEDULED "
    # The matrix entries: the `- name` items directly under `lane:`.
    while read -r lane; do
        [[ " $LANES " == *" $lane "* ]] || {
            echo "FAIL the $WORKFLOW matrix lists lane '$lane', which script/fork-lanes.sh does not define"
            failures=$((failures + 1))
        }
    done < <(awk '/^ +lane:$/ {in_lane = 1; next} in_lane && /^ +- / {print $2; next} {in_lane = 0}' "$WORKFLOW")
    for lane in $LANES; do
        grep -qE "^ +- $lane\$" "$WORKFLOW" || {
            echo "FAIL lane '$lane' is not in the $WORKFLOW matrix"
            failures=$((failures + 1))
        }
        for suite in $(suites "$lane"); do
            file="$FORK_DIR/$suite.t.sol"
            if [ ! -f "$file" ]; then
                echo "FAIL $lane lists $suite, but $file does not exist"
                failures=$((failures + 1))
                continue
            fi
            if [[ "$assigned" == *" $suite "* ]]; then
                echo "FAIL $suite is in more than one lane"
                failures=$((failures + 1))
            fi
            assigned+="$suite "
            while read -r var; do
                if [[ " $(secrets "$lane") " != *" $var "* ]]; then
                    echo "FAIL $suite reads $var, which lane '$lane' does not provide"
                    failures=$((failures + 1))
                fi
            done < <(grep -ohE '[A-Z_]+_RPC_URL' "$file" | sort -u)
        done
    done
    for file in "$FORK_DIR"/*.t.sol; do
        suite=$(basename "$file" .t.sol)
        [[ "$assigned" == *" $suite "* ]] || {
            echo "FAIL $file is in no lane: add it to script/fork-lanes.sh (or to UNSCHEDULED)"
            failures=$((failures + 1))
        }
    done
    for owner in $UNSCHEDULED; do
        [ -f "$FORK_DIR/$owner.t.sol" ] || {
            echo "FAIL UNSCHEDULED lists $owner, but $FORK_DIR/$owner.t.sol does not exist"
            failures=$((failures + 1))
        }
    done
    if [ "$failures" -gt 0 ]; then
        echo "fork-lanes: $failures problem(s)"
        return 1
    fi
    echo "fork-lanes: every fork suite is in one lane (lanes: $LANES; unscheduled: $UNSCHEDULED)"
}

case "${1:-}" in
    glob) glob "${2:?usage: fork-lanes.sh glob <lane>}" ;;
    secrets) secrets "${2:?usage: fork-lanes.sh secrets <lane>}" ;;
    require) require "${2:?usage: fork-lanes.sh require <lane>}" ;;
    run) run "${2:?usage: fork-lanes.sh run <lane>}" ;;
    check) check ;;
    *) echo "usage: fork-lanes.sh glob <lane> | secrets <lane> | require <lane> | run <lane> | check" >&2; exit 2 ;;
esac
