#!/usr/bin/env bash
# Author: David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
# API: Sourcify v2 (https://docs.sourcify.dev/docs/api/)
# Transport/response checks. The entry point proves frozen input and pinned RPC identities first.
SOURCIFY_API=https://sourcify.dev/server
SOURCIFY_AGENT='LatticeReleaseVerifier/1 (+https://github.com/dadadave80/lattice)'

verification_json_object() {
    jq -e -s 'length == 1 and (.[0] | type == "object")' "$1" >/dev/null 2>&1
}

sourcify_uuid() { [[ "$1" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; }

# A 2xx response or conflict does not prove a match. The caller checks SC_HTTP_STATUS separately.
sourcify_http() {
    local method=$1 url=$2 request=$3 response=$4 headers=$5 attempt=0 rc delay retry_after
    local -a args
    while :; do
        : > "$response"
        : > "$headers"
        args=(-q --silent --show-error --connect-timeout 10 --max-time 60 --max-filesize 2097152
            --max-redirs 0 --proto '=https' --user-agent "$SOURCIFY_AGENT" --dump-header "$headers"
            --output "$response" --write-out '%{http_code}' --request "$method")
        if [ "$method" = POST ]; then args+=(-H 'Content-Type: application/json' --data-binary "@$request"); fi
        if SC_HTTP_STATUS=$(env -u ETHERSCAN_API_KEY -u VERIFIER_API_KEY -u ETH_RPC_JWT_SECRET -u ETH_RPC_HEADERS curl "${args[@]}" "$url"); then rc=0; else rc=$?; fi
        [[ "$SC_HTTP_STATUS" =~ ^[0-9]{3}$ ]] || return 2
        if [ "$rc" = 0 ] && [[ "$SC_HTTP_STATUS" != 429 && ! "$SC_HTTP_STATUS" =~ ^5 ]]; then return 0; fi
        # A POST may have been accepted before a transport/server error. Never blindly repeat it.
        if [ "$method" = POST ] && [ "$SC_HTTP_STATUS" != 429 ]; then return 75; fi
        attempt=$((attempt + 1))
        [ "$attempt" -lt 3 ] || return 75
        delay=$((1 << (attempt - 1)))
        retry_after=$(awk 'tolower($1)=="retry-after:" {sub(/^[^:]*:[ \t]*/, ""); sub(/\r$/, ""); value=$0} END {print value}' "$headers")
        if [ -n "$retry_after" ]; then
            # Unknown HTTP-date or a longer wait: stop rather than retry before the server permits it.
            [[ "$retry_after" =~ ^[0-9]{1,3}$ ]] && [ "$retry_after" -le 60 ] || return 75
            if [ "$retry_after" -gt "$delay" ]; then delay=$retry_after; fi
        fi
        sleep "$delay"
    done
}

sourcify_identity() {
    local response=$1 chain=$2 at=$3
    verification_json_object "$response" && jq -e --arg chain "$chain" --arg at "$at" '
        has("match") and has("creationMatch") and has("runtimeMatch") and
        .chainId == $chain and (.address|type)=="string" and
        (.address|ascii_downcase)==($at|ascii_downcase) and
        all([.match,.creationMatch,.runtimeMatch][]; .==null or .=="match" or .=="exact_match")
    ' "$response" >/dev/null 2>&1
}

# 0 = exact and bound to both hashes; 1 = valid non-exact; 2 = malformed/conflicting proof.
sourcify_lookup_exact() {
    local response=$1 chain=$2 at=$3 init_hash=$4 codehash=$5 creation runtime
    sourcify_identity "$response" "$chain" "$at" || return 2
    jq -e '.match=="exact_match" and .creationMatch=="exact_match" and .runtimeMatch=="exact_match"' "$response" >/dev/null || return 1
    jq -e '
        (.creationBytecode.onchainBytecode|type)=="string" and
        (.runtimeBytecode.onchainBytecode|type)=="string" and
        (.creationBytecode.onchainBytecode|length)<=98306 and
        (.runtimeBytecode.onchainBytecode|length)<=49154 and
        (.creationBytecode.onchainBytecode|test("^0x([a-fA-F0-9]{2})+$")) and
        (.runtimeBytecode.onchainBytecode|test("^0x([a-fA-F0-9]{2})+$"))
    ' "$response" >/dev/null 2>&1 || return 2
    creation=$(jq -r '.creationBytecode.onchainBytecode' "$response")
    runtime=$(jq -r '.runtimeBytecode.onchainBytecode' "$response")
    [ "$(cast keccak "$creation")" = "$init_hash" ] && [ "$(cast keccak "$runtime")" = "$codehash" ] || return 2
}

sourcify_completed_exact() {
    local response=$1 job=$2 chain=$3 at=$4
    sourcify_uuid "$job" || return 1
    verification_json_object "$response" && jq -e --arg job "$job" --arg chain "$chain" --arg at "$at" '
        .verificationId==$job and .isJobCompleted==true and .error==null and
        .contract.chainId==$chain and (.contract.address|type)=="string" and
        (.contract.address|ascii_downcase)==($at|ascii_downcase) and
        .contract.match=="exact_match" and .contract.creationMatch=="exact_match" and .contract.runtimeMatch=="exact_match"
    ' "$response" >/dev/null 2>&1
}

verification_save() {
    local chain_file=$1 name=$2 verified=$3 job=$4 next
    if [ "$verified" = true ]; then verification_can_commit || return 75; fi
    next=$(mktemp "${chain_file}.tmp.XXXXXX") || return 2
    if ! jq -S --arg name "$name" --argjson verified "$verified" --arg job "$job" '
        .contracts |= map(if .name==$name then
            .verified=$verified | .verifier=(if $verified then "sourcify" else null end) |
            if $job=="" then del(.verificationId) else .verificationId=$job end
          else . end)
    ' "$chain_file" > "$next"; then rm -f "$next"; return 2; fi
    mv "$next" "$chain_file"
}

# The operational entry point overrides this with its recorded RPC chain/block check.
verification_can_commit() { return 0; }

# Prepared data comes from validated frozen build-info, not a production preflight bypass.
# 75 = retryable/pending work; 1 = definitive error/non-exact; 2 = malformed/conflicting proof.
sourcify_verify_record() {
    local chain_file=$1 name=$2 at=$3 chain=$4 init_hash=$5 codehash=$6 request=$7 work=$8
    local response=$work/response.json headers=$work/headers job attempt result
    job=$(jq -r --arg name "$name" '.contracts[]|select(.name==$name)|.verificationId // ""' "$chain_file")
    verification_save "$chain_file" "$name" false "$job" || return 2
    sourcify_http GET "$SOURCIFY_API/v2/contract/$chain/$at?fields=creationBytecode.onchainBytecode,runtimeBytecode.onchainBytecode" '' "$response" "$headers" || return $?
    case "$SC_HTTP_STATUS" in 200|404) ;; *) return 1 ;; esac
    if [ "$SC_HTTP_STATUS" = 404 ]; then
        verification_json_object "$response" && jq -e '.match==null and .creationMatch==null and .runtimeMatch==null' "$response" >/dev/null || return 2
    fi
    if sourcify_lookup_exact "$response" "$chain" "$at" "$init_hash" "$codehash"; then
        [ "$SC_HTTP_STATUS" = 200 ] || return 2
        verification_save "$chain_file" "$name" true '' || return $?
        return 0
    else result=$?; fi
    [ "$result" = 1 ] || return "$result"
    if [ -z "$job" ]; then
        sourcify_http POST "$SOURCIFY_API/v2/verify/$chain/$at" "$request" "$response" "$headers" || return $?
        verification_json_object "$response" || return 2
        case "$SC_HTTP_STATUS" in
            202)
                job=$(jq -er '.verificationId|select(type=="string")' "$response") || return 2
                sourcify_uuid "$job" || return 2
                verification_save "$chain_file" "$name" false "$job" || return 2
                ;;
            409) job= ;;
            *) return 1 ;;
        esac
    else sourcify_uuid "$job" || return 2; fi
    if [ -n "$job" ]; then
        for attempt in {1..12}; do
            sourcify_http GET "$SOURCIFY_API/v2/verify/$job" '' "$response" "$headers" || return $?
            if [ "$SC_HTTP_STATUS" = 404 ]; then
                verification_json_object "$response" || return 2
                verification_save "$chain_file" "$name" false ''
                return 1
            fi
            [ "$SC_HTTP_STATUS" = 200 ] && verification_json_object "$response" || return 2
            jq -e --arg job "$job" --arg chain "$chain" --arg at "$at" '
                .verificationId==$job and (.isJobCompleted|type)=="boolean" and
                (.contract==null or (.contract.chainId==$chain and (.contract.address|type)=="string" and
                    (.contract.address|ascii_downcase)==($at|ascii_downcase))) and
                (.error==null or ((.error|type)=="object" and (.error.customCode|type)=="string"))
            ' "$response" >/dev/null || return 2
            if jq -e '.isJobCompleted' "$response" >/dev/null; then
                if ! sourcify_completed_exact "$response" "$job" "$chain" "$at"; then
                    # The already-verified race still requires an authoritative fresh lookup.
                    if ! jq -e '.error.customCode=="already_verified"' "$response" >/dev/null; then
                        verification_save "$chain_file" "$name" false ''
                        return 1
                    fi
                fi
                break
            fi
            [ "$attempt" -lt 12 ] || return 75
            sleep 5
        done
    fi
    # A completed job, conflict or already_verified string does not prove the final result.
    sourcify_http GET "$SOURCIFY_API/v2/contract/$chain/$at?fields=creationBytecode.onchainBytecode,runtimeBytecode.onchainBytecode" '' "$response" "$headers" || return $?
    [ "$SC_HTTP_STATUS" = 200 ] || return 1
    if sourcify_lookup_exact "$response" "$chain" "$at" "$init_hash" "$codehash"; then
        verification_save "$chain_file" "$name" true ''
    else
        result=$?
        verification_save "$chain_file" "$name" false ''
        return "$result"
    fi
}
