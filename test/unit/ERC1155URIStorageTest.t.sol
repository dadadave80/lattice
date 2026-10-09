// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC1155URIStorage} from "@lattice-script/base/tokens/DeployERC1155URIStorage.s.sol";
import {ERC1155TestBase} from "@lattice-test/base/ERC1155TestBase.sol";
import {ERC1155TestFacet} from "@lattice-test/helpers/ERC1155TestFacet.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IERC1155URIStorage} from "@lattice/interfaces/tokens/IERC1155URIStorage.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";
import {ERC1155URIStorage} from "@lattice/tokens/ERC1155/ERC1155URIStorage.sol";

/// @title ERC1155URIStorageTest
/// @notice Exercises the {ERC1155URIStorage} facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployERC1155URIStorage} script: base ERC-1155 + the URI-storage facet (Add setters, Replace `uri`) +
///         AccessControl. Every call routes through the diamond's `delegatecall` dispatch.
contract ERC1155URIStorageTest is ERC1155TestBase {
    ERC1155URIStorage internal uriStorage;

    address internal admin = address(0xA);
    address internal stranger = address(0xBEEF);

    string internal constant TEMPLATE = "https://example.com/{id}.json";

    event URI(string value, uint256 indexed id);

    function setUp() public override {
        DeployERC1155URIStorage d = new DeployERC1155URIStorage();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = d.buildCuts(TEMPLATE, admin);
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC1155(diamond);
        helper = ERC1155TestFacet(diamond);
        uriStorage = ERC1155URIStorage(diamond);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               RESOLUTION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice With no per-token URI, `uri` falls back to the ERC-1155 template.
    function test_UriFallsBackToTemplate() public view {
        assertEq(token.uri(1), TEMPLATE);
    }

    /// @notice A per-token URI overrides the template; the base URI is empty by default.
    function test_PerTokenUriOverridesTemplate() public {
        vm.prank(admin);
        uriStorage.setURI(1, "ipfs://token-one");
        assertEq(token.uri(1), "ipfs://token-one");
        assertEq(token.uri(2), TEMPLATE, "other ids keep the template");
    }

    /// @notice The base URI prefixes per-token URIs only (OZ concatenation semantics).
    function test_BaseUriPrefixesPerTokenUriOnly() public {
        vm.startPrank(admin);
        uriStorage.setBaseURI("ipfs://base/");
        uriStorage.setURI(1, "one.json");
        vm.stopPrank();

        assertEq(token.uri(1), "ipfs://base/one.json");
        assertEq(token.uri(2), TEMPLATE, "the base URI never prefixes the template");
    }

    /// @notice A base URI set after a per-token URI applies retroactively.
    function test_BaseUriSetLaterAppliesToExistingTokenUri() public {
        vm.prank(admin);
        uriStorage.setURI(1, "one.json");
        vm.prank(admin);
        uriStorage.setBaseURI("ar://");
        assertEq(token.uri(1), "ar://one.json");
    }

    /// @notice Setting an empty per-token URI clears it, restoring the template fallback.
    function test_EmptyTokenUriRestoresFallback() public {
        vm.startPrank(admin);
        uriStorage.setBaseURI("ipfs://base/");
        uriStorage.setURI(1, "one.json");
        uriStorage.setURI(1, "");
        vm.stopPrank();
        assertEq(token.uri(1), TEMPLATE);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice `setURI` emits `URI` with the RESOLVED uri (base + token URI), as OpenZeppelin does.
    function test_SetUriEmitsResolvedUri() public {
        vm.prank(admin);
        uriStorage.setBaseURI("ipfs://base/");

        vm.expectEmit(true, false, false, true, diamond);
        emit URI("ipfs://base/one.json", 1);
        vm.prank(admin);
        uriStorage.setURI(1, "one.json");
    }

    /// @notice Clearing a per-token URI emits `URI` with the template it falls back to.
    function test_ClearingUriEmitsTemplate() public {
        vm.prank(admin);
        uriStorage.setURI(7, "seven");

        vm.expectEmit(true, false, false, true, diamond);
        emit URI(TEMPLATE, 7);
        vm.prank(admin);
        uriStorage.setURI(7, "");
    }

    /// @notice `setBaseURI` emits nothing (OpenZeppelin's `_setBaseURI` emits nothing).
    function test_SetBaseUriEmitsNothing() public {
        vm.recordLogs();
        vm.prank(admin);
        uriStorage.setBaseURI("ipfs://base/");
        assertEq(vm.getRecordedLogs().length, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ACCESS CONTROL
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetUriUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, DEFAULT_ADMIN_ROLE
            )
        );
        vm.prank(stranger);
        uriStorage.setURI(1, "evil");
        assertEq(token.uri(1), TEMPLATE);
    }

    function test_SetBaseUriUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, DEFAULT_ADMIN_ROLE
            )
        );
        vm.prank(stranger);
        uriStorage.setBaseURI("evil://");
    }

    /// @notice A newly granted admin may set URIs; the recipe seeded `admin` with `DEFAULT_ADMIN_ROLE`.
    function test_GrantedAdminCanSetUri() public {
        assertTrue(AccessControl(diamond).hasRole(DEFAULT_ADMIN_ROLE, admin));
        vm.prank(admin);
        AccessControl(diamond).grantRole(DEFAULT_ADMIN_ROLE, stranger);
        vm.prank(stranger);
        uriStorage.setURI(1, "granted");
        assertEq(token.uri(1), "granted");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           SEAM AND INTROSPECTION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The recipe routes `uri(uint256)` (0x0e89341c) to the URI-storage facet, not the base facet, and
    ///         the setters to the same facet.
    function test_UriSelectorRoutesToUriStorageFacet() public view {
        address uriFacet = DiamondLoupeFacet(diamond).facetAddress(IERC1155URIStorage.setURI.selector);
        assertTrue(uriFacet != address(0));
        assertEq(DiamondLoupeFacet(diamond).facetAddress(ERC1155URIStorage.uri.selector), uriFacet);
        assertEq(DiamondLoupeFacet(diamond).facetAddress(IERC1155URIStorage.setBaseURI.selector), uriFacet);
        assertTrue(DiamondLoupeFacet(diamond).facetAddress(ERC1155.balanceOf.selector) != uriFacet);
    }

    function test_SupportsInterface() public view {
        assertEq(type(IERC1155URIStorage).interfaceId, bytes4(0xd3dc4451));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC1155URIStorage).interfaceId));
        assertTrue(ERC165Facet(diamond).supportsInterface(0x0e89341c)); // IERC1155MetadataURI (base)
        assertTrue(ERC165Facet(diamond).supportsInterface(0xd9b67a26)); // IERC1155 (base)
    }

    /// @notice Transfers are unaffected by the extension.
    function test_TransfersStillWork() public {
        helper.mint(admin, 1, 10, "");
        vm.prank(admin);
        token.safeTransferFrom(admin, stranger, 1, 4, "");
        assertEq(token.balanceOf(stranger, 1), 4);
    }

    /// @notice Any per-token URI resolves to base ++ tokenURI.
    function testFuzz_UriConcatenation(string calldata base, string calldata tokenUri, uint256 id) public {
        vm.assume(bytes(tokenUri).length > 0);
        vm.startPrank(admin);
        uriStorage.setBaseURI(base);
        uriStorage.setURI(id, tokenUri);
        vm.stopPrank();
        assertEq(token.uri(id), string.concat(base, tokenUri));
    }
}
