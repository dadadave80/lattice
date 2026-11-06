// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {RecipeGuards} from "@lattice-test/composability/RecipeGuards.sol";
import {IEIP712} from "@lattice/interfaces/utils/IEIP712.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";
import {EIP712} from "@lattice/utils/EIP712.sol";

contract RoutingClaimInit is DiamondIntrospectionInit {
    function init() external {
        ERC165Lib.registerInterface();
        ERC165Lib.erc165Storage().supportedInterfaces[type(IEIP712).interfaceId] = true;
    }
}

/// @notice Self-tests prove the shared recipe guard rejects a claimed but unrouted interface.
contract RecipeInterfaceRoutingTest is RecipeGuards {
    function test_HarnessRejectsUnroutedClaim() public {
        address diamond = _fixture(false);
        vm.expectRevert(
            abi.encodeWithSelector(
                UnroutedInterfaceSelector.selector,
                "src/interfaces/utils/IEIP712.sol:IEIP712",
                IEIP712.eip712Domain.selector
            )
        );
        this.checkRoutes(diamond);
    }

    function test_HarnessAcceptsRoutedClaim() public {
        _assertInterfacesRouted(_fixture(true));
    }

    function checkRoutes(address diamond) external view {
        _assertInterfacesRouted(diamond);
    }

    function _fixture(bool includeView) private returns (address diamond) {
        FacetCut[] memory cuts = new FacetCut[](includeView ? 3 : 2);
        bytes4[] memory erc165 = new bytes4[](1);
        erc165[0] = ERC165Facet.supportsInterface.selector;
        cuts[0] = FacetCut(address(new ERC165Facet()), FacetCutAction.Add, erc165);
        bytes4[] memory loupe = new bytes4[](4);
        loupe[0] = DiamondLoupeFacet.facets.selector;
        loupe[1] = DiamondLoupeFacet.facetAddresses.selector;
        loupe[2] = DiamondLoupeFacet.facetAddress.selector;
        loupe[3] = DiamondLoupeFacet.facetFunctionSelectors.selector;
        cuts[1] = FacetCut(address(new DiamondLoupeFacet()), FacetCutAction.Add, loupe);
        if (includeView) {
            bytes4[] memory domain = new bytes4[](1);
            domain[0] = IEIP712.eip712Domain.selector;
            cuts[2] = FacetCut(address(new EIP712()), FacetCutAction.Add, domain);
        }
        diamond = _assemble(cuts, address(new RoutingClaimInit()), abi.encodeCall(RoutingClaimInit.init, ()));
    }
}
