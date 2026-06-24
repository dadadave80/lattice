// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";
import {IERC7802} from "@lattice/interfaces/external/IERC7802.sol";
import {ERC20} from "@lattice/tokens/ERC20.sol";
import {ERC7802} from "@lattice/tokens/ERC7802.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {CROSSCHAIN_BRIDGE_ROLE, ERC7802Lib} from "@lattice/tokens/libraries/ERC7802Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice A crosschain-native ERC-20: ERC20 + ERC7802 mint/burn, role-gated to a bridge.
contract MockERC7802Token is AccessControl, ERC20, ERC7802 {
    function initialize(address admin_, address bridge_, string memory name_, string memory symbol_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC7802Lib.__ERC7802_init();
        AccessControlLib._grantRole(CROSSCHAIN_BRIDGE_ROLE, bridge_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract ERC7802Tester is Test {
    MockERC7802Token token;

    address admin = address(0x1);
    address bridge = address(0xB0B);
    address user = address(0x2);

    uint256 constant AMT = 100e18;
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        token = new MockERC7802Token();
        token.initialize(admin, bridge, "Lattice USD", "lUSD");
    }

    function test_CrosschainMintByBridge() public {
        vm.prank(bridge);
        vm.expectEmit(true, true, false, true);
        emit IERC7802.CrosschainMint(user, AMT, bridge);
        token.crosschainMint(user, AMT);

        assertEq(IERC20(address(token)).balanceOf(user), AMT);
        assertEq(IERC20(address(token)).totalSupply(), AMT);
    }

    function test_CrosschainMintRevertsNonBridge() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, CROSSCHAIN_BRIDGE_ROLE));
        token.crosschainMint(user, AMT);
    }

    function test_CrosschainBurnByBridge() public {
        vm.startPrank(bridge);
        token.crosschainMint(user, AMT);
        vm.expectEmit(true, true, false, true);
        emit IERC7802.CrosschainBurn(user, 40e18, bridge);
        token.crosschainBurn(user, 40e18);
        vm.stopPrank();

        assertEq(IERC20(address(token)).balanceOf(user), AMT - 40e18);
        assertEq(IERC20(address(token)).totalSupply(), AMT - 40e18);
    }

    function test_CrosschainBurnRevertsNonBridge() public {
        vm.prank(bridge);
        token.crosschainMint(user, AMT);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, CROSSCHAIN_BRIDGE_ROLE));
        token.crosschainBurn(user, AMT);
    }

    function test_SupportsInterfaceERC7802() public view {
        assertEq(type(IERC7802).interfaceId, bytes4(0x33331994), "ERC-7802 interfaceId must be canonical");
        assertTrue(token.supportsInterface(type(IERC7802).interfaceId));
    }
}
