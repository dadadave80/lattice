// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RevertOptions} from "@lattice/interfaces/external/zetachain/IGatewayEVM.sol";

/// @title IZetaChainGatewayAttributes
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ZetaChain (https://github.com/zeta-chain/protocol-contracts)
/// @notice Attribute encodings for ZetaChain `sendMessage`; these are not callable facet functions.
interface IZetaChainGatewayAttributes {
    /// @notice Encodes one per-message override with `abi.encodeCall`. Both recovery addresses must be nonzero,
    ///         `callOnRevert` must be false, and the gas limit must be at most 2,000,000. The adapter wraps
    ///         `revertMessage` as `(senderInterop, recipientInterop, userData, nonce)` to preserve the caller.
    /// @dev Recovery consumers must authenticate the protocol caller, source adapter and source chain before
    ///      trusting the envelope. An envelope alone authenticates nothing; no `onRevert` callback is requested.
    function revertOptions(RevertOptions calldata options) external;
}
