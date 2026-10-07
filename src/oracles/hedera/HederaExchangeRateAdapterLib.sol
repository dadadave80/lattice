// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IExchangeRate} from "@lattice/interfaces/external/hedera/IExchangeRate.sol";
import {IHederaExchangeRateAdapter} from "@lattice/interfaces/oracles/IHederaExchangeRateAdapter.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev 0x409e5cd5 is `type(IHederaExchangeRateAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x409e5cd5), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IHEDERAEXCHANGERATEADAPTER_SLOT =
    0x63eb9226e864b43834b3b55a3188cdb0170b49fdd7f8a67c2a48bd7b9f6a8378;

/// @dev The Exchange Rate system contract (HIP-475). No bytecode; never `delegatecall` it.
address constant EXCHANGE_RATE_SYSTEM_CONTRACT = 0x0000000000000000000000000000000000000168;

/// @dev 1 tinybar = 1e10 weibar; 1 US cent = 1e8 tinycents (1 tinycent = 1e-10 USD); 1 HBAR = 1e8 tinybars.
uint256 constant WEIBAR_PER_TINYBAR = 1e10;
uint256 constant TINYCENTS_PER_CENT = 1e8;
uint256 constant TINYBARS_PER_HBAR = 1e8;

/// @title HederaExchangeRateAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Stateless wrapper around the Exchange Rate system contract — no storage, no admin, no staleness
///         (the network itself refreshes the rate roughly hourly).
/// @dev The two conversion calls are view-classified by the network, so `staticcall` is valid (probe on
///      testnet in the day-0 checklist before relying on it from a `view`).
library HederaExchangeRateAdapterLib {
    function __HederaExchangeRateAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IHEDERAEXCHANGERATEADAPTER_SLOT, true)
        }
    }

    function tinycentsToTinybars(uint256 tinycents) internal view returns (uint256 tinybars) {
        return _query(abi.encodeCall(IExchangeRate.tinycentsToTinybars, (tinycents)));
    }

    function tinybarsToTinycents(uint256 tinybars) internal view returns (uint256 tinycents) {
        return _query(abi.encodeCall(IExchangeRate.tinybarsToTinycents, (tinybars)));
    }

    function usdCentsToWei(uint256 cents) internal view returns (uint256 weibar) {
        return tinycentsToTinybars(cents * TINYCENTS_PER_CENT) * WEIBAR_PER_TINYBAR;
    }

    /// @notice USD per HBAR, 18 decimals: tinycents per HBAR is USD * 1e10, so scale by 1e8.
    function hbarUsdWad() internal view returns (uint256 priceWad) {
        return tinybarsToTinycents(TINYBARS_PER_HBAR) * 1e8;
    }

    function _query(bytes memory data) private view returns (uint256 result) {
        (bool ok, bytes memory ret) = EXCHANGE_RATE_SYSTEM_CONTRACT.staticcall(data);
        if (!ok || ret.length < 32) revert IHederaExchangeRateAdapter.HederaExchangeRateCallFailed();
        result = abi.decode(ret, (uint256));
    }
}
