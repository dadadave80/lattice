// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title ReentrancyGuard
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/ReentrancyGuard.sol)
/// @notice Abstract base contract providing reentrant call protection.
/// @dev Inherit this contract in Diamond facets that require reentrancy protection.
/// Concrete facets must call `ReentrancyGuardLib.__ReentrancyGuard_init()` inside their
/// own initializer (between `preInitializer` / `postInitializer`) to set up storage.
///
/// Usage pattern in a guarded function:
/// ```solidity
/// function sensitiveAction() external {
///     ReentrancyGuardLib.nonReentrantBefore();
///     // ... logic ...
///     ReentrancyGuardLib.nonReentrantAfter();
/// }
/// ```
abstract contract ReentrancyGuard {
    // All reentrancy logic lives in ReentrancyGuardLib.
    // Inheriting this contract signals intent and enables code navigation.
}
