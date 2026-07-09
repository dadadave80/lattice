// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AcrossBridgeAdapterLib} from "@lattice/crosschain/libraries/AcrossBridgeAdapterLib.sol";
import {IAcrossBridgeAdapter} from "@lattice/interfaces/crosschain/IAcrossBridgeAdapter.sol";
import {AcrossMessageHandler} from "@lattice/interfaces/external/AcrossMessageHandler.sol";

/// @title AcrossBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Across (https://github.com/across-protocol/contracts)
/// @notice Across v3 intent/optimistic token-bridge facet: `deposit` escrows the input token on this chain
///         toward an ERC-7930 recipient (a relayer fronts the output token on the destination and is later
///         reimbursed via UMA optimistic settlement); `handleV3AcrossMessage` is the SpokePool-authenticated
///         fill-time delivery hook. Across is an INTENT bridge with NO guaranteed fill — an unfilled deposit
///         past `fillDeadline` is refunded ON THIS CHAIN to the depositor (always the calling user). It is NOT
///         an ERC-7786 message gateway (no `receiveId`, no source attribution) and NOT burn/mint — this facet
///         is deliberately not an `IERC7786GatewaySource` and never routes through OpenBridge.
/// @dev Stateless delegator — logic/storage live in {AcrossBridgeAdapterLib}. The outbound deposit is
///      `nonReentrant` with strict CEI and exact-amount approval hygiene and is NOT payable (ERC-20 inputs only
///      in v1; native ETH users wrap first). Inbound fills are relayer-pushed and optimistic — NOT yet
///      UMA-finalized when the hook runs (treat received funds/messages as reversible-until-finalized).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Across
contract AcrossBridgeAdapter is IAcrossBridgeAdapter, AcrossMessageHandler {
    /// @inheritdoc IAcrossBridgeAdapter
    function deposit(DepositParams calldata params) external virtual {
        AcrossBridgeAdapterLib.deposit(params);
    }

    /// @inheritdoc IAcrossBridgeAdapter
    function handleV3AcrossMessage(address tokenSent, uint256 amount, address relayer, bytes calldata message)
        external
        virtual
        override(IAcrossBridgeAdapter, AcrossMessageHandler)
    {
        AcrossBridgeAdapterLib.handleV3AcrossMessage(tokenSent, amount, relayer, message);
    }

    /// @inheritdoc IAcrossBridgeAdapter
    function spokePool() external view virtual returns (address) {
        return AcrossBridgeAdapterLib.spokePool();
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect AcrossBridgeAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `deposit((bytes,bytes32,address,uint256,uint256,uint256,bytes32,uint32,uint32,uint32,bytes))` 0xd3948fec
    ///      `handleV3AcrossMessage(address,uint256,address,bytes)` 0x3a5be8cb
    ///      `spokePool()` 0xafdac3d6
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"d3948fec3a5be8cbafdac3d6";
    }
}
