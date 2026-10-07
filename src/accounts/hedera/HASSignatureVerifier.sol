// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HASSignatureVerifierLib} from "@lattice/accounts/hedera/HASSignatureVerifierLib.sol";
import {IHASSignatureVerifier} from "@lattice/interfaces/accounts/IHASSignatureVerifier.sol";

/// @title HASSignatureVerifier
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Diamond facet exposing HIP-632 native Hedera account signature verification (ED25519 + ECDSA, key
///         lists via the protobuf path) as two never-reverting views.
/// @dev Stateless delegator over HASSignatureVerifierLib. Only meaningful on Hedera.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Hedera
contract HASSignatureVerifier is IHASSignatureVerifier {
    /// @inheritdoc IHASSignatureVerifier
    function isAuthorizedRaw(address account, bytes32 messageHash, bytes calldata signature)
        external
        view
        virtual
        override
        returns (bool authorized)
    {
        return HASSignatureVerifierLib.isAuthorizedRaw(account, messageHash, signature);
    }

    /// @inheritdoc IHASSignatureVerifier
    function isAuthorized(address account, bytes calldata message, bytes calldata signatureMap)
        external
        view
        virtual
        override
        returns (bool authorized)
    {
        return HASSignatureVerifierLib.isAuthorized(account, message, signatureMap);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643). Order matches `forge inspect HASSignatureVerifier
    ///      methodIdentifiers` (alphabetical by signature); kept in exact parity by ExportSelectorsParityTest. Chunks:
    ///      `isAuthorized(address,bytes,bytes)` 0xb2526367
    ///      `isAuthorizedRaw(address,bytes32,bytes)` 0x249024ac
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"b2526367249024ac";
    }
}
