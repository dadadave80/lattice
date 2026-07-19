// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title ReentrancyGuard
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Solady (https://github.com/vectorized/solady/blob/main/src/utils/ReentrancyGuardTransient.sol)
/// @notice Companion mixin to {ReentrancyGuardLib}: exposes the guard as `nonReentrant` and
///         `nonReadReentrant` modifiers so facets inherit reentrancy protection instead of
///         hand-rolling the `entry()`/`exit()` pair.
/// @dev Transient-storage variant on Ethereum mainnet, plain-`SSTORE` guard everywhere else (the
///      lib bakes in Solady's default; the per-contract virtual
///      `_useTransientReentrancyGuardOnlyOnMainnet()` hook is dropped — library functions cannot
///      see contract-level overrides). Stateless — adds no storage and no selectors, safe to mix
///      into any facet. All facets sharing one diamond share one lock, which is exactly the
///      cross-facet protection wanted.
abstract contract ReentrancyGuard {
    /// @dev Guards a function from reentrancy.
    modifier nonReentrant() virtual {
        ReentrancyGuardLib.entry();
        _;
        ReentrancyGuardLib.exit();
    }

    /// @dev Guards a view function from read-only reentrancy.
    modifier nonReadReentrant() virtual {
        ReentrancyGuardLib.check();
        _;
    }
}
