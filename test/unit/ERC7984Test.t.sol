// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC7984TestBase} from "@lattice-test/base/ERC7984TestBase.sol";
import {
    AcceptReceiver,
    EmptyRevertReceiver,
    Euint64AsBoolReceiver,
    ForeignBoolReceiver,
    OperatorRecordingReceiver,
    RejectReceiver,
    SpendThenRejectReceiver,
    StringRevertReceiver,
    UninitializedReceiver
} from "@lattice-test/helpers/ERC7984Actors.sol";
import {ERC7984TestFacet} from "@lattice-test/helpers/ERC7984TestFacet.sol";
import {aclAdd} from "@lattice-test/helpers/fhevm/fhevm-host/addresses/FHEVMHostAddresses.sol";
import {FheType} from "@lattice-test/helpers/fhevm/fhevm-host/contracts/shared/FheType.sol";
import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IACL} from "@lattice/interfaces/external/fhevm/IACL.sol";
import {IFHEVMExecutor} from "@lattice/interfaces/external/fhevm/IFHEVMExecutor.sol";
import {IKMSVerifier} from "@lattice/interfaces/external/fhevm/IKMSVerifier.sol";
import {IERC7984, IERC7984Disclosure} from "@lattice/interfaces/tokens/IERC7984.sol";
import {IMulticall} from "@lattice/interfaces/utils/IMulticall.sol";
import {ERC7984} from "@lattice/tokens/ERC7984/ERC7984.sol";

/// @dev Calls `confidentialTransferAndCall` and reads its own access to the result within the same call.
contract TransientGrantProbe {
    function sendAndCall(IERC7984 token, address to, externalEuint64 x, bytes calldata p)
        external
        returns (bytes32 t, bool allowed)
    {
        t = euint64.unwrap(token.confidentialTransferAndCall(to, x, p, ""));
        allowed = IACL(aclAdd).isAllowed(t, address(this));
    }
}

/// @title ERC7984Test
/// @notice Behaviour of the ERC-7984 (confidential fungible token) facet over a real diamond: the entry guard,
///         handle checks, exact access control list (ACL) grant sets, receiver callbacks, operators and disclosure.
contract ERC7984Test is ERC7984TestBase {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Calldata for guarded entrypoint `i`: the eight movers, `setOperator`, `requestDiscloseEncryptedAmount`.
    function _guardedCall(uint256 i) internal view returns (bytes memory) {
        bytes32 h = bytes32(uint256(1));
        if (i == 0) return abi.encodeWithSelector(bytes4(0x2fb74e62), alice, h, hex"00");
        if (i == 1) return abi.encodeWithSelector(bytes4(0x5bebed7e), alice, h);
        if (i == 2) return abi.encodeWithSelector(bytes4(0xe064b9bb), holder, alice, h, hex"00");
        if (i == 3) return abi.encodeWithSelector(bytes4(0xeb3155b5), holder, alice, h);
        if (i == 4) return abi.encodeWithSelector(bytes4(0xde642119), alice, h, hex"00", "");
        if (i == 5) return abi.encodeWithSelector(bytes4(0x537d3c50), alice, h, "");
        if (i == 6) return abi.encodeWithSelector(bytes4(0x34c45743), holder, alice, h, hex"00", "");
        if (i == 7) return abi.encodeWithSelector(bytes4(0xc7b8a75e), holder, alice, h, "");
        if (i == 8) return abi.encodeWithSelector(bytes4(0xd4febb96), alice, uint48(1));
        return abi.encodeWithSelector(bytes4(0xd8061806), h);
    }

    /// @dev Sends an encrypted 10 from `holder` to `to` through `confidentialTransferAndCall`.
    function _sendAndCall(address to) internal returns (euint64 t) {
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        vm.prank(holder);
        t = token.confidentialTransferAndCall(to, x, p, "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         SELF-CALLS (H-03, H-16)
    //////////////////////////////////////////////////////////////////////////*//

    function testFuzz_SelfCall_RevertOnEveryGuardedEntrypoint(uint8 i) public {
        bytes memory data = _guardedCall(bound(i, 0, 9));
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984UnauthorizedCaller.selector, diamond));
        ERC7984TestFacet(diamond).selfCall(data);
    }

    function test_SelfCall_ProofBoundToDiamondReverts() public {
        (externalEuint64 x, bytes memory p) = encryptUint64(1, diamond, diamond);
        bytes memory data = abi.encodeWithSelector(bytes4(0x2fb74e62), alice, x, p);
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984UnauthorizedCaller.selector, diamond));
        ERC7984TestFacet(diamond).selfCall(data);
    }

    function test_Multicall_KeepsOuterSender() public {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(bytes4(0x5bebed7e), alice, token.confidentialBalanceOf(holder));
        vm.prank(holder);
        IMulticall(diamond).multicall(calls);
        assertEq(decrypt(token.confidentialBalanceOf(alice)), 1_000_000);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //            FOREIGN, WRONG-TYPED AND ZERO HANDLES (H-11, H-12)
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Security requirement 1 (SR-01, `isAllowed(amount, msg.sender)`) passes; the executor's check on the
    ///      diamond does not (spec Q3).
    function test_ProofFreeTransfer_RevertWhen_AmountNotAllowedToDiamond() public {
        bytes32 h = maker.make(5, uint8(FheType.Uint64), _one(holder));
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IFHEVMExecutor.ACLNotAllowed.selector, h, diamond));
        token.confidentialTransfer(alice, euint64.wrap(h));
    }

    function test_ConfidentialTransfer_RevertWhen_AmountHandleNotAllowedToSender() public {
        euint64 victim = token.confidentialBalanceOf(holder);
        vm.prank(mallory);
        vm.expectRevert(
            abi.encodeWithSelector(IERC7984.ERC7984UnauthorizedUseOfEncryptedAmount.selector, victim, mallory)
        );
        token.confidentialTransfer(alice, victim);
    }

    function test_ConfidentialTransfer_RevertWhen_HandleTypeMismatch() public {
        bytes32 h32 = maker.make(7, uint8(FheType.Uint32), _two(holder, diamond));
        vm.prank(holder);
        vm.expectRevert(bytes4(0xb9688461));
        token.confidentialTransfer(alice, euint64.wrap(h32));
    }

    function test_RequestDisclose_RevertWhen_HandleTypeMismatch() public {
        bytes32 b = maker.make(1, uint8(FheType.Bool), _one(holder));
        vm.prank(holder);
        vm.expectRevert(bytes4(0xb9688461));
        IERC7984Disclosure(diamond).requestDiscloseEncryptedAmount(euint64.wrap(b));
    }

    function test_RequestDisclose_RevertWhen_TotalSupplyHandle() public {
        euint64 s = token.confidentialTotalSupply();
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984UnauthorizedUseOfEncryptedAmount.selector, s, holder));
        IERC7984Disclosure(diamond).requestDiscloseEncryptedAmount(s);
    }

    function test_ConfidentialTransfer_FromNeverFundedSenderMovesZero() public {
        (externalEuint64 x, bytes memory p) = _input(bob, 5);
        vm.prank(bob);
        euint64 t = token.confidentialTransfer(alice, x, p);
        assertEq(decrypt(t), 0);
        assertEq(decrypt(token.confidentialBalanceOf(alice)), 0);
    }

    function test_FirstReceiverBalanceIsInitialized() public {
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        vm.prank(holder);
        token.confidentialTransfer(alice, x, p);
        bytes32 ab = euint64.unwrap(token.confidentialBalanceOf(alice));
        assertTrue(ab != bytes32(0));
        assertTrue(_acl.persistAllowed(ab, alice));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    EXACT ACL GRANT SETS (H-07, H-25)
    //////////////////////////////////////////////////////////////////////////*//

    function test_Update_GrantsExactAclSet() public {
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        vm.prank(holder);
        bytes32 th = euint64.unwrap(token.confidentialTransfer(alice, x, p));
        bytes32 hb = euint64.unwrap(token.confidentialBalanceOf(holder));
        bytes32 ab = euint64.unwrap(token.confidentialBalanceOf(alice));
        assertTrue(_acl.persistAllowed(hb, holder));
        assertTrue(_acl.persistAllowed(hb, diamond));
        assertFalse(_acl.persistAllowed(hb, alice));
        assertFalse(_acl.persistAllowed(hb, mallory));
        assertTrue(_acl.persistAllowed(ab, alice));
        assertTrue(_acl.persistAllowed(ab, diamond));
        assertFalse(_acl.persistAllowed(ab, holder));
        assertFalse(_acl.persistAllowed(ab, mallory));
        assertTrue(_acl.persistAllowed(th, holder));
        assertTrue(_acl.persistAllowed(th, alice));
        assertTrue(_acl.persistAllowed(th, diamond));
        assertFalse(_acl.persistAllowed(th, mallory));
    }

    /// @dev Spec 5.3, H-30: handles are per block, not per account.
    function test_UnfundedSendersInOneBlockShareTheZeroBalanceHandle() public {
        (externalEuint64 x1, bytes memory p1) = _input(bob, 5);
        vm.prank(bob);
        token.confidentialTransfer(alice, x1, p1);
        (externalEuint64 x2, bytes memory p2) = _input(mallory, 5);
        vm.prank(mallory);
        token.confidentialTransfer(alice, x2, p2);
        bytes32 b1 = euint64.unwrap(token.confidentialBalanceOf(bob));
        assertEq(b1, euint64.unwrap(token.confidentialBalanceOf(mallory)));
        assertTrue(_acl.persistAllowed(b1, mallory));
        assertTrue(_acl.persistAllowed(b1, bob));
        assertEq(decrypt(b1), 0);
    }

    /// @dev H-25: `tryIncrease` returns the delta while the supply is uninitialized.
    function test_FirstMint_TotalSupplyIsTheMintAmountHandle() public {
        address t2 = _deployToken();
        bytes32 m = _executor.trivialEncrypt(500, FheType.Uint64);
        ERC7984TestFacet(t2).mint(alice, 500);
        assertEq(euint64.unwrap(IERC7984(t2).confidentialTotalSupply()), m);
    }

    function test_TotalSupply_AllowedOnlyToDiamond() public view {
        bytes32 s = euint64.unwrap(token.confidentialTotalSupply());
        assertTrue(_acl.persistAllowed(s, diamond));
        assertFalse(_acl.persistAllowed(s, holder));
        assertFalse(_acl.persistAllowed(s, address(this)));
    }

    function test_BalanceOf_DoesNotGrantAccess() public {
        vm.record();
        token.confidentialBalanceOf(holder);
        (, bytes32[] memory writes) = vm.accesses(aclAdd);
        assertEq(writes.length, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               RECEIVERS (H-09)
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransferAndCall_ReceiverAcceptsKeepsFunds() public {
        AcceptReceiver accept = new AcceptReceiver();
        euint64 t = _sendAndCall(address(accept));
        assertEq(decrypt(t), 10);
        assertEq(decrypt(token.confidentialBalanceOf(address(accept))), 10);
    }

    /// @dev OZ `ERC7984.sol:283`: `sent - refund` is transiently allowed to the caller, and persistently to no one.
    ///      The host clears transient grants between top-level test calls, so a probe reads it in the same call.
    function test_TransferAndCall_ResultTransientlyAllowedToCallerOnly() public {
        AcceptReceiver accept = new AcceptReceiver();
        TransientGrantProbe probe = new TransientGrantProbe();
        ERC7984TestFacet(diamond).mint(address(probe), 10);
        (externalEuint64 x, bytes memory p) = _input(address(probe), 10);
        (bytes32 t, bool allowed) = probe.sendAndCall(token, address(accept), x, p);
        assertTrue(allowed);
        assertFalse(_acl.persistAllowed(t, address(probe)));
        assertFalse(_acl.persistAllowed(t, address(accept)));
        assertEq(decrypt(t), 10);
    }

    function test_TransferAndCall_ReceiverRejectsRefundsFully() public {
        RejectReceiver reject = new RejectReceiver();
        euint64 t = _sendAndCall(address(reject));
        assertEq(decrypt(t), 0);
        assertEq(decrypt(token.confidentialBalanceOf(holder)), 1_000_000);
    }

    /// @dev The receiver forwards 10 to bob and returns false; the refund finds nothing (C-01).
    function test_TransferAndCall_ReceiverSpendsThenRejects_ReturnsSentMinusRefund() public {
        SpendThenRejectReceiver spender = new SpendThenRejectReceiver(token, bob);
        euint64 t = _sendAndCall(address(spender));
        assertEq(decrypt(t), 10);
        assertEq(decrypt(token.confidentialBalanceOf(holder)), 999_990);
        assertEq(decrypt(token.confidentialBalanceOf(bob)), 10);
    }

    function test_TransferAndCall_UninitializedReturnTreatedAsFalse() public {
        UninitializedReceiver uninit = new UninitializedReceiver();
        euint64 t = _sendAndCall(address(uninit));
        assertEq(decrypt(t), 0);
        assertEq(decrypt(token.confidentialBalanceOf(holder)), 1_000_000);
    }

    function test_TransferAndCall_RevertWhen_ReceiverReturnsHandleItCannotUse() public {
        ForeignBoolReceiver foreign = new ForeignBoolReceiver(maker);
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        bytes32 fh = foreign.handle();
        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(IERC7984.ERC7984UtilsUnauthorizedUseOfEncryptedAmount.selector, fh, address(foreign))
        );
        token.confidentialTransferAndCall(address(foreign), x, p, "");
    }

    function test_TransferAndCall_RevertWhen_ReceiverReturnsEuint64AsEbool() public {
        Euint64AsBoolReceiver wrong = new Euint64AsBoolReceiver();
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        vm.prank(holder);
        vm.expectRevert(bytes4(0xb9688461));
        token.confidentialTransferAndCall(address(wrong), x, p, "");
    }

    /// @dev alice has no code: she is credited 10 with no callback.
    function test_TransferAndCall_ToEoaIsPlainTransfer() public {
        euint64 t = _sendAndCall(alice);
        assertEq(decrypt(t), 10);
        assertEq(decrypt(token.confidentialBalanceOf(alice)), 10);
    }

    function test_TransferAndCall_EmptyRevertIsInvalidReceiver() public {
        EmptyRevertReceiver emptyRevert = new EmptyRevertReceiver();
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984InvalidReceiver.selector, address(emptyRevert)));
        token.confidentialTransferAndCall(address(emptyRevert), x, p, "");
    }

    function test_TransferAndCall_BubblesReceiverError() public {
        StringRevertReceiver nope = new StringRevertReceiver("nope");
        (externalEuint64 x, bytes memory p) = _input(holder, 10);
        vm.prank(holder);
        vm.expectRevert(bytes("nope"));
        token.confidentialTransferAndCall(address(nope), x, p, "");
    }

    function test_TransferFromAndCall_CallbackSeesOperator() public {
        OperatorRecordingReceiver recorder = new OperatorRecordingReceiver();
        vm.prank(holder);
        token.setOperator(op, uint48(vm.getBlockTimestamp() + 100));
        (externalEuint64 x, bytes memory p) = _input(op, 10);
        vm.prank(op);
        token.confidentialTransferFromAndCall(holder, address(recorder), x, p, "");
        assertEq(recorder.lastOperator(), op);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    INTEGER BEHAVIOUR (H-13, SR-09, SR-11)
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConfidentialTransfer_InsufficientBalanceTransfersZero() public {
        (externalEuint64 x, bytes memory p) = _input(holder, 1_000_001);
        vm.prank(holder);
        euint64 t = token.confidentialTransfer(alice, x, p);
        assertEq(decrypt(t), 0);
        assertEq(decrypt(token.confidentialBalanceOf(holder)), 1_000_000);
    }

    function test_Mint_OverflowingTotalSupplyMintsZero() public {
        euint64 m = ERC7984TestFacet(diamond).mint(alice, type(uint64).max);
        assertEq(decrypt(m), 0);
        assertEq(decrypt(token.confidentialTotalSupply()), 1_000_000);
    }

    function testFuzz_Transfer_ConservesSupply(uint64 a) public {
        (externalEuint64 x, bytes memory p) = _input(holder, a);
        vm.prank(holder);
        token.confidentialTransfer(alice, x, p);
        assertEq(
            uint256(decrypt(token.confidentialBalanceOf(holder))) + decrypt(token.confidentialBalanceOf(alice)),
            1_000_000
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                  GUARDS AND OPERATORS (H-19, H-23, H-31)
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev A diamond with the ERC7984 facet cut and no ERC7984Init.
    function test_Uninitialized_TransferReverts() public {
        vm.prank(holder);
        vm.expectRevert(IERC7984.ERC7984NotInitialized.selector);
        IERC7984(bare).confidentialTransfer(alice, euint64.wrap(bytes32(uint256(1))));
    }

    /// @dev Another `FHE.sol` facet's initializer wrote the shared config slot (H-19).
    function test_ForeignConfigWithoutInit_TransferReverts() public {
        address d = _bareWithConfig();
        vm.prank(holder);
        vm.expectRevert(IERC7984.ERC7984NotInitialized.selector);
        IERC7984(d).confidentialTransfer(alice, euint64.wrap(bytes32(uint256(1))));
    }

    function test_Transfer_RevertWhen_ToIsDiamond() public {
        euint64 b = token.confidentialBalanceOf(holder);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984InvalidReceiver.selector, diamond));
        token.confidentialTransfer(diamond, b);
    }

    function test_Mint_RevertWhen_ToIsDiamond() public {
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984InvalidReceiver.selector, diamond));
        ERC7984TestFacet(diamond).mint(diamond, 1);
    }

    function test_ConfidentialTransfer_RevertWhen_ToIsZero() public {
        euint64 b = token.confidentialBalanceOf(holder);
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984InvalidReceiver.selector, address(0)));
        token.confidentialTransfer(address(0), b);
    }

    function test_ConfidentialTransferFrom_RevertWhen_NotOperator() public {
        (externalEuint64 x, bytes memory p) = _input(mallory, 1);
        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984UnauthorizedSpender.selector, holder, mallory));
        token.confidentialTransferFrom(holder, mallory, x, p);
    }

    function test_IsOperator_ExpiresAfterUntil() public {
        uint256 t0 = vm.getBlockTimestamp();
        vm.prank(holder);
        token.setOperator(op, uint48(t0 + 100));
        vm.warp(t0 + 100);
        assertTrue(token.isOperator(holder, op));
        vm.warp(t0 + 101);
        assertFalse(token.isOperator(holder, op));
        assertTrue(token.isOperator(holder, holder));
    }

    /// @dev OZ 0.5.3 behaviour kept (H-31).
    function test_SetOperator_SelfAndZeroAreInert() public {
        uint48 until = uint48(vm.getBlockTimestamp() + 1);
        vm.startPrank(holder);
        token.setOperator(holder, 1);
        token.setOperator(address(0), until);
        vm.stopPrank();
        assertTrue(token.isOperator(holder, holder));
        assertTrue(token.isOperator(holder, address(0)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               DISCLOSURE (H-06)
    //////////////////////////////////////////////////////////////////////////*//

    function test_RequestDiscloseAndDisclose_ByHolder() public {
        euint64 h = token.confidentialBalanceOf(holder);
        vm.expectEmit(true, true, false, false, diamond);
        emit IERC7984Disclosure.AmountDiscloseRequested(h, holder);
        vm.prank(holder);
        IERC7984Disclosure(diamond).requestDiscloseEncryptedAmount(h);
        assertTrue(_acl.isAllowedForDecryption(euint64.unwrap(h)));
        (, bytes memory proof) = publicDecrypt(_one32(euint64.unwrap(h)));
        vm.expectEmit(true, false, false, true, diamond);
        emit IERC7984.AmountDisclosed(h, 1_000_000);
        IERC7984Disclosure(diamond).discloseEncryptedAmount(h, 1_000_000, proof);
    }

    /// @dev Same proof, cleartext 1_000_001: the recovered signer is not a KMS (Key Management Service) signer.
    function test_Disclose_RevertWhen_WrongCleartext() public {
        euint64 h = token.confidentialBalanceOf(holder);
        vm.prank(holder);
        IERC7984Disclosure(diamond).requestDiscloseEncryptedAmount(h);
        (, bytes memory proof) = publicDecrypt(_one32(euint64.unwrap(h)));
        vm.expectPartialRevert(IKMSVerifier.KMSInvalidSigner.selector);
        IERC7984Disclosure(diamond).discloseEncryptedAmount(h, 1_000_001, proof);
    }

    function test_Disclose_RevertWhen_ProofForOtherHandle() public {
        euint64 h = token.confidentialBalanceOf(holder);
        euint64 other = token.confidentialTotalSupply();
        vm.prank(holder);
        IERC7984Disclosure(diamond).requestDiscloseEncryptedAmount(h);
        (, bytes memory proof) = publicDecrypt(_one32(euint64.unwrap(h)));
        vm.expectPartialRevert(IKMSVerifier.KMSInvalidSigner.selector);
        IERC7984Disclosure(diamond).discloseEncryptedAmount(other, 1_000_000, proof);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SURFACE
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExportSelectors_Pinned() public {
        assertEq(
            new ERC7984().exportSelectors(),
            hex"344ff101540952275bebed7e2fb74e62537d3c50de642119eb3155b5e064b9bbc7b8a75e34c45743e8a3d485313ce567b1af281eb6363cf206fdde03d8061806d4febb9695d89b41"
        );
    }

    function test_Metadata() public view {
        assertEq(token.name(), "Confidential Token");
        assertEq(token.symbol(), "cTKN");
        assertEq(token.decimals(), 6);
        assertEq(token.contractURI(), "ipfs://contract");
    }
}
