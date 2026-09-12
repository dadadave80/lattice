// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HederaPrngAdapterLib} from "@lattice/oracles/hedera/HederaPrngAdapterLib.sol";

/// @title HederaPrngAdapterInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for a PRNG diamond — registers the IHederaPrngAdapter interface (ERC-165) and
///         nothing else: the module is stateless (the seed comes straight from the system contract at call
///         time, so there is no subscription, no keeper and no request book to seed). Delegatecalled by
///         {Diamond.initialize} inside the initializing window (so it must NOT open its own
///         pre/postInitializer).
contract HederaPrngAdapterInit {
    /// @notice Runs the PRNG module initializer. MUST be invoked via the diamond's `initialize` `_init`
    ///         delegatecall.
    function init() external {
        HederaPrngAdapterLib.__HederaPrngAdapter_init();
    }
}
