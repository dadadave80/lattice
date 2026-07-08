// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPlonkVerifier} from "@lattice/interfaces/privacy/IPlonkVerifier.sol";
import {PlonkVerifierLib} from "@lattice/privacy/libraries/PlonkVerifierLib.sol";

/// @title PlonkVerifier
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from snarkjs (https://github.com/iden3/snarkjs)
/// @notice Stateless Diamond facet exposing a GENERIC PLONK verifier over BN254. The verifying key is a
///         parameter, so one deployment verifies proofs for any circuit — a reusable verifier primitive
///         for the ZK privacy modules and consumers who bring PLONK circuits.
/// @dev All logic lives in {PlonkVerifierLib}. Pure verification (view): no state beyond the ERC-165
///      registration written at init.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Generalized from the snarkjs (iden3) PLONK verifier template (GPL-3.0),
///         reimplemented under MIT with the key as a parameter; verification follows eprint 2019/953.
contract PlonkVerifier is IPlonkVerifier {
    /// @inheritdoc IPlonkVerifier
    function verifyProof(VerifyingKey calldata vk, Proof calldata proof, uint256[] calldata input)
        external
        view
        virtual
        returns (bool)
    {
        return PlonkVerifierLib.verifyProof(vk, proof, input);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect PlonkVerifier methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `verifyProof((uint256[2],uint256[2],uint256[2],uint256[2],uint256[2],uint256[2],uint256[2],uint256[2],uint256,uint256,uint256,uint256,uint256[2][2]),(uint256[2],uint256[2],uint256[2],uint256[2],uint256[2],uint256[2],uint256[2],uint256[2],uint256[2],uint256,uint256,uint256,uint256,uint256,uint256),uint256[])` 0x5d484314
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"5d484314";
    }
}
