// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC7984TestBase} from "@lattice-test/base/ERC7984TestBase.sol";
import {
    CleanTransientReceiver,
    OperatorDiscloser,
    PublishSentReceiver,
    RecomputingMinter,
    ReentrantReceiver
} from "@lattice-test/helpers/ERC7984Actors.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IERC7984, IERC7984Disclosure} from "@lattice/interfaces/tokens/IERC7984.sol";
import {IERC7984Mintable} from "@lattice/interfaces/tokens/IERC7984Mintable.sol";
import {ERC7984_MINTER_ROLE} from "@lattice/tokens/ERC7984/libraries/ERC7984MintableLib.sol";

/// @title ERC7984AcceptedHazardsTest
/// @notice Pins the hazards the ERC-7984 (confidential fungible token) port accepts as inherited OpenZeppelin
///         Confidential Contracts 0.5.3 behaviour: zero transfers by strangers (audit finding M-01), operator
///         disclosure (audit finding M-05), receiver publication, re-entry and transient-storage cleanup, disclosure
///         replay, input-proof reuse, and what a minter can learn (hazard H-34).
contract ERC7984AcceptedHazardsTest is ERC7984TestBase {
    address internal minter = makeAddr("minter");

    OperatorDiscloser internal discloser;
    PublishSentReceiver internal publish;
    CleanTransientReceiver internal cleaner;
    ReentrantReceiver internal reenterTransfer;
    ReentrantReceiver internal reenterAndCall;
    RecomputingMinter internal recomputer;

    function setUp() public override {
        super.setUp();
        discloser = new OperatorDiscloser();
        publish = new PublishSentReceiver();
        cleaner = new CleanTransientReceiver();
        reenterTransfer = new ReentrantReceiver(token, bob, 0);
        reenterAndCall = new ReentrantReceiver(token, bob, 1);
        recomputer = new RecomputingMinter();
    }

    /// @dev The decrypted balances of every account a test in this file can credit.
    function _sumDecryptedBalances() internal returns (uint256 sum) {
        address[6] memory accounts = [holder, alice, bob, mallory, address(reenterTransfer), address(reenterAndCall)];
        for (uint256 i; i < accounts.length; ++i) {
            sum += decrypt(token.confidentialBalanceOf(accounts[i]));
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         TRANSFERS AND DISCLOSURE
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev M-01, H-14: a stranger's zero transfer rotates the recipient's balance handle.
    function test_ZeroHandleEmptyProofTransfer_ByStranger() public {
        bytes32 before = euint64.unwrap(token.confidentialBalanceOf(holder));
        vm.prank(mallory);
        euint64 t = token.confidentialTransfer(holder, externalEuint64.wrap(0), "");
        assertTrue(euint64.unwrap(token.confidentialBalanceOf(holder)) != before);
        assertEq(decrypt(token.confidentialBalanceOf(holder)), 1_000_000);
        assertEq(decrypt(t), 0);
    }

    /// @dev M-05, H-08: an operator publishes what it moved, through its transient grant on `transferred`.
    function test_RequestDisclose_ByOperatorWithTransientAccess() public {
        vm.prank(holder);
        token.setOperator(address(discloser), uint48(block.timestamp + 1));
        (externalEuint64 x, bytes memory p) = encryptUint64(1_000_000, address(discloser), diamond);
        bytes32 t = discloser.pullAndDisclose(token, holder, alice, x, p);
        assertTrue(_acl.isAllowedForDecryption(t));
        assertEq(decrypt(token.confidentialBalanceOf(alice)), 1_000_000);
    }

    /// @dev H-09: a callback receiver holds a persistent grant on `sent` and publishes it.
    function test_TransferAndCall_ReceiverPublishesSent() public {
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        vm.prank(holder);
        token.confidentialTransferAndCall(address(publish), x, p, "");
        assertTrue(_acl.isAllowedForDecryption(publish.lastSent()));
        assertTrue(_acl.persistAllowed(publish.lastSent(), address(publish)));
    }

    /// @dev H-10: a receiver that wipes the transaction's transient grants breaks nothing the token relies on.
    function test_TransferAndCall_ReceiverCleansTransientStorage() public {
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        vm.prank(holder);
        euint64 t = token.confidentialTransferAndCall(address(cleaner), x, p, "");
        assertEq(decrypt(t), 10);
        assertEq(
            decrypt(token.confidentialBalanceOf(holder)) + decrypt(token.confidentialBalanceOf(address(cleaner))),
            1_000_000
        );
    }

    /// @dev H-26, mode 0: the receiver re-enters `confidentialTransfer`; supply is conserved.
    function test_TransferAndCall_ReceiverReentersTransfer() public {
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        vm.prank(holder);
        token.confidentialTransferAndCall(address(reenterTransfer), x, p, "");
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 10);
        assertEq(_sumDecryptedBalances(), 1_000_000);
    }

    /// @dev H-26, mode 1: the receiver re-enters `confidentialTransferAndCall`; supply is conserved.
    function test_TransferAndCall_ReceiverReentersAndCall() public {
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        vm.prank(holder);
        token.confidentialTransferAndCall(address(reenterAndCall), x, p, "");
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 10);
        assertEq(_sumDecryptedBalances(), 1_000_000);
    }

    /// @dev H-15: a disclosure proof replays, re-emits {IERC7984.AmountDisclosed} and writes nothing.
    function test_Disclose_ReplayEmitsAgainAndChangesNoState() public {
        euint64 h = token.confidentialBalanceOf(holder);
        vm.prank(holder);
        IERC7984Disclosure(diamond).requestDiscloseEncryptedAmount(h);
        (, bytes memory proof) = publicDecrypt(_one32(euint64.unwrap(h)));
        IERC7984Disclosure(diamond).discloseEncryptedAmount(h, 1_000_000, proof);

        vm.record();
        vm.expectEmit(true, false, false, true, diamond);
        emit IERC7984.AmountDisclosed(h, 1_000_000);
        IERC7984Disclosure(diamond).discloseEncryptedAmount(h, 1_000_000, proof);
        (, bytes32[] memory writes) = vm.accesses(diamond);
        assertEq(writes.length, 0);
    }

    /// @dev H-16: an input proof is reusable by the sender it is bound to.
    function test_FromExternal_SameProofReusableBySameSender() public {
        (externalEuint64 x, bytes memory p) = _input(holder, 1);
        vm.startPrank(holder);
        token.confidentialTransfer(alice, x, p);
        token.confidentialTransfer(alice, x, p);
        vm.stopPrank();
        assertEq(decrypt(token.confidentialBalanceOf(alice)), 2);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             MINTERS (H-34)
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConfidentialMint_MinterLearnsOverflowBit() public {
        address d = _deployMintable(address(this), minter);
        (externalEuint64 x1, bytes memory p1) = encryptUint64(1_000_000, minter, d);
        (externalEuint64 x2, bytes memory p2) = encryptUint64(type(uint64).max, minter, d);
        vm.prank(minter);
        IERC7984Mintable(d).confidentialMint(holder, x1, p1);
        vm.prank(minter);
        euint64 m = IERC7984Mintable(d).confidentialMint(alice, x2, p2);
        assertTrue(_acl.persistAllowed(euint64.unwrap(m), minter));
        assertEq(decrypt(m), 0);
        assertEq(decrypt(IERC7984(d).confidentialTotalSupply()), 1_000_000);
    }

    /// @dev The empty-proof path of `fromExternal`: a minter mints a handle it is already allowed on.
    function test_ConfidentialMint_EmptyProofMintsAHandleTheMinterHolds() public {
        address d = _deployMintable(address(this), minter);
        (externalEuint64 x, bytes memory p) = encryptUint64(500, minter, d);
        vm.prank(minter);
        euint64 m = IERC7984Mintable(d).confidentialMint(alice, x, p);
        vm.prank(minter);
        IERC7984Mintable(d).confidentialMint(bob, externalEuint64.wrap(euint64.unwrap(m)), "");
        assertEq(decrypt(IERC7984(d).confidentialBalanceOf(bob)), 500);
        assertEq(decrypt(IERC7984(d).confidentialTotalSupply()), 1_000);
    }

    /// @dev One bit per mint, `S > 2^64-1-a`: 64 probes recover another minter's supply with no grant on it.
    function test_ConfidentialMint_OverflowBitIsASupplyThresholdOracle() public {
        address d = _deployMintable(address(this), minter);
        address probe = makeAddr("probe");
        IAccessControl(d).grantRole(ERC7984_MINTER_ROLE, probe);
        uint64 secret = 123_456_789;
        (externalEuint64 x0, bytes memory p0) = encryptUint64(secret, minter, d);
        vm.prank(minter);
        IERC7984Mintable(d).confidentialMint(holder, x0, p0);
        uint64 headroom;
        for (uint256 k = 64; k > 0; --k) {
            vm.roll(block.number + 1);
            vm.warp(block.timestamp + 12);
            uint64 a = uint64(1) << (k - 1);
            (externalEuint64 x, bytes memory p) = encryptUint64(a, probe, d);
            vm.prank(probe);
            euint64 m = IERC7984Mintable(d).confidentialMint(probe, x, p);
            assertFalse(_acl.persistAllowed(euint64.unwrap(IERC7984(d).confidentialTotalSupply()), probe));
            if (decrypt(m) != 0) headroom += a;
        }
        assertEq(type(uint64).max - headroom, secret);
    }

    /// @dev A minter contract recomputes, in its own mint's transaction, handles whose value it chose.
    function test_ConfidentialMint_RecomputingMinterGetsGrantsOnlyOnValuesItChose() public {
        address d = _deployMintable(address(this), address(recomputer));
        IERC7984Mintable t = IERC7984Mintable(d);
        (externalEuint64 x1, bytes memory p1) = encryptUint64(100, address(recomputer), d);
        bytes32 s1 = recomputer.firstMintAndTrack(t, alice, x1, p1);
        assertEq(s1, euint64.unwrap(IERC7984(d).confidentialTotalSupply()));
        assertTrue(_acl.persistAllowed(s1, address(recomputer)));
        vm.roll(block.number + 1);
        (externalEuint64 x2, bytes memory p2) = encryptUint64(250, address(recomputer), d);
        bytes32 s2 = recomputer.nextMintAndTrack(t, alice, x2, p2);
        assertEq(s2, euint64.unwrap(IERC7984(d).confidentialTotalSupply()));
        assertTrue(_acl.persistAllowed(s2, address(recomputer)));
        vm.roll(block.number + 1);
        (externalEuint64 x3, bytes memory p3) = encryptUint64(5, address(recomputer), d);
        bytes32 b = recomputer.mintAndGrabFreshBalance(t, bob, x3, p3);
        assertEq(b, euint64.unwrap(IERC7984(d).confidentialBalanceOf(bob)));
        assertTrue(_acl.persistAllowed(b, address(recomputer)));
        recomputer.disclose(IERC7984Disclosure(d), b);
        assertTrue(_acl.isAllowedForDecryption(b));
        assertEq(decrypt(IERC7984(d).confidentialTotalSupply()), 355);
        assertEq(decrypt(euint64.wrap(b)), 5);
    }
}
