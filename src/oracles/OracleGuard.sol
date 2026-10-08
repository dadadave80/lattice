// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IOracleGuard} from "@lattice/interfaces/oracles/IOracleGuard.sol";
import {OracleGuardLib} from "@lattice/oracles/libraries/OracleGuardLib.sol";

/// @title OracleGuard
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink (https://docs.chain.link/data-feeds/l2-sequencer-feeds)
/// @notice Diamond facet that serves guarded price reads over any Lattice price adapter: an opt-in Chainlink L2
///         sequencer-uptime check with a grace period, plus per-key WAD bounds.
/// @dev Stateless delegator — all logic and storage live in OracleGuardLib. Its selectors do not overlap the
///      adapters', so it can be cut next to an adapter (reading its own diamond) or into a separate diamond.
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source Chainlink
contract OracleGuard is IOracleGuard {
    /// @inheritdoc IOracleGuard
    function guardedAnswer(bytes32 key) external view virtual override returns (int256 answerWad) {
        return OracleGuardLib.guardedAnswer(key);
    }

    /// @inheritdoc IOracleGuard
    function checkSequencerUptime() external view virtual override {
        OracleGuardLib.checkSequencerUptime();
    }

    /// @inheritdoc IOracleGuard
    function getSequencerConfig() external view virtual override returns (address sequencerFeed, uint48 gracePeriod) {
        return OracleGuardLib.getSequencerConfig();
    }

    /// @inheritdoc IOracleGuard
    function getGuardedFeed(bytes32 key)
        external
        view
        virtual
        override
        returns (address oracle, int256 minAnswer, int256 maxAnswer)
    {
        return OracleGuardLib.getGuardedFeed(key);
    }

    /// @inheritdoc IOracleGuard
    function setSequencerConfig(address sequencerFeed, uint48 gracePeriod) external virtual override {
        OracleGuardLib.setSequencerConfig(sequencerFeed, gracePeriod);
    }

    /// @inheritdoc IOracleGuard
    function setGuardedFeed(bytes32 key, address oracle, int256 minAnswer, int256 maxAnswer) external virtual override {
        OracleGuardLib.setGuardedFeed(key, oracle, minAnswer, maxAnswer);
    }

    /// @inheritdoc IOracleGuard
    function removeGuardedFeed(bytes32 key) external virtual override {
        OracleGuardLib.removeGuardedFeed(key);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect OracleGuard methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `checkSequencerUptime()` 0x6244363c
    ///      `getGuardedFeed(bytes32)` 0x8ea079a7
    ///      `getSequencerConfig()` 0xb4eee64e
    ///      `guardedAnswer(bytes32)` 0x12ac8379
    ///      `removeGuardedFeed(bytes32)` 0x11bdc3e7
    ///      `setGuardedFeed(bytes32,address,int256,int256)` 0x20c84cb8
    ///      `setSequencerConfig(address,uint48)` 0x487205e4
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"6244363c8ea079a7b4eee64e12ac837911bdc3e720c84cb8487205e4";
    }
}
