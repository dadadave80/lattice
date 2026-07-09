// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC721URIStorageTestBase} from "@lattice-test/base/ERC721URIStorageTestBase.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";

/// @title ERC721URIStorageTest
/// @notice Exercises the ERC-721 per-token URI storage facet (EIP-4906) through a REAL {Diamond} assembled by
///         the ready-to-deploy {DeployERC721URIStorage} script (see {ERC721URIStorageTestBase}) — every call
///         routes through the diamond's `delegatecall` dispatch, not a flattened inheritance mock. `mint`/
///         `burn` and direct URI seeding come from the test-only {ERC721TestFacet} (`helper`); the admin-gated
///         `setTokenURI` and `supportsInterface` come from the cut-in production facets.
contract ERC721URIStorageTest is ERC721URIStorageTestBase {
    address alice = address(0x1);
    address bob = address(0x2);

    uint256 constant TOKEN_1 = 1;
    uint256 constant TOKEN_2 = 2;

    event MetadataUpdate(uint256 _tokenId);

    //*//////////////////////////////////////////////////////////////////////////
    //                             URI STORAGE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetTokenURIStoresURI() public {
        helper.mint(alice, TOKEN_1);

        helper.setTokenURIRaw(TOKEN_1, "ipfs://QmHash1");

        assertEq(token.tokenURI(TOKEN_1), "ipfs://QmHash1");
    }

    function test_SetTokenURIEmitsMetadataUpdate() public {
        helper.mint(alice, TOKEN_1);

        vm.expectEmit(true, false, false, false);
        emit MetadataUpdate(TOKEN_1);

        helper.setTokenURIRaw(TOKEN_1, "ipfs://QmHash1");
    }

    function test_TokenURIReturnsStoredURI() public {
        helper.mint(alice, TOKEN_1);

        helper.setTokenURIRaw(TOKEN_1, "https://example.com/token/1");

        assertEq(token.tokenURI(TOKEN_1), "https://example.com/token/1");
    }

    function test_TokenURIWithoutPerTokenURIReturnsEmpty() public {
        helper.mint(alice, TOKEN_1);

        // No base URI in default ERC721, no per-token URI set → returns empty
        assertEq(token.tokenURI(TOKEN_1), "");
    }

    function test_DifferentTokensHaveDifferentURIs() public {
        helper.mint(alice, TOKEN_1);
        helper.mint(alice, TOKEN_2);

        helper.setTokenURIRaw(TOKEN_1, "ipfs://token1");
        helper.setTokenURIRaw(TOKEN_2, "ipfs://token2");

        assertEq(token.tokenURI(TOKEN_1), "ipfs://token1");
        assertEq(token.tokenURI(TOKEN_2), "ipfs://token2");
    }

    function test_SetTokenURIViaFacetRequiresAdmin() public {
        helper.mint(alice, TOKEN_1);

        // Non-admin call to setTokenURI on the facet should revert
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );
        vm.prank(alice);
        token.setTokenURI(TOKEN_1, "ipfs://QmHash1");
    }

    function test_AdminCanSetTokenURIViaFacet() public {
        helper.mint(alice, TOKEN_1);

        vm.prank(admin);
        token.setTokenURI(TOKEN_1, "ipfs://QmHashAdmin");

        assertEq(token.tokenURI(TOKEN_1), "ipfs://QmHashAdmin");
    }

    function test_TokenURIForNonexistentReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, uint256(999)));
        token.tokenURI(999);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //       IMP-01: tokenURI must revert for nonexistent tokens even with pre-set URI
    //////////////////////////////////////////////////////////////////////////*//

    function test_TokenURIPreSetBeforeMint_Reverts() public {
        // Set a URI for token 999 before it is minted (helper bypasses existence check on _setTokenURI)
        helper.setTokenURIRaw(999, "ipfs://pre-mint-uri");

        // tokenURI must still revert — existence check is in tokenURI, not _setTokenURI
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, uint256(999)));
        token.tokenURI(999);
    }

    function test_TokenURIAfterBurnRevertsEvenIfURISet() public {
        helper.mint(alice, TOKEN_1);
        helper.setTokenURIRaw(TOKEN_1, "ipfs://Qm...");

        helper.burn(TOKEN_1);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, TOKEN_1));
        token.tokenURI(TOKEN_1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsERC4906Interface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(0x49064906)); // ERC-4906
    }

    function test_SupportsERC721Interface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(0x80ac58cd)); // IERC721
    }
}
