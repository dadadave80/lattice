#!/usr/bin/env bash
# Reproduce a frozen manifest and resolve exact archived compiler inputs. No verifier submission.
set -euo pipefail
cd "$(dirname "$0")/../.."
unset ETHERSCAN_API_KEY VERIFIER_API_KEY
source script/release/chain-evidence.sh
fail() { echo "verification prepare: $*" >&2; exit 1; }
[ "$#" = 3 ] || [ "$#" = 5 ] || fail 'usage: prepare-verification.sh <release> <inputs> <stage> [chain-status rpc]'
release=$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")
inputs=$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")
mkdir -p "$3"
stage=$(cd "$3" && pwd -P)
root=$(pwd -P)
case "$stage" in "$root"|"$root"/*) fail 'stage outside the checkout to preserve the input witness' ;; esac
shopt -s nullglob dotglob
existing=("$stage"/*)
[ "${#existing[@]}" = 0 ] || fail 'use an empty stage directory'
shopt -u dotglob
./script/release/validate-manifest.sh "$release"
jq -e -s 'length==1 and (.[0]|type)=="array" and (.[0]|length)>0' "$inputs" >/dev/null || fail 'one compiler-input array required'
jq -cS . "$inputs" > "$stage/inputs.json"
expected=$(jq -r '.compiler.inputHash' "$release")
[ "$(tr -d '\n' < "$stage/inputs.json" | cast keccak)" = "$expected" ] || fail 'archived compiler-input hash differs'
version=$(jq -r '.compiler.solc' "$release")
jq -e --arg version "$version" 'all(.[];
    .solcVersion==$version and (.solcLongVersion|type)=="string" and
    .input.language=="Solidity" and (.input.sources|type)=="object" and (.input.sources|length)>0 and
    all(.input.sources[]; (.content|type)=="string") and
    .input.settings.evmVersion=="cancun" and .input.settings.optimizer=={enabled:true,runs:1000000} and
    .input.settings.viaIR==false and (.input.settings.libraries // {})=={} and
    .input.settings.metadata.bytecodeHash=="ipfs" and .input.settings.metadata.appendCBOR==true)
' "$stage/inputs.json" >/dev/null || fail 'unsupported or incomplete archived compiler settings'
source_commit=$(jq -r '.lattice.commit' "$release")
publication=$(jq -r '.publication' "$release")
git cat-file -e "$source_commit^{commit}"
if [ "$publication" = release ]; then
    ./script/release/source-boundary.sh "$source_commit"
    tag=$(jq -r '.lattice.tag' "$release")
    if git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
        git merge-base --is-ancestor "$source_commit" "$tag"
        git diff --quiet "$source_commit" "$tag" -- src script test/helpers/ArachnidProxy.sol lib foundry.toml foundry.lock remappings.txt .github/actions/foundry-setup/action.yml || fail 'tag differs from frozen source'
    fi
elif [ "$#" = 5 ]; then fail 'fixture material is offline only'; fi
checkout=$stage/source
[ ! -e "$checkout" ] || fail 'stage already contains a source checkout'
cleanup() { git worktree remove --force --force "$checkout" >/dev/null 2>&1 || true; }
trap cleanup EXIT
git worktree add --detach "$checkout" "$source_commit" >/dev/null
git -C "$checkout" submodule update --init --recursive
(cd "$checkout"; ./script/release-manifest.sh generate \
    "$(jq -r '.lattice.version' "$release")" "$(jq -r '.lattice.tag' "$release")" \
    "$(jq -r '.initialOwner' "$release")" "$publication" deployments/.verification-golden.json) > "$stage/build.log" 2>&1 || fail 'frozen native build failed'
diff -u <(jq -S . "$release") <(jq -S . "$checkout/deployments/.verification-golden.json") > "$stage/identity.diff" || fail 'frozen identities differ'
cmp "$stage/inputs.json" "$checkout/out/release-build-inputs.json" || fail 'reproduced compiler witness differs'
shopt -s nullglob
builds=("$checkout"/out/build-info/*.json)
[ "${#builds[@]}" -gt 0 ] || fail 'missing reproduced build-info'
# Resolve compiler targets from actual compiler output. Basename inventory entries must resolve uniquely.
jq -s --slurpfile archive "$stage/inputs.json" --slurpfile release "$release" '
    [.[] as $build |
      ($build.input|{language,sources,settings}) as $input |
      ($archive[0]|to_entries|map(select(.value.input==$input and .value.solcVersion==$build.solcVersion))|.[0].key) as $index |
      select($index!=null) |
      $build.output.contracts|to_entries[]|.key as $source|.value|to_entries[]|
      select((.value.evm.bytecode.object // "")|length>0) |
      (.value.metadata|if type=="string" then fromjson else . end) as $metadata |
      {source:$source,contract:.key,inputIndex:$index,metadata:$metadata,compilerVersion:$metadata.compiler.version}
    ] as $targets |
    [$release[0].contracts[] as $record |
      ($record.artifact|split(":")) as $artifact |
      [$targets[]|select(.contract==$artifact[1] and
        (if $artifact[0]|contains("/") then .source==$artifact[0] else (.source|split("/")|last)==$artifact[0] end))] as $matches |
      if ($matches|length)==0 or ([$matches[].source]|unique|length)!=1 or ([$matches[].metadata]|unique|length)!=1
        then error("missing or ambiguous frozen compiler target: "+$record.artifact) else
        ($matches|sort_by(.inputIndex)|first) as $target |
        if ($target.compilerVersion|split("+")[0])!=$release[0].compiler.solc or
           ($target.compilerVersion|test("^[0-9]+\\.[0-9]+\\.[0-9]+\\+commit\\.[0-9a-f]{8}$")|not)
          then error("compiler version mismatch") else
        {name:$record.name,address:$record.address,identifier:($target.source+":"+$target.contract),
         compilerVersion:$target.compilerVersion,inputIndex:$target.inputIndex,initCodeHash:$record.initCodeHash,codehash:$record.codehash}
        end
      end]
' "${builds[@]}" > "$stage/catalog.json"
cp "$release" "$stage/release.json"
if [ "$#" = 5 ]; then
    chain_file=$(cd "$(dirname "$4")" && pwd -P)/$(basename "$4")
    rpc=$5
    ./script/release/validate-manifest.sh "$release" "$chain_file"
    chain=$(jq -r '.chain.id' "$chain_file")
    number=$(jq -r '.chain.blockNumber' "$chain_file")
    hash=$(jq -r '.chain.blockHash' "$chain_file")
    verification_block_matches "$rpc" "$chain" "$number" "$hash" || fail 'RPC chain or recorded block differs'
    for observer in ObserveManifest StatusRecordWriter; do
        jq -e '.bytecode.linkReferences|length==0' "$checkout/out/ObserveManifest.s.sol/$observer.json" >/dev/null || fail 'observer has linked dependencies'
    done
    cp "$release" "$checkout/deployments/.verification-release.json"
    (cd "$checkout"; FOUNDRY_PROFILE=ci forge script script/release/ObserveManifest.s.sol:ObserveManifest \
        --sig 'run(string,bytes32,string)' deployments/.verification-release.json "$hash" deployments/.verification-observed.json \
        --rpc-url "$rpc" --fork-block-number "$number" --no-storage-caching --non-interactive) > "$stage/observation.log" 2>&1 || fail 'pinned read-only observation failed'
    release_hash=$(jq -cS . "$release"|tr -d '\n'|cast keccak)
    jq -S --arg hash "$release_hash" '. + {releaseManifestHash:$hash}' "$checkout/deployments/.verification-observed.json" > "$stage/observed.json"
    ./script/release/validate-manifest.sh "$release" "$stage/observed.json"
    verification_block_matches "$rpc" "$chain" "$number" "$hash" || fail 'observed chain or block changed'
    jq -e 'all(.contracts[]; .deployed!=null and .codeMatches)' "$stage/observed.json" >/dev/null || fail 'missing or mismatched shared code'
    deployer=$(jq -r '.deployer.address' "$release")
    while IFS=$'\t' read -r tx salt init_hash; do
        verification_transaction_matches "$rpc" "$tx" "$deployer" "$salt" "$init_hash" "$number" "$stage" || fail 'deployment transaction does not prove the frozen CREATE2 input'
    done < <(jq -r --slurpfile release "$release" '.contracts[]|select(.deployed!=null and .deployed!="pre-existing") as $status|
        $release[0].contracts[]|select(.name==$status.name)|[$status.deployed,.salt,.initCodeHash]|@tsv' "$chain_file")
    verification_block_matches "$rpc" "$chain" "$number" "$hash" || fail 'transaction evidence block changed'
fi
echo "verification prepare: $(jq length "$stage/catalog.json") frozen compiler targets reproduced"
