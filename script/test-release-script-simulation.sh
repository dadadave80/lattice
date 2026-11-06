#!/usr/bin/env bash
# Exercise the actual filtered native linker, which a full test compilation can mask. No RPC/broadcast.
set -euo pipefail
cd "$(dirname "$0")/.."
snapshot=deployments/.release-script-identities.json
plan=deployments/31337/plan-99.0.0.json
[ ! -e "$snapshot" ] && [ ! -e "$plan" ] || { echo 'release simulation: preserve existing output; move it before running this check' >&2; exit 1; }
trap 'rm -f "$snapshot" "$plan"; rmdir deployments/31337 2>/dev/null || true' EXIT
export FOUNDRY_PROFILE=ci
forge script script/release/GenerateManifest.s.sol:GenerateManifest \
    --sig 'generate(string,address,string)' 99.0.0 0x000000000000000000000000000000000000bEEF "$snapshot" --non-interactive
forge script script/deploy/DeployRelease.s.sol:DeployRelease \
    --sig 'run(string,address)' 99.0.0 0x000000000000000000000000000000000000bEEF --non-interactive
jq -e --slurpfile plan "$plan" '
  all(.contracts[]; . as $c |
    if .kind == "registry" then .address == $plan[0].registry
    elif .kind == "factory" then .address == $plan[0].factory
    else (if .kind == "facet" then $plan[0].facets[.name]
          elif .kind == "init" then $plan[0].inits[.name]
          elif .kind == "account-init" or .kind == "account-factory" then $plan[0].accounts[.name]
          else $plan[0].libraries[.name] end) as $p |
      .address == $p.address and .salt == $p.salt and .codehash == $p.codehash and
      (if .kind == "facet" then .selectorsHash == $p.selectorsHash else .initCodeHash == $p.initCodeHash end) and
      (if .kind == "account-init" or .kind == "account-factory" then .constructorArgs == $p.constructorArgs else true end)
    end)
' "$snapshot" >/dev/null
echo 'release simulation: filtered generator and release script reproduce the same native-linked identities'
