// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IERC8153
/// @author Vendored minimal subset of ERC-8153 Draft (https://eips.ethereum.org/EIPS/eip-8153)
/// @notice Facet-introspection half of ERC-8153: a facet self-reports its cuttable function selectors.
/// @dev ERC-8153 is a DRAFT standard - only `exportSelectors()` is vendored; Lattice stays EIP-2535 and
///      uses this to build `FacetCut`s. Implementations MUST be pure/deterministic, return a tightly
///      packed sequence of 4-byte selectors (length % 4 == 0, no duplicates), and MUST NOT include
///      `exportSelectors()` (0x0ef22643) itself - the diamond never exposes it. diamond-lib >=0.2.0 ships
///      the byte-identical interface as `IFacet` (under the lib's interfaces directory) and its stock
///      facets implement it; the two are ABI-interchangeable (same selector), this vendored copy simply
///      predates the upstream one and is kept so `src/` facets need no dependency on the lib's path.
interface IERC8153 {
    /// @notice This facet's cuttable selectors, tightly packed (4 bytes per selector).
    function exportSelectors() external pure returns (bytes memory selectors);
}
