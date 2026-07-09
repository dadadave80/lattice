// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IRateLimiter} from "@lattice/interfaces/security/IRateLimiter.sol";
import {RateLimiterLib} from "@lattice/security/libraries/RateLimiterLib.sol";

/// @title RateLimiter
/// @author Modified from Chainlink CCIP (https://github.com/smartcontractkit/ccip/blob/ccip-develop/contracts/src/v0.8/ccip/libraries/RateLimiter.sol)
/// @notice Thin Diamond facet that exposes token-bucket rate limiting keyed by bytes32.
/// @dev All logic lives in {RateLimiterLib}. This contract is stateless and forwards
///      every call to the library. Inherit this in your Diamond facet to add rate limiting.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Chainlink CCIP
contract RateLimiter is IRateLimiter {
    /// @inheritdoc IRateLimiter
    function getConfig(bytes32 key) public view virtual returns (uint256 capacity, uint256 refillRate) {
        return RateLimiterLib.getConfig(key);
    }

    /// @inheritdoc IRateLimiter
    function getAvailable(bytes32 key) public view virtual returns (uint256 available) {
        return RateLimiterLib.getAvailable(key);
    }

    /// @inheritdoc IRateLimiter
    function configure(bytes32 key, uint256 capacity, uint256 refillRate) public virtual {
        RateLimiterLib.configure(key, capacity, refillRate);
    }

    /// @inheritdoc IRateLimiter
    function consume(bytes32 key, uint256 amount) public virtual {
        RateLimiterLib.consume(key, amount);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect RateLimiter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `configure(bytes32,uint256,uint256)` 0xbe0b31ab
    ///      `consume(bytes32,uint256)` 0x98017489
    ///      `getAvailable(bytes32)` 0xd121f72c
    ///      `getConfig(bytes32)` 0x6dd5b69d
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"be0b31ab98017489d121f72c6dd5b69d";
    }
}
