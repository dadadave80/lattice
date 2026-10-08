// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ShieldedPoolTestBase} from "@lattice-test/base/ShieldedPoolTestBase.sol";
import {ShieldedWithdrawFixture, TestWithdrawVerifier} from "@lattice-test/helpers/ShieldedWithdrawFixture.sol";
import {IGroth16Verifier} from "@lattice/interfaces/privacy/IGroth16Verifier.sol";
import {IShieldedPool} from "@lattice/interfaces/privacy/IShieldedPool.sol";
import {Groth16Verifier} from "@lattice/privacy/Groth16Verifier.sol";
import {ShieldedPool} from "@lattice/privacy/ShieldedPool.sol";

/// @notice Minimal ERC-20 for the pool test.
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @title ShieldedPoolTest
/// @notice Tests the deposit -> withdraw flow through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployShieldedPool} script (see {ShieldedPoolTestBase}) with a REAL Groth16 withdrawal proof (3
///         commitments, depth 2, recipient 0xbeef, relayer 0xc0fe, fee 5). The proof passes `snarkjs groth16
///         verify`. Every deposit/withdraw call routes through the diamond's `delegatecall` dispatch;
///         `supportsInterface` is served by the cut-in `ERC165Facet`. The pool's ERC-20 token and its Groth16
///         `TestWithdrawVerifier` adapter stay external dependencies (NOT the facet under test).
contract ShieldedPoolTest is ShieldedPoolTestBase {
    MockERC20 token;
    TestWithdrawVerifier verifier;

    uint256 poolId;

    uint256 constant DENOM = 1000;
    uint256 constant ROOT = ShieldedWithdrawFixture.ROOT;
    uint256 constant NULLIFIER_HASH = ShieldedWithdrawFixture.NULLIFIER_HASH;
    address constant RECIPIENT = ShieldedWithdrawFixture.RECIPIENT;
    address constant RELAYER = ShieldedWithdrawFixture.RELAYER;
    uint256 constant FEE = ShieldedWithdrawFixture.FEE;

    function setUp() public {
        Groth16Verifier g = new Groth16Verifier();
        verifier = new TestWithdrawVerifier(g);
        token = new MockERC20();
        diamond = _deployShieldedPool(address(this));
        pool = ShieldedPool(diamond);
        poolId = pool.createPool(address(token), DENOM, address(verifier));

        // This contract is the depositor: fund + approve 3 deposits.
        token.mint(address(this), 3 * DENOM);
        token.approve(address(pool), 3 * DENOM);
        uint256[] memory c = _commitments();
        for (uint256 i; i < c.length; ++i) {
            pool.deposit(poolId, c[i]);
        }
    }

    function _commitments() internal pure returns (uint256[] memory c) {
        c = new uint256[](3);
        c[0] = 20595346326572914964186581639484694308224330290454662633399973481953444150659;
        c[1] = 20403006909364192806930024120627684483381303094884559877071101381067530732246;
        c[2] = 6494326098466164952080577608230455345257528668955319299844368625460411395488;
    }

    function _proof() internal pure returns (IShieldedPool.WithdrawProof memory p) {
        IGroth16Verifier.Proof memory g = ShieldedWithdrawFixture.proof();
        (p.a, p.b, p.c) = (g.a, g.b, g.c);
    }

    function _withdraw() internal {
        pool.withdraw(poolId, _proof(), ROOT, NULLIFIER_HASH, RECIPIENT, RELAYER, FEE);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_DepositsMatchProofRoot() public view {
        (,,, uint256 root, uint256 numLeaves) = pool.getPool(poolId);
        assertEq(root, ROOT, "on-chain root != proof root");
        assertEq(numLeaves, 3);
        assertEq(token.balanceOf(address(pool)), 3 * DENOM);
    }

    function test_WithdrawRealProof() public {
        _withdraw();
        assertEq(token.balanceOf(RECIPIENT), DENOM - FEE, "recipient amount");
        assertEq(token.balanceOf(RELAYER), FEE, "relayer fee");
        assertEq(token.balanceOf(address(pool)), 2 * DENOM, "pool keeps the other two deposits");
        assertTrue(pool.isSpent(poolId, NULLIFIER_HASH));
    }

    function test_DoubleWithdrawReverts() public {
        _withdraw();
        vm.expectRevert(IShieldedPool.ShieldedPoolNullifierAlreadySpent.selector);
        _withdraw();
    }

    function test_UnknownRootReverts() public {
        vm.expectRevert(IShieldedPool.ShieldedPoolUnknownRoot.selector);
        pool.withdraw(poolId, _proof(), ROOT + 1, NULLIFIER_HASH, RECIPIENT, RELAYER, FEE);
    }

    function test_FeeExceedsDenominationReverts() public {
        vm.expectRevert(IShieldedPool.ShieldedPoolFeeExceedsDenomination.selector);
        pool.withdraw(poolId, _proof(), ROOT, NULLIFIER_HASH, RECIPIENT, RELAYER, DENOM + 1);
    }

    function test_TamperedProofReverts() public {
        IShieldedPool.WithdrawProof memory p = _proof();
        unchecked {
            p.a[0] = p.a[0] + 1;
        }
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidProof.selector);
        pool.withdraw(poolId, p, ROOT, NULLIFIER_HASH, RECIPIENT, RELAYER, FEE);
    }

    function test_WrongRecipientReverts() public {
        // recipient is bound in the proof; changing it makes the public signals mismatch -> false.
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidProof.selector);
        pool.withdraw(poolId, _proof(), ROOT, NULLIFIER_HASH, address(0xDEAD), RELAYER, FEE);
    }

    function test_CreatePoolOnlyAdmin() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        pool.createPool(address(token), DENOM, address(verifier));
    }

    function test_CreatePoolInvalidConfigReverts() public {
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidConfig.selector);
        pool.createPool(address(0), DENOM, address(verifier));
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidConfig.selector);
        pool.createPool(address(token), 0, address(verifier));
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidConfig.selector);
        pool.createPool(address(token), DENOM, address(0));
    }

    /// @notice A token address with no code would accept deposits that move nothing, so `createPool` rejects it.
    function test_CreatePoolNoCodeTokenReverts() public {
        address noCode = address(0xDEAD);
        assertEq(noCode.code.length, 0);
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidConfig.selector);
        pool.createPool(noCode, DENOM, address(verifier));
    }

    /// @notice A call to an address with no code returns success with empty data; the deposit pull must not
    ///         count that as a transfer.
    function test_DepositNoCodeTokenReverts() public {
        vm.etch(address(token), hex"");
        vm.expectRevert(abi.encodeWithSelector(IShieldedPool.ShieldedPoolTransferFailed.selector, address(token)));
        pool.deposit(poolId, 1);
    }

    /// @notice The withdraw payout must not count a call to a token with no code as a transfer.
    function test_WithdrawNoCodeTokenReverts() public {
        vm.etch(address(token), hex"");
        vm.expectRevert(abi.encodeWithSelector(IShieldedPool.ShieldedPoolTransferFailed.selector, address(token)));
        _withdraw();
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IShieldedPool).interfaceId, bytes4(0x8f5cc2c7), "IShieldedPool interfaceId moved");
    }

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IShieldedPool).interfaceId));
    }
}
