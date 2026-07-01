// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Capped} from "@lattice/interfaces/tokens/IERC20Capped.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Capped} from "@lattice/tokens/ERC20/ERC20Capped.sol";
import {ERC20CappedLib} from "@lattice/tokens/ERC20/libraries/ERC20CappedLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockERC20CappedContract
/// @notice Mock combining AccessControl + ERC20Capped. The MINTER_ROLE gate
///         is enforced in the external mint function.
contract MockERC20CappedContract is AccessControl, ERC20, ERC20Capped {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function initialize(string memory name_, string memory symbol_, uint256 cap_, address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin);
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC20CappedLib.__ERC20Capped_init(cap_);
        InitializableLib.postInitializer(s);
    }

    /// @notice Mints `value` tokens to `to`. Requires MINTER_ROLE.
    function mint(address to, uint256 value) external {
        AccessControlLib.checkRole(MINTER_ROLE);
        _mint(to, value);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC20CappedTester
contract ERC20CappedTester is Test {
    MockERC20CappedContract token;

    address admin = address(0x1);
    address minter = address(0x2);
    address alice = address(0x3);

    uint256 constant CAP = 1_000_000e18;

    function setUp() public {
        token = new MockERC20CappedContract();
        token.initialize("Capped Token", "CAP", CAP, admin);

        // Grant minter role
        vm.prank(admin);
        token.grantRole(keccak256("MINTER_ROLE"), minter);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               CAP QUERY
    //////////////////////////////////////////////////////////////////////////*//

    function test_CapIsQueryable() public view {
        assertEq(token.cap(), CAP);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            MINT UP TO CAP
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintUpToCapSucceeds() public {
        vm.prank(minter);
        token.mint(alice, CAP);
        assertEq(token.totalSupply(), CAP);
        assertEq(token.balanceOf(alice), CAP);
    }

    function test_MintBelowCapSucceeds() public {
        vm.prank(minter);
        token.mint(alice, CAP / 2);
        assertEq(token.totalSupply(), CAP / 2);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           MINT BEYOND CAP
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintBeyondCapReverts() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC20Capped.ERC20ExceededCap.selector, CAP + 1, CAP));
        token.mint(alice, CAP + 1);
    }

    function test_MintBeyondCapAfterPartialMintReverts() public {
        vm.prank(minter);
        token.mint(alice, CAP - 10e18);

        uint256 remaining = token.cap() - token.totalSupply();
        uint256 overMint = remaining + 1;
        uint256 newSupply = token.totalSupply() + overMint;

        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC20Capped.ERC20ExceededCap.selector, newSupply, CAP));
        token.mint(alice, overMint);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //         MIN-02: boundary — minting exactly to cap in two steps succeeds
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintExactlyToCapInTwoStepsSucceeds() public {
        uint256 firstMint = CAP / 2;
        uint256 secondMint = CAP - firstMint; // CAP - CAP/2 handles odd CAP values

        vm.prank(minter);
        token.mint(alice, firstMint);

        vm.prank(minter);
        token.mint(alice, secondMint);

        // totalSupply == cap (check is >, not >=, so this must not revert)
        assertEq(token.totalSupply(), CAP);
        assertEq(token.totalSupply(), token.cap());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          INVALID CAP ON INIT
    //////////////////////////////////////////////////////////////////////////*//

    function test_ZeroCapInInitReverts() public {
        MockERC20CappedContract t2 = new MockERC20CappedContract();
        vm.expectRevert(abi.encodeWithSelector(IERC20Capped.ERC20InvalidCap.selector, 0));
        t2.initialize("Bad Cap Token", "BAD", 0, admin);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIERC20Capped() public view {
        assertTrue(token.supportsInterface(type(IERC20Capped).interfaceId));
    }

    function test_SupportsIERC20() public view {
        assertTrue(token.supportsInterface(type(IERC20).interfaceId));
    }
}
