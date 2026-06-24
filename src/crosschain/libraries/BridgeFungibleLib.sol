// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IBridgeFungible} from "@lattice/interfaces/IBridgeFungible.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

/// @dev 0x28dcc8d8 is `type(IBridgeFungible).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x28dcc8d8), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IBRIDGEFUNGIBLE_SLOT = 0xc98ec5eb76ed7701e7884a55fd8dcc6ba54f192d7f68011281537265c16215d4;

/// @dev Handler tag both fungible bridges register/dispatch under: `bytes4(keccak256("lattice.crosschain.BridgeFungible"))`.
bytes4 constant FUNGIBLE_BRIDGE_TAG = 0xde362b7d;

/// @title BridgeFungibleLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `BridgeFungible` v5.6.1
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/crosschain/bridges/abstract/BridgeFungible.sol).
/// @notice Stateless shared helpers for the fungible bridge facets: the shared ERC-165 registration, the
///         common payload codec (interop-compatible with OZ's encoding), and USDT-safe ERC-20 transfers.
/// @dev No storage of its own. The on-the-wire payload is `abi.encode(fromInteropAddr, toAddrBytes, amount)`,
///      prefixed by {FUNGIBLE_BRIDGE_TAG} so the {CrosschainLink} dispatcher routes it to the bridge.
library BridgeFungibleLib {
    /// @notice Writes `true` to the ERC-165 map slot for IBridgeFungible (shared by both bridges).
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IBRIDGEFUNGIBLE_SLOT, true)
        }
    }

    /// @notice Splits a full interoperable `to` into its chain-only routing key and raw address bytes.
    /// @dev Validates the address part is exactly 20 bytes HERE (on send, before any funds move), so a
    ///      malformed recipient reverts instead of locking/burning funds that the inbound 20-byte decode
    ///      could never credit (send/receive symmetry).
    function splitDestination(bytes memory to) internal pure returns (bytes memory chain, bytes memory addr) {
        bytes2 chainType;
        bytes memory chainReference;
        (chainType, chainReference, addr) = InteroperableAddress.parseV1(to);
        if (addr.length != 20) revert IBridgeFungible.BridgeInvalidRecipient();
        chain = InteroperableAddress.formatV1(chainType, chainReference, hex"");
    }

    /// @notice Builds the tagged outbound payload (source-chain `from` interop addr, dest addr bytes, amount).
    function buildPayload(address from, bytes memory toAddr, uint256 amount) internal view returns (bytes memory) {
        return bytes.concat(
            FUNGIBLE_BRIDGE_TAG, abi.encode(InteroperableAddress.formatEvmV1(block.chainid, from), toAddr, amount)
        );
    }

    /// @notice Decodes a tag-stripped inbound payload. Reverts if the destination is not a 20-byte address.
    function decodeInbound(bytes calldata payload)
        internal
        pure
        returns (bytes memory from, address to, uint256 amount)
    {
        bytes memory toBinary;
        (from, toBinary, amount) = abi.decode(payload, (bytes, bytes, uint256));
        if (toBinary.length != 20) revert IBridgeFungible.BridgeInvalidRecipient();
        to = address(bytes20(toBinary));
    }

    /// @notice ERC-20 `transfer` that tolerates no-return-data tokens (USDT) and reverts on failure.
    function safeTransfer(address token, address to, uint256 amount) internal {
        _call(token, abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
    }

    /// @notice Pulls EXACTLY `amount` of `token` from `from` into this contract; reverts if the measured
    ///         balance delta differs (rejects fee-on-transfer tokens, which would break the 1:1 invariant).
    function pullExact(address token, address from, uint256 amount) internal {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        _call(token, abi.encodeWithSelector(IERC20.transferFrom.selector, from, address(this), amount));
        uint256 received = IERC20(token).balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert IBridgeFungible.BridgeAmountMismatch(amount, received);
    }

    /// @dev Low-level ERC-20 call: reverts on a failed call or an explicit `false` return.
    function _call(address token, bytes memory data) private {
        (bool ok, bytes memory ret) = token.call(data);
        if (!ok || (ret.length > 0 && !abi.decode(ret, (bool)))) {
            revert IBridgeFungible.BridgeTransferFailed(token);
        }
    }
}
