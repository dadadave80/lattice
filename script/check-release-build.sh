#!/usr/bin/env bash
# Canonical release settings and dependency identity (#197, #336).
# Usage: ./script/check-release-build.sh [root] (`make release-build-check`).
# The shared action's exact stable Foundry pin is also the local-development pin.
set -euo pipefail

cd "${1:-$(dirname "$0")/..}"
fail() { echo "release-build: $*" >&2; exit 1; }

pin=$(awk '$1 == "version:" {print $2}' .github/actions/foundry-setup/action.yml)
[[ "$pin" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Foundry must have one exact stable pin"
version=$(forge --version | sed -n '1s/^forge Version: //p')
[ "$version" = "${pin#v}" ] || fail "use Foundry $pin (installed: $version)"

for profile in default ci; do
    config=$(forge config --json --profile "$profile")
    jq -e '
        .solc == "0.8.36" and .evm_version == "cancun" and
        .optimizer == true and .optimizer_runs == 1000000 and .via_ir == false and
        .bytecode_hash == "ipfs" and .cbor_metadata == true and
        .libraries == [] and
        .create2_deployer == "0x4e59b44847b379578588920ca78fbf26c0b4956c" and
        .create2_library_salt == "0x0000000000000000000000000000000000000000000000000000000000000000"
    ' <<<"$config" >/dev/null || fail "$profile must use solc 0.8.36, Cancun, optimizer 1000000, legacy pipeline, IPFS/CBOR metadata and canonical native CREATE2 library linking"
    if [ "$profile" = ci ]; then
        jq -e '.build_info == true' <<<"$config" >/dev/null || fail "ci must emit build info"
    fi
done

jq -e '
    type == "object" and length > 0 and
    all(to_entries[]; (.key | startswith("lib/")) and
        (.value.rev | type == "string" and test("^[0-9a-f]{40}$")))
' foundry.lock >/dev/null || fail "foundry.lock must pin each dependency to a full commit"
links=$(git ls-files --stage | awk '$1 == "160000" {sub(/^[^\t]*\t/, ""); print}' |
    jq -Rsc 'split("\n") | map(select(length > 0)) | sort')
[ "$(jq -c 'keys | sort' foundry.lock)" = "$links" ] || fail "foundry.lock paths differ from submodule gitlinks"

while IFS= read -r path; do
    locked=$(jq -r --arg path "$path" '.[$path].rev' foundry.lock)
    indexed=$(git ls-files --stage -- "$path" | awk '$1 == "160000" {print $2}')
    [ "$locked" = "$indexed" ] || fail "$path gitlink differs from foundry.lock"
    actual=$(git -C "$path" rev-parse HEAD 2>/dev/null) || fail "initialize $path (make install)"
    [ "$actual" = "$locked" ] || fail "$path checkout differs from foundry.lock (make install)"
    [ -z "$(git -C "$path" status --porcelain)" ] || fail "$path contains uncommitted dependency changes"
done < <(jq -r 'keys[]' foundry.lock)

status=$(git submodule status --recursive)
if grep -qE '^[+U-]' <<<"$status"; then
    fail "a nested dependency is uninitialized or differs from its gitlink (make install)"
fi
echo "release-build: $pin, solc 0.8.36, Cancun and locked submodules verified"
