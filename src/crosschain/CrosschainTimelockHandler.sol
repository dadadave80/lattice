// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    CROSSCHAIN_TIMELOCK_TAG,
    CrosschainTimelockHandlerLib
} from "@lattice/crosschain/libraries/CrosschainTimelockHandlerLib.sol";
import {IERC7786MessageHandler} from "@lattice/interfaces/crosschain/IERC7786MessageHandler.sol";

/// @title CrosschainTimelockHandler
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Cross-chain governance handler facet: on an authenticated inbound ERC-7786 message routed by
///         {CrosschainLink}, schedules the encoded operation on the co-mounted {TimelockController}. This
///         realises remote governance — an L1 governor proposing a timelocked action on an L2 Diamond.
/// @dev Stateless delegator — no storage. Mount alongside {CrosschainLink} + {TimelockController}; register
///      this handler under {CROSSCHAIN_TIMELOCK_TAG} and grant the Diamond PROPOSER_ROLE. `processMessage`
///      is callable only via the Diamond's own `receiveMessage` dispatch (`msg.sender == address(this)`).
///      Payload: `abi.encode(address target, uint256 value, bytes data, bytes32 predecessor, bytes32 salt,
///      uint256 delay)`.
///
///      SECURITY: the linked counterpart is a full timelock proposer and can schedule ANY operation —
///      including grants on the Diamond's own roles (the timelock self-administers DEFAULT_ADMIN_ROLE).
///      The only safety net is the timelock delay plus a CANCELLER_ROLE held by a LOCAL guardian that is
///      NOT reachable through this same cross-chain channel. Deploy accordingly.
/// @custom:lattice-version 0.1.0
contract CrosschainTimelockHandler is IERC7786MessageHandler {
    /// @inheritdoc IERC7786MessageHandler
    function processMessage(
        bytes32 receiveId,
        bytes calldata,
        /*sender*/
        bytes calldata payload
    )
        external
        virtual
        override
    {
        CrosschainTimelockHandlerLib.processMessage(receiveId, payload);
    }

    /// @notice The handler tag this facet must be registered under on the {CrosschainLink} facet.
    function crosschainTimelockTag() external pure returns (bytes4) {
        return CROSSCHAIN_TIMELOCK_TAG;
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect CrosschainTimelockHandler methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `crosschainTimelockTag()` 0xae5501c0
    ///      `processMessage(bytes32,bytes,bytes)` 0x902d5027
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"ae5501c0902d5027";
    }
}
