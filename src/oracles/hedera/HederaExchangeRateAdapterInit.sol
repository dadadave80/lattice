// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HederaExchangeRateAdapterLib} from "@lattice/oracles/hedera/HederaExchangeRateAdapterLib.sol";

/// @title HederaExchangeRateAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for an exchange-rate diamond — registers the IHederaExchangeRateAdapter
///         interface (ERC-165) and nothing else: the module is stateless (the network itself keeps the rate
///         fresh, so there is no feed address, no admin and no staleness window to seed). Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer).
contract HederaExchangeRateAdapterInit {
    /// @notice Runs the exchange-rate module initializer. MUST be invoked via the diamond's `initialize`
    ///         `_init` delegatecall.
    function init() external {
        HederaExchangeRateAdapterLib.__HederaExchangeRateAdapter_init();
    }
}
