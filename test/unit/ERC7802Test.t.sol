// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC7802TestBase} from "@lattice-test/base/ERC7802TestBase.sol";
import {IERC7802} from "@lattice/interfaces/external/IERC7802.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {CROSSCHAIN_BRIDGE_ROLE} from "@lattice/tokens/ERC7802/libraries/ERC7802Lib.sol";

/// @notice ERC-7802 crosschain mint/burn exercised through a REAL diamond (ERC165 + ERC20 + AccessControl +
///         ERC7802), assembled by the ready-to-deploy {DeployERC7802} recipe — not a flattened inheritance mock.
contract ERC7802Test is ERC7802TestBase {
    IERC7802 token; // typed handle on the diamond (crosschain calls dispatch through it)

    address admin = address(0x1);
    address bridge = address(0xB0B);
    address user = address(0x2);

    uint256 constant AMT = 100e18;
    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        diamond = _deployERC7802(admin, bridge, "Lattice USD", "lUSD");
        token = IERC7802(diamond);
    }

    function test_CrosschainMintByBridge() public {
        vm.prank(bridge);
        vm.expectEmit(true, true, false, true);
        emit IERC7802.CrosschainMint(user, AMT, bridge);
        token.crosschainMint(user, AMT);

        assertEq(IERC20(diamond).balanceOf(user), AMT);
        assertEq(IERC20(diamond).totalSupply(), AMT);
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

        assertEq(IERC20(diamond).balanceOf(user), AMT - 40e18);
        assertEq(IERC20(diamond).totalSupply(), AMT - 40e18);
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
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC7802).interfaceId));
    }
}
