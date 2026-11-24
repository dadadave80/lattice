// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity ^0.8.24;

// These addresses are used in two different ways:
// 1. For local testing, we use the addresses of the `_getLocalConfig` in `ZamaConfig.sol`
// 2. When deploying the stack on a fresh network, the deployment script will auto-generate new addresses.
// Either way: don't update these addresses.

address constant aclAdd = address(0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D);

address constant fhevmExecutorAdd = address(0xe3a9105a3a932253A70F126eb1E3b589C643dD24);

address constant kmsVerifierAdd = address(0x901F8942346f7AB3a01F6D7613119Bca447Bb030);

address constant inputVerifierAdd = address(0x36772142b74871f255CbD7A3e89B401d3e45825f);

address constant hcuLimitAdd = address(0x5f3f1dBD7B74C6B46e8c44f98792A1dAf8d69154);

address constant pauserSetAdd = address(0xb7278A61aa25c888815aFC32Ad3cC52fF24fE575);

address constant protocolConfigAdd = address(0x00000000000000000000000000000000fe4C0F16);

address constant kmsGenerationAdd = address(0x00000000000000000000000000000000fE4C6E4e);
