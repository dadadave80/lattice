// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAggregatorV3} from "@lattice/interfaces/external/chainlink/IAggregatorV3.sol";
import {IOracleGuard} from "@lattice/interfaces/oracles/IOracleGuard.sol";
import {IPriceOracleReader} from "@lattice/interfaces/oracles/IPriceOracleReader.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.OracleGuard")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ORACLE_GUARD_STORAGE_SLOT = 0xcb4d3b20d6a2c3be74f0770f2a6fab88f83473f0767b2765ccc6af180a66bc00;

/// @dev 0x33a1a017 is `type(IOracleGuard).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x33a1a017), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IORACLEGUARD_SLOT = 0x41da0c252d134ba14fd7bb076efcd912935e2490fdd095fda46ea7b4ab0cb258;

/// @notice Guard configuration of a single key.
struct GuardedFeed {
    /// @notice The adapter (or adapter diamond) whose `latestAnswer(key)` is read; `address(0)` = unconfigured.
    address oracle;
    /// @notice Lowest accepted WAD answer.
    int256 minAnswer;
    /// @notice Highest accepted WAD answer (`(0, 0)` disables the bounds).
    int256 maxAnswer;
}

/// @notice ERC-7201 namespaced storage for OracleGuard.
/// @custom:storage-location erc7201:lattice.storage.OracleGuard
struct OracleGuardStorage {
    address _sequencerFeed;
    uint48 _gracePeriod;
    mapping(bytes32 key => GuardedFeed) _feeds;
}

/// @title OracleGuardLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink (https://docs.chain.link/data-feeds/l2-sequencer-feeds)
/// @notice Library behind the OracleGuard facet: an opt-in L2 sequencer-uptime check and per-key WAD bounds
///         applied on top of any {IPriceOracleReader} adapter. See {IOracleGuard} for the full semantics.
library OracleGuardLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for OracleGuard.
    function oracleGuardStorage() internal pure returns (OracleGuardStorage storage $) {
        assembly {
            $.slot := ORACLE_GUARD_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IOracleGuard ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __OracleGuard_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IOracleGuard.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IORACLEGUARD_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the oracle's WAD answer for `key` after the sequencer and bounds checks.
    /// @param key The feed identifier.
    /// @return answerWad The checked price scaled to 1e18.
    function guardedAnswer(bytes32 key) internal view returns (int256 answerWad) {
        GuardedFeed storage f = oracleGuardStorage()._feeds[key];
        address oracle = f.oracle;
        if (oracle == address(0)) revert IOracleGuard.OracleGuardKeyNotConfigured(key);

        checkSequencerUptime();
        answerWad = IPriceOracleReader(oracle).latestAnswer(key);
        if (answerWad <= 0) revert IOracleGuard.OracleGuardInvalidAnswer(key, answerWad);

        int256 minAnswer = f.minAnswer;
        int256 maxAnswer = f.maxAnswer;
        if ((minAnswer != 0 || maxAnswer != 0) && (answerWad < minAnswer || answerWad > maxAnswer)) {
            revert IOracleGuard.OracleGuardAnswerOutOfBounds(key, answerWad, minAnswer, maxAnswer);
        }
    }

    /// @notice Reverts unless the sequencer is up and past its grace period. No-op while no feed is set.
    function checkSequencerUptime() internal view {
        OracleGuardStorage storage $ = oracleGuardStorage();
        address feed = $._sequencerFeed;
        if (feed == address(0)) return;

        (, int256 status, uint256 startedAt,,) = IAggregatorV3(feed).latestRoundData();
        if (status != 0 || startedAt == 0) revert IOracleGuard.OracleGuardSequencerDown(status, startedAt);

        uint256 gracePeriod = $._gracePeriod;
        // A future `startedAt` is treated as inside the grace period rather than underflowing.
        if (startedAt > block.timestamp || block.timestamp - startedAt <= gracePeriod) {
            revert IOracleGuard.OracleGuardGracePeriodNotOver(startedAt, gracePeriod);
        }
    }

    /// @notice Returns the sequencer-uptime configuration.
    function getSequencerConfig() internal view returns (address sequencerFeed, uint48 gracePeriod) {
        OracleGuardStorage storage $ = oracleGuardStorage();
        return ($._sequencerFeed, $._gracePeriod);
    }

    /// @notice Returns the guard configuration of `key`.
    function getGuardedFeed(bytes32 key) internal view returns (address oracle, int256 minAnswer, int256 maxAnswer) {
        GuardedFeed storage f = oracleGuardStorage()._feeds[key];
        return (f.oracle, f.minAnswer, f.maxAnswer);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the sequencer-uptime feed and grace period. `address(0)` disables the check.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE. A non-zero feed requires a non-zero grace period.
    function setSequencerConfig(address sequencerFeed, uint48 gracePeriod) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (sequencerFeed != address(0) && gracePeriod == 0) revert IOracleGuard.OracleGuardInvalidConfig();

        OracleGuardStorage storage $ = oracleGuardStorage();
        $._sequencerFeed = sequencerFeed;
        $._gracePeriod = gracePeriod;
        emit IOracleGuard.SequencerConfigSet(sequencerFeed, gracePeriod);
    }

    /// @notice Configures the oracle and WAD bounds of `key`.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE. Requires a non-zero oracle and `0 <= minAnswer <= maxAnswer`.
    function setGuardedFeed(bytes32 key, address oracle, int256 minAnswer, int256 maxAnswer) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (oracle == address(0) || minAnswer < 0 || minAnswer > maxAnswer) {
            revert IOracleGuard.OracleGuardInvalidConfig();
        }

        oracleGuardStorage()._feeds[key] = GuardedFeed({oracle: oracle, minAnswer: minAnswer, maxAnswer: maxAnswer});
        emit IOracleGuard.GuardedFeedSet(key, oracle, minAnswer, maxAnswer);
    }

    /// @notice Removes the guard configuration of `key`.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    function removeGuardedFeed(bytes32 key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        delete oracleGuardStorage()._feeds[key];
        emit IOracleGuard.GuardedFeedRemoved(key);
    }
}
