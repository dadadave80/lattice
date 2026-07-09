// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGroth16Verifier} from "@lattice/interfaces/privacy/IGroth16Verifier.sol";
import {Groth16VerifierLib} from "@lattice/privacy/libraries/Groth16VerifierLib.sol";

/// @title Groth16Verifier
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from snarkjs (https://github.com/iden3/snarkjs)
/// @notice Stateless Diamond facet exposing a GENERIC Groth16 verifier over BN254. The verifying key is
///         a parameter, so one deployment verifies proofs for any circuit — the primitive the ZK
///         privacy modules plug their circuit's key into.
/// @dev All logic lives in {Groth16VerifierLib}. Pure verification (view): no state beyond the ERC-165
///      registration written at init.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Generalized from the snarkjs (iden3) Groth16 verifier template (GPL-3.0),
///         reimplemented under MIT with the key as a parameter; pairing math is the standard BN254 check.
contract Groth16Verifier is IGroth16Verifier {
    /// @inheritdoc IGroth16Verifier
    function verifyProof(VerifyingKey calldata vk, Proof calldata proof, uint256[] calldata input)
        external
        view
        virtual
        returns (bool)
    {
        return Groth16VerifierLib.verifyProof(vk, proof, input);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect Groth16Verifier methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `verifyProof((uint256[2],uint256[2][2],uint256[2][2],uint256[2][2],uint256[2][]),(uint256[2],uint256[2][2],uint256[2]),uint256[])` 0x6d832d8e
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"6d832d8e";
    }
}
