// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC3156FlashBorrower} from "@lattice/interfaces/external/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@lattice/interfaces/external/IERC3156FlashLender.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20FlashMint} from "@lattice/interfaces/tokens/IERC20FlashMint.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20FlashMint} from "@lattice/tokens/ERC20/ERC20FlashMint.sol";
import {ERC20FlashMintLib} from "@lattice/tokens/ERC20/libraries/ERC20FlashMintLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {Test} from "forge-std/Test.sol";

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

contract MockERC20FlashMintContract is ERC20, ERC20FlashMint {
    function initialize(string memory name_, string memory symbol_, address mintTo, uint256 mintAmount) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC20FlashMintLib.__ERC20FlashMint_init();
        if (mintTo != address(0) && mintAmount > 0) ERC20Lib._mint(mintTo, mintAmount);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC20FlashMintTest
/// @notice ERC20 batch (token-extension completion): ERC-3156 flash mint.
contract ERC20FlashMintTest is Test {
    MockERC20FlashMintContract token;
    FlashBorrower borrower;

    address alice = address(0x1);
    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 constant LOAN = 5000e18;

    function setUp() public {
        token = new MockERC20FlashMintContract();
        token.initialize("Flash Token", "FLASH", alice, INITIAL_SUPPLY);
        borrower = new FlashBorrower();
    }

    function test_MaxFlashLoan() public view {
        assertEq(token.maxFlashLoan(address(token)), type(uint256).max - INITIAL_SUPPLY);
        assertEq(token.maxFlashLoan(address(0xdead)), 0);
    }

    function test_SupportsFlashLenderInterface() public view {
        assertTrue(token.supportsInterface(type(IERC3156FlashLender).interfaceId), "registers IERC3156FlashLender");
    }

    function test_FlashFeeIsZeroForToken() public view {
        assertEq(token.flashFee(address(token), LOAN), 0);
    }

    function test_FlashFeeRevertsForUnsupportedToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20FlashMint.ERC3156UnsupportedToken.selector, address(0xdead)));
        token.flashFee(address(0xdead), LOAN);
    }

    function test_FlashLoanMintsToBorrowerAndBurnsBack() public {
        bool ok = token.flashLoan(borrower, address(token), LOAN, "");
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
        uint256 tooMuch = token.maxFlashLoan(address(token)) + 1;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20FlashMint.ERC3156ExceededMaxLoan.selector, type(uint256).max - INITIAL_SUPPLY)
        );
        token.flashLoan(borrower, address(token), tooMuch, "");
    }

    function test_FlashLoanRevertsOnBadCallbackReturn() public {
        borrower.setReturn(keccak256("wrong"));
        vm.expectRevert(abi.encodeWithSelector(IERC20FlashMint.ERC3156InvalidReceiver.selector, address(borrower)));
        token.flashLoan(borrower, address(token), LOAN, "");
    }
}
