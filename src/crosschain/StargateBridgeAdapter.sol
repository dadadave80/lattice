// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StargateBridgeAdapterLib} from "@lattice/crosschain/libraries/StargateBridgeAdapterLib.sol";
import {IStargateBridgeAdapter} from "@lattice/interfaces/crosschain/IStargateBridgeAdapter.sol";

/// @title StargateBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Stargate (https://github.com/stargate-protocol/stargate-v2)
/// @notice Stargate v2 pooled-liquidity token-bridge facet — the third token rail beside CCTP (burn/mint) and
///         Across (intent): `sendToken` pulls the token from the caller and deposits it into the LOCAL
///         Stargate pool (unified liquidity), which has the DESTINATION pool credit the ERC-7930 recipient.
///         OUTBOUND-ONLY for plain transfers: the destination-side LayerZero receiver is Stargate's own pool,
///         NOT a Lattice facet — there is no inbound surface, no `receiveId`, no source attribution, and this
///         facet is never routed through OpenBridge. `composeMsg`/`lzCompose` and bus mode are DEFERRED.
/// @dev Stateless delegator — logic/storage live in {StargateBridgeAdapterLib}. The outbound send is
///      `nonReentrant` with strict CEI, a quoted fee PRECHECK, exact-amount approval hygiene, and a dust
///      sweep (pools truncate to shared decimals — any un-debited remainder returns to the caller in the same
///      call). `msg.value` is the LayerZero fee EXCLUSIVELY (ERC-20 pools only in v1; `StargatePoolNative` is
///      deferred); excess fee refunds go to the calling user, never the diamond.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Stargate
contract StargateBridgeAdapter is IStargateBridgeAdapter {
    /// @inheritdoc IStargateBridgeAdapter
    function sendToken(SendTokenParams calldata p)
        external
        payable
        virtual
        returns (bytes32 guid, uint256 amountSentLD, uint256 amountReceivedLD)
    {
        return StargateBridgeAdapterLib.sendToken(p);
    }

    /// @inheritdoc IStargateBridgeAdapter
    function registerStargateEid(uint256 chainId, uint32 eid) external virtual {
        StargateBridgeAdapterLib.registerStargateEid(chainId, eid);
    }

    /// @inheritdoc IStargateBridgeAdapter
    function registerPool(address token, address pool) external virtual {
        StargateBridgeAdapterLib.registerPool(token, pool);
    }

    /// @inheritdoc IStargateBridgeAdapter
    function stargateEidOf(uint256 chainId) external view virtual returns (uint32) {
        return StargateBridgeAdapterLib.stargateEidOf(chainId);
    }

    /// @inheritdoc IStargateBridgeAdapter
    function stargateChainIdOf(uint32 eid) external view virtual returns (uint256) {
        return StargateBridgeAdapterLib.stargateChainIdOf(eid);
    }

    /// @inheritdoc IStargateBridgeAdapter
    function poolOf(address token) external view virtual returns (address) {
        return StargateBridgeAdapterLib.poolOf(token);
    }

    /// @inheritdoc IStargateBridgeAdapter
    function quoteSendFee(SendTokenParams calldata p) external view virtual returns (uint256 nativeFee) {
        return StargateBridgeAdapterLib.quoteSendFee(p);
    }
}
