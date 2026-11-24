// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IERC7984Mintable} from "@lattice/interfaces/tokens/IERC7984Mintable.sol";
import {ERC7984MintableLib} from "@lattice/tokens/ERC7984/libraries/ERC7984MintableLib.sol";

/// @title ERC7984Mintable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin Confidential Contracts (https://github.com/OpenZeppelin/openzeppelin-confidential-contracts)
/// @notice Role-gated confidential mint facet for an ERC-7984 (confidential fungible token) diamond: a holder of
///         `ERC7984_MINTER_ROLE` mints an encrypted, proven amount to any account. Mount alongside the {ERC7984}
///         facet and an AccessControl facet.
/// @dev Stateless delegator; all logic, and every difference from OpenZeppelin, lives in {ERC7984MintableLib}.
/// @custom:lattice-source OpenZeppelin Confidential Contracts v0.5.3
/// @custom:lattice-requires AccessControl|AccessControlEnumerable|AccessControlTimed convention role-management-surface;
/// @custom:lattice-requires ERC7984 convention complete-token-surface;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.ERC7984;
/// @custom:lattice-seam none;
/// @custom:lattice-init ERC7984MintableInit
contract ERC7984Mintable is IERC7984Mintable {
    /// @inheritdoc IERC7984Mintable
    function confidentialMint(address to, externalEuint64 encryptedAmount, bytes calldata inputProof)
        external
        virtual
        returns (euint64 minted)
    {
        return ERC7984MintableLib.confidentialMint(to, encryptedAmount, inputProof);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC7984Mintable methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `confidentialMint(address,bytes32,bytes)` 0x1b4d3d0d
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"1b4d3d0d";
    }
}
