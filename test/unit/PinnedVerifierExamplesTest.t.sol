// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ShieldedWithdrawFixture, TestWithdrawVerifier} from "@lattice-test/helpers/ShieldedWithdrawFixture.sol";
import {HashPinnedGroth16Verifier} from "@lattice/examples/privacy/HashPinnedGroth16Verifier.sol";
import {PinnedWithdrawVerifier} from "@lattice/examples/privacy/PinnedWithdrawVerifier.sol";
import {IGroth16Verifier} from "@lattice/interfaces/privacy/IGroth16Verifier.sol";
import {Groth16Verifier} from "@lattice/privacy/Groth16Verifier.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Key B: the fixture key with `ic[1]` and `ic[2]` swapped. Every point is still on the curve and the
///         arity is unchanged, so a proof made under key A reaches the pairing and fails there.
library KeyB {
    function verifyingKey() internal pure returns (IGroth16Verifier.VerifyingKey memory vk) {
        vk = ShieldedWithdrawFixture.verifyingKey();
        uint256[2] memory ic1 = vk.ic[1];
        vk.ic[1] = vk.ic[2];
        vk.ic[2] = ic1;
    }
}

/// @notice The {PinnedWithdrawVerifier} example pinned to key B.
contract KeyBWithdrawVerifier is PinnedWithdrawVerifier {
    constructor(IGroth16Verifier g) PinnedWithdrawVerifier(g) {}

    function _verifyingKey() internal pure override returns (IGroth16Verifier.VerifyingKey memory) {
        return KeyB.verifyingKey();
    }
}

/// @title PinnedVerifierExamplesTest
/// @notice Regression tests for the two key-pinning examples in `src/examples/privacy/`, using the real
///         shielded-pool withdraw proof (key A). A proof valid under key A must pass a verifier pinned to A and
///         fail one pinned to B; a hash-pinned verifier must refuse any key but its own before verifying.
contract PinnedVerifierExamplesTest is Test {
    IGroth16Verifier groth16;

    function setUp() public {
        groth16 = new Groth16Verifier();
    }

    function _input() internal pure returns (uint256[] memory input) {
        uint256[5] memory s = ShieldedWithdrawFixture.signals();
        input = new uint256[](5);
        for (uint256 i; i < 5; ++i) {
            input[i] = s[i];
        }
    }

    function _hash(IGroth16Verifier.VerifyingKey memory vk) internal pure returns (bytes32) {
        return keccak256(abi.encode(vk));
    }

    function test_KeysDiffer() public pure {
        assertTrue(_hash(ShieldedWithdrawFixture.verifyingKey()) != _hash(KeyB.verifyingKey()));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        CONSTANT PATTERN (ADAPTER)
    //////////////////////////////////////////////////////////////////////////*//

    function test_PinnedAdapter_AcceptsProofUnderItsKey() public {
        TestWithdrawVerifier pinnedA = new TestWithdrawVerifier(groth16);
        IGroth16Verifier.Proof memory p = ShieldedWithdrawFixture.proof();
        assertTrue(pinnedA.verifyProof(p.a, p.b, p.c, ShieldedWithdrawFixture.signals()));
    }

    function test_PinnedAdapter_RejectsProofUnderOtherKey() public {
        KeyBWithdrawVerifier pinnedB = new KeyBWithdrawVerifier(groth16);
        IGroth16Verifier.Proof memory p = ShieldedWithdrawFixture.proof();
        assertFalse(pinnedB.verifyProof(p.a, p.b, p.c, ShieldedWithdrawFixture.signals()));
    }

    function test_PinnedAdapter_ZeroVerifierReverts() public {
        vm.expectRevert(PinnedWithdrawVerifier.PinnedWithdrawVerifier__ZeroAddress.selector);
        new TestWithdrawVerifier(IGroth16Verifier(address(0)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           STORED-HASH PATTERN
    //////////////////////////////////////////////////////////////////////////*//

    function test_HashPinned_AcceptsPinnedKey() public {
        IGroth16Verifier.VerifyingKey memory keyA = ShieldedWithdrawFixture.verifyingKey();
        HashPinnedGroth16Verifier pinnedA = new HashPinnedGroth16Verifier(groth16, _hash(keyA));
        assertTrue(pinnedA.verifyProof(keyA, ShieldedWithdrawFixture.proof(), _input()));
    }

    /// @notice A caller cannot substitute their own key: the verifier pinned to B's hash reverts on key A
    ///         before any verification runs, even though the proof is valid under A.
    function test_HashPinned_RevertsOnUnpinnedKey() public {
        IGroth16Verifier.VerifyingKey memory keyA = ShieldedWithdrawFixture.verifyingKey();
        HashPinnedGroth16Verifier pinnedB = new HashPinnedGroth16Verifier(groth16, _hash(KeyB.verifyingKey()));
        assertTrue(groth16.verifyProof(keyA, ShieldedWithdrawFixture.proof(), _input()), "proof valid under A");

        vm.expectRevert(
            abi.encodeWithSelector(
                HashPinnedGroth16Verifier.HashPinnedGroth16Verifier__UnpinnedKey.selector, _hash(keyA)
            )
        );
        pinnedB.verifyProof(keyA, ShieldedWithdrawFixture.proof(), _input());
    }

    function test_HashPinned_RejectsProofUnderOtherKey() public {
        IGroth16Verifier.VerifyingKey memory keyB = KeyB.verifyingKey();
        HashPinnedGroth16Verifier pinnedB = new HashPinnedGroth16Verifier(groth16, _hash(keyB));
        assertFalse(pinnedB.verifyProof(keyB, ShieldedWithdrawFixture.proof(), _input()));
    }

    function test_HashPinned_ConstructorRejectsZeroes() public {
        vm.expectRevert(HashPinnedGroth16Verifier.HashPinnedGroth16Verifier__ZeroAddress.selector);
        new HashPinnedGroth16Verifier(IGroth16Verifier(address(0)), bytes32(uint256(1)));
        vm.expectRevert(HashPinnedGroth16Verifier.HashPinnedGroth16Verifier__ZeroHash.selector);
        new HashPinnedGroth16Verifier(groth16, bytes32(0));
    }
}
