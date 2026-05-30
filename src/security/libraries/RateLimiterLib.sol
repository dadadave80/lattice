// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IRateLimiter} from "@lattice/interfaces/IRateLimiter.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.RateLimiter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant RATE_LIMITER_STORAGE_SLOT = 0xb9ee9c1434713ac0213faa3d41a1dd3c78042ad8ee2d7f6e110f73cd6f19bd00;

/// @dev `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant RATE_LIMITER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x9afe0493 is `type(IRateLimiter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x9afe0493), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IRATELIMITER_SLOT = 0x58fa1bc4807b27651ddeaa1871a010e28c99455295cf3f3424edd8a3f6c6db45;

/// @notice Storage bucket for a single rate limit key.
struct RateLimiterBucket {
    uint256 capacity;
    uint256 refillRate; // tokens per second
    uint256 tokens;
    uint48 lastRefill;
}

/// @notice Top-level storage struct for the RateLimiter module.
/// @custom:storage-location erc7201:lattice.storage.RateLimiter
struct RateLimiterStorage {
    mapping(bytes32 key => RateLimiterBucket) _buckets;
}

/// @title RateLimiter Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing a token-bucket rate limiter for Diamond facets.
/// @dev Each key has an independent bucket with a `capacity` (max tokens) and
///      `refillRate` (tokens per second). Tokens are lazily refilled on each
///      `consume` call based on elapsed time since the last interaction.
library RateLimiterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                           RATE LIMITER STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the storage struct for RateLimiter at its ERC-7201 slot.
    function rateLimiterStorage() internal pure returns (RateLimiterStorage storage $) {
        assembly {
            $.slot := RATE_LIMITER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IRateLimiter interface via ERC-165.
    /// @dev Writes `true` to the precomputed ERC-165 map slot.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IRATELIMITER_SLOT, true)
        }
    }

    /// @notice Initializes the RateLimiter module.
    /// @dev Must be called between `InitializableLib.preInitializer` and `postInitializer`.
    ///      Registers the IRateLimiter interface ID for ERC-165 discovery.
    function __RateLimiter_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          RATE LIMITER OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Configures or reconfigures a rate limit bucket.
    /// @dev Requires DEFAULT_ADMIN_ROLE. Sets tokens = capacity and lastRefill = now.
    ///      Reverts `RateLimitInvalidConfig` if `capacity == 0` or `refillRate == 0`.
    ///      Emits `RateLimitConfigured`.
    /// @param key        The rate limit key.
    /// @param capacity   The maximum token capacity (must be > 0).
    /// @param refillRate The tokens-per-second refill rate (must be > 0).
    function configure(bytes32 key, uint256 capacity, uint256 refillRate) internal {
        AccessControlLib.checkRole(0x00);
        _configure(key, capacity, refillRate);
    }

    /// @notice Consumes `amount` tokens from the bucket for `key`.
    /// @dev Refills the bucket based on elapsed time, then deducts `amount`.
    ///      Reverts `RateLimitNotConfigured` if the key has no configuration (capacity == 0).
    ///      Reverts `RateLimitExceeded` if fewer than `amount` tokens are available.
    ///      Emits `RateLimitConsumed`.
    /// @param key    The rate limit key.
    /// @param amount The number of tokens to consume.
    function consume(bytes32 key, uint256 amount) internal {
        _consume(key, amount);
    }

    /// @notice Returns the currently available tokens for `key` without modifying state.
    /// @dev Computes the refilled token count based on elapsed time but does not persist it.
    ///      Returns 0 for unconfigured keys.
    /// @param key The rate limit key to query.
    /// @return available The number of tokens available right now.
    function getAvailable(bytes32 key) internal view returns (uint256 available) {
        RateLimiterBucket storage b = rateLimiterStorage()._buckets[key];
        if (b.capacity == 0) return 0;
        return _currentTokens(b);
    }

    /// @notice Returns the capacity and refill rate configured for `key`.
    /// @param key The rate limit key to query.
    /// @return capacity   The maximum token capacity of the bucket.
    /// @return refillRate The number of tokens refilled per second.
    function getConfig(bytes32 key) internal view returns (uint256 capacity, uint256 refillRate) {
        RateLimiterBucket storage b = rateLimiterStorage()._buckets[key];
        return (b.capacity, b.refillRate);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Internal — configures a bucket, resetting tokens and lastRefill.
    function _configure(bytes32 key, uint256 capacity, uint256 refillRate) internal {
        if (capacity == 0 || refillRate == 0) revert IRateLimiter.RateLimitInvalidConfig();
        RateLimiterBucket storage b = rateLimiterStorage()._buckets[key];
        b.capacity = capacity;
        b.refillRate = refillRate;
        b.tokens = capacity;
        b.lastRefill = uint48(block.timestamp);
        emit IRateLimiter.RateLimitConfigured(key, capacity, refillRate);
    }

    /// @notice Internal — refills and deducts tokens, reverts on insufficient balance.
    function _consume(bytes32 key, uint256 amount) internal {
        RateLimiterBucket storage b = rateLimiterStorage()._buckets[key];
        if (b.capacity == 0) revert IRateLimiter.RateLimitNotConfigured(key);

        uint256 available = _refill(b);
        if (available < amount) revert IRateLimiter.RateLimitExceeded(key, amount, available);

        uint256 remaining = available - amount;
        b.tokens = remaining;

        emit IRateLimiter.RateLimitConsumed(key, ContextLib.msgSender(), amount, remaining);
    }

    /// @notice Internal — computes refilled token count (min of capacity and tokens + accrued).
    /// @dev Does NOT write to storage.
    function _currentTokens(RateLimiterBucket storage b) internal view returns (uint256) {
        uint256 elapsed = block.timestamp - uint256(b.lastRefill);
        uint256 accrued = elapsed * b.refillRate;
        uint256 total = b.tokens + accrued;
        return total > b.capacity ? b.capacity : total;
    }

    /// @notice Internal — persists the refilled token amount and updates lastRefill timestamp.
    /// @return available The token count after refilling.
    function _refill(RateLimiterBucket storage b) internal returns (uint256 available) {
        available = _currentTokens(b);
        b.tokens = available;
        b.lastRefill = uint48(block.timestamp);
    }
}
