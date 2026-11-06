#!/usr/bin/env bash
# Mutation fixtures for the canonical build boundary (`make release-build-check`).
set -euo pipefail

CHECK="$(cd "$(dirname "$0")" && pwd)/check-release-build.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
n=0
failures=0

fixture() {
    local d=$1 rev
    mkdir -p "$d/lib/dep" "$d/.github/actions/foundry-setup"
    git init -q "$d"
    git init -q "$d/lib/dep"
    printf '// fixture\n' >"$d/lib/dep/Dependency.sol"
    git -C "$d/lib/dep" add Dependency.sol
    git -C "$d/lib/dep" -c user.name=Fixture -c user.email=fixture@example.test \
        -c commit.gpgsign=false commit -q -m fixture
    rev=$(git -C "$d/lib/dep" rev-parse HEAD)
    git -C "$d" update-index --add --cacheinfo "160000,$rev,lib/dep"
    printf '[submodule "dep"]\n\tpath = lib/dep\n\turl = ./lib/dep\n' >"$d/.gitmodules"
    git -C "$d" config submodule.dep.url ./lib/dep
    printf '{"lib/dep":{"rev":"%s"}}\n' "$rev" >"$d/foundry.lock"
    printf 'version: v1.9.0\n' >"$d/.github/actions/foundry-setup/action.yml"
    cat >"$d/foundry.toml" <<'EOF'
[profile.default]
solc = "0.8.36"
evm_version = "cancun"
optimizer = true
optimizer_runs = 1_000_000
via_ir = false
bytecode_hash = "ipfs"
cbor_metadata = true

[profile.ci]
build_info = true
EOF
}

edit() { sed -e "$1" foundry.toml >foundry.tmp && mv foundry.tmp foundry.toml; }

expect() {
    local want=$1 name=$2 setup=$3 d got
    n=$((n + 1))
    d="$tmp/case$n"
    fixture "$d"
    (cd "$d" && eval "$setup")
    if "$CHECK" "$d" >"$d.log" 2>&1; then got=pass; else got=fail; fi
    if [ "$want" = "$got" ]; then
        echo "ok   $name"
    else
        echo "FAIL $name (expected $want, got $got)"
        cat "$d.log"
        failures=$((failures + 1))
    fi
}

expect pass "canonical fixture" ':'
expect fail "unresolved default EVM target" 'edit "/evm_version/d"'
expect fail "default target drift" 'edit "s/cancun/osaka/"'
expect fail "CI target drift" 'printf "evm_version = \"prague\"\n" >>foundry.toml'
expect fail "compiler drift" 'edit "s/0.8.36/0.8.35/"'
expect fail "optimizer disabled" 'edit "s/optimizer = true/optimizer = false/"'
expect fail "optimizer runs drift" 'edit "s/1_000_000/200/"'
expect fail "IR pipeline drift" 'edit "s/via_ir = false/via_ir = true/"'
expect fail "metadata hash removed" 'edit "s/\"ipfs\"/\"none\"/"'
expect fail "CBOR metadata removed" 'edit "s/cbor_metadata = true/cbor_metadata = false/"'
expect fail "noncanonical library deployer" 'printf "create2_deployer = \"0x1111111111111111111111111111111111111111\"\n" >>foundry.toml'
expect fail "library salt drift" 'printf "create2_library_salt = \"0x1111111111111111111111111111111111111111111111111111111111111111\"\n" >>foundry.toml'
expect fail "solc library metadata map" 'printf "libraries = [\"src/L.sol:L:0x1111111111111111111111111111111111111111\"]\n" >>foundry.toml'
expect fail "CI build info disabled" 'edit "s/build_info = true/build_info = false/"'
expect fail "runtime Foundry differs from shared pin" \
    'printf "version: v1.9.1\n" >.github/actions/foundry-setup/action.yml'
expect fail "floating Foundry pin" 'printf "version: stable\n" >.github/actions/foundry-setup/action.yml'
expect fail "missing lock entry" 'printf "{}\n" >foundry.lock'
expect fail "extra lock entry" \
    'jq '\''. + {"lib/other":{"rev":"0000000000000000000000000000000000000000"}}'\'' foundry.lock >lock.tmp && mv lock.tmp foundry.lock'
expect fail "lock revision differs from gitlink" \
    'jq '\''.["lib/dep"].rev="0000000000000000000000000000000000000000"'\'' foundry.lock >lock.tmp && mv lock.tmp foundry.lock'
expect fail "checked-out dependency differs from gitlink" \
    'git -C lib/dep -c user.name=Fixture -c user.email=fixture@example.test -c commit.gpgsign=false commit -q --allow-empty -m drift'
expect fail "modified dependency source" 'printf "// drift\n" >>lib/dep/Dependency.sol'
expect fail "untracked dependency source" 'touch lib/dep/Untracked.sol'
expect fail "uninitialized dependency" 'rm -rf lib/dep/.git'

echo "$((n - failures))/$n release-build cases passed"
[ "$failures" -eq 0 ]
