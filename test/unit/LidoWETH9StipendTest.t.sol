// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {LidoAdapter} from "@lattice/defi/LidoAdapter.sol";
import {LidoAdapterLib} from "@lattice/defi/libraries/LidoAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev CANONICAL WETH9 semantics: `withdraw` pays via `msg.sender.transfer` — a 2,300-gas stipend.
/// The repo's other WETH mocks pay with full-gas `call`, which masked the diamond-hosted regression.
contract WETH9TransferMock {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
    }

    function withdraw(uint256 wad) external {
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad); // the stipend-limited canonical payout
    }

    function transfer(address to, uint256 wad) external returns (bool) {
        balanceOf[msg.sender] -= wad;
        balanceOf[to] += wad;
        return true;
    }

    function approve(address spender, uint256 wad) external returns (bool) {
        allowance[msg.sender][spender] = wad;
        return true;
    }
}

/// @dev stETH: `submit` mints 1:1 for attached ETH.
contract MockLidoStETH {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function submit(address) external payable returns (uint256) {
        balanceOf[msg.sender] += msg.value;
        return msg.value;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev wstETH: `wrap` pulls stETH and mints 1:1.
contract MockWstETH {
    MockLidoStETH internal immutable ST;
    mapping(address => uint256) public balanceOf;

    constructor(MockLidoStETH _st) {
        ST = _st;
    }

    function wrap(uint256 amount) external returns (uint256) {
        ST.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
        return amount;
    }
}

/// @dev Delegatecalled init: AccessControl admin + the Lido adapter config.
contract LidoStipendInit {
    function init(address admin, address weth, address lido, address wst, address queue, address vault) external {
        AccessControlLib.__AccessControl_init(admin);
        LidoAdapterLib.__LidoAdapter_init(weth, lido, wst, queue, vault, admin);
    }
}

/// @title LidoWETH9StipendTest
/// @notice Regression for the Receive-facet migration: a DIAMOND-HOSTED LidoAdapter must survive
///         canonical WETH9's 2,300-gas `transfer` payout in `deploy()`. `vm.cool` restores the
///         realistic cold access-list state (in-test warmth otherwise masks the stipend failure).
contract LidoWETH9StipendTest is Test, GetSelectors {
    address internal diamond;
    address internal receiveFacet;
    WETH9TransferMock internal weth;
    MockLidoStETH internal steth;
    MockWstETH internal wst;

    function setUp() public {
        weth = new WETH9TransferMock();
        steth = new MockLidoStETH();
        wst = new MockWstETH(steth);
        receiveFacet = address(new Receive());

        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = FacetCut({
            facetAddress: address(new LidoAdapter()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("LidoAdapter")
        });
        bytes4[] memory zero = new bytes4[](1);
        zero[0] = bytes4(0);
        cuts[1] = FacetCut({facetAddress: receiveFacet, action: FacetCutAction.Add, functionSelectors: zero});

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(
            cuts,
            address(new LidoStipendInit()),
            abi.encodeCall(
                LidoStipendInit.init,
                (address(this), address(weth), address(steth), address(wst), makeAddr("queue"), makeAddr("vault"))
            )
        );
        diamond = address(d);

        LidoAdapter(payable(diamond)).setOperator(address(this));

        // Seed the adapter's idle WETH buffer.
        weth.deposit{value: 5 ether}();
        weth.transfer(diamond, 5 ether);
    }

    /// @notice The staking leg completes with canonical WETH9 stipend semantics under COLD state —
    ///         exactly the on-chain shape where `withdraw`'s 2,300-gas payout meets the diamond.
    function test_DeployLeg_SurvivesWETH9StipendCold() public {
        vm.cool(diamond);
        vm.cool(receiveFacet);
        vm.cool(address(weth));

        uint256 deployed = LidoAdapter(payable(diamond)).deploy();

        assertEq(deployed, 5 ether);
        assertEq(wst.balanceOf(diamond), 5 ether, "staked position not held as wstETH");
        assertEq(address(diamond).balance, 0, "no ETH stranded on the diamond");
    }
}
