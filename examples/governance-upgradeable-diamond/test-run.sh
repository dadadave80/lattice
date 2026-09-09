#!/usr/bin/env bash
# Small CLI-contract regression: real Bash runner/Make targets, mocked forge/cast, no RPC or secrets.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
TEMP=$(mktemp -d)
trap 'rm -rf "$TEMP"' EXIT
export MOCK_LOG="$TEMP/calls" MOCK_CLOCK="$TEMP/clock"
cat > "$TEMP/tool" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s ' "$(basename "$0")" "$@" >> "$MOCK_LOG"
printf '\n' >> "$MOCK_LOG"
if [[ "$(basename "$0")" == forge ]]; then
  printf 'VAULT 0x1111111111111111111111111111111111111111\nASSET 0x2222222222222222222222222222222222222222\nPROBE 0x3333333333333333333333333333333333333333\n'
  exit
fi
clock() {
  if [[ ${MOCK_FREEZE:-0} == 1 ]]; then echo 0; return; fi
  if [[ ${MOCK_BAD_CLOCK:-0} == 1 ]]; then echo invalid; return; fi
  n=$(cat "$MOCK_CLOCK")
  n=$((n + 1000))
  echo "$n" > "$MOCK_CLOCK"
  echo "$n"
}
case "$1" in
  wallet) echo 0x4444444444444444444444444444444444444444 ;;
  chain-id) echo 31337 ;;
  rpc) [[ " $* " == *' web3_clientVersion '* ]] && echo '"anvil/v1.8.1"' || { echo 'public RPC must not receive time-travel methods' >&2; exit 1; } ;;
  block) clock ;;
  sig) echo 0x12345678 ;;
  calldata|keccak) echo 0x00 ;;
  send) printf '{"status":"%s","transactionHash":"0xabc"}\n' "${MOCK_STATUS:-0x1}" ;;
  call)
    case " $* " in
      *' asset()(address) '*) echo 0x2222222222222222222222222222222222222222 ;;
      *' grantVersion()(uint256) '*) echo 2 ;;
      *' facetAddress(bytes4)(address) '*) echo 0x0000000000000000000000000000000000000000 ;;
      *' clock()(uint48) '*) clock ;;
      *' proposalSnapshot(uint256)(uint256) '*) echo 2000 ;;
      *' proposalDeadline(uint256)(uint256) '*) echo 5000 ;;
      *' proposalEta(uint256)(uint256) '*) echo 8000 ;;
      *' hashProposal('* ) echo 1 ;;
      *' totalAssets()(uint256) '*|*' balanceOf(address)(uint256) '*) echo 1000000000000000000000 ;;
      *) echo "unexpected call" >&2; exit 1 ;;
    esac ;;
  *) echo 'unexpected cast command' >&2; exit 1 ;;
esac
MOCK
chmod +x "$TEMP/tool"
ln -s tool "$TEMP/forge"
ln -s tool "$TEMP/cast"
export PATH="$TEMP:$PATH"
reset_mock() { : > "$MOCK_LOG"; echo 0 > "$MOCK_CLOCK"; }
run() { make --no-print-directory RPC=https://example.invalid FORGE_AUTH='--account fixture --password-file /fixture/password' POLL_INTERVAL=1 WAIT_TIMEOUT=10 "$@" > "$TEMP/output" 2>&1; }
absent() { if grep -q "$1" "$MOCK_LOG"; then echo "unexpected call: $1" >&2; exit 1; fi; }
reset_mock
run example-ens-grant-m2
grep -q 'assets and shares preserved' "$TEMP/output"
grep -q -- '--broadcast --slow --verify --verifier etherscan' "$MOCK_LOG"
grep -q -- '--account fixture --password-file /fixture/password' "$MOCK_LOG"
absent 'evm_'
reset_mock
run example-ens-grant-m2 VERIFIER=blockscout VERIFIER_URL=https://explorer.invalid/api
grep -q -- '--verifier-url https://explorer.invalid/api' "$MOCK_LOG"
grep -q 'execute(address' "$MOCK_LOG"
reset_mock
if run example-ens-grant-m2 LOCAL=1; then echo 'accepted remote time travel' >&2; exit 1; fi
absent 'cast send\|^forge '
reset_mock
if run example-ens-grant-m2 FORGE_AUTH=; then echo 'accepted missing signer' >&2; exit 1; fi
reset_mock
if MOCK_STATUS=0x0 run example-ens-grant-m2; then echo 'ignored reverted receipt' >&2; exit 1; fi
absent 'approve(address'
reset_mock
if MOCK_FREEZE=1 run example-ens-grant-m2 WAIT_TIMEOUT=1; then echo 'ignored clock timeout' >&2; exit 1; fi
absent 'propose(address'
reset_mock
if MOCK_BAD_CLOCK=1 run example-ens-grant-m2; then echo 'accepted malformed clock' >&2; exit 1; fi
echo 'Example runner: deployment, governance, RPC, signer, verification, clock, and receipt checks passed'
