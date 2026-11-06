#!/usr/bin/env bash
# Keep actual standard-JSON compiler inputs, without compiler output or host-dependent CLI paths.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ "$#" = 1 ] || { echo 'usage: package-build-info.sh <destination>' >&2; exit 1; }
shopt -s nullglob
files=(out/build-info/*.json)
[ "${#files[@]}" -gt 0 ] || { echo 'build-info: clean CI-profile build required' >&2; exit 1; }
jq -cS -s '[.[] | {solcVersion,solcLongVersion,input:(.input | {language,sources,settings})}] | unique | sort_by(tojson)' "${files[@]}" > "$1"
jq -e 'length > 0 and all(.[]; .solcVersion == "0.8.36" and .input.language == "Solidity" and (.input.sources|length)>0 and .input.settings.evmVersion == "cancun")' "$1" >/dev/null
