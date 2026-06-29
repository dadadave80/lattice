// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {IVestingWallet} from "@lattice/interfaces/utils/IVestingWallet.sol";
import {VestingWalletStandalone} from "@lattice/utils/VestingWalletStandalone.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

//*//////////////////////////////////////////////////////////////////////////
//                               HELPERS
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal ERC20 used purely in tests.
contract TestToken {
    mapping(address => uint256) public balanceOf;

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

/// @notice USDT-style token that does NOT return a bool from transfer().
contract USDTStyleToken {
    mapping(address => uint256) public balanceOf;

    /// @dev Intentionally omits the bool return value, like USDT on mainnet.
    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
}

/// @notice Extended standalone that exposes owner transfer in tests without auth.
contract MockVestingWalletStandalone is VestingWalletStandalone {
    constructor(address b, uint64 s, uint64 d) VestingWalletStandalone(b, s, d) {}

    /// @dev Bypasses ownership auth — only for test use.
    function transferOwnerHelper(address newOwner) external {
        OwnableLib.setOwner(newOwner);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                           TEST CONTRACT
//////////////////////////////////////////////////////////////////////////*//

/// @title VestingWalletTester
/// @notice Comprehensive tests for VestingWallet.
contract VestingWalletTester is Test {
    MockVestingWalletStandalone wallet;
    TestToken token;

    address beneficiary = address(0xBEEF);
    address other = address(0xCAFE);

    uint64 constant START = 1_000_000;
    uint64 constant DURATION = 365 days; // 31_536_000 seconds
    uint256 constant DEPOSIT = 100 ether;

    event EtherReleased(uint256 amount);
    event ERC20Released(address indexed token, uint256 amount);

    function setUp() public {
        wallet = new MockVestingWalletStandalone(beneficiary, START, DURATION);
        token = new TestToken();

        // Fund the wallet with ETH
        vm.deal(address(wallet), DEPOSIT);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_StartReturnedCorrectly() public view {
        assertEq(wallet.start(), START);
    }

    function test_DurationReturnedCorrectly() public view {
        assertEq(wallet.duration(), DURATION);
    }

    function test_EndIsStartPlusDuration() public view {
        assertEq(wallet.end(), uint256(START) + uint256(DURATION));
    }

    function test_ReleasedInitiallyZero() public view {
        assertEq(wallet.released(), 0);
    }

    function test_ERC20ReleasedInitiallyZero() public view {
        assertEq(wallet.released(address(token)), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         ERC-165 SUPPORT
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIVestingWalletInterface() public view {
        assertTrue(wallet.supportsInterface(type(IVestingWallet).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        BEFORE START TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_BeforeStart_ReleasableIsZero() public view {
        // block.timestamp defaults to 1 in Foundry, which is < START
        assertEq(wallet.releasable(), 0);
    }

    function test_BeforeStart_VestedAmountIsZero() public view {
        assertEq(wallet.vestedAmount(START - 1), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         AT START TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_AtStart_ReleasableIsZero() public {
        vm.warp(START);
        assertEq(wallet.releasable(), 0);
    }

    function test_AtStart_VestedAmountIsZero() public view {
        assertEq(wallet.vestedAmount(START), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        MIDWAY VESTING TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_Midway_ReleasableIsHalfOfDeposit() public {
        vm.warp(START + DURATION / 2);
        uint256 r = wallet.releasable();
        // At exactly halfway: vested = DEPOSIT * (DURATION/2) / DURATION = DEPOSIT/2
        assertApproxEqAbs(r, DEPOSIT / 2, 1); // within 1 wei rounding
    }

    function test_Midway_VestedAmountLinear() public view {
        uint64 elapsed = DURATION / 4;
        uint256 vested = wallet.vestedAmount(START + elapsed);
        uint256 expected = (DEPOSIT * elapsed) / DURATION;
        assertApproxEqAbs(vested, expected, 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          AT END TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_AtEnd_ReleasableEqualsDeposit() public {
        vm.warp(START + DURATION);
        assertEq(wallet.releasable(), DEPOSIT);
    }

    function test_AtEnd_VestedAmountEqualsDeposit() public view {
        assertEq(wallet.vestedAmount(START + DURATION), DEPOSIT);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         AFTER END TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_AfterEnd_ReleasableDoesNotIncrease() public {
        vm.warp(START + DURATION + 365 days);
        assertEq(wallet.releasable(), DEPOSIT);
    }

    function test_AfterEnd_VestedAmountIsCapped() public view {
        assertEq(wallet.vestedAmount(START + DURATION + 1), DEPOSIT);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          RELEASE ETH TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_Release_TransfersEthToBeneficiary() public {
        vm.warp(START + DURATION); // full vesting
        uint256 before = beneficiary.balance;
        wallet.release();
        assertEq(beneficiary.balance - before, DEPOSIT);
    }

    function test_Release_UpdatesReleasedState() public {
        vm.warp(START + DURATION);
        wallet.release();
        assertEq(wallet.released(), DEPOSIT);
    }

    function test_Release_EmitsEtherReleasedEvent() public {
        vm.warp(START + DURATION);
        vm.expectEmit(false, false, false, true, address(wallet));
        emit EtherReleased(DEPOSIT);
        wallet.release();
    }

    function test_Release_DropsReleasableToZero() public {
        vm.warp(START + DURATION);
        wallet.release();
        assertEq(wallet.releasable(), 0);
    }

    function test_Release_SuccessiveCallsOnlyPayNewVesting() public {
        // Release at halfway
        vm.warp(START + DURATION / 2);
        wallet.release();
        uint256 firstRelease = wallet.released();
        assertApproxEqAbs(firstRelease, DEPOSIT / 2, 1);

        // Warp to end and release remainder
        vm.warp(START + DURATION);
        wallet.release();
        uint256 secondRelease = wallet.released() - firstRelease;
        assertApproxEqAbs(secondRelease, DEPOSIT / 2, 1);

        // All ETH released
        assertEq(wallet.released(), DEPOSIT);
        assertEq(wallet.releasable(), 0);
    }

    function test_Release_ZeroAmountAtStart() public {
        vm.warp(START);
        uint256 before = beneficiary.balance;
        wallet.release(); // 0 amount, should not revert
        assertEq(beneficiary.balance, before);
        assertEq(wallet.released(), 0);
    }

    function test_Release_CallerIsNotBeneficiary_StillWorksBeneficiaryReceives() public {
        vm.warp(START + DURATION);
        uint256 before = beneficiary.balance;
        // Release is called by `other`, but ETH must go to beneficiary
        vm.prank(other);
        wallet.release();
        assertEq(beneficiary.balance - before, DEPOSIT);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         RELEASE ERC20 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ReleaseToken_TransfersTokenToBeneficiary() public {
        token.mint(address(wallet), DEPOSIT);
        vm.warp(START + DURATION);
        wallet.release(address(token));
        assertEq(token.balanceOf(beneficiary), DEPOSIT);
    }

    function test_ReleaseToken_UpdatesERC20ReleasedState() public {
        token.mint(address(wallet), DEPOSIT);
        vm.warp(START + DURATION);
        wallet.release(address(token));
        assertEq(wallet.released(address(token)), DEPOSIT);
    }

    function test_ReleaseToken_EmitsERC20ReleasedEvent() public {
        token.mint(address(wallet), DEPOSIT);
        vm.warp(START + DURATION);
        vm.expectEmit(true, false, false, true, address(wallet));
        emit ERC20Released(address(token), DEPOSIT);
        wallet.release(address(token));
    }

    function test_ReleaseToken_ReleasableDropsToZero() public {
        token.mint(address(wallet), DEPOSIT);
        vm.warp(START + DURATION);
        wallet.release(address(token));
        assertEq(wallet.releasable(address(token)), 0);
    }

    function test_ReleaseToken_SuccessiveCallsOnlyPayNewVesting() public {
        token.mint(address(wallet), DEPOSIT);

        vm.warp(START + DURATION / 2);
        wallet.release(address(token));
        uint256 firstRelease = wallet.released(address(token));
        assertApproxEqAbs(firstRelease, DEPOSIT / 2, 1);

        vm.warp(START + DURATION);
        wallet.release(address(token));
        uint256 totalReleased = wallet.released(address(token));
        assertApproxEqAbs(totalReleased, DEPOSIT, 1);
        assertEq(wallet.releasable(address(token)), 0);
    }

    function test_ReleaseToken_BeforeStart_ReleasableIsZero() public {
        token.mint(address(wallet), DEPOSIT);
        assertEq(wallet.releasable(address(token)), 0);
    }

    function test_ReleaseTokenWorksWithUSDTStyleToken() public {
        USDTStyleToken usdtLike = new USDTStyleToken();
        usdtLike.mint(address(wallet), DEPOSIT);

        vm.warp(START + DURATION);
        wallet.release(address(usdtLike));

        assertEq(usdtLike.balanceOf(beneficiary), DEPOSIT);
        assertEq(wallet.released(address(usdtLike)), DEPOSIT);
        assertEq(wallet.releasable(address(usdtLike)), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      BENEFICIARY CHANGE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_BeneficiaryChange_RoutesReleaseToNewOwner() public {
        address newBeneficiary = address(0xDEAD);
        wallet.transferOwnerHelper(newBeneficiary);

        vm.warp(START + DURATION);
        wallet.release();

        assertEq(newBeneficiary.balance, DEPOSIT);
        assertEq(beneficiary.balance, 0); // original got nothing
    }

    function test_BeneficiaryChange_PartialVestBeforeSwap() public {
        // Release half to original beneficiary
        vm.warp(START + DURATION / 2);
        wallet.release();
        uint256 firstHalf = beneficiary.balance;
        assertApproxEqAbs(firstHalf, DEPOSIT / 2, 1);

        // Switch beneficiary, then release remainder
        address newBeneficiary = address(0xDEAD);
        wallet.transferOwnerHelper(newBeneficiary);

        vm.warp(START + DURATION);
        wallet.release();

        // Original gets only first half; new beneficiary gets the rest
        assertApproxEqAbs(beneficiary.balance, DEPOSIT / 2, 1);
        assertApproxEqAbs(newBeneficiary.balance, DEPOSIT / 2, 1);
    }
}
