#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# mutation-test.sh
#
# Local Gambit mutation pilot (#245; LatticeRegistry and LatticeFactory added in
# #176). NOT run in CI and not a repo dependency: install Gambit
# (https://github.com/Certora/gambit) yourself to use it.
#
#   1. Generates mutants of the files in test/mutation/gambit.conf.json into
#      gambit_out/ (gitignored). Generation is skipped while the config, the
#      target sources and the solc binary are unchanged (gambit_out/.stamp).
#   2. Copies the repo to one scratch directory per target file (mktemp, minus
#      out/ cache/ .git/ gambit_out/), never touching the working tree's src/.
#      Forge runs from inside the scratch copy, so the `forge inspect` FFI in
#      test/helpers/GetSelectors.sol reads the scratch build, not ./out.
#   3. Per target: a baseline run of its test set on the unmutated copy (abort
#      if red), then for each mutant: copy it over the scratch source, run the
#      test set with --fail-fast, restore the pristine source, and classify it
#      KILLED (a test failed), SURVIVED (all passed) or STILLBORN (did not
#      compile; left out of the score). Targets run in parallel.
#   4. Writes gambit_out/run/report.md (score per file + survivor list) and
#      keeps each mutant's forge log in gambit_out/run/logs/<id>.log for triage
#      (gambit_out/rerun/ for a MUTANTS subset).
#
# Deterministic: Gambit's default seed, a fixed --fuzz-seed, FOUNDRY_PROFILE=ci.
# FOUNDRY_BUILD_INFO=false keeps build-info files from piling up per recompile.
#
# Usage: ./script/mutation-test.sh   (`make mutation`)
#   SOLC=<path>        solc binary for Gambit's validation compile (default: the
#                      svm solc matching foundry.toml's pin, else `solc`)
#   MUTANTS="3 17 42"  run only these mutant ids (e.g. re-check survivors after
#                      adding tests); ids are stable while the stamp matches
#   TARGETS="ERC4626Lib AccessManagerLib"  run only these target files
#   KEEP=1             keep the scratch copies (path printed) for debugging
#   FUZZ_SEED=<hex>    fuzz/invariant seed (default 0x245)
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

CONF=test/mutation/gambit.conf.json
OUT=gambit_out
FUZZ_SEED=${FUZZ_SEED:-0x245}
MUTANTS=${MUTANTS:-}
TARGETS=${TARGETS:-}
KEEP=${KEEP:-0}
# A full run writes gambit_out/run/; a MUTANTS subset writes gambit_out/rerun/ and leaves the full run intact.
RUN=$OUT/${MUTANTS:+re}run

# Test set per target: every non-fork, non-gas suite that reaches the library through a recipe diamond.
match_set() {
    case "$1" in
        ERC4626Lib)
            echo 'test/{unit/{ERC4626Test,VaultCoreTest,StrategyManagerTest,GovernedVaultENSInitTest,GovernedVaultUpgradeTest},fuzz/{ERC4626*,MulDivDifferentialFuzz},integration/{AaveV3AdapterVaultTest,AMMVaultTest,CompoundV3AdapterTest,ERC4626AdapterTest,GovernedVaultTest,StrategyLiquidityTest,Vault*},invariant/{ERC4626RoundTripInvariant,VaultDiamondInvariant}}.t.sol'
            ;;
        StrategyManagerLib)
            echo 'test/{unit/{StrategyManagerTest,VaultCoreTest},fuzz/ERC4626PreviewDifferentialFuzz,integration/{AaveV3Adapter*,AdapterOperatorGuardTest,CompoundV3AdapterTest,CurveStableSwapAdapterTest,ERC4626AdapterTest,GovernedVaultTest,LidoAdapterTest,StrategyLiquidityTest,UniswapV3AdapterTest,Vault*},invariant/{ERC4626RoundTripInvariant,VaultDiamondInvariant}}.t.sol'
            ;;
        AccessManagerLib)
            echo 'test/{unit/{AccessManagerTest,AccessManagerStandaloneTest,AccessManagedTest},invariant/AccessManagerDiamondInvariant}.t.sol'
            ;;
        LatticeRegistry | LatticeFactory)
            echo 'test/{unit/{LatticeRegistryTest,LatticeRegistryHostileExporterTest,LatticeFactoryTest,LatticeFactoryHardeningTest,DeployFactoryTest},fuzz/{LatticeRegistryFuzz,LatticeFactoryFuzz},integration/{LatticeRegistryCompositionTest,LatticeFactoryCompositionTest,LatticeFactoryGovernedVaultTest},invariant/{LatticeRegistryInvariant,LatticeFactoryInvariant}}.t.sol'
            ;;
        *)
            echo "mutation: no test set for $1; add one to match_set()" >&2
            return 1
            ;;
    esac
}

command -v gambit >/dev/null 2>&1 || {
    echo "mutation: gambit not installed (cargo install --git https://github.com/Certora/gambit)" >&2
    exit 1
}

if [ -z "${SOLC:-}" ]; then
    pin=$(sed -n 's/^solc *= *"\(.*\)"/\1/p' foundry.toml | head -n 1)
    for dir in "$HOME/Library/Application Support/svm" "$HOME/.svm"; do
        [ -x "$dir/$pin/solc-$pin" ] && SOLC="$dir/$pin/solc-$pin" && break
    done
    SOLC=${SOLC:-solc}
fi
"$SOLC" --version | grep -q "Version: ${pin:-}" || echo "mutation: warning: $SOLC is not solc ${pin:-}" >&2

# The target sources, from the config (paths there are relative to the config's own directory).
sources=$(sed -n 's#.*"filename": *"\.\./\.\./\(.*\)".*#\1#p' "$CONF")
[ -n "$sources" ] || {
    echo "mutation: no \"../../<path>\" filename entries in $CONF" >&2
    exit 1
}

# ---- 1. generate (cached) --------------------------------------------------
stamp=$({
    cat "$CONF"
    for f in $sources; do cat "$f"; done
    "$SOLC" --version
} | shasum -a 256 | cut -d' ' -f1)
if [ -f "$OUT/.stamp" ] && [ "$(cat "$OUT/.stamp")" = "$stamp" ]; then
    echo "mutation: reusing mutants in $OUT/ (sources unchanged)"
else
    echo "mutation: generating mutants (Gambit validates each one with solc; this takes a few minutes)"
    rm -rf "$OUT"
    gambit mutate --json "$CONF" --solc "$SOLC" >/dev/null
    echo "$stamp" >"$OUT/.stamp"
fi
rm -rf "$RUN/logs" "$RUN/results"
mkdir -p "$RUN/logs" "$RUN/results"

# ---- 2/3. one scratch lane per target --------------------------------------
scratches=()
cleanup() {
    jobs -p | xargs kill 2>/dev/null || true
    if [ "$KEEP" = 1 ]; then
        [ ${#scratches[@]} -eq 0 ] || echo "mutation: scratch copies kept: ${scratches[*]}"
    else
        for d in "${scratches[@]+"${scratches[@]}"}"; do rm -rf "$d"; done
    fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

run_tests() { # <scratch> <glob> [extra forge args...]
    local dir=$1 glob=$2
    shift 2
    (cd "$dir" && FOUNDRY_PROFILE=ci FOUNDRY_BUILD_INFO=false FORGE_SNAPSHOT_EMIT=false \
        forge test --match-path "$glob" --no-match-path 'test/fork/*' --fuzz-seed "$FUZZ_SEED" "$@")
}

lane() { # <source path> <scratch>
    local src=$1 dir=$2 name glob ids id log res
    name=$(basename "$src" .sol)
    glob=$(match_set "$name")
    res="$RUN/results/$name.tsv"
    : >"$res"

    if ! run_tests "$dir" "$glob" >"$RUN/logs/baseline-$name.log" 2>&1; then
        echo "mutation: $name baseline is red; see $RUN/logs/baseline-$name.log" >&2
        echo "BASELINE_FAILED" >"$res"
        return 1
    fi

    # mutants.log: id,operator,file,line:col,original,replacement (only the first four fields are comma-safe).
    ids=$(awk -F, -v f="$src" '$3 == f { print $1 }' "$OUT/mutants.log")
    for id in $ids; do
        if [ -n "$MUTANTS" ] && ! grep -qw "$id" <<<"$MUTANTS"; then continue; fi
        log="$RUN/logs/$id.log"
        cp "$OUT/mutants/$id/$src" "$dir/$src"
        if run_tests "$dir" "$glob" --fail-fast >"$log" 2>&1; then
            status=SURVIVED
        elif grep -q "Compiler run failed" "$log"; then
            status=STILLBORN
        else
            status=KILLED
        fi
        cp "$src" "$dir/$src"
        printf '%s\t%s\n' "$id" "$status" >>"$res"
        echo "mutation: $name #$id $status"
    done
}

pids=()
for src in $sources; do
    name=$(basename "$src" .sol)
    if [ -n "$TARGETS" ] && ! grep -qw "$name" <<<"$TARGETS"; then continue; fi
    dir=$(mktemp -d "${TMPDIR:-/tmp}/lattice-mutation-$name.XXXXXX")
    scratches+=("$dir")
    rsync -a --exclude /.git --exclude /out --exclude /cache --exclude "/$OUT" ./ "$dir/"
    lane "$src" "$dir" &
    pids+=($!)
done
fail=0
for p in "${pids[@]}"; do wait "$p" || fail=1; done

# ---- 4. report -------------------------------------------------------------
report="$RUN/report.md"
{
    echo "# Mutation pilot report"
    echo
    echo "Gambit config: \`$CONF\`; fuzz seed $FUZZ_SEED; profile ci."
    [ -z "$MUTANTS" ] || echo "Subset run: MUTANTS=\"$MUTANTS\"."
    echo
    echo "| File | Mutants | Killed | Survived | Stillborn | Score |"
    echo "| --- | ---: | ---: | ---: | ---: | ---: |"
    for f in "$RUN"/results/*.tsv; do
        [ -e "$f" ] || continue
        awk -F'\t' -v n="$(basename "$f" .tsv)" '
            $1 == "BASELINE_FAILED" { printf "| %s | baseline failed | | | | |\n", n; bad = 1; next }
            { t++; c[$2]++ }
            END {
                if (bad) exit
                s = c["KILLED"] + c["SURVIVED"]
                printf "| %s | %d | %d | %d | %d | %s |\n", n, t, c["KILLED"], c["SURVIVED"], c["STILLBORN"],
                    s ? sprintf("%.1f%%", 100 * c["KILLED"] / s) : "n/a"
            }' "$f"
    done
    echo
    echo "## Survivors"
    echo
    echo "| Id | File:line:col | Operator | Original,replacement |"
    echo "| ---: | --- | --- | --- |"
    for f in "$RUN"/results/*.tsv; do
        [ -e "$f" ] || continue
        awk -F'\t' '$2 == "SURVIVED" { print $1 }' "$f" | while read -r id; do
            awk -F, -v id="$id" '$1 == id {
                tail = $0; for (i = 1; i <= 4; i++) sub(/^[^,]*,/, "", tail)
                gsub(/\|/, "\\|", tail)
                printf "| %s | %s:%s | %s | `%s` |\n", $1, $3, $4, $2, tail
            }' "$OUT/mutants.log"
        done
    done
} >"$report"
cat "$report"
exit "$fail"
