#!/usr/bin/env bash
# Mutation fixtures using current compiler artifacts; only the fixture's build step is stubbed.
# shellcheck disable=SC2016
# Fixture mutations are shell source evaluated inside each isolated directory.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK="$ROOT/script/erc3643-profile.sh"
REAL_FORGE=$(command -v forge)
export REAL_FORGE
PROFILE_FIXTURE=$(mktemp -d)
trap 'rm -rf "$PROFILE_FIXTURE"' EXIT
mkdir -p "$PROFILE_FIXTURE/base/script/config" "$PROFILE_FIXTURE/base/src/tokens/ERC3643/libraries" "$PROFILE_FIXTURE/bin"
cp "$ROOT/script/config/erc3643-profile.json" "$PROFILE_FIXTURE/base/script/config/"
cp "$ROOT/src/tokens/ERC3643/libraries/ERC3643Profile.sol" "$PROFILE_FIXTURE/base/src/tokens/ERC3643/libraries/"
# Copy a bounded, real artifact subset. Nothing in the production helper can skip compilation.
while IFS= read -r artifact; do
    source=${artifact%:*}
    name=${artifact##*:}
    path="out/${source##*/}/$name.json"
    mkdir -p "$PROFILE_FIXTURE/base/$(dirname "$path")"
    jq '{deployedBytecode,rawMetadata,methodIdentifiers}' "$ROOT/$path" >"$PROFILE_FIXTURE/base/$path"
done < <(jq -r '.host.artifact, .facets[].artifact' "$ROOT/script/config/erc3643-profile.json")
cat >"$PROFILE_FIXTURE/bin/forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == build ]]; then exit 0; fi
exec "$REAL_FORGE" "$@"
EOF
chmod +x "$PROFILE_FIXTURE/bin/forge"
export PATH="$PROFILE_FIXTURE/bin:$PATH"
n=0
failures=0
edit_json() { jq "$1" "$2" >"$2.tmp" && mv "$2.tmp" "$2"; }
expect() {
    local want=$1 label=$2 mutation=$3 got
    n=$((n + 1))
    cp -R "$PROFILE_FIXTURE/base" "$PROFILE_FIXTURE/case$n"
    (cd "$PROFILE_FIXTURE/case$n" && eval "$mutation")
    if "$CHECK" --check "$PROFILE_FIXTURE/case$n" >"$PROFILE_FIXTURE/case$n.log" 2>&1; then got=pass; else got=fail; fi
    if [[ "$want" == "$got" ]]; then echo "ok   $label"; else
        echo "FAIL $label (expected $want, got $got)"
        tail -n 30 "$PROFILE_FIXTURE/case$n.log"
        failures=$((failures + 1))
    fi
}
export TOKEN=out/ERC3643.sol/ERC3643.json
export HOST=out/Lattice.sol/Lattice.json
expect pass 'reviewed host, all facets and routes' ':'
expect fail 'host runtime drift' 'edit_json '\''.deployedBytecode.object += "00"'\'' "$HOST"'
expect fail 'facet runtime drift' 'edit_json '\''.deployedBytecode.object += "00"'\'' "$TOKEN"'
expect fail 'required selector ownership drift' 'edit_json '\''.methodIdentifiers["transfer(address,uint256)"]="deadbeef"'\'' "$TOKEN"'
expect fail 'generated input fingerprint drift' 'sed -E "s/INPUT_HASH = 0x[0-9a-f]+;/INPUT_HASH = 0x0000000000000000000000000000000000000000000000000000000000000000;/" src/tokens/ERC3643/libraries/ERC3643Profile.sol >changed && mv changed src/tokens/ERC3643/libraries/ERC3643Profile.sol'
expect fail 'linked facet rejected' 'edit_json '\''.deployedBytecode.linkReferences={"Library.sol":{"Library":[{"start":0,"length":20}]}}'\'' "$TOKEN"'
expect fail 'immutable facet rejected' 'edit_json '\''.deployedBytecode.immutableReferences={"1":[{"start":0,"length":32}]}'\'' "$TOKEN"'
expect fail 'empty facet runtime rejected' 'edit_json '\''.deployedBytecode.object="0x"'\'' "$TOKEN"'
expect fail 'compiler drift rejected' 'edit_json '\''.rawMetadata |= (fromjson | .compiler.version="0.8.35+commit.fixture" | tojson)'\'' "$TOKEN"'
expect fail 'EVM drift rejected' 'edit_json '\''.rawMetadata |= (fromjson | .settings.evmVersion="prague" | tojson)'\'' "$HOST"'
expect fail 'IR build rejected' 'edit_json '\''.rawMetadata |= (fromjson | .settings.viaIR=true | tojson)'\'' "$TOKEN"'
expect fail 'different host configuration rejected' 'edit_json '\''.host.name="AccountDiamond"'\'' script/config/erc3643-profile.json'
expect fail 'different optional facet rejected' 'edit_json '\''.facets[-1].name="ERC20Permit"'\'' script/config/erc3643-profile.json'
expect fail 'facet dependency on profile rejected' 'edit_json '\''.rawMetadata |= (fromjson | .sources["src/tokens/ERC3643/libraries/ERC3643Profile.sol"]={"keccak256":"0x00"} | tojson)'\'' "$TOKEN"'
expect fail 'duplicate actual facet hash rejected' 'jq -s '\''.[0].deployedBytecode.object=.[1].deployedBytecode.object | .[0]'\'' "$TOKEN" out/ERC3643AgentRole.sol/ERC3643AgentRole.json >changed && mv changed "$TOKEN"'
echo "$((n - failures))/$n ERC3643 profile cases passed"
[[ "$failures" -eq 0 ]]
