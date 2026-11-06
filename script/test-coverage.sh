#!/usr/bin/env bash
# Exercise the shared Make coverage entrypoint with isolated fake Forge commands; no compiler or RPC.
set -euo pipefail
cd "$(dirname "$0")/.."
temporary=$(mktemp -d "${TMPDIR:-/tmp}/lattice-coverage-fixtures.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
fixture=$temporary/checkout
mkdir -p "$fixture/script" "$fixture/bin"
cp Makefile "$fixture/Makefile"
cat > "$fixture/script/check-release-build.sh" <<'GUARD'
#!/usr/bin/env bash
set -euo pipefail
[ "${FOUNDRY_PROFILE:-}" = ci ] && [ "${FORGE_SNAPSHOT_EMIT:-}" = false ]
printf 'guard\n' >> "$FIXTURE_PHASES"
[ "$SCENARIO" != guard-fails ]
GUARD
cat > "$fixture/bin/forge" <<'FORGE'
#!/usr/bin/env bash
set -euo pipefail
[ "${FOUNDRY_PROFILE:-}" = ci ] && [ "${FORGE_SNAPSHOT_EMIT:-}" = false ]
jq -cn --arg profile "$FOUNDRY_PROFILE" --arg snapshots "$FORGE_SNAPSHOT_EMIT" --args '{args:$ARGS.positional,profile:$profile,snapshots:$snapshots}' -- "$@" >> "$FIXTURE_CALLS"
contract='^(ERC3643GasTest|ERC3643TemporaryGasTest|ERC3643AccountingInvariant|ERC3643ProfileTest|ERC3643RecoveryTest|ERC3643TemporaryApprovalTest|ERC3643TokenBoundsTest|ERC3643TokenEventsTest|ERC3643TokenTest)$'
method='^(test_Immutable_ERC3643|test_Immutable_ERC3643TemporaryApproval|test_AllFacetsUnderEip170Limit)\(\)$'
phase=
case "${1:-}" in
    build)
        [ "$#" = 2 ] && [ "$2" = --locked ]
        phase=build
        ;;
    test)
        if [ "$#" = 5 ] && [ "$2" = --no-match-path ] && [ "$3" = 'test/fork/*' ] && [ "$4" = --match-contract ] && [ "$5" = "$contract" ]; then phase=native-contracts
        elif [ "$#" = 7 ] && [ "$2" = --no-match-path ] && [ "$3" = 'test/fork/*' ] && [ "$4" = --no-match-contract ] && [ "$5" = "$contract" ] && [ "$6" = --match-test ] && [ "$7" = "$method" ]; then phase=native-methods
        else echo 'coverage fixture: native selection differs from exact partition' >&2; exit 1; fi
        ;;
    coverage)
        [ "$#" -ge 11 ] && [ "$2" = --report ] && [ "$3" = summary ] && [ "$4" = --no-match-path ] && [ "$5" = 'test/fork/*' ] && [ "$6" = --no-match-coverage ] && [ "$7" = '(test|script)/' ] && [ "$8" = --no-match-contract ] && [ "$9" = "$contract" ] && [ "${10}" = --no-match-test ] && [ "${11}" = "$method" ]
        shift 11
        if [ "$SCENARIO" = reports ]; then [ "$#" = 3 ] && [ "$1" = --md ] && [ "$2" = --report ] && [ "$3" = lcov ]; else [ "$#" = 0 ]; fi
        phase=coverage
        ;;
    *) echo 'coverage fixture: unexpected Forge command' >&2; exit 1 ;;
esac
printf '%s\n' "$phase" >> "$FIXTURE_PHASES"
if [ "$SCENARIO" = "$phase-fails" ]; then
    case "$phase" in native-contracts) echo 'ERC3643UnexpectedHost(canonical-hash-control)' >&2 ;; native-methods) echo 'ERC3643 runtime code exceeds EIP-170' >&2 ;; esac
    exit 1
fi
FORGE
chmod +x "$fixture/bin/forge" "$fixture/script/check-release-build.sh"
export FIXTURE_PHASES=$temporary/phases FIXTURE_CALLS=$temporary/calls
export PATH="$fixture/bin:$PATH"
# Caller settings must not silently replace the canonical native prerequisite or emit gas snapshots.
export FOUNDRY_PROFILE=unexpected FORGE_SNAPSHOT_EMIT=true
passed=0
run() {
    local scenario=$1 expected=$2 phases=$3
    : > "$FIXTURE_PHASES"; : > "$FIXTURE_CALLS"
    local -a command=(make -s -C "$fixture" coverage)
    [ "$scenario" != reports ] || command+=('ARGS=--md --report lcov')
    local actual=pass
    SCENARIO=$scenario "${command[@]}" > "$temporary/last.log" 2>&1 || actual=fail
    if [ "$actual" != "$expected" ]; then cat "$temporary/last.log" >&2; echo "coverage fixture $scenario: expected $expected, got $actual" >&2; exit 1; fi
    printf '%b' "$phases" > "$temporary/expected-phases"
    cmp "$temporary/expected-phases" "$FIXTURE_PHASES"
    jq -s -e 'all(.[];.profile=="ci" and .snapshots=="false")' "$FIXTURE_CALLS" >/dev/null
    passed=$((passed+1))
}
run success pass 'guard\nbuild\nnative-contracts\nnative-methods\ncoverage\n'
run reports pass 'guard\nbuild\nnative-contracts\nnative-methods\ncoverage\n'
run guard-fails fail 'guard\n'
run build-fails fail 'guard\nbuild\n'
run native-contracts-fails fail 'guard\nbuild\nnative-contracts\n'
run native-methods-fails fail 'guard\nbuild\nnative-contracts\nnative-methods\n'
run coverage-fails fail 'guard\nbuild\nnative-contracts\nnative-methods\ncoverage\n'
# Literal anchors keep independent ERC3643 components and the remaining mixed recipe methods measured.
contract=$(jq -sr '.[1].args[4]' "$FIXTURE_CALLS")
method=$(jq -sr '.[2].args[6]' "$FIXTURE_CALLS")
for name in ERC3643GasTest ERC3643TemporaryGasTest ERC3643AccountingInvariant ERC3643ProfileTest ERC3643RecoveryTest ERC3643TemporaryApprovalTest ERC3643TokenBoundsTest ERC3643TokenEventsTest ERC3643TokenTest; do [[ "$name" =~ $contract ]]; done
for name in ERC3643AgentRoleTest ERC3643ApiTest ERC3643RegistryConstantsTest ERC3643VerificationTest ERC3643RegistryEventsTest ERC3643RegistriesTest ERC3643IdentityRegistryStorageTest ERC3643ComplianceTest ERC3643TokenTestSuffix PrefixERC3643TokenTest RecipeUpgradeabilityTokensTest; do [[ ! "$name" =~ $contract ]]; done
for name in 'test_Immutable_ERC3643()' 'test_Immutable_ERC3643TemporaryApproval()' 'test_AllFacetsUnderEip170Limit()'; do [[ "$name" =~ $method ]]; done
for name in test_Immutable_ERC3643 test_Immutable_ERC3643TemporaryApproval test_AllFacetsUnderEip170Limit 'test_Immutable_ERC20()' 'test_Upgradeable_ERC20()' 'test_Immutable_ERC3643Suffix()' 'prefixtest_Immutable_ERC3643()'; do [[ ! "$name" =~ $method ]]; done
# Scheduled must reuse this tested entrypoint rather than grow a second coverage implementation.
check_scheduled() {
    local coverage_job
    coverage_job=$(sed -n '/^  coverage:$/,/^  invariant-deep:$/p' "$1")
    [ "$(grep -c '^[[:space:]]*make coverage ARGS=' <<< "$coverage_job")" = 1 ] || return 1
    if grep -Eq '^[[:space:]]*forge coverage([[:space:]]|$)' <<< "$coverage_job"; then return 1; fi
    grep -Fq "make coverage ARGS='--md --report lcov' | tee coverage.md" <<< "$coverage_job"
}
check_scheduled .github/workflows/scheduled.yml
passed=$((passed+1))
sed 's/make coverage ARGS=/forge coverage ARGS=/' .github/workflows/scheduled.yml > "$temporary/direct-coverage.yml"
if check_scheduled "$temporary/direct-coverage.yml"; then echo 'coverage fixture: direct Scheduled caller accepted' >&2; exit 1; fi
passed=$((passed+1))
sed '/^[[:space:]]*make coverage ARGS=/p' .github/workflows/scheduled.yml > "$temporary/duplicate-coverage.yml"
if check_scheduled "$temporary/duplicate-coverage.yml"; then echo 'coverage fixture: duplicate Scheduled caller accepted' >&2; exit 1; fi
passed=$((passed+1))
printf 'coverage fixtures: %s phase/report/abort cases passed; exact anchored native/complement partition preserved\n' "$passed"
