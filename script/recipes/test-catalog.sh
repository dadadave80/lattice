#!/usr/bin/env bash
# Isolated catalog/ABI fixtures: no Forge, real artifacts, RPC, or binding evaluation.
set -euo pipefail
cd "$(dirname "$0")/../.."
checker=$PWD/script/recipes/check-catalog.sh
[ -f "$checker" ] || { echo 'catalog fixtures: checker is missing' >&2; exit 1; }
temporary=$(mktemp -d "${TMPDIR:-/tmp}/lattice-catalog-fixtures.XXXXXX")
cleanup() { chmod -R u+w "$temporary" 2>/dev/null || true; rm -rf "$temporary"; }
trap cleanup EXIT
mkdir -p "$temporary/corpora" "$temporary/checker-temp"
mkdir -p "$temporary/checker-temp/caller-owned"
printf 'preserve caller-owned temporary files\n' > "$temporary/checker-temp/caller-owned/keep.txt"
cp -R "$temporary/checker-temp" "$temporary/checker-temp-expected"
maximum=115792089237316195423570985008687907853269984665640564039457584007913129639935
cat > "$temporary/fixture.jq" <<'JQ'
def field($n;$t): {name:$n,type:$t,internalType:$t};
def fields($pairs): [$pairs[]|field(.[0];.[1])];
def structure($n;$name;$suffix;$components):
  {name:$n,type:("tuple"+$suffix),internalType:("struct "+$name+$suffix),components:$components};
def enumfield($n;$name): {name:$n,type:"uint8",internalType:("enum "+$name)};
def parameterABI: fields([["name","string"],["abiType","string"],["unit","string"],["example","string"],["rule","string"]]);
def facetABI: [field("name";"string"),enumfield("action";"FacetCutAction"),enumfield("selection";"RecipeSelectorSelection"),field("selectors";"bytes4[]")];
def seamABI: fields([["id","string"],["selector","bytes4"],["participants","string[]"],["allowedOwners","string[]"],["allowUnrouted","bool"],["reason","string"]]);
def initABI: [field("name";"string"),field("signature";"string"),field("parent";"uint256"),field("constructorBound";"bool"),structure("constructorParameters";"RecipeParameter";"[]";parameterABI),field("constructorBindings";"string[]"),structure("parameters";"RecipeParameter";"[]";parameterABI),field("bindings";"string[]")];
def authorityABI: [enumfield("kind";"RecipeAuthorityKind")]+fields([["module","string"],["role","string"],["roleType","string"],["roleId","bytes32"],["grantee","string"],["reason","string"]]);
def variantABI: [field("id";"string"),field("buildSignature";"string"),enumfield("proxyKind";"RecipeProxyKind"),enumfield("initOutputKind";"RecipeInitOutputKind"),structure("facets";"RecipeFacet";"[]";facetABI),structure("seams";"RecipeSeam";"[]";seamABI),structure("initPlan";"RecipeInitStep";"[]";initABI),structure("inputs";"RecipeParameter";"[]";parameterABI),structure("authorities";"RecipeAuthority";"[]";authorityABI),field("conditions";"string[]")];
def contextABI: [field("id";"string"),field("signature";"string"),field("createsProxy";"bool"),field("variants";"string[]"),structure("inputs";"RecipeParameter";"[]";parameterABI),field("bindings";"string[]"),field("conditions";"string[]")];
def specABI: structure("result";"RecipeSpec";"";[field("name";"string"),field("source";"string"),structure("variants";"RecipeVariant";"[]";variantABI),structure("deploymentContexts";"RecipeDeploymentContext";"[]";contextABI)]);
def fn($n;$inputs;$outputs;$mutability): {type:"function",name:$n,inputs:$inputs,outputs:$outputs,stateMutability:$mutability};
def specmethod: fn("recipeSpec";[];[specABI];"pure");
def cutABI: structure("cuts";"FacetCut";"[]";[field("facetAddress";"address"),enumfield("action";"FacetCutAction"),field("functionSelectors";"bytes4[]")]);
def singleoutputs: [cutABI,field("init";"address"),field("initCalldata";"bytes")];
def paralleloutputs: [cutABI,field("inits";"address[]"),field("initCalldatas";"bytes[]")];
def constructor($inputs): {type:"constructor",inputs:$inputs,stateMutability:"nonpayable"};
def artifact($source;$name;$abi): {path:(($source|split("/")|last)+"/"+$name+".json"),content:{abi:$abi,metadata:{settings:{compilationTarget:{($source):$name}}},ast:{absolutePath:$source,nodes:[{nodeType:"ContractDefinition",name:$name,abstract:false,contractKind:"contract"}]}}};
def param($n;$t): {name:$n,abiType:$t,unit:"fixture-unit",example:"fixture-example",rule:"fixture descriptive rule"};
def leaf($n;$sig;$params;$bindings;$parent): {name:$n,signature:$sig,parent:$parent,constructorBound:false,constructorParameters:[],constructorBindings:[],parameters:$params,bindings:$bindings};
def multi($parent): leaf("MultiInit";"multiInit(address[],bytes[])";[param("_initAddresses";"address[]"),param("_initData";"bytes[]")];["children.targets","children.calldata"];$parent);
def fixturevariant($root): {id:"DeployFixture:buildCuts(address)",buildSignature:"buildCuts(address)",proxyKind:0,initOutputKind:0,facets:[{name:"FixtureFacet",action:0,selection:0,selectors:[]}],seams:[],initPlan:[leaf("FixtureInit";"init(address)";[param("admin";"address")];["admin"];$root)],inputs:[param("admin";"address")],authorities:[],conditions:[]};
def fixturecontext($id): {id:"DeployFixture:run(address)",signature:"run(address)",createsProxy:true,variants:[$id],inputs:[param("admin";"address")],bindings:["buildCuts(admin)"],conditions:[]};
def ordinaryABI($inputs;$outputs): [fn("buildCuts";$inputs;$outputs;"nonpayable"),fn("run";$inputs;[field("diamond";"address")];"nonpayable"),specmethod];
def replaceabi($path;$abi): .artifacts|=map(if .path==$path then .content.abi=$abi else . end);
def replacerecipe($name;$source;$abi):
  .artifacts|=map(if .path=="DeployFixture.s.sol/DeployFixture.json" then artifact($source;$name;$abi) else . end) |
  .catalog.recipes[0].name=$name | .catalog.recipes[0].source=$source;
$max as $root |
{catalog:{schemaVersion:1,latticeVersion:"99.0.0",typeDescription:"set-from-compiler-formatter",sourceCommit:"1111111111111111111111111111111111111111",sourceDirty:true,facetNames:["FixtureFacet","OtherFacet","ERC20TemporaryApproval"],facetArtifacts:["FixtureFacet.sol:FixtureFacet","OtherFacet.sol:OtherFacet","ERC20TemporaryApproval.sol:ERC20TemporaryApproval"],initializerNames:["FixtureInit","OtherInit","MultiInit"],initializerArtifacts:["FixtureInit.sol:FixtureInit","OtherInit.sol:OtherInit","MultiInit.sol:MultiInit"],accountProfiles:[],excludedContexts:[],abstractHelpers:[],recipes:[{name:"DeployFixture",source:"script/base/fixtures/DeployFixture.s.sol",variants:[fixturevariant($root)],deploymentContexts:[fixturecontext("DeployFixture:buildCuts(address)")]}]},artifacts:[
  artifact("script/lib/RecipeSpec.sol";"IRecipeSpec";[specmethod]),
  (artifact("src/fixtures/FixtureFacet.sol";"FixtureFacet";[fn("ping";[];[field("value";"uint256")];"view"),fn("pong";[];[];"view")])|.content.methodIdentifiers={"ping()":"5c36b186"}),
  artifact("src/fixtures/OtherFacet.sol";"OtherFacet";[fn("other";[];[];"view")]),
  artifact("src/fixtures/ERC20TemporaryApproval.sol";"ERC20TemporaryApproval";[fn("temporaryAllowance";[];[];"view")]),
  artifact("src/fixtures/FixtureInit.sol";"FixtureInit";[fn("init";[field("admin";"address")];[];"nonpayable")]),
  artifact("src/fixtures/OtherInit.sol";"OtherInit";[fn("init";[];[];"nonpayable")]),
  artifact("lib/diamond/initializers/MultiInit.sol";"MultiInit";[fn("multiInit";[field("_initAddresses";"address[]"),field("_initData";"bytes[]")];[];"nonpayable")]),
  artifact("script/base/fixtures/DeployFixture.s.sol";"DeployFixture";ordinaryABI([field("admin";"address")];singleoutputs))]} |
if $mode=="basic" then .
elif $mode=="nested" or $mode=="parallel" then
  .catalog.recipes[0].variants[0].initPlan=[multi($root),multi(0),leaf("FixtureInit";"init(address)";[param("admin";"address")];["admin"];1),leaf("OtherInit";"init()";[];[];0)] |
  if $mode=="parallel" then .catalog.recipes[0].variants[0].initOutputKind=1 | replaceabi("DeployFixture.s.sol/DeployFixture.json";ordinaryABI([field("admin";"address")];paralleloutputs)) else . end
elif $mode=="tuple" then
  [structure("config";"FixtureConfig";"";[field("admin";"address"),structure("limits";"FixtureLimits";"";[field("cap";"uint256"),field("beneficiaries";"address[]")])])] as $inputs |
  [param("config.admin";"address"),param("config.limits.cap";"uint256"),param("config.limits.beneficiaries";"address[]")] as $flat |
  replaceabi("DeployFixture.s.sol/DeployFixture.json";ordinaryABI($inputs;singleoutputs)) |
  .catalog.recipes[0].variants[0].buildSignature="buildCuts((address,(uint256,address[])))" |
  .catalog.recipes[0].variants[0].inputs=$flat | .catalog.recipes[0].variants[0].initPlan[0].bindings=["config.admin"] |
  .catalog.recipes[0].deploymentContexts[0].signature="run((address,(uint256,address[])))" | .catalog.recipes[0].deploymentContexts[0].inputs=$flat | .catalog.recipes[0].deploymentContexts[0].bindings=["buildCuts(config)"]
elif $mode=="tuple-array" then
  [structure("config";"FixtureConfig";"[]";[field("admin";"address"),field("weights";"uint256[]")])] as $inputs |
  [param("config.admin";"address[]"),param("config.weights";"uint256[][]")] as $flat |
  replaceabi("DeployFixture.s.sol/DeployFixture.json";ordinaryABI($inputs;singleoutputs)) |
  .catalog.recipes[0].variants[0].buildSignature="buildCuts((address,uint256[])[])" |
  .catalog.recipes[0].variants[0].inputs=$flat | .catalog.recipes[0].variants[0].initPlan[0].bindings=["config[0].admin"] |
  .catalog.recipes[0].deploymentContexts[0].signature="run((address,uint256[])[])" | .catalog.recipes[0].deploymentContexts[0].inputs=$flat | .catalog.recipes[0].deploymentContexts[0].bindings=["buildCuts(config)"]
elif $mode=="account" then
  [fn("buildCuts";[field("entryPoint";"address")];[cutABI,field("init";"address")];"nonpayable"),fn("run";[field("entryPoint";"address"),field("owner";"address"),field("salt";"bytes32")];[field("account";"address")];"nonpayable"),fn("buildFactory";[field("entryPoint";"address")];[field("factory";"address")];"nonpayable"),specmethod] as $abi |
  replaceabi("DeployFixture.s.sol/DeployFixture.json";$abi) |
  .artifacts += [artifact("src/fixtures/AccountInit.sol";"AccountInit";[constructor([field("entryPoint_";"address")]),fn("init";[field("owner_";"address")];[];"nonpayable")]),artifact("src/fixtures/AccountFactory.sol";"AccountFactory";[constructor([cutABI,field("init";"address")])]),artifact("lib/diamond/AccountDiamond.sol";"AccountDiamond";[])] |
  .catalog.accountProfiles=[{initializer:"AccountInitV07",initializerArtifact:"AccountInit.sol:AccountInit",factory:"AccountFactoryV07",factoryArtifact:"AccountFactory.sol:AccountFactory",proxyKind:"AccountDiamond",proxyArtifact:"AccountDiamond.sol:AccountDiamond",entryPoint:"0x000000000000000000000000000000000000e117",entryPointVersion:"v0.7-fixture",modular:false}] |
  .catalog.recipes[0].variants[0] |= (.proxyKind=1 | .initOutputKind=2 | .inputs=[param("entryPoint";"address")] | .initPlan=[(leaf("AccountInit";"init(address)";[param("owner_";"address")];["factory.createAccount owner"];$root) | .constructorBound=true | .constructorParameters=[param("entryPoint_";"address")] | .constructorBindings=["entryPoint"])]) |
  .catalog.recipes[0].deploymentContexts=[{id:"DeployFixture:run(address,address,bytes32)",signature:"run(address,address,bytes32)",createsProxy:true,variants:["DeployFixture:buildCuts(address)"],inputs:[param("entryPoint";"address"),param("owner";"address"),param("salt";"bytes32")],bindings:["buildCuts(entryPoint); createAccount(owner,salt)"],conditions:[]},{id:"DeployFixture:buildFactory(address)",signature:"buildFactory(address)",createsProxy:false,variants:["DeployFixture:buildCuts(address)"],inputs:[param("entryPoint";"address")],bindings:["buildFactory(entryPoint)"],conditions:[]}]
elif $mode=="inherited" then
  replacerecipe("DeployDerivedFixture";"script/base/fixtures/DeployDerivedFixture.s.sol";[fn("buildCuts";[field("admin";"address")];singleoutputs;"nonpayable"),fn("buildCutsWithENS";[field("admin";"address"),field("ensName";"string")];singleoutputs;"nonpayable"),fn("run";[field("admin";"address")];[field("diamond";"address")];"nonpayable"),fn("run";[field("admin";"address"),field("ensName";"string")];[field("diamond";"address")];"nonpayable"),specmethod]) |
  .catalog.recipes[0].variants=[(fixturevariant($root)|.id="DeployDerivedFixture:base"),(fixturevariant($root)|.id="DeployDerivedFixture:ens"|.buildSignature="buildCutsWithENS(address,string)"|.inputs=[param("admin";"address"),param("ensName";"string")])] |
  .catalog.recipes[0].deploymentContexts=[(fixturecontext("DeployDerivedFixture:base")|.id="DeployDerivedFixture:run(address)"),(fixturecontext("DeployDerivedFixture:ens")|.id="DeployDerivedFixture:run(address,string)"|.signature="run(address,string)"|.inputs=[param("admin";"address"),param("ensName";"string")]|.bindings=["buildCutsWithENS(admin,ensName)"])] |
  .artifacts += [artifact("script/base/fixtures/FixtureDemo.s.sol";"FixtureDemo";ordinaryABI([field("admin";"address")];singleoutputs)),(artifact("script/base/fixtures/FixtureBase.s.sol";"FixtureBase";ordinaryABI([field("admin";"address")];singleoutputs))|.content.ast.nodes[0].abstract=true)] |
  .catalog.excludedContexts=[{name:"FixtureDemo",source:"script/base/fixtures/FixtureDemo.s.sol",canonicalParent:"DeployDerivedFixture",disposition:"excluded fixture-only inherited demo"}] | .catalog.abstractHelpers=["script/base/fixtures/FixtureBase.s.sol"]
elif $mode=="profiles" then
  [structure("config";"FixtureConfig";"";[field("owner";"address"),field("temporaryApproval";"bool")])] as $inputs |
  [param("config.owner";"address"),param("config.temporaryApproval";"bool")] as $flat |
  replacerecipe("DeployERC3643";"script/base/fixtures/DeployERC3643.s.sol";ordinaryABI($inputs;singleoutputs)) |
  .catalog.recipes[0].variants=[(fixturevariant($root)|.id="DeployERC3643:temporaryApproval=false"|.buildSignature="buildCuts((address,bool))"|.inputs=$flat|.inputs[1].example="false"|.initPlan[0].bindings=["config.owner"]|.conditions=["profile: config.temporaryApproval=false"]),(fixturevariant($root)|.id="DeployERC3643:temporaryApproval=true"|.buildSignature="buildCuts((address,bool))"|.inputs=$flat|.inputs[1].example="true"|.initPlan[0].bindings=["config.owner"]|.facets += [{name:"ERC20TemporaryApproval",action:0,selection:0,selectors:[]}]|.conditions=["profile: config.temporaryApproval=true"])] |
  .catalog.recipes[0].deploymentContexts=[(fixturecontext("DeployERC3643:temporaryApproval=false")|.id="DeployERC3643:run((address,bool))"|.signature="run((address,bool))"|.inputs=$flat|.variants=["DeployERC3643:temporaryApproval=false","DeployERC3643:temporaryApproval=true"]|.bindings=["buildCuts(config)"])]
else error("unknown fixture corpus") end
JQ
for mode in basic nested parallel tuple tuple-array account inherited profiles; do
    corpus=$temporary/corpora/$mode
    mkdir -p "$corpus/artifacts"
    jq -n --arg max "$maximum" --arg mode "$mode" -f "$temporary/fixture.jq" > "$temporary/bundle.json"
    jq '.catalog' "$temporary/bundle.json" > "$corpus/catalog.json"
    while IFS= read -r record; do
        relative=$(jq -r '.path' <<< "$record")
        mkdir -p "$corpus/artifacts/$(dirname "$relative")"
        jq '.content' <<< "$record" > "$corpus/artifacts/$relative"
    done < <(jq -c '.artifacts[]' "$temporary/bundle.json")
    description=$(jq -er -f script/recipes/type-description.jq "$corpus/artifacts/RecipeSpec.sol/IRecipeSpec.json")
    jq --arg description "$description" '.typeDescription=$description' "$corpus/catalog.json" > "$corpus/next.json"
    mv "$corpus/next.json" "$corpus/catalog.json"
    printf 'unrelated input must remain intact\n' > "$corpus/preserve.txt"
done
passed=0 positive=0 negative=0
reset() {
    chmod -R u+w "$temporary/work" "$temporary/snapshot" 2>/dev/null || true
    rm -rf "$temporary/work" "$temporary/snapshot"
    cp -R "$temporary/corpora/$1" "$temporary/work"
    work=$temporary/work
}
mutate_catalog() { jq "$1" "$work/catalog.json" > "$work/next.json"; mv "$work/next.json" "$work/catalog.json"; }
mutate_artifact() { jq "$2" "$work/artifacts/$1" > "$work/next.json"; mv "$work/next.json" "$work/artifacts/$1"; }
check() {
    local label=$1 wanted=$2 diagnostic=${3:-} cli=${4:-explicit} actual output
    local -a command=(bash "$checker" "$work/catalog.json" "$work/artifacts")
    if [ "$cli" = default ]; then
        command=(bash "$work/script/recipes/check-catalog.sh" "$work/catalog.json")
    elif [ "$cli" = spaces ]; then
        command=(bash "$checker" "$work/catalog with spaces.json" "$work/compiled artifacts")
    fi
    cp -R "$work" "$temporary/snapshot"
    chmod -R a-w "$work"
    if TMPDIR="$temporary/checker-temp" "${command[@]}" > "$temporary/last-output.log" 2>&1; then actual=pass; else actual=fail; fi
    chmod -R u+w "$work"
    diff -r "$temporary/snapshot" "$work" >/dev/null || { echo "catalog fixtures: checker mutated input: $label" >&2; exit 1; }
    diff -r "$temporary/checker-temp-expected" "$temporary/checker-temp" >/dev/null || { echo "catalog fixtures: checker changed caller temp files or leaked its own: $label" >&2; exit 1; }
    if [ "$actual" != "$wanted" ]; then
        echo "catalog fixtures: $label: expected $wanted, got $actual" >&2
        cat "$temporary/last-output.log" >&2
        exit 1
    fi
    output=$(cat "$temporary/last-output.log")
    if [ -n "$diagnostic" ] && [[ "$output" != *"$diagnostic"* ]]; then
        echo "catalog fixtures: $label: wrong failure boundary (expected $diagnostic)" >&2
        cat "$temporary/last-output.log" >&2
        exit 1
    fi
    passed=$((passed + 1))
    if [ "$wanted" = pass ]; then positive=$((positive + 1)); else negative=$((negative + 1)); fi
}
good() { reset "$1"; check "$2" pass; }
bad_catalog() { local label=$1 mode=$2 filter=$3 diagnostic=${4:-}; reset "$mode"; mutate_catalog "$filter"; check "$label" fail "$diagnostic"; }
bad_artifact() { local label=$1 mode=$2 relative=$3 filter=$4 diagnostic=${5:-}; reset "$mode"; mutate_artifact "$relative" "$filter"; check "$label" fail "$diagnostic"; }

# Genuine positive controls exercise each nontrivial schema/ABI branch.
for mode in basic nested parallel tuple tuple-array account inherited profiles; do good "$mode" "valid $mode corpus"; done
reset basic
mutate_catalog '.recipes[0].variants[0].initPlan[0].bindings=["config.owner ?? callerChoice(msg.sender)"] | .recipes[0].deploymentContexts[0].bindings=["descriptive only: choose the reviewed factory and arguments"]'
check 'bindings remain uninterpreted descriptions' pass
reset basic
mutate_artifact DeployFixture.s.sol/DeployFixture.json '(.abi[]|select(.name=="recipeSpec")|.outputs[0].name)="anotherReturnVariable"'
check 'only outer recipeSpec return-variable name may differ' pass
reset basic
mutate_artifact FixtureInit.sol/FixtureInit.json 'del(.metadata)'
check 'initializer artifact AST absolutePath fallback' pass
[ "$(jq -r '.recipes[0].variants[0].initPlan[0].parent' "$work/catalog.json")" = "$maximum" ] || { echo 'catalog fixtures: uint256 maximum changed' >&2; exit 1; }
reset basic
mutate_catalog '.recipes[0].variants[0].facets[0] |= (.selection=2|.selectors=["0x5c36b186"])'
check 'valid Only subset' pass
reset basic
mutate_catalog '.recipes[0].variants[0].facets[0] |= (.selection=1|.selectors=["0x5c36b186"])'
check 'valid Except subset' pass
reset basic
mutate_catalog '.initializerArtifacts[0]="src/fixtures/FixtureInit.sol:FixtureInit" | .facetArtifacts[0]="src/fixtures/FixtureFacet.sol:FixtureFacet"'
check 'full source FQNs match compiler targets; basename aliases remain valid' pass
reset basic
mutate_artifact FixtureFacet.sol/FixtureFacet.json '.abi += [{type:"receive",stateMutability:"payable"}]'
mutate_catalog '.recipes[0].variants[0].facets[0] |= (.selection=2|.selectors=["0x00000000"])'
check 'zero selector requires a genuine receive ABI' pass
reset basic
mutate_catalog '.recipes[0].variants[0].facets += [{name:"OtherFacet",action:0,selection:0,selectors:[]}] | .recipes[0].variants[0].seams=[{id:"fixture-ping",selector:"0x5c36b186",participants:["FixtureFacet","OtherFacet"],allowedOwners:["FixtureFacet"],allowUnrouted:false,reason:"fixed fixture owner"}]'
check 'valid seam metadata' pass
reset basic
mkdir -p "$work/script/recipes"
cp "$checker" "$work/script/recipes/check-catalog.sh"
cp script/recipes/type-description.jq "$work/script/recipes/type-description.jq"
mv "$work/artifacts" "$work/out"
check 'default artifact root uses isolated out only' pass '' default
reset basic
mv "$work/catalog.json" "$work/catalog with spaces.json"
mv "$work/artifacts" "$work/compiled artifacts"
check 'quoted catalog and artifact paths' pass '' spaces

# Envelope, inventories, provenance and dangling references.
bad_catalog 'malformed envelope' basic 'del(.accountProfiles)' 'invalid catalog envelope'
bad_catalog 'wrong schema version' basic '.schemaVersion=2' 'invalid catalog envelope'
bad_catalog 'wrong compiler type description' basic '.typeDescription="incorrect-schema"' 'compiler type description or canonical version differs'
bad_catalog 'noncanonical lattice version' basic '.latticeVersion="v99.0.0-fixture"' 'compiler type description or canonical version differs'
bad_catalog 'leading-zero version is noncanonical' basic '.latticeVersion="099.0.0"' 'compiler type description or canonical version differs'
bad_catalog 'missing provenance' basic 'del(.sourceCommit)' 'invalid provenance/schema metadata'
bad_catalog 'invalid source commit' basic '.sourceCommit="unfrozen"' 'invalid provenance/schema metadata'
bad_catalog 'nonboolean dirty flag' basic '.sourceDirty="false"' 'invalid provenance/schema metadata'
bad_catalog 'inventory lengths differ' basic '.facetArtifacts|=.[0:1]' 'invalid facet/initializer inventory'
bad_catalog 'duplicate inventory names' basic '.facetNames[1]=.facetNames[0]' 'invalid facet/initializer inventory'
bad_catalog 'coordinated facet label rename is not an artifact alias' basic '.facetNames[0]="RenamedFacet" | .recipes[0].variants[0].facets[0].name="RenamedFacet"' 'facet inventory name differs from artifact contract'
bad_catalog 'coordinated initializer label rename is not an artifact alias' basic '.initializerNames[0]="RenamedInit" | .recipes[0].variants[0].initPlan[0].name="RenamedInit"' 'initializer inventory name differs from artifact contract'
bad_catalog 'unknown facet' basic '.recipes[0].variants[0].facets[0].name="UnknownFacet"' 'unknown facet'
bad_catalog 'unknown initializer' basic '.recipes[0].variants[0].initPlan[0].name="UnknownInit"' 'unknown initializer'
bad_catalog 'same basename initializer FQN with wrong source' basic '.initializerArtifacts[0]="not-real/FixtureInit.sol:FixtureInit"' 'artifact source path differs'
bad_catalog 'FQN third colon is malformed' basic '.initializerArtifacts[0]="FixtureInit.sol:FixtureInit:Ignored"' 'invalid artifact name'
bad_catalog 'FQN contract must not be empty' basic '.initializerArtifacts[0]="FixtureInit.sol:"' 'invalid artifact name'
bad_catalog 'FQN source must end in sol suffix' basic '.initializerArtifacts[0]="FixtureInit:FixtureInit"' 'invalid artifact name'
bad_catalog 'duplicate recipe ID' basic '.recipes += [.recipes[0]]' 'duplicate recipe name/source'
bad_catalog 'duplicate variant ID' profiles '.recipes[0].variants[1].id=.recipes[0].variants[0].id' 'missing/duplicate variants'
bad_catalog 'duplicate context ID' basic '.recipes[0].deploymentContexts += [.recipes[0].deploymentContexts[0]]' 'invalid deployment contexts'
bad_catalog 'duplicate context variant references' basic '.recipes[0].deploymentContexts[0].variants += [.recipes[0].deploymentContexts[0].variants[0]]' 'dangling or incomplete deployment context'
bad_catalog 'dangling context variant' basic '.recipes[0].deploymentContexts[0].variants=["missing-variant"]' 'dangling or incomplete deployment context'
bad_catalog 'profile has no context' profiles '.recipes[0].deploymentContexts[0].variants|=.[0:1]' 'variant has no deployment context'
bad_catalog 'missing context ABI' basic '.recipes[0].deploymentContexts=[]' 'deployment ABI coverage differs'
bad_catalog 'context binding count empty' basic '.recipes[0].deploymentContexts[0].bindings=[]' 'dangling or incomplete deployment context'
bad_catalog 'missing variant units' basic 'del(.recipes[0].variants[0].inputs[0].unit)' 'incomplete parameter metadata'
bad_catalog 'missing leaf examples' basic 'del(.recipes[0].variants[0].initPlan[0].parameters[0].example)' 'incomplete parameter metadata'
bad_catalog 'missing context rules' basic '.recipes[0].deploymentContexts[0].inputs[0].rule=""' 'incomplete parameter metadata'
bad_catalog 'initializer binding count differs' basic '.recipes[0].variants[0].initPlan[0].bindings=[]' 'initializer bindings differ'
bad_catalog 'constructor binding count differs' account '.recipes[0].variants[0].initPlan[0].constructorBindings=[]' 'constructor bindings differ'

# Native builder/run/initializer/constructor/schema ABI checks.
bad_catalog 'builder signature mismatch' basic '.recipes[0].variants[0].buildSignature="buildCuts(uint256)"' 'builder ABI coverage differs'
bad_catalog 'builder input name mismatch' basic '.recipes[0].variants[0].inputs[0].name="owner"' 'ABI parameter names/types differ'
bad_catalog 'builder input type mismatch' basic '.recipes[0].variants[0].inputs[0].abiType="uint256"' 'ABI parameter names/types differ'
bad_catalog 'initializer signature mismatch' basic '.recipes[0].variants[0].initPlan[0].signature="init(uint256)"' 'missing or ambiguous ABI'
bad_catalog 'initializer input name mismatch' basic '.recipes[0].variants[0].initPlan[0].parameters[0].name="admin_"' 'ABI parameter names/types differ'
bad_catalog 'run signature mismatch' basic '.recipes[0].deploymentContexts[0].signature="run(uint256)"' 'deployment ABI coverage differs'
bad_catalog 'factory owner name mismatch' account '.recipes[0].deploymentContexts[0].inputs[1].name="admin"' 'ABI parameter names/types differ'
bad_catalog 'factory salt type mismatch' account '.recipes[0].deploymentContexts[0].inputs[2].abiType="uint256"' 'ABI parameter names/types differ'
bad_catalog 'constructor parameter name mismatch' account '.recipes[0].variants[0].initPlan[0].constructorParameters[0].name="entryPoint"' 'ABI parameter names/types differ'
bad_catalog 'constructor parameter type mismatch' account '.recipes[0].variants[0].initPlan[0].constructorParameters[0].abiType="bytes32"' 'ABI parameter names/types differ'
bad_catalog 'account release label is not artifact contract' account '.recipes[0].variants[0].initPlan[0].name="AccountInitV07"' 'unknown initializer'
bad_catalog 'account constructor flag mismatch' account '.recipes[0].variants[0].initPlan[0].constructorBound=false' 'constructor-bound flag differs'
bad_catalog 'account profile family mismatch' account '.accountProfiles[0].modular=true' 'account profile artifact/family association differs'
bad_catalog 'factory context must not create proxy' account '.recipes[0].deploymentContexts[1].createsProxy=true' 'deployment/factory kind differs'
bad_catalog 'run context must create proxy' account '.recipes[0].deploymentContexts[0].createsProxy=false' 'deployment/factory kind differs'
bad_artifact 'class recipeSpec must be pure' basic DeployFixture.s.sol/DeployFixture.json '(.abi[]|select(.name=="recipeSpec")|.stateMutability)="view"' 'pure recipeSpec output ABI differs'
bad_artifact 'missing recipeSpec' basic DeployFixture.s.sol/DeployFixture.json '.abi|=map(select(.name!="recipeSpec"))' 'pure recipeSpec output ABI differs'
bad_artifact 'recipeSpec component schema mismatch' basic DeployFixture.s.sol/DeployFixture.json '(.abi[]|select(.name=="recipeSpec")|.outputs[0].components[0].name)="wrong"' 'pure recipeSpec output ABI differs'
bad_artifact 'recipeSpec output type mismatch' basic DeployFixture.s.sol/DeployFixture.json '(.abi[]|select(.name=="recipeSpec")|.outputs[0].type)="tuple[]"' 'pure recipeSpec output ABI differs'
bad_artifact 'schema interface must be pure' basic RecipeSpec.sol/IRecipeSpec.json '(.abi[]|.stateMutability)="view"' 'recipeSpec'
bad_artifact 'ambiguous recipeSpec method' basic DeployFixture.s.sol/DeployFixture.json '.abi += [.abi[]|select(.name=="recipeSpec")]' 'pure recipeSpec output ABI differs'

# Exact tuple flattening and tree topology, including lossless uint256 root representation.
bad_catalog 'tuple dotted name mismatch' tuple '.recipes[0].variants[0].inputs[1].name="config.cap"' 'ABI parameter names/types differ'
bad_catalog 'tuple nested array type mismatch' tuple-array '.recipes[0].variants[0].inputs[1].abiType="uint256[]"' 'ABI parameter names/types differ'
bad_catalog 'numeric maximum root is lossy' basic '.recipes[0].variants[0].initPlan[0].parent|=tonumber' 'missing initializer root'
bad_catalog 'wrong root value' basic '.recipes[0].variants[0].initPlan[0].parent="0"' 'missing initializer root'
bad_catalog 'forward parent' nested '.recipes[0].variants[0].initPlan[1].parent=2' 'initializer parent is not preorder'
bad_catalog 'negative parent' nested '.recipes[0].variants[0].initPlan[1].parent=-1' 'initializer parent is not preorder'
bad_catalog 'fractional parent' nested '.recipes[0].variants[0].initPlan[2].parent=1.5' 'initializer parent is not preorder'
bad_catalog 'ordinary parent must be numeric' nested '.recipes[0].variants[0].initPlan[2].parent="1"' 'initializer parent is not preorder'
bad_catalog 'second root' nested '.recipes[0].variants[0].initPlan[1].parent=.recipes[0].variants[0].initPlan[0].parent' 'initializer parent is not preorder'
bad_catalog 'non-MultiInit parent' nested '.recipes[0].variants[0].initPlan[3].parent=2' 'initializer tree is not depth-first MultiInit preorder'
bad_catalog 'closed subtree reopened' nested '.recipes[0].variants[0].initPlan += [(.recipes[0].variants[0].initPlan[2]|.parent=1)]' 'initializer tree is not depth-first MultiInit preorder'
bad_catalog 'wrong parallel output shape' parallel '.recipes[0].variants[0].initOutputKind=0' 'initializer/proxy output shape differs'
bad_catalog 'wrong ordinary proxy family' basic '.recipes[0].variants[0].proxyKind=1' 'initializer/proxy output shape differs'
bad_catalog 'invalid proxy enum' basic '.recipes[0].variants[0].proxyKind=3' 'invalid variant'
bad_catalog 'proxy enum must be numeric' basic '.recipes[0].variants[0].proxyKind="0"' 'invalid variant'
bad_catalog 'invalid output enum' basic '.recipes[0].variants[0].initOutputKind=9' 'invalid variant'

# Selector/seam/authority shape and case-normalized uniqueness.
bad_catalog 'Remove action is unsupported' basic '.recipes[0].variants[0].facets[0].action=2' 'invalid selector declaration'
bad_catalog 'invalid selection enum' basic '.recipes[0].variants[0].facets[0].selection=9' 'invalid selector declaration'
bad_catalog 'All must not list selectors' basic '.recipes[0].variants[0].facets[0].selectors=["0x12345678"]' 'invalid selector declaration'
bad_catalog 'Only must list selectors' basic '.recipes[0].variants[0].facets[0].selection=2' 'invalid selector declaration'
bad_catalog 'malformed selector' basic '.recipes[0].variants[0].facets[0] |= (.selection=2|.selectors=["0x123"])' 'invalid selector declaration'
bad_catalog 'exportSelectors must not be routed' basic '.recipes[0].variants[0].facets[0] |= (.selection=2|.selectors=["0x0ef22643"])' 'invalid selector declaration'
bad_catalog 'Only selector absent from compiler ABI' basic '.recipes[0].variants[0].facets[0] |= (.selection=2|.selectors=["0x12345678"])' 'selector missing from facet ABI'
bad_catalog 'Except selector absent from compiler ABI' basic '.recipes[0].variants[0].facets[0] |= (.selection=1|.selectors=["0x12345678"])' 'selector missing from facet ABI'
bad_catalog 'zero selector without fallback or receive' basic '.recipes[0].variants[0].facets[0] |= (.selection=2|.selectors=["0x00000000"])' 'selector missing from facet ABI'
bad_catalog 'mixed-case duplicate selectors' basic '.recipes[0].variants[0].facets[0] |= (.selection=2|.selectors=["0xaAbBcCdD","0xAABBCCDD"])' 'invalid selector declaration'
bad_catalog 'unknown seam participant' basic '.recipes[0].variants[0].seams=[{id:"fixture",selector:"0x12345678",participants:["FixtureFacet","UnknownFacet"],allowedOwners:["FixtureFacet"],allowUnrouted:false,reason:"fixture"}]' 'unknown seam facet'
bad_catalog 'unknown seam owner' basic '.recipes[0].variants[0].seams=[{id:"fixture",selector:"0x12345678",participants:["FixtureFacet","OtherFacet"],allowedOwners:["UnknownFacet"],allowUnrouted:false,reason:"fixture"}]' 'unknown seam facet'
bad_catalog 'duplicate seam IDs' basic '.recipes[0].variants[0].seams=[{id:"fixture",selector:"0x12345678",participants:["FixtureFacet","OtherFacet"],allowedOwners:["FixtureFacet"],allowUnrouted:false,reason:"fixture"}] | .recipes[0].variants[0].seams += [.recipes[0].variants[0].seams[0]]' 'invalid seam IDs'
bad_catalog 'missing required facet metadata array' basic 'del(.initializerArtifacts)' 'invalid catalog envelope'
bad_catalog 'invalid authority metadata' basic '.recipes[0].variants[0].authorities=[{kind:7,module:"FixtureFacet",role:"fixture",roleType:"bytes32",roleId:("0x"+("0"*64)),grantee:"admin",reason:"fixture"}]' 'incomplete authorities'

# Complete compiler census, inherited ABIs, exclusions and explicit same-ABI ERC3643 profiles.
reset basic
rm "$work/artifacts/DeployFixture.s.sol/DeployFixture.json"
check 'missing canonical compiler builder' fail 'canonical compiler builder census differs'
reset basic
mkdir -p "$work/artifacts/ExtraFixture.s.sol"
jq '.metadata.settings.compilationTarget={"script/base/fixtures/ExtraFixture.s.sol":"ExtraFixture"}|.ast.absolutePath="script/base/fixtures/ExtraFixture.s.sol"|.ast.nodes[0].name="ExtraFixture"' "$work/artifacts/DeployFixture.s.sol/DeployFixture.json" > "$work/artifacts/ExtraFixture.s.sol/ExtraFixture.json"
check 'extra canonical compiler builder' fail 'canonical compiler builder census differs'
bad_catalog 'inherited builder omitted' inherited '.recipes[0].variants|=.[1:]' 'builder ABI coverage differs'
bad_catalog 'excluded demo parent must exist' inherited '.excludedContexts[0].canonicalParent="UnknownParent"' 'invalid excluded demo context'
bad_catalog 'unknown excluded demo' inherited '.excludedContexts[0].name="UnknownDemo"' 'invalid excluded demo context'
bad_catalog 'duplicate excluded demo' inherited '.excludedContexts += [.excludedContexts[0]]' 'duplicate account/demo/helper metadata'
bad_catalog 'unknown abstract helper source' inherited '.abstractHelpers=["script/base/fixtures/Missing.s.sol"]' 'compiler-proven abstract'
bad_artifact 'concrete helper spoof' inherited FixtureBase.s.sol/FixtureBase.json '.ast.nodes[0].abstract=false' 'compiler-proven abstract'
bad_artifact 'wrong AST contract cannot prove helper abstract' inherited FixtureBase.s.sol/FixtureBase.json '.ast.nodes[0].name="DifferentContract"' 'compiler-proven abstract'
reset inherited
jq '.metadata.settings.compilationTarget={"script/base/fixtures/FixtureBase.s.sol":"ConcreteHelper"}|.ast.nodes[0].abstract=false|.ast.nodes[0].name="ConcreteHelper"' "$work/artifacts/FixtureBase.s.sol/FixtureBase.json" > "$work/artifacts/FixtureBase.s.sol/ConcreteHelper.json"
check 'concrete builder alongside abstract helper is still canonical' fail 'canonical compiler builder census differs'
bad_catalog 'ERC3643 profiles must differ in cuts' profiles '.recipes[0].variants[1].facets=.recipes[0].variants[0].facets' 'duplicate builder ABI requires explicit ERC3643 profiles'
bad_catalog 'ERC3643 profiles must be explicit' profiles '.recipes[0].variants[1].conditions=[]' 'duplicate builder ABI requires explicit ERC3643 profiles'
reset basic
mutate_catalog '.recipes[0].variants += [(.recipes[0].variants[0]|.id="alternate"|.conditions=["not ERC3643"]|.facets += [{name:"OtherFacet",action:0,selection:0,selectors:[]}])]'
check 'other recipes cannot duplicate one builder ABI' fail 'duplicate builder ABI requires explicit ERC3643 profiles'
reset basic
rm "$work/artifacts/FixtureFacet.sol/FixtureFacet.json"
check 'missing facet compiler artifact' fail 'missing compiler artifact'
reset basic
rm "$work/artifacts/FixtureInit.sol/FixtureInit.json"
check 'missing initializer compiler artifact' fail 'missing compiler artifact'
reset basic
printf '{' > "$work/artifacts/FixtureInit.sol/FixtureInit.json"
check 'malformed compiler artifact fails closed' fail
reset basic
printf '{' > "$work/catalog.json"
check 'malformed JSON fails closed' fail
reset basic
printf '\n{}\n' >> "$work/catalog.json"
check 'multiple JSON documents fail closed' fail 'invalid catalog envelope'
printf 'catalog fixtures: %s passed (%s positive, %s negative); read-only inputs and own-temp cleanup checked\n' "$passed" "$positive" "$negative"
