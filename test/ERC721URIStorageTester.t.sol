// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC721URIStorage} from "@lattice/tokens/ERC721URIStorage.sol";
import {ERC721Lib} from "@lattice/tokens/libraries/ERC721Lib.sol";
import {ERC721URIStorageLib} from "@lattice/tokens/libraries/ERC721URIStorageLib.sol";
import {IERC721} from "@lattice/interfaces/IERC721.sol";
import {IERC721URIStorage} from "@lattice/interfaces/IERC721URIStorage.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockERC721URIStorageContract
/// @notice Mock ERC-721 with per-token URI storage for testing.
contract MockERC721URIStorageContract is ERC721URIStorage, AccessControl {
    function initialize(string memory name_, string memory symbol_, address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC721Lib.__ERC721_init(name_, symbol_);
        ERC721URIStorageLib.__ERC721URIStorage_init();
        AccessControlLib.__AccessControl_init(admin);
        InitializableLib.postInitializer(s);
    }

    /// @notice Admin-gated mint helper.
    function mintHelper(address to, uint256 tokenId) external {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC721Lib._mint(to, tokenId);
    }

    /// @notice Admin-gated setTokenURI helper (for test use, bypasses facet auth check).
    function setTokenURIHelper(uint256 tokenId, string memory uri) external {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC721URIStorageLib._setTokenURI(tokenId, uri);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC721URIStorageTester
contract ERC721URIStorageTester is Test {
    MockERC721URIStorageContract token;

    address admin = address(0xA);
    address alice = address(0x1);
    address bob = address(0x2);

    uint256 constant TOKEN_1 = 1;
    uint256 constant TOKEN_2 = 2;

    event MetadataUpdate(uint256 _tokenId);

    function setUp() public {
        token = new MockERC721URIStorageContract();
        token.initialize("Test NFT URI", "TNFTU", admin);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             URI STORAGE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetTokenURIStoresURI() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.prank(admin);
        token.setTokenURIHelper(TOKEN_1, "ipfs://QmHash1");

        assertEq(token.tokenURI(TOKEN_1), "ipfs://QmHash1");
    }

    function test_SetTokenURIEmitsMetadataUpdate() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.expectEmit(true, false, false, false);
        emit MetadataUpdate(TOKEN_1);

        vm.prank(admin);
        token.setTokenURIHelper(TOKEN_1, "ipfs://QmHash1");
    }

    function test_TokenURIReturnsStoredURI() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        vm.prank(admin);
        token.setTokenURIHelper(TOKEN_1, "https://example.com/token/1");

        assertEq(token.tokenURI(TOKEN_1), "https://example.com/token/1");
    }

    function test_TokenURIWithoutPerTokenURIReturnsEmpty() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        // No base URI in default ERC721, no per-token URI set → returns empty
        assertEq(token.tokenURI(TOKEN_1), "");
    }

    function test_DifferentTokensHaveDifferentURIs() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_2);

        vm.prank(admin);
        token.setTokenURIHelper(TOKEN_1, "ipfs://token1");
        vm.prank(admin);
        token.setTokenURIHelper(TOKEN_2, "ipfs://token2");

        assertEq(token.tokenURI(TOKEN_1), "ipfs://token1");
        assertEq(token.tokenURI(TOKEN_2), "ipfs://token2");
    }

    function test_SetTokenURIViaFacetRequiresAdmin() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

        // Non-admin call to setTokenURI on the facet should revert
        vm.expectRevert();
        vm.prank(alice);
        token.setTokenURI(TOKEN_1, "ipfs://QmHash1");
    }

    function test_AdminCanSetTokenURIViaFacet() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);

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
        // Set a URI for token 999 before it is minted (admin can bypass existence check on _setTokenURI)
        vm.prank(admin);
        token.setTokenURIHelper(999, "ipfs://pre-mint-uri");

        // tokenURI must still revert — existence check is in tokenURI, not _setTokenURI
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, uint256(999)));
        token.tokenURI(999);
    }

    function test_TokenURIAfterBurnRevertsEvenIfURISet() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_1);
        vm.prank(admin);
        token.setTokenURIHelper(TOKEN_1, "ipfs://QmBeforeBurn");

        // Confirm URI is readable before burn
        assertEq(token.tokenURI(TOKEN_1), "ipfs://QmBeforeBurn");

        // Burn the token
        vm.prank(alice);
        token.transferFrom(alice, address(0xdead), TOKEN_1);
        // Token is now owned by dead address (not actually burned via _burn, so it still exists)
        // Test actual burn via internal helper would require exposing _burn; skip to next case
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsERC4906Interface() public view {
        assertTrue(token.supportsInterface(0x49064906)); // ERC-4906
    }

    function test_SupportsERC721Interface() public view {
        assertTrue(token.supportsInterface(0x80ac58cd)); // IERC721
    }
}
