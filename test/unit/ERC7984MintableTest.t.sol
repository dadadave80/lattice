// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC7984TestBase} from "@lattice-test/base/ERC7984TestBase.sol";
import {SelectorStub} from "@lattice-test/helpers/ERC7984Actors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IERC7984} from "@lattice/interfaces/tokens/IERC7984.sol";
import {IERC7984Mintable} from "@lattice/interfaces/tokens/IERC7984Mintable.sol";
import {ERC7984Mintable} from "@lattice/tokens/ERC7984/ERC7984Mintable.sol";
import {ERC7984MintableInit} from "@lattice/tokens/ERC7984/ERC7984MintableInit.sol";
import {ERC7984_MINTER_ROLE} from "@lattice/tokens/ERC7984/libraries/ERC7984MintableLib.sol";
import {IERC165} from "forge-std/interfaces/IERC165.sol";

contract ERC7984MintableTest is ERC7984TestBase {
    address internal admin;
    address internal minter;
    address internal m;

    function setUp() public override {
        super.setUp();
        admin = makeAddr("admin");
        minter = makeAddr("minter");
        m = _deployMintable(admin, minter);
    }

    function _withOne(FacetCut[] memory cuts, address facet, bytes4 sel) internal pure returns (FacetCut[] memory out) {
        out = new FacetCut[](cuts.length + 1);
        for (uint256 i; i < cuts.length; ++i) {
            out[i] = cuts[i];
        }
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;
        out[cuts.length] = FacetCut(facet, FacetCutAction.Add, selectors);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  SURFACE
    //////////////////////////////////////////////////////////////////////////*//

    function test_InterfaceId_Is0x1b4d3d0d() public pure {
        assertEq(type(IERC7984Mintable).interfaceId, bytes4(0x1b4d3d0d));
        assertEq(IERC7984Mintable.confidentialMint.selector, bytes4(0x1b4d3d0d));
    }

    function test_MinterRole_IsKeccakOfItsName() public pure {
        assertEq(ERC7984_MINTER_ROLE, 0xdfcb28dfca469556780a91efe7acdaa556dbafce4d85e228699b92f5f8f18d35);
    }

    function test_ExportSelectors_Pinned() public {
        assertEq(new ERC7984Mintable().exportSelectors(), hex"1b4d3d0d");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                INITIALIZER
    //////////////////////////////////////////////////////////////////////////*//

    function test_Init_GrantsRolesAndRegistersInterfaces() public view {
        assertTrue(IAccessControl(m).hasRole(bytes32(0), admin));
        assertTrue(IAccessControl(m).hasRole(ERC7984_MINTER_ROLE, minter));
        assertFalse(IAccessControl(m).hasRole(ERC7984_MINTER_ROLE, admin));
        assertEq(IAccessControl(m).getRoleAdmin(ERC7984_MINTER_ROLE), bytes32(0));
        assertTrue(IERC165(m).supportsInterface(0x1b4d3d0d));
        assertTrue(IERC165(m).supportsInterface(0x4958f2a4));
        assertTrue(IERC165(m).supportsInterface(0x7965db0b));
    }

    /// @dev The bundle calls `__ERC7984_init`, so the 15-selector refusal binds it.
    function test_Init_InheritsTheDiamondCallerDenyList() public {
        address stub = address(new SelectorStub());
        address init = address(new ERC7984MintableInit());
        FacetCut[] memory cuts = _withOne(_mintableCuts(), stub, 0x1626ba7e);
        Lattice d = new Lattice();
        vm.expectRevert(
            abi.encodeWithSelector(IERC7984.ERC7984DiamondCallerInstalled.selector, bytes4(0x1626ba7e), stub)
        );
        d.initialize(cuts, init, abi.encodeCall(ERC7984MintableInit.init, (admin, minter, "C", "C", "")));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    MINTING AND THE EXACT GRANT SET (H-25, H-34)
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConfidentialMint_CreditsRecipientAndSupply() public {
        (externalEuint64 x, bytes memory p) = encryptUint64(500, minter, m);
        vm.prank(minter);
        euint64 minted = IERC7984Mintable(m).confidentialMint(alice, x, p);
        assertEq(decrypt(minted), 500);
        assertEq(decrypt(IERC7984(m).confidentialBalanceOf(alice)), 500);
        assertEq(decrypt(IERC7984(m).confidentialTotalSupply()), 500);
    }

    /// @dev The honest (externally owned account) minter's grant set; a recomputing minter contract is Task 3.8.
    function test_ConfidentialMint_GrantsExactAclSet() public {
        (externalEuint64 x, bytes memory p) = encryptUint64(500, minter, m);
        vm.prank(minter);
        bytes32 mh = euint64.unwrap(IERC7984Mintable(m).confidentialMint(alice, x, p));
        bytes32 b = euint64.unwrap(IERC7984(m).confidentialBalanceOf(alice));
        bytes32 s = euint64.unwrap(IERC7984(m).confidentialTotalSupply());
        assertTrue(_acl.persistAllowed(mh, minter));
        assertTrue(_acl.persistAllowed(mh, alice));
        assertTrue(_acl.persistAllowed(mh, m));
        assertFalse(_acl.persistAllowed(mh, admin));
        assertFalse(_acl.persistAllowed(mh, mallory));
        assertTrue(_acl.persistAllowed(b, alice));
        assertTrue(_acl.persistAllowed(b, m));
        assertFalse(_acl.persistAllowed(b, minter));
        assertFalse(_acl.persistAllowed(b, admin));
        assertTrue(_acl.persistAllowed(s, m));
        assertFalse(_acl.persistAllowed(s, minter));
        assertFalse(_acl.persistAllowed(s, alice));
        assertFalse(_acl.persistAllowed(s, admin));
    }

    /// @dev Without the re-derivation, the first supply handle is the input handle.
    function test_ConfidentialMint_FirstMintSupplyIsNotTheInputHandle() public {
        (externalEuint64 x, bytes memory p) = encryptUint64(500, minter, m);
        vm.prank(minter);
        IERC7984Mintable(m).confidentialMint(alice, x, p);
        assertTrue(euint64.unwrap(IERC7984(m).confidentialTotalSupply()) != externalEuint64.unwrap(x));
    }

    function test_ConfidentialMint_EmptyProof_RevertWhen_HandleNotAllowedToMinter() public {
        (externalEuint64 x, bytes memory p) = encryptUint64(500, minter, m);
        vm.prank(minter);
        IERC7984Mintable(m).confidentialMint(alice, x, p);
        bytes32 b = euint64.unwrap(IERC7984(m).confidentialBalanceOf(alice));
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x0276b5d9), b, minter));
        IERC7984Mintable(m).confidentialMint(bob, externalEuint64.wrap(b), "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               AUTHORIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConfidentialMint_RevertWhen_NotMinter() public {
        (externalEuint64 x, bytes memory p) = encryptUint64(1, mallory, m);
        vm.prank(mallory);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, mallory, ERC7984_MINTER_ROLE
            )
        );
        IERC7984Mintable(m).confidentialMint(mallory, x, p);
    }

    /// @dev `DEFAULT_ADMIN_ROLE` is not a mint right.
    function test_ConfidentialMint_RevertWhen_AdminLacksMinterRole() public {
        (externalEuint64 x, bytes memory p) = encryptUint64(1, admin, m);
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, ERC7984_MINTER_ROLE)
        );
        IERC7984Mintable(m).confidentialMint(admin, x, p);
    }

    function test_ConfidentialMint_RevertWhen_MinterRevoked() public {
        vm.prank(admin);
        IAccessControl(m).revokeRole(ERC7984_MINTER_ROLE, minter);
        (externalEuint64 x, bytes memory p) = encryptUint64(1, minter, m);
        vm.prank(minter);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, minter, ERC7984_MINTER_ROLE
            )
        );
        IERC7984Mintable(m).confidentialMint(alice, x, p);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             GUARD (H-03, H-19)
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConfidentialMint_SelfCallRevertsBeforeTheRoleCheck() public {
        (externalEuint64 x, bytes memory p) = encryptUint64(1, m, m);
        // Without the role: the guard error, not AccessControlUnauthorizedAccount.
        vm.prank(m);
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984UnauthorizedCaller.selector, m));
        IERC7984Mintable(m).confidentialMint(alice, x, p);
        vm.prank(admin);
        IAccessControl(m).grantRole(ERC7984_MINTER_ROLE, m);
        // With the role: still the guard error.
        vm.prank(m);
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984UnauthorizedCaller.selector, m));
        IERC7984Mintable(m).confidentialMint(alice, x, p);
    }

    /// @dev Facets cut, no init: the init marker is unset.
    function test_ConfidentialMint_RevertWhen_Uninitialized() public {
        Lattice d = new Lattice();
        d.initialize(_mintableCuts(), address(0), "");
        vm.prank(minter);
        vm.expectRevert(IERC7984.ERC7984NotInitialized.selector);
        IERC7984Mintable(address(d)).confidentialMint(alice, externalEuint64.wrap(0), "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              RECEIVERS (H-23)
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConfidentialMint_RevertWhen_ToIsZero() public {
        (externalEuint64 x, bytes memory p) = encryptUint64(1, minter, m);
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984InvalidReceiver.selector, address(0)));
        IERC7984Mintable(m).confidentialMint(address(0), x, p);
    }

    function test_ConfidentialMint_RevertWhen_ToIsDiamond() public {
        (externalEuint64 x, bytes memory p) = encryptUint64(1, minter, m);
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984InvalidReceiver.selector, m));
        IERC7984Mintable(m).confidentialMint(m, x, p);
    }
}
