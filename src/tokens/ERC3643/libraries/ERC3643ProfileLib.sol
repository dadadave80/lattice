// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, DiamondStorage} from "@diamond/libraries/DiamondLib.sol";
import {ERC3643Profile} from "@lattice/tokens/ERC3643/libraries/ERC3643Profile.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

error ERC3643UnexpectedHost(bytes32 actual);
error ERC3643UnexpectedFacet(address facet, bytes32 codeHash);
error ERC3643UnexpectedRoute(bytes4 selector, address facet);
error ERC3643MissingRoutes(uint256 actualMask, uint256 expectedMask);
error ERC3643ProfileOutsideInitialSetup();

/// @title ERC3643ProfileLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Specific closed-profile admission, invoked only by the trusted canonical initializer.
/// @dev No facet imports this library/data. No caller supplies approved hashes, selectors or init targets.
///      The general factory can execute arbitrary initializers; this is not a certificate for those flows.
library ERC3643ProfileLib {
    function validate(bool temporaryApproval) internal view {
        bytes32 slot = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(slot);
        if (InitializableLib.getInitializedVersion(slot) != 1) revert ERC3643ProfileOutsideInitialSetup();
        if (address(this).codehash != ERC3643Profile.HOST_CODEHASH) {
            revert ERC3643UnexpectedHost(address(this).codehash);
        }
        DiamondStorage storage ds = DiamondLib.diamondStorage();
        uint256 seen;
        for (uint256 i; i < ds.facetAddresses.length; ++i) {
            address facet = ds.facetAddresses[i];
            (uint256 index, bytes memory expected) = ERC3643Profile.expected(facet.codehash);
            if (
                index == type(uint256).max || (!temporaryApproval && index == ERC3643Profile.TEMPORARY_INDEX)
                    || (seen & (uint256(1) << index)) != 0
            ) revert ERC3643UnexpectedFacet(facet, facet.codehash);
            seen |= uint256(1) << index;
            bytes4[] memory actual = DiamondLib.facetToSelectors(ds, facet);
            if (actual.length * 4 != expected.length) revert ERC3643UnexpectedFacet(facet, facet.codehash);
            for (uint256 j; j < expected.length; j += 4) {
                bytes4 selector;
                assembly ("memory-safe") { selector := mload(add(add(expected, 32), j)) }
                if (DiamondLib.selectorToFacet(ds, selector) != facet) revert ERC3643UnexpectedRoute(selector, facet);
            }
        }
        uint256 required = ERC3643Profile.REQUIRED_MASK;
        if (temporaryApproval) required |= uint256(1) << ERC3643Profile.TEMPORARY_INDEX;
        if (seen != required) revert ERC3643MissingRoutes(seen, required);
    }
}
