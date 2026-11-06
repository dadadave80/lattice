// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title CoreCompositionMetadata
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from diamond-lib (https://github.com/dadadave80/diamond-lib)
/// @notice Composition records for the five unmodified, pinned diamond-lib release artifacts.
/// @dev Provenance: diamond-lib commit 393435fbd01a85f9626cd62f436cdebf90ecdfdf
///      (https://github.com/dadadave80/diamond-lib/tree/393435fbd01a85f9626cd62f436cdebf90ecdfdf/src).
///      This is an explicit upstream overlay, not compiler-emitted NatSpec. First-party entries must use
///      their own rawMetadata. A submodule update requires reviewing these five records against upstream.
library CoreCompositionMetadata {
    function devdoc(string memory name) internal pure returns (string memory) {
        bytes32 key = keccak256(bytes(name));
        if (key == keccak256("DiamondCutFacet")) {
            return _facet(
                "OwnableFacet convention ownership-management;",
                "upgrade",
                "diamondCut((address,uint8,bytes4[])[],address,bytes);",
                "diamond.lib.storage;",
                "DiamondIntrospectionInit"
            );
        }
        if (key == keccak256("DiamondLoupeFacet")) {
            return _facet("none;", "none", "none;", "none;", "DiamondIntrospectionInit");
        }
        if (key == keccak256("ERC165Facet")) {
            return _facet("none;", "none", "none;", "none;", "DiamondIntrospectionInit");
        }
        if (key == keccak256("OwnableFacet")) {
            return _facet(
                "none;",
                "none",
                "none;",
                "slot:0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff74873927;derived:OwnableHandover;",
                "none"
            );
        }
        if (key == keccak256("MultiInit")) {
            return '{"output":{"devdoc":{"custom:lattice-kind":"bundle","methods":{"multiInit(address[],bytes[])":{"custom:lattice-initializes":"caller-defined;","custom:lattice-after":"none;","custom:lattice-same-call":"Initializable convention called-steps-may-require-window;","custom:lattice-sequence":"caller-defined;","custom:lattice-param":"_initAddresses rule=ordered-code-bearing-addresses-zero-terminates;_initData rule=length-matches-initAddresses;"}}}}}';
        }
        return "";
    }

    function _facet(
        string memory requires_,
        string memory family,
        string memory owns,
        string memory touches,
        string memory init
    ) private pure returns (string memory) {
        return string.concat(
            '{"output":{"devdoc":{"custom:lattice-requires":"',
            requires_,
            '","custom:lattice-family":"',
            family,
            '","custom:lattice-owns":"',
            owns,
            '","custom:lattice-touches":"',
            touches,
            '","custom:lattice-init":"',
            init,
            '","custom:lattice-seam":"none;"}}}'
        );
    }
}
