#!/usr/bin/env bash
# Exercise the exporter with isolated native-command fixtures; never compile or contact an RPC.
set -euo pipefail
cd "$(dirname "$0")/../.."
temporary=$(mktemp -d "${TMPDIR:-/tmp}/lattice-recipe-export-fixtures.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
fixture=$temporary/checkout
mkdir -p "$fixture/script/recipes" "$fixture/bin" "$fixture/out/RecipeSpec.sol" "$fixture/deployments"
cp script/recipes.sh "$fixture/script/recipes.sh"
cp script/recipes/type-description.jq "$fixture/script/recipes/type-description.jq"
cat > "$temporary/interface.json" <<'JSON'
{"abi":[{"type":"function","name":"recipeSpec","stateMutability":"pure","inputs":[],"outputs":[{"name":"","type":"tuple","internalType":"struct RecipeSpec","components":[{"name":"name","type":"string","internalType":"string"},{"name":"source","type":"string","internalType":"string"},{"name":"variants","type":"tuple[]","internalType":"struct RecipeVariant[]","components":[{"name":"id","type":"string","internalType":"string"},{"name":"initPlan","type":"tuple[]","internalType":"struct RecipeInitStep[]","components":[{"name":"parent","type":"uint256","internalType":"uint256"}]}]},{"name":"deploymentContexts","type":"tuple[]","internalType":"struct RecipeDeploymentContext[]","components":[{"name":"signature","type":"string","internalType":"string"}]}]}]}]}
JSON
cat > "$temporary/inventory.json" <<'JSON'
{"names":["DeployZeta","DeployAlpha","DeployMiddle"],"artifacts":["script/base/fixtures/DeployZeta.s.sol:DeployZeta","script/base/fixtures/DeployAlpha.s.sol:DeployAlpha","script/base/fixtures/DeployMiddle.s.sol:DeployMiddle"],"schemaVersion":1,"latticeVersion":"99.0.0","futureMetadata":{"retained":"yes"}}
JSON
cat > "$fixture/script/check-release-build.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
[ "${FOUNDRY_PROFILE:-}" = ci ]
printf 'guard\n' >> "$FIXTURE_EVENTS"
[ "$SCENARIO" != guard-fails ]
BASH
cat > "$fixture/script/recipes/check-catalog.sh" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" = 1 ]
case "$1" in deployments/.recipes-export.*/catalog.json) ;; *) exit 1 ;; esac
[ -f "$1" ]
jq -e '(.recipes|length)==3' "$1" >/dev/null
printf 'catalog\n' >> "$FIXTURE_EVENTS"
[ "$SCENARIO" != catalog-fails ]
BASH
cat > "$fixture/bin/git" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    'rev-parse HEAD')
        printf 'git:commit\n' >> "$FIXTURE_EVENTS"
        [ "$SCENARIO" != git-fails ] || exit 1
        printf '%040d\n' 1
        ;;
    'status --porcelain --untracked-files=all')
        printf 'git:status\n' >> "$FIXTURE_EVENTS"
        # Creating the export stage before provenance would make the clean positive fixture dirty.
        if [ "$SCENARIO" = dirty-source ] || compgen -G 'deployments/.recipes-export.*' >/dev/null; then
            printf '?? source-change.sol\n'
        fi
        ;;
    *) printf 'unexpected git fixture command\n' >&2; exit 1 ;;
esac
BASH
cat > "$fixture/bin/forge" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
[ "${FOUNDRY_PROFILE:-}" = ci ]
if [ "${1:-}" = build ]; then
    [ "$*" = 'build --locked --skip test' ]
    printf 'build\n' >> "$FIXTURE_EVENTS"
    [ "$SCENARIO" != build-fails ]
    exit
fi
[ "$#" -ge 4 ] && [ "$1" = script ] && [ "$2" = script/recipes/GenerateRecipes.s.sol:GenerateRecipes ] && [ "$3" = --sig ]
signature=$4
shift 4
case "$signature" in
    'inventory(string,string)')
        [ "$#" = 3 ] && [ "$3" = --non-interactive ]
        description=$1 destination=$2
        [[ "$destination" == deployments/.recipes-export.*/* ]]
        printf 'inventory\n' >> "$FIXTURE_EVENTS"
        [ "$SCENARIO" != inventory-fails ] || exit 61
        [ "$SCENARIO" != missing-inventory ] || exit 0
        if [ "$SCENARIO" = malformed-inventory ]; then printf '{' > "$destination"; exit 0; fi
        jq --arg description "$description" '. + {typeDescription:$description}' "$FIXTURE_INVENTORY" > "$destination"
        case "$SCENARIO" in
            wrong-count) jq '.artifacts |= .[0:2]' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
            duplicate-name) jq '.names[1]=.names[0]' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
            duplicate-artifact) jq '.artifacts[1]=.artifacts[0]' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
            empty-inventory) jq '.names=[] | .artifacts=[]' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
            bad-fqn) jq '.artifacts[1]="../outside.sol:DeployAlpha"' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
            class-name-mismatch) jq '.artifacts[1]="script/base/fixtures/DeployAlpha.s.sol:Other"' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
            wrong-description) jq '.typeDescription="wrong"' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
            wrong-schema) jq '.schemaVersion=2' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
            multiple-inventory) printf '\n{}\n' >> "$destination" ;;
        esac
        ;;
    'generate(string,string,string,string)')
        [ "$#" = 5 ] && [ "$5" = --non-interactive ]
        name=$1 artifact=$2 description=$3 destination=$4
        [[ "$destination" == deployments/.recipes-export.*/* ]]
        [ "$description" = "$(jq -r '.typeDescription' "$(dirname "$destination")/inventory.json")" ]
        printf 'generate:%s\n' "$name" >> "$FIXTURE_EVENTS"
        if [ "$name" = DeployAlpha ]; then
            case "$SCENARIO" in
                record-fails) exit 61 ;;
                missing-record) exit 0 ;;
                partial-output) printf '{"name":' > "$destination"; exit 61 ;;
                malformed-record) printf '{"name":' > "$destination"; exit 0 ;;
            esac
        fi
        jq -n --arg name "$name" --arg source "${artifact%:*}" \
            --arg maximum '115792089237316195423570985008687907853269984665640564039457584007913129639935' \
            '{name:$name,source:$source,variants:[{id:($name+":buildCuts()"),initPlan:[{parent:$maximum}]}],deploymentContexts:[{signature:"run()"}]}' > "$destination"
        if [ "$name" = DeployAlpha ]; then
            case "$SCENARIO" in
                wrong-name) jq '.name="Unexpected"' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
                wrong-source) jq '.source="script/base/fixtures/Unexpected.s.sol"' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
                partial-record) jq 'del(.variants,.deploymentContexts)' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
                empty-variants) jq '.variants=[]' "$destination" > "$destination.next"; mv "$destination.next" "$destination" ;;
                multiple-record) printf '\n{}\n' >> "$destination" ;;
            esac
        fi
        ;;
    *) printf 'unexpected forge fixture command\n' >&2; exit 1 ;;
esac
BASH
chmod +x "$fixture/bin/forge" "$fixture/bin/git" "$fixture/script/check-release-build.sh" "$fixture/script/recipes/check-catalog.sh"
export FIXTURE_EVENTS=$temporary/events FIXTURE_INVENTORY=$temporary/inventory.json
export PATH="$fixture/bin:$PATH"
passed=0
reset_fixture() {
    cp "$temporary/interface.json" "$fixture/out/RecipeSpec.sol/IRecipeSpec.json"
    for name in DeployZeta DeployAlpha DeployMiddle; do
        mkdir -p "$fixture/out/$name.s.sol"
        # A return-variable name may differ; the returned tuple shape must still match the interface.
        jq '.abi[0].outputs[0].name="result"' "$temporary/interface.json" > "$fixture/out/$name.s.sol/$name.json"
    done
    rm -rf "$fixture/out/recipes.json"
    printf '{"previous":"keep"}\n' > "$fixture/out/recipes.json"
    cp "$fixture/out/recipes.json" "$temporary/previous.json"
    : > "$FIXTURE_EVENTS"
    mkdir -p "$fixture/deployments/.recipes-export-unrelated"
    printf 'keep\n' > "$fixture/deployments/.recipes-export-unrelated/keep"
}
check_cleanup() {
    [ "$(cat "$fixture/deployments/.recipes-export-unrelated/keep")" = keep ]
    if compgen -G "$fixture/deployments/.recipes-export.*" >/dev/null; then
        echo 'recipe export left its own temporary output behind' >&2; exit 1
    fi
    diff -r -x recipes.json "$temporary/out-before" "$fixture/out"
}
snapshot_out() { rm -rf "$temporary/out-before"; cp -R "$fixture/out" "$temporary/out-before"; }
invoke() { SCENARIO=$1 bash "$fixture/script/recipes.sh" > "$temporary/run.log" 2>&1; }
reject() {
    local scenario=$1
    reset_fixture
    case "$scenario" in
        missing-abi) rm "$fixture/out/DeployAlpha.s.sol/DeployAlpha.json" ;;
        missing-method) jq '.abi=[]' "$temporary/interface.json" > "$fixture/out/DeployAlpha.s.sol/DeployAlpha.json" ;;
        impure-method) jq '.abi[0].stateMutability="view"' "$temporary/interface.json" > "$fixture/out/DeployAlpha.s.sol/DeployAlpha.json" ;;
        method-input) jq '.abi[0].inputs=[{name:"unexpected",type:"address"}]' "$temporary/interface.json" > "$fixture/out/DeployAlpha.s.sol/DeployAlpha.json" ;;
        wrong-output-type) jq '.abi[0].outputs[0].components[2].components[1].components[0].type="uint128"' "$temporary/interface.json" > "$fixture/out/DeployAlpha.s.sol/DeployAlpha.json" ;;
        wrong-output-field) jq '.abi[0].outputs[0].components[2].components[1].components[0].name="differentParent"' "$temporary/interface.json" > "$fixture/out/DeployAlpha.s.sol/DeployAlpha.json" ;;
        duplicate-method) jq '.abi += .abi' "$temporary/interface.json" > "$fixture/out/DeployAlpha.s.sol/DeployAlpha.json" ;;
        malformed-abi) printf '{' > "$fixture/out/DeployAlpha.s.sol/DeployAlpha.json" ;;
        output-directory)
            rm "$fixture/out/recipes.json"
            mkdir "$fixture/out/recipes.json"
            cp "$temporary/previous.json" "$fixture/out/recipes.json/keep"
            ;;
    esac
    snapshot_out
    if invoke "$scenario"; then printf 'recipe export accepted %s\n' "$scenario" >&2; exit 1; fi
    if [ "$scenario" = output-directory ]; then cmp "$temporary/previous.json" "$fixture/out/recipes.json/keep"
    else cmp "$temporary/previous.json" "$fixture/out/recipes.json"; fi
    case "$scenario" in
        missing-abi|missing-method|impure-method|method-input|wrong-output-type|wrong-output-field|duplicate-method|malformed-abi)
            grep -Fq 'DeployAlpha:' "$temporary/run.log"
            ! grep -q '^generate:DeployAlpha$' "$FIXTURE_EVENTS"
            ;;
    esac
    if [ "$scenario" = catalog-fails ]; then
        grep -q '^catalog$' "$FIXTURE_EVENTS"
        [ "$(grep -c '^generate:' "$FIXTURE_EVENTS")" = 3 ]
    fi
    check_cleanup
    passed=$((passed+1))
}
for scenario in git-fails guard-fails build-fails inventory-fails missing-inventory malformed-inventory \
    multiple-inventory wrong-count duplicate-name duplicate-artifact empty-inventory bad-fqn class-name-mismatch \
    wrong-description wrong-schema missing-abi missing-method impure-method method-input wrong-output-type \
    wrong-output-field duplicate-method malformed-abi record-fails missing-record partial-output malformed-record \
    wrong-name wrong-source partial-record empty-variants multiple-record output-directory catalog-fails; do
    reject "$scenario"
done
for scenario in success dirty-source; do
    reset_fixture
    snapshot_out
    invoke "$scenario" || { cat "$temporary/run.log" >&2; exit 1; }
    dirty=false
    [ "$scenario" != dirty-source ] || dirty=true
    jq -e --argjson dirty "$dirty" \
        --arg maximum '115792089237316195423570985008687907853269984665640564039457584007913129639935' '
        .schemaVersion==1 and .latticeVersion=="99.0.0" and .futureMetadata.retained=="yes" and
        (.typeDescription|startswith("RecipeSpec(")) and
        .sourceCommit=="0000000000000000000000000000000000000001" and .sourceDirty==$dirty and
        (has("names")|not) and (has("artifacts")|not) and
        [.recipes[].name]==["DeployZeta","DeployAlpha","DeployMiddle"] and
        all(.recipes[]; .variants[0].initPlan[0].parent==$maximum and (.variants[0].initPlan[0].parent|type)=="string")
    ' "$fixture/out/recipes.json" >/dev/null
    printf 'git:commit\ngit:status\nguard\nbuild\ninventory\ngenerate:DeployZeta\ngenerate:DeployAlpha\ngenerate:DeployMiddle\ncatalog\n' > "$temporary/expected-events"
    cmp "$temporary/expected-events" "$FIXTURE_EVENTS"
    check_cleanup
    passed=$((passed+1))
done
printf 'recipe export fixtures: %s cases passed; ordered bounded calls, atomic failure, provenance, ABI guards and uint256 strings preserved\n' "$passed"
