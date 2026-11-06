#!/usr/bin/env bash
# Validate native recipe data against the compiler ABI; bindings remain descriptions, never expressions.
set -euo pipefail
cd "$(dirname "$0")/../.."
fail() { echo "recipe-catalog: $*" >&2; exit 1; }
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || fail 'usage: check-catalog.sh <catalog.json> [artifact-root=out]'
catalog=$1 artifact_root=${2:-out}
[ -f "$catalog" ] && [ -d "$artifact_root" ] || fail 'catalog file and compiler artifact directory are required'
jq -e -s 'length==1 and (.[0]|type)=="object" and (.[0] |
  .schemaVersion==1 and (.recipes|type)=="array" and (.recipes|length)>0 and
  (.facetNames|type)=="array" and (.facetArtifacts|type)=="array" and
  (.initializerNames|type)=="array" and (.initializerArtifacts|type)=="array" and
  (.accountProfiles|type)=="array" and (.excludedContexts|type)=="array" and (.abstractHelpers|type)=="array")' "$catalog" >/dev/null || fail 'invalid catalog envelope'
interface=$artifact_root/RecipeSpec.sol/IRecipeSpec.json
[ -f "$interface" ] || fail 'missing IRecipeSpec compiler ABI'
type_description=$(jq -erf script/recipes/type-description.jq "$interface")
jq -e --arg description "$type_description" '.typeDescription==$description and (.latticeVersion|test("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"))' "$catalog" >/dev/null || fail 'compiler type description or canonical version differs'
temporary=$(mktemp -d "${TMPDIR:-/tmp}/lattice-recipe-catalog.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
shopt -s nullglob
artifacts=("$artifact_root"/*.sol/*.json)
[ "${#artifacts[@]}" -gt 0 ] || fail 'no compiler contract artifacts found'
# Stream large bytecode artifacts one at a time; retain only the ABIs needed by this catalog and source census.
jq -c --slurpfile catalog "$catalog" '
  ($catalog[0] | [.facetArtifacts[],.initializerArtifacts[],"RecipeSpec.sol:IRecipeSpec",
    (.accountProfiles[] | .initializerArtifact,.proxyArtifact,.factoryArtifact)] |
    map(split(":") as $p | ($p[0]|split("/")|last)+":"+$p[1])) as $needed |
  (input_filename|split("/")) as $path |
  ($path[-2]+":"+($path[-1]|sub("\\.json$";""))) as $key |
  ((.metadata.settings.compilationTarget // {} | keys[0]) // .ast.absolutePath // "") as $source |
  select(($source|startswith("script/base/")) or ($needed|index($key))) |
  ($path[-1]|sub("\\.json$";"")) as $contract |
  ([.ast.nodes[]?|select(.nodeType=="ContractDefinition" and .name==$contract)][0] // {}) as $definition |
  {key:$key,source:$source,contract:$contract,abstract:($definition.abstract // false),kind:($definition.contractKind // ""),abi:.abi,methods:(.methodIdentifiers // {})}
' "${artifacts[@]}" > "$temporary/artifacts.jsonl"
cat > "$temporary/check.jq" <<'JQ'
($A|INDEX(.key)) as $db |
($C[0]) as $c |
"115792089237316195423570985008687907853269984665640564039457584007913129639935" as $max |
def namedmap($names;$files): reduce range(0;$names|length) as $i ({};.[$names[$i]]=$files[$i]);
namedmap($c.facetNames;$c.facetArtifacts) as $facetmap |
(namedmap($c.initializerNames;$c.initializerArtifacts) | reduce $c.accountProfiles[] as $p (. ; .[$p.initializerArtifact|split(":")|last]=$p.initializerArtifact)) as $initmap |
def req($ok;$message): if $ok then true else error("recipe-catalog: "+$message) end;
def text: type=="string" and length>0;
def fqnkey: . as $fqn | split(":") as $p |
  if ($p|length)==2 and ($p[0]|endswith(".sol")) and ($p[1]|test("^[A-Za-z_$][A-Za-z0-9_$]*$"))
  then ($p[0]|split("/")|last)+":"+$p[1] else error("recipe-catalog: invalid artifact name "+$fqn) end;
def artifact($fqn):
  ($db[($fqn|fqnkey)] // error("recipe-catalog: missing compiler artifact "+$fqn)) as $a |
  ($fqn|split(":")[0]) as $source |
  if ($source|contains("/")) and $a.source!=$source then error("recipe-catalog: artifact source path differs "+$fqn) else $a end;
def atype: if (.type|startswith("tuple")) then "("+(.components|map(atype)|join(","))+")"+(.type|ltrimstr("tuple")) else .type end;
def signature: .name+"("+(.inputs|map(atype)|join(","))+")";
def leaves($prefix;$suffix): .[] | . as $p |
  (if $prefix=="" then $p.name else $prefix+"."+$p.name end) as $name |
  if ($p.type|startswith("tuple")) then $p.components|leaves($name;($p.type|ltrimstr("tuple"))+$suffix)
  else {name:$name,abiType:($p.type+$suffix)} end;
def parameters($data;$abi;$where):
  req(($data|type)=="array" and all($data[]; (.name|text) and (.abiType|text) and (.unit|text) and (.example|text) and (.rule|text));$where+": incomplete parameter metadata") and
  req([$data[]|{name,abiType}]==[$abi|leaves("";"")];$where+": ABI parameter names/types differ");
def strings($data): ($data|type)=="array" and all($data[];text);
def unique($data): ($data|unique|length)==($data|length);
def method($abi;$sig;$where): [$abi[]|select(.type=="function" and signature==$sig)] as $m |
  if ($m|length)==1 then $m[0] else error("recipe-catalog: "+$where+": missing or ambiguous ABI "+$sig) end;
def ctor($abi): [$abi[]|select(.type=="constructor")][0].inputs // [];
def specabi($a;$where):
  [artifact("RecipeSpec.sol:IRecipeSpec").abi[]|select(.type=="function" and .name=="recipeSpec" and .inputs==[])] as $schema |
  [$a.abi[]|select(.type=="function" and .name=="recipeSpec" and .inputs==[])] as $methods |
  req(($schema|length)==1 and $schema[0].stateMutability=="pure" and ($schema[0].outputs|length)==1 and $schema[0].outputs[0].type=="tuple" and
    ($methods|length)==1 and $methods[0].stateMutability=="pure" and ($methods[0].outputs|length)==1 and
    ($methods[0].outputs[0]|del(.name))==($schema[0].outputs[0]|del(.name));$where+": pure recipeSpec output ABI differs");
def initstep($step;$where):
  req(($step.name|text) and ($step.signature|text) and ($step.constructorBound|type)=="boolean";$where+": invalid initializer node") and
  req($initmap[$step.name]!=null;$where+": unknown initializer "+$step.name) and
  (artifact($initmap[$step.name]) as $a | method($a.abi;$step.signature;$where) as $m |
    parameters($step.parameters;$m.inputs;$where+" "+$step.name) and
    req(strings($step.bindings) and ($step.bindings|length)==($step.parameters|length);$where+": initializer bindings differ") and
    parameters($step.constructorParameters;ctor($a.abi);$where+" constructor "+$step.name) and
    req(strings($step.constructorBindings) and ($step.constructorBindings|length)==($step.constructorParameters|length);$where+": constructor bindings differ") and
    req($step.constructorBound==((ctor($a.abi)|length)>0);$where+": constructor-bound flag differs"));
def ancestors($steps;$index): [$index] + (if $steps[$index].parent==$max then [] else ancestors($steps;$steps[$index].parent) end);
def variant($v;$r;$a):
  ($r.name+" "+$v.id) as $where |
  req(($v.id|text) and ($v.buildSignature|text) and ($v.proxyKind|IN(0,1,2)) and ($v.initOutputKind|IN(0,1,2));$where+": invalid variant") and
  (method($a.abi;$v.buildSignature;$where) as $m |
    req($m.name=="buildCuts" or $m.name=="buildCutsWithENS";$where+": unexpected builder") and
    req(if $v.proxyKind==0 and $v.initOutputKind==0 then [$m.outputs[].type]==["tuple[]","address","bytes"]
      elif $v.proxyKind==0 and $v.initOutputKind==1 then [$m.outputs[].type]==["tuple[]","address[]","bytes[]"] and $v.initPlan[0].name=="MultiInit"
      else $v.proxyKind!=0 and $v.initOutputKind==2 and [$m.outputs[].type]==["tuple[]","address"] and ($v.initPlan|length)==1 end;$where+": initializer/proxy output shape differs") and
    parameters($v.inputs;$m.inputs;$where)) and
  req(($v.facets|type)=="array" and ($v.facets|length)>0;$where+": empty facets") and
  all($v.facets[]; . as $f |
    req($facetmap[$f.name]!=null;$where+": unknown facet "+$f.name) and
    req(($f.action|IN(0,1)) and ($f.selection|IN(0,1,2)) and ($f.selectors|type)=="array" and unique($f.selectors|map(ascii_downcase)) and
      all($f.selectors[];type=="string" and test("^0x[0-9a-fA-F]{8}$") and ascii_downcase!="0x0ef22643") and
      (if $f.selection==0 then ($f.selectors|length)==0 else ($f.selectors|length)>0 end);$where+": invalid selector declaration") and
    (artifact($facetmap[$f.name]) as $a |
      req(all($f.selectors[];. as $selector | any($a.methods[];("0x"+ascii_downcase)==($selector|ascii_downcase)) or
        ($selector=="0x00000000" and any($a.abi[];.type=="fallback" or .type=="receive")));$where+": selector missing from facet ABI"))) and
  req(($v.seams|type)=="array" and unique([$v.seams[].id]);$where+": invalid seam IDs") and
  all($v.seams[]; . as $s |
    req(($s.id|text) and ($s.reason|text) and ($s.selector|type)=="string" and ($s.selector|test("^0x[0-9a-fA-F]{8}$")) and
      strings($s.participants) and ($s.participants|length)>=2 and unique($s.participants) and strings($s.allowedOwners) and unique($s.allowedOwners) and
      ($s.allowUnrouted|type)=="boolean" and (($s.allowedOwners|length)>0 or $s.allowUnrouted);$where+": invalid seam") and
    req(all(($s.participants+$s.allowedOwners)[];. as $name | $facetmap[$name]!=null);$where+": unknown seam facet")) and
  req(($v.initPlan|type)=="array" and ($v.initPlan|length)>0 and $v.initPlan[0].parent==$max;$where+": missing initializer root") and
  all(range($v.initPlan|length);. as $i | $v.initPlan[$i] as $step |
    req(if $i==0 then $step.parent==$max else ($step.parent|type)=="number" and $step.parent>=0 and $step.parent==($step.parent|floor) and $step.parent<$i end;$where+": initializer parent is not preorder") and
    req(if $i==0 then true else $v.initPlan[$step.parent].name=="MultiInit" and (ancestors($v.initPlan;$i-1)|index($step.parent))!=null end;$where+": initializer tree is not depth-first MultiInit preorder") and
    initstep($step;$where)) and
  req(($v.authorities|type)=="array" and all($v.authorities[];(.kind|IN(0,1,2)) and (.module|text) and (.role|text) and (.roleType|text) and (.roleId|type)=="string" and (.roleId|test("^0x[0-9a-fA-F]{64}$")) and (.grantee|text) and (.reason|text));$where+": incomplete authorities") and
  req(strings($v.conditions);$where+": invalid conditions") and
  req(if $v.proxyKind==0 then all($v.initPlan[];.constructorBound==false) else
    [$v.initPlan[]|select(.constructorBound)] as $bound | ($bound|length)==1 and
    any($c.accountProfiles[];(.initializerArtifact|split(":")|last)==$bound[0].name and .modular==($v.proxyKind==2)) end;$where+": account constructor/proxy family differs");
([$A[]|select((.source|startswith("script/base/")) and any(.abi[];.type=="function" and (.name=="buildCuts" or .name=="buildCutsWithENS"))) |
  . as $a | select((($c.abstractHelpers|index($a.source))==null or $a.abstract!=true) and (any($c.excludedContexts[];.source==$a.source and .name==$a.contract)|not)) | .source+":"+.contract]|sort) as $expected |
req(($c.sourceCommit|type)=="string" and ($c.sourceCommit|test("^[0-9a-f]{40}$")) and ($c.sourceDirty|type)=="boolean" and ($c.latticeVersion|text) and ($c.typeDescription|text);"invalid provenance/schema metadata") and
req(strings($c.facetNames) and strings($c.facetArtifacts) and ($c.facetNames|length)==($c.facetArtifacts|length) and unique($c.facetNames) and unique($c.facetArtifacts) and
  strings($c.initializerNames) and strings($c.initializerArtifacts) and ($c.initializerNames|length)==($c.initializerArtifacts|length) and unique($c.initializerNames) and unique($c.initializerArtifacts);"invalid facet/initializer inventory") and
all(($c.facetArtifacts+$c.initializerArtifacts)[];artifact(.)|true) and
all(range($c.facetNames|length);. as $i | req(artifact($c.facetArtifacts[$i]).contract==$c.facetNames[$i];"facet inventory name differs from artifact contract")) and
all(range($c.initializerNames|length);. as $i | req(artifact($c.initializerArtifacts[$i]).contract==$c.initializerNames[$i];"initializer inventory name differs from artifact contract")) and
req(unique([$c.recipes[].name]) and unique([$c.recipes[].source]);"duplicate recipe name/source") and
all($c.accountProfiles[];. as $p |
  req(($p.initializer|text) and ($p.initializerArtifact|text) and ($p.factory|text) and ($p.factoryArtifact|text) and ($p.proxyKind|text) and ($p.proxyArtifact|text) and ($p.entryPointVersion|text) and
    ($p.entryPoint|type)=="string" and ($p.entryPoint|test("^0x[0-9a-fA-F]{40}$")) and ($p.modular|type)=="boolean";"invalid account profile") and
  req((artifact($p.initializerArtifact)|.abi|ctor(.)|length)>0 and (artifact($p.factoryArtifact)|.abi|ctor(.)|length)>0 and artifact($p.proxyArtifact).contract==$p.proxyKind and $p.proxyKind==(if $p.modular then "ModularAccount6900" else "AccountDiamond" end);"account profile artifact/family association differs")) and
req(unique([$c.accountProfiles[].initializer]) and unique([$c.accountProfiles[].factory]) and unique([$c.accountProfiles[]|[.modular,.entryPointVersion]]) and unique([$c.excludedContexts[]|[.name,.source]]) and strings($c.abstractHelpers);"duplicate account/demo/helper metadata") and
all($c.excludedContexts[];. as $e | req(($e.name|text) and ($e.source|text) and ($e.disposition|text) and ($e.canonicalParent|type)=="string" and
  ($e.canonicalParent=="" or any($c.recipes[];.name==$e.canonicalParent)) and any($A[];.source==$e.source and .contract==$e.name);"invalid excluded demo context")) and
all($c.abstractHelpers[];. as $source | req(any($A[];.source==$source and .kind=="contract" and .abstract==true);"helper is not compiler-proven abstract "+$source)) and
req($expected==([$c.recipes[]|.source+":"+.name]|sort);"canonical compiler builder census differs from catalog") and
all($c.recipes[];. as $r |
  ($A|map(select(.source==$r.source and .contract==$r.name))) as $matches |
  ($matches[0]) as $a |
  req(($r.name|text) and ($r.source|text) and ($matches|length)==1;$r.name+": missing or ambiguous source ABI") and
  specabi($a;$r.name) and
  req(($r.variants|type)=="array" and ($r.variants|length)>0 and unique([$r.variants[].id]);$r.name+": missing/duplicate variants") and
  req(([$a.abi[]|select(.type=="function" and (.name=="buildCuts" or .name=="buildCutsWithENS"))|signature]|sort)==([$r.variants[].buildSignature]|unique|sort);$r.name+": builder ABI coverage differs") and
  all($r.variants|group_by(.buildSignature)[]; . as $group | req(($group|length)==1 or ($r.name=="DeployERC3643" and ($group|length)==2 and all($group[];(.conditions|length)>0) and ([$group[].facets]|unique|length)==2);$r.name+": duplicate builder ABI requires explicit ERC3643 profiles")) and
  all($r.variants[];variant(.;$r;$a)) and
  req(($r.deploymentContexts|type)=="array" and unique([$r.deploymentContexts[].id]);$r.name+": invalid deployment contexts") and
  req(([$a.abi[]|select(.type=="function" and (.name=="run" or .name=="buildFactory" or .name=="deployAtomic"))|signature]|sort)==([$r.deploymentContexts[].signature]|unique|sort);$r.name+": deployment ABI coverage differs") and
  all($r.deploymentContexts[];. as $context | method($a.abi;$context.signature;$r.name) as $m |
    req(($context.id|text) and ($context.createsProxy|type)=="boolean" and strings($context.variants) and ($context.variants|length)>0 and unique($context.variants) and
      all($context.variants[];. as $id | any($r.variants[];.id==$id)) and strings($context.bindings) and ($context.bindings|length)>0 and strings($context.conditions);$r.name+": dangling or incomplete deployment context") and
    req($context.createsProxy==($m.name!="buildFactory");$r.name+": deployment/factory kind differs") and
    parameters($context.inputs;$m.inputs;$r.name+" "+$context.signature)) and
  req(all($r.variants[];.id as $id | any($r.deploymentContexts[];.variants|index($id)));$r.name+": variant has no deployment context"))
JQ
jq -ne --slurpfile C "$catalog" --slurpfile A "$temporary/artifacts.jsonl" -f "$temporary/check.jq" >/dev/null || fail 'catalog/ABI validation failed'
echo "recipe-catalog: checked $(jq '.recipes|length' "$catalog") recipes against source, variant, context and initializer ABIs"
