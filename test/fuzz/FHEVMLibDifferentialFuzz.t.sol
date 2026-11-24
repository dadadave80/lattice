// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FhevmTestBase} from "@lattice-test/base/FhevmTestBase.sol";
import {FHEVMLibDiff, IFHEVMProbe, Seeder} from "@lattice-test/helpers/FHEVMLibProbes.sol";
import {externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IACL} from "@lattice/interfaces/external/fhevm/IACL.sol";
import {IKMSVerifier} from "@lattice/interfaces/external/fhevm/IKMSVerifier.sol";
import {FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";

/// @title FHEVMLibDifferentialFuzz
/// @notice Differential gate: every {FHEVMLib} member makes the same host calls, storage accesses, logs and
///         return or revert data as Zama's `FHE.sol` 0.13.4 (with OpenZeppelin Confidential Contracts 0.5.3
///         `FHESafeMath` over it) under every operand class.
contract FHEVMLibDifferentialFuzz is FhevmTestBase, FHEVMLibDiff {
    address constant USER = address(0xA11CE);

    /// @dev Operand classes: 0 uninitialized, 1 euint64 allowed to the probe and USER, 2 ebool allowed to the
    ///      probe and USER, 3 a foreign euint64 the probe is not allowed on.
    bytes32[4] internal cls;
    /// @dev A publicly decryptable class-1 handle for op 16.
    bytes32 internal h;
    /// @dev A Key Management Service (KMS) decryption proof of `h` decrypting to 7.
    bytes internal proofOk;
    /// @dev Accesses a pure op (id 0) records: the baseline every host-reaching case must exceed.
    uint256 internal pureAccesses;

    function setUp() public override {
        super.setUp();
        _install(false, FHEVMLib.hostsFor(block.chainid));
        vm.startPrank(USER);
        cls[1] = IFHEVMProbe(PROBE_AT).seed64(7);
        cls[2] = IFHEVMProbe(PROBE_AT).seedBool(true);
        vm.stopPrank();
        Seeder seeder = new Seeder();
        (externalEuint64 x, bytes memory p) = encryptUint64(9, address(this), address(seeder));
        cls[3] = seeder.seedFromInput(x, p);
        vm.prank(PROBE_AT);
        IACL(FHEVMLib.hostsFor(block.chainid).acl).allowForDecryption(_one(cls[1]));
        h = cls[1];
        proofOk = buildDecryptionProof(h, abi.encode(uint256(7)));
        // Access control list (ACL) grants are keyed by PROBE_AT, so they survive installing ThinProbe there.
        (,, pureAccesses) = _diff(USER, abi.encodeCall(IFHEVMProbe.op, (0, 0, 0, 0, 0, "")));
        assertGt(pureAccesses, 0, "pure baseline");
    }

    function test_EveryMemberEveryOperandClassMatchesFHE_Ids0To8() public {
        for (uint8 id; id <= 8; ++id) {
            _everyOperandClass(id);
        }
    }

    function test_EveryMemberEveryOperandClassMatchesFHE_Id9() public {
        _everyOperandClass(9);
    }

    function test_EveryMemberEveryOperandClassMatchesFHE_Ids10To18() public {
        for (uint8 id = 10; id <= 18; ++id) {
            _everyOperandClass(id);
        }
    }

    function test_CheckSignatures_VerifierReturnsFalse_BothRevertInvalidKMSSignatures() public {
        // The 1-signer harness never returns false, so mock it; the mock survives `_diff`'s state reverts.
        vm.mockCall(
            FHEVMLib.hostsFor(block.chainid).kmsVerifier,
            abi.encodeWithSelector(IKMSVerifier.verifyDecryptionEIP712KMSSignatures.selector),
            abi.encode(false)
        );
        (bool ok, bytes memory ret,) = _diff(USER, abi.encodeCall(IFHEVMProbe.op, (16, h, 0, 0, 7, proofOk)));
        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(FHEVMLib.InvalidKMSSignatures.selector));
    }

    function testFuzz_ArbitraryHandlesMatchFHE(uint8 id, bytes32 a, bytes32 b, bytes32 c, uint64 s) public {
        _diff(USER, abi.encodeCall(IFHEVMProbe.op, (uint8(bound(id, 0, 18)), a, b, c, s, "")));
    }

    function testFuzz_FromExternalMatchesFHE(uint64 value) public {
        (externalEuint64 x, bytes memory p) = encryptUint64(value, USER, PROBE_AT);
        (bool ok,,) = _diff(USER, abi.encodeCall(IFHEVMProbe.op, (4, externalEuint64.unwrap(x), 0, 0, 0, p)));
        assertTrue(ok, "success path");
    }

    function testFuzz_UpdatePathMatchesFHE(uint64 balance, uint64 amount, bool fromZero) public {
        (bool ok,,) = _diff(USER, abi.encodeCall(IFHEVMProbe.update, (balance, amount, fromZero)));
        assertTrue(ok, "success path");
    }

    function testFuzz_CheckSignaturesMatchesFHE(uint64 value, bool corrupt) public {
        // Seeded through the probe at PROBE_AT; the grants are keyed by PROBE_AT, so both runs see them.
        vm.prank(USER);
        bytes32 hv = IFHEVMProbe(PROBE_AT).seed64(value);
        vm.prank(PROBE_AT);
        IACL(FHEVMLib.hostsFor(block.chainid).acl).allowForDecryption(_one(hv));
        (, bytes memory proof) = publicDecrypt(_one(hv));
        (bool ok, bytes memory ret,) =
            _diff(USER, abi.encodeCall(IFHEVMProbe.op, (16, hv, 0, 0, corrupt ? value ^ 1 : value, proof)));
        assertEq(ok, !corrupt, "success path");
        if (corrupt) assertEq(bytes4(ret), IKMSVerifier.KMSInvalidSigner.selector);
    }

    /// @dev Every operand class of every operand position member `id` reads, for `s` in {0, 1, max} where `id`
    ///      reads `s`. Split across tests by id group to keep each test far below the block gas limit.
    function _everyOperandClass(uint8 id) internal {
        uint64[3] memory ss = [uint64(0), 1, type(uint64).max];
        if (id == 2 || id == 3 || id == 8) {
            for (uint256 k; k < 3; ++k) {
                for (uint256 i; i < (id == 8 ? 4 : 1); ++i) {
                    _check(id, cls[i], 0, 0, ss[k], "", id != 8 || i == 1);
                }
            }
        } else if (id == 4) {
            for (uint256 k; k < 3; ++k) {
                (externalEuint64 x, bytes memory p) = encryptUint64(ss[k], USER, PROBE_AT);
                _check(id, externalEuint64.unwrap(x), 0, 0, 0, p, true);
            }
            for (uint256 i; i < 4; ++i) {
                _check(id, cls[i], 0, 0, 0, "", i == 1);
            }
        } else if (id == 9) {
            for (uint256 i; i < 4; ++i) {
                for (uint256 j; j < 4; ++j) {
                    for (uint256 k; k < 4; ++k) {
                        _check(id, cls[i], cls[j], cls[k], 0, "", i == 2 && j == 1 && k == 1);
                    }
                }
            }
        } else if (id == 5 || id == 6 || id == 7) {
            for (uint256 i; i < 4; ++i) {
                for (uint256 j; j < 4; ++j) {
                    _check(id, cls[i], cls[j], 0, 0, "", i == 1 && j == 1);
                }
            }
        } else if (id == 16) {
            _check(id, h, 0, 0, 7, proofOk, true);
            (bool ok, bytes memory ret,) = _diff(USER, abi.encodeCall(IFHEVMProbe.op, (id, h, 0, 0, 8, proofOk)));
            assertFalse(ok);
            assertEq(bytes4(ret), IKMSVerifier.KMSInvalidSigner.selector);
        } else if (id == 17 || id == 18) {
            uint256[3] memory c3 = [uint256(0), 1, 3];
            for (uint256 i; i < 3; ++i) {
                for (uint256 j; j < 3; ++j) {
                    _check(id, cls[c3[i]], cls[c3[j]], 0, 0, "", i == 1 && j == 1);
                }
            }
        } else {
            for (uint256 i; i < 4; ++i) {
                _check(id, cls[i], 0, 0, 0, "", i == (id == 11 ? 2 : 1));
            }
        }
    }

    /// @dev Runs one differential case. The pure ids 0 and 1 record exactly {pureAccesses} accesses; every
    ///      other case must also reach a host contract. A `mustSucceed` case (a well-typed, allowed operand
    ///      set) must succeed on both sides, so the gate cannot pass on two identical reverts alone.
    function _check(uint8 id, bytes32 a, bytes32 b, bytes32 c, uint64 s, bytes memory data, bool mustSucceed) internal {
        (bool ok,, uint256 accessCount) = _diff(USER, abi.encodeCall(IFHEVMProbe.op, (id, a, b, c, s, data)));
        if (id > 1) assertGt(accessCount, pureAccesses, "empty trace");
        else assertEq(accessCount, pureAccesses, "pure trace");
        if (mustSucceed) assertTrue(ok, "success path");
    }
}
