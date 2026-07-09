// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BridgeERC20Lib} from "@lattice/crosschain/libraries/BridgeERC20Lib.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {IERC7786MessageHandler} from "@lattice/interfaces/crosschain/IERC7786MessageHandler.sol";

/// @title BridgeERC20
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `BridgeERC20` v5.6.1 (https://github.com/OpenZeppelin/openzeppelin-contracts)
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/crosschain/bridges/BridgeERC20.sol)
/// @notice Custody bridge facet for legacy ERC-20 tokens: locks tokens on `crosschainTransfer`, releases
///         them on an inbound message. Registered as a handler on a co-mounted {CrosschainLink} facet.
/// @dev Stateless delegator — logic/storage live in {BridgeERC20Lib}. `processMessage` is callable only via
///      the Diamond's own authenticated `receiveMessage` dispatch (it enforces `msg.sender == address(this)`).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin
contract BridgeERC20 is IBridgeFungible, IERC7786MessageHandler {
    /// @inheritdoc IBridgeFungible
    function crosschainTransfer(bytes calldata to, uint256 amount) external virtual override returns (bytes32 sendId) {
        return BridgeERC20Lib.crosschainTransfer(to, amount);
    }

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
        BridgeERC20Lib.processMessage(receiveId, payload);
    }

    /// @notice The bridged ERC-20 token.
    function token() external view virtual returns (address) {
        return BridgeERC20Lib.token();
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect BridgeERC20 methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `crosschainTransfer(bytes,uint256)` 0x28dcc8d8
    ///      `processMessage(bytes32,bytes,bytes)` 0x902d5027
    ///      `token()` 0xfc0c546a
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"28dcc8d8902d5027fc0c546a";
    }
}
