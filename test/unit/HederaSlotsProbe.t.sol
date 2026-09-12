// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IHASSignatureVerifier} from "@lattice/interfaces/accounts/IHASSignatureVerifier.sol";
import {IHSSAdapter} from "@lattice/interfaces/oracles/IHSSAdapter.sol";
import {IHederaExchangeRateAdapter} from "@lattice/interfaces/oracles/IHederaExchangeRateAdapter.sol";
import {IHederaPrngAdapter} from "@lattice/interfaces/oracles/IHederaPrngAdapter.sol";
import {IHTSAdapter} from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import {Test, console2} from "forge-std/Test.sol";

/// @dev THROWAWAY probe: prints the ERC-7201 storage slots and ERC-165 map slots for the Hedera modules so the
///      precomputed constants can be pasted into the libraries and STORAGE_REGISTRY.md.
contract HederaSlotsProbe is Test {
    bytes32 constant ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

    function _erc7201(string memory ns) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(ns))) - 1)) & ~bytes32(uint256(0xff));
    }

    function _map(bytes4 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(id, ERC165_STORAGE_LOCATION));
    }

    function test_PrintHederaSlots() public pure {
        console2.log("--- ERC-7201 storage slots ---");
        console2.logBytes32(_erc7201("lattice.storage.HTSAdapter"));
        console2.logBytes32(_erc7201("lattice.storage.HSSAdapter"));
        console2.log("--- interfaceIds ---");
        console2.logBytes4(type(IHTSAdapter).interfaceId);
        console2.logBytes4(type(IHASSignatureVerifier).interfaceId);
        console2.logBytes4(type(IHederaExchangeRateAdapter).interfaceId);
        console2.logBytes4(type(IHederaPrngAdapter).interfaceId);
        console2.logBytes4(type(IHSSAdapter).interfaceId);
        console2.log("--- ERC-165 map slots ---");
        console2.logBytes32(_map(type(IHTSAdapter).interfaceId));
        console2.logBytes32(_map(type(IHASSignatureVerifier).interfaceId));
        console2.logBytes32(_map(type(IHederaExchangeRateAdapter).interfaceId));
        console2.logBytes32(_map(type(IHederaPrngAdapter).interfaceId));
        console2.logBytes32(_map(type(IHSSAdapter).interfaceId));
    }
}
