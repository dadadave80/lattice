// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ComposedTokenInit} from "@lattice-test/composability/ComposedTokenInit.sol";
import {TokenBlueprintHelper} from "@lattice-test/helpers/TokenBlueprintHelper.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IERC3156FlashBorrower} from "@lattice/interfaces/external/ercs/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@lattice/interfaces/external/ercs/IERC3156FlashLender.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Burnable} from "@lattice/interfaces/tokens/IERC20Burnable.sol";
import {IERC20Capped} from "@lattice/interfaces/tokens/IERC20Capped.sol";

/// @dev The composed token's non-standard entrypoints, exposed by ComposedTokenTestFacet + ERC165Facet.
interface IComposedExtras {
    function mint(address to, uint256 amount) external;
    function pauseIt() external;
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

contract Borrower is IERC3156FlashBorrower {
    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        IERC20(token).approve(token, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

/// @title ERC20DiamondComposition
/// @notice Gold-standard composability proof: assembles a REAL diamond from base ERC20 + Burnable + Capped +
///         FlashMint + (Replace) Pausable and exercises every feature through real fallback dispatch over one
///         shared {ERC20Lib} ledger. Before the de-inheritance refactor this cut was impossible — each
///         `ERC20Foo is ERC20` re-exported the base selectors and the second `Add` reverted
///         `CannotAddFunctionToDiamondThatAlreadyExists`. Replaces the old inheritance-flattened ComposedToken mock.
contract ERC20DiamondComposition is TokenBlueprintHelper {
    address token; // the assembled diamond
    address alice = address(0x1);
    address bob = address(0x2);
    uint256 constant CAP = 1_000_000e18;

    function setUp() public {
        (FacetCut[] memory cuts, ComposedTokenInit init) = _composedErc20Blueprint();
        Lattice diamond = new Lattice();
        // If any extension re-exported a base selector, this cut reverts CannotAddFunctionToDiamondThatAlreadyExists.
        diamond.initialize(cuts, address(init), abi.encodeCall(ComposedTokenInit.init, (CAP)));
        token = address(diamond);
        IComposedExtras(token).mint(alice, 100_000e18);
    }

    function test_AllExtensionInterfacesRegisteredOnOneDiamond() public view {
        assertTrue(IComposedExtras(token).supportsInterface(type(IERC20).interfaceId), "IERC20");
        assertTrue(IComposedExtras(token).supportsInterface(type(IERC20Burnable).interfaceId), "IERC20Burnable");
        assertTrue(IComposedExtras(token).supportsInterface(type(IERC20Capped).interfaceId), "IERC20Capped");
        assertTrue(
            IComposedExtras(token).supportsInterface(type(IERC3156FlashLender).interfaceId), "IERC3156FlashLender"
        );
    }

    function test_CapEnforcedAcrossMint() public {
        assertEq(IERC20Capped(token).cap(), CAP);
        vm.expectRevert(abi.encodeWithSelector(IERC20Capped.ERC20ExceededCap.selector, CAP + 1, CAP));
        IComposedExtras(token).mint(bob, CAP - 100_000e18 + 1); // 100k already minted in setUp => supply CAP+1
    }

    function test_BurnAndTransferShareOneLedger() public {
        vm.prank(alice);
        IERC20(token).transfer(bob, 40_000e18);
        assertEq(IERC20(token).balanceOf(bob), 40_000e18);
        vm.prank(bob);
        IERC20Burnable(token).burn(10_000e18);
        assertEq(IERC20(token).balanceOf(bob), 30_000e18);
        assertEq(IERC20(token).totalSupply(), 90_000e18, "mint+transfer+burn all hit one ERC20Lib ledger");
    }

    function test_PauseGatesTransferButNotOtherFacets() public {
        IComposedExtras(token).pauseIt();
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        IERC20(token).transfer(bob, 1e18);
        // a different facet (burn) still operates while paused
        vm.prank(alice);
        IERC20Burnable(token).burn(1e18);
        assertEq(IERC20(token).balanceOf(alice), 99_999e18);
    }

    function test_FlashMintLeavesCappedLedgerIntact() public {
        Borrower borrower = new Borrower();
        uint256 supplyBefore = IERC20(token).totalSupply();
        IERC3156FlashLender(token).flashLoan(borrower, token, 500e18, "");
        assertEq(IERC20(token).totalSupply(), supplyBefore, "flash principal minted then burned; ledger restored");
    }
}
