#!/usr/bin/env bash
# Block-pinned RPC and optional direct Arachnid transaction witnesses for source verification.
verification_block_matches() {
    local rpc=$1 chain=$2 number=$3 hash=$4
    [ "$(cast chain-id --rpc-url "$rpc")" = "$chain" ] &&
      [ "$(cast rpc --rpc-url "$rpc" eth_getBlockByNumber "$(cast to-hex "$number")" false | jq -r '.hash')" = "$hash" ]
}

# A transaction hash is only a submission hint after proving its canonical salt and full initcode.
# Existing deployments without a known direct transaction use the truthful pre-existing marker.
verification_transaction_matches() {
    local rpc=$1 tx=$2 deployer=$3 salt=$4 init_hash=$5 observed_number=$6 work=$7
    local number block_hash input
    cast rpc --rpc-url "$rpc" eth_getTransactionReceipt "$tx" > "$work/receipt.json" || return 1
    cast rpc --rpc-url "$rpc" eth_getTransactionByHash "$tx" > "$work/transaction.json" || return 1
    jq -e -s 'length==1 and (.[0]|type)=="object"' "$work/receipt.json" >/dev/null || return 1
    jq -e -s 'length==1 and (.[0]|type)=="object"' "$work/transaction.json" >/dev/null || return 1
    jq -e --arg tx "$tx" --arg deployer "$deployer" --slurpfile receipt "$work/receipt.json" '
        .hash==$tx and $receipt[0].transactionHash==$tx and $receipt[0].status=="0x1" and
        (.to|ascii_downcase)==($deployer|ascii_downcase) and
        .blockNumber==$receipt[0].blockNumber and .blockHash==$receipt[0].blockHash and
        (.blockNumber|test("^0x[0-9a-fA-F]+$")) and (.blockHash|test("^0x[0-9a-fA-F]{64}$")) and
        (.input|test("^0x([0-9a-fA-F]{2})+$")) and (.input|length)>66
    ' "$work/transaction.json" >/dev/null || return 1
    number=$(cast to-dec "$(jq -r '.blockNumber' "$work/transaction.json")") || return 1
    [ "$number" -le "$observed_number" ] || return 1
    block_hash=$(jq -r '.blockHash' "$work/transaction.json")
    [ "$(cast rpc --rpc-url "$rpc" eth_getBlockByNumber "$(cast to-hex "$number")" false | jq -r '.hash')" = "$block_hash" ] || return 1
    input=$(jq -r '.input|ascii_downcase' "$work/transaction.json")
    [ "${input:0:66}" = "$(printf '%s' "$salt" | tr '[:upper:]' '[:lower:]')" ] &&
      [ "$(cast keccak "0x${input:66}")" = "$init_hash" ]
}
