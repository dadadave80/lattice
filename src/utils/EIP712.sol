// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";

/// @title EIP712
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/EIP712.sol)
/// @notice Thin facet that exposes the ERC-5267 `eip712Domain()` view.
/// @dev All signing helpers (domainSeparatorV4, hashTypedDataV4) are internal
///      functions in EIP712Lib and consumed by other modules (e.g. Permit variants).
///      Only the ERC-5267 discovery function needs a public entry point.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract EIP712 {
    /// @notice Returns the ERC-5267 domain descriptor for this contract.
    /// @dev Delegates to EIP712Lib.eip712Domain().
    function eip712Domain()
        public
        view
        virtual
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return EIP712Lib.eip712Domain();
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect EIP712 methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `eip712Domain()` 0x84b0196e
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"84b0196e";
    }
}
