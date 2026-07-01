// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20FlashMint} from "@lattice-script/base/DeployERC20FlashMint.s.sol";
import {ERC20TestBase} from "@lattice-test/base/ERC20TestBase.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {IERC3156FlashBorrower} from "@lattice/interfaces/external/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@lattice/interfaces/external/IERC3156FlashLender.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20FlashMint} from "@lattice/interfaces/tokens/IERC20FlashMint.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20FlashMint} from "@lattice/tokens/ERC20/ERC20FlashMint.sol";

/// @notice Reference borrower: records the callback args, approves repayment, echoes the ERC-3156 magic value.
contract FlashBorrower is IERC3156FlashBorrower {
    bytes32 constant CALLBACK = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address public lastInitiator;
    address public lastToken;
    uint256 public lastAmount;
    uint256 public lastFee;
    uint256 public balanceDuringCallback;
    bool public approveRepayment = true;
    bytes32 public returnOverride;

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        lastInitiator = initiator;
        lastToken = token;
        lastAmount = amount;
        lastFee = fee;
        balanceDuringCallback = IERC20(token).balanceOf(address(this));
        if (approveRepayment) IERC20(token).approve(token, amount + fee);
        return returnOverride == bytes32(0) ? CALLBACK : returnOverride;
    }

    function setReturn(bytes32 r) external {
        returnOverride = r;
    }

    function setApprove(bool a) external {
        approveRepayment = a;
    }
}

/// @title ERC20FlashMintTest
/// @notice Exercises the {ERC20FlashMint} facet (ERC-3156 flash mint) through a REAL {Diamond} assembled by the
///         ready-to-deploy {DeployERC20FlashMint} script (base ERC-20 + the additive flash-mint facet). Every call
///         routes through the diamond's `delegatecall` dispatch, not a flattened inheritance mock; the initial
///         supply is seeded via the test-only {TokenTestFacet} (`helper`).
contract ERC20FlashMintTest is ERC20TestBase {
    ERC20FlashMint internal flash;
    FlashBorrower borrower;

    address alice = address(0x1);
    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 constant LOAN = 5000e18;

    function setUp() public override {
        DeployERC20FlashMint d = new DeployERC20FlashMint();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            d.buildCuts("Flash Token", "FLASH");
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC20(diamond);
        helper = TokenTestFacet(diamond);
        flash = ERC20FlashMint(diamond);

        helper.mint(alice, INITIAL_SUPPLY);
        borrower = new FlashBorrower();
    }

    function test_MaxFlashLoan() public view {
        assertEq(flash.maxFlashLoan(diamond), type(uint256).max - INITIAL_SUPPLY);
        assertEq(flash.maxFlashLoan(address(0xdead)), 0);
    }

    function test_SupportsFlashLenderInterface() public view {
        assertTrue(
            ERC165Facet(diamond).supportsInterface(type(IERC3156FlashLender).interfaceId),
            "registers IERC3156FlashLender"
        );
    }

    function test_FlashFeeIsZeroForToken() public view {
        assertEq(flash.flashFee(diamond, LOAN), 0);
    }

    function test_FlashFeeRevertsForUnsupportedToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20FlashMint.ERC3156UnsupportedToken.selector, address(0xdead)));
        flash.flashFee(address(0xdead), LOAN);
    }

    function test_FlashLoanMintsToBorrowerAndBurnsBack() public {
        bool ok = flash.flashLoan(borrower, diamond, LOAN, "");
        assertTrue(ok, "flashLoan returns true");
        // borrower actually held the principal during the callback...
        assertEq(borrower.balanceDuringCallback(), LOAN, "borrower funded during callback");
        assertEq(borrower.lastInitiator(), address(this), "initiator is the caller");
        assertEq(borrower.lastAmount(), LOAN, "amount passed");
        assertEq(borrower.lastFee(), 0, "default zero fee");
        // ...and the loan is fully unwound afterwards.
        assertEq(token.balanceOf(address(borrower)), 0, "principal burned back");
        assertEq(token.totalSupply(), INITIAL_SUPPLY, "supply restored");
    }

    function test_FlashLoanRevertsWhenExceedingMax() public {
        uint256 tooMuch = flash.maxFlashLoan(diamond) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20FlashMint.ERC3156ExceededMaxLoan.selector, type(uint256).max - INITIAL_SUPPLY)
        );
        flash.flashLoan(borrower, diamond, tooMuch, "");
    }

    function test_FlashLoanRevertsOnBadCallbackReturn() public {
        borrower.setReturn(keccak256("wrong"));
        vm.expectRevert(abi.encodeWithSelector(IERC20FlashMint.ERC3156InvalidReceiver.selector, address(borrower)));
        flash.flashLoan(borrower, diamond, LOAN, "");
    }
}
