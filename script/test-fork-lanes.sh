#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test-fork-lanes.sh
#
# Regression tests for script/fork-lanes.sh. `run` is driven against a fake `forge`
# placed first on PATH, which records its arguments and plays back one outcome per call;
# `check` is pointed at fixture workflows through FORK_LANES_WORKFLOW.
#
# Usage: ./script/test-fork-lanes.sh   (`make scripts-check` runs it)
# ---------------------------------------------------------------------------
set -euo pipefail

LANES_SH="$(cd "$(dirname "$0")" && pwd)/fork-lanes.sh"
WORKFLOW="$(cd "$(dirname "$0")/.." && pwd)/.github/workflows/scheduled.yml"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
failures=0
n=0

# The fake forge: call k plays the k-th word of FAKE_FORGE_OUTCOMES (ok | rpc | fail).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/forge" <<'FAKE'
#!/usr/bin/env bash
count=$(($(cat "$FAKE_FORGE_DIR/count" 2>/dev/null || echo 0) + 1))
echo "$count" > "$FAKE_FORGE_DIR/count"
echo "$*" >> "$FAKE_FORGE_DIR/calls"
outcome=$(echo "$FAKE_FORGE_OUTCOMES" | cut -d' ' -f"$count")
case "$outcome" in
    ok) echo "Suite result: ok. 1 passed; 0 failed; 0 skipped"; exit 0 ;;
    rpc)
        echo "[FAIL: setup dead] setUp() (gas: 0)"
        echo "[FAIL: error sending request for url (https://rpc.example)] test_Body() (gas: 0)"
        exit 1
        ;;
    *) echo "[FAIL: setup dead] setUp() (gas: 0)"; exit 1 ;;
esac
FAKE
chmod +x "$TMP/bin/forge"

pass() { echo "ok   $1"; }
fail() { echo "FAIL $1 ($2)"; failures=$((failures + 1)); }

# expect_run <name> <lane> <outcomes> <want exit> <want forge calls>
# Also requires that no call uses --rerun: forge's failure cache omits failed setUp()s.
expect_run() {
    local name=$1 lane=$2 outcomes=$3 want_rc=$4 want_calls=$5 rc calls
    n=$((n + 1))
    rm -f "$TMP/count" "$TMP/calls"
    touch "$TMP/calls"
    rc=0
    (cd "$TMP" && PATH="$TMP/bin:$PATH" FAKE_FORGE_DIR="$TMP" FAKE_FORGE_OUTCOMES="$outcomes" \
        "$LANES_SH" run "$lane" > /dev/null 2>&1) || rc=$?
    calls=$(wc -l < "$TMP/calls" | tr -d ' ')
    if { [ "$want_rc" -eq 0 ] && [ "$rc" -ne 0 ]; } || { [ "$want_rc" -ne 0 ] && [ "$rc" -eq 0 ]; }; then
        fail "$name" "exit $rc, expected $([ "$want_rc" -eq 0 ] && echo 0 || echo non-zero)"
    elif [ "$calls" -ne "$want_calls" ]; then
        fail "$name" "$calls forge calls, expected $want_calls"
    elif grep -q -- '--rerun' "$TMP/calls"; then
        fail "$name" "a retry used --rerun: $(grep -- '--rerun' "$TMP/calls")"
    elif [ "$calls" -gt 0 ] && [ "$(sort -u "$TMP/calls" | wc -l | tr -d ' ')" -ne 1 ]; then
        fail "$name" "the retry ran a different selection than the first run"
    else
        pass "$name"
    fi
}

# expect_status <name> <want: 0 | nonzero> <command...>
expect_status() {
    local name=$1 want=$2 rc=0
    shift 2
    n=$((n + 1))
    "$@" > "$TMP/out" 2>&1 || rc=$?
    if { [ "$want" = 0 ] && [ "$rc" -eq 0 ]; } || { [ "$want" = nonzero ] && [ "$rc" -ne 0 ]; }; then
        pass "$name"
    else
        fail "$name" "exit $rc, expected $want: $(tail -n 3 "$TMP/out" | tr '\n' ' ')"
    fi
}

expect_run "run: passing lane runs once" mainnet "ok" 0 1
expect_run "run: RPC failure reruns the whole lane once" mainnet "rpc ok" 0 2
expect_run "run: RPC failure, retry still failing" mainnet "rpc rpc" 1 2
expect_run "run: setUp failure without an RPC error is not retried" mainnet "fail ok" 1 1
expect_run "run: unknown lane fails before forge" bogus "ok" 1 0

expect_status "glob: unknown lane fails" nonzero "$LANES_SH" glob bogus
expect_status "secrets: unknown lane fails" nonzero "$LANES_SH" secrets bogus
expect_status "require: unknown lane fails" nonzero "$LANES_SH" require bogus
expect_status "require: missing secret fails" nonzero env -u MAINNET_RPC_URL "$LANES_SH" require mainnet
expect_status "require: empty secret fails" nonzero env MAINNET_RPC_URL= "$LANES_SH" require mainnet
expect_status "require: set secrets pass" 0 env SEPOLIA_RPC_URL=x BASE_SEPOLIA_RPC_URL=y ARC_TESTNET_RPC_URL=z \
    "$LANES_SH" require cctp-testnet

expect_status "check: the committed workflow passes" 0 "$LANES_SH" check
awk '{print} /^ +- cctp-testnet$/ {sub(/cctp-testnet/, "cctp-mainnet"); print}' "$WORKFLOW" > "$TMP/extra.yml"
expect_status "check: a matrix lane the script lacks fails" nonzero env FORK_LANES_WORKFLOW="$TMP/extra.yml" \
    "$LANES_SH" check
n=$((n + 1))
if grep -q "matrix lists lane 'cctp-mainnet'" "$TMP/out"; then
    pass "check: names the unknown matrix lane"
else
    fail "check: names the unknown matrix lane" "$(tail -n 3 "$TMP/out" | tr '\n' ' ')"
fi
grep -vE '^ +- sepolia$' "$WORKFLOW" > "$TMP/missing.yml"
expect_status "check: a script lane missing from the matrix fails" nonzero env FORK_LANES_WORKFLOW="$TMP/missing.yml" \
    "$LANES_SH" check

echo "$((n - failures))/$n fork-lanes cases passed"
[ "$failures" -eq 0 ]
