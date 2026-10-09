// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Harness that exposes ECDSA internal functions as external calls.
contract ECDSAFuzzHarness {
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) external pure returns (address) {
        return ECDSA.recover(hash, v, r, s);
    }

    function recoverBytes(bytes32 hash, bytes memory signature) external pure returns (address) {
        return ECDSA.recover(hash, signature);
    }

    function recoverCompact(bytes32 hash, bytes32 r, bytes32 vs) external pure returns (address) {
        return ECDSA.recover(hash, r, vs);
    }

    function tryRecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        external
        pure
        returns (address recovered, ECDSA.RecoverError err, bytes32 errArg)
    {
        return ECDSA.tryRecover(hash, v, r, s);
    }

    function tryRecoverBytes(bytes32 hash, bytes memory signature)
        external
        pure
        returns (address recovered, ECDSA.RecoverError err, bytes32 errArg)
    {
        return ECDSA.tryRecover(hash, signature);
    }
}

/// @title ECDSAFuzz
contract ECDSAFuzz is Test {
    /// @dev secp256k1 group order n.
    uint256 internal constant SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    ECDSAFuzzHarness harness;

    function setUp() public {
        harness = new ECDSAFuzzHarness();
    }

    // -------------------------------------------------------------------------
    // Round-trip: sign then recover
    // -------------------------------------------------------------------------

    /// @notice vm.sign + ECDSA.recover returns the expected signer for any hash and any private key.
    function testFuzz_RecoverRoundTrip(bytes32 hash, uint256 pkSeed) public view {
        // Derive a valid private key in [1, n-1].
        uint256 pk = bound(pkSeed, 1, SECP256K1_N - 1);

        address expected = vm.addr(pk);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);

        address recovered = harness.recover(hash, v, r, s);
        assertEq(recovered, expected, "recovered signer must match vm.addr(pk)");
    }

    // -------------------------------------------------------------------------
    // High-S rejection
    // -------------------------------------------------------------------------

    /// @notice Flipping s to its high-half complement causes ECDSA.recover to revert ECDSAInvalidSignatureS.
    function testFuzz_HighSReverts(bytes32 hash, uint256 pkSeed) public {
        uint256 pk = bound(pkSeed, 1, SECP256K1_N - 1);

        (, bytes32 r, bytes32 s) = vm.sign(pk, hash);

        // vm.sign always returns low-S; skip if s is already in the high half (shouldn't happen, but guard).
        vm.assume(uint256(s) <= SECP256K1_N / 2);

        // High-S complement: s' = n - s.
        bytes32 highS = bytes32(SECP256K1_N - uint256(s));
        // Pack as 65-byte signature; v doesn't matter since the high-S check fires first.
        bytes memory sig = abi.encodePacked(r, highS, uint8(27));

        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, highS));
        harness.recoverBytes(hash, sig);
    }

    // -------------------------------------------------------------------------
    // Differential: raw ecrecover plus the malleability rules
    // -------------------------------------------------------------------------

    /// @notice On arbitrary (hash, v, r, s), tryRecover and recover agree with the reference rules: reject
    ///         `s > n / 2` (InvalidSignatureS), else defer to the ecrecover precompile and reject a zero address.
    function testFuzz_TryRecoverMatchesEcrecoverRules(bytes32 hash, uint8 v, bytes32 r, bytes32 s) public view {
        _assertMatchesReference(hash, v, r, s);
    }

    /// @notice As above with a well-formed `v` and a low `s`, so ecrecover runs and usually yields an address.
    function testFuzz_TryRecoverMatchesEcrecoverWithLowS(bytes32 hash, bool yParity, bytes32 r, uint256 s) public view {
        s = bound(s, 0, SECP256K1_N / 2);
        _assertMatchesReference(hash, yParity ? 28 : 27, r, bytes32(s));
    }

    /// @notice The malleable twin of a valid signature, `(v ^ 1, r, n - s)`, recovers the SAME signer through raw
    ///         ecrecover, and ECDSA rejects exactly that twin.
    function testFuzz_MalleableTwinRejected(bytes32 hash, uint256 pkSeed) public view {
        uint256 pk = bound(pkSeed, 1, SECP256K1_N - 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        bytes32 twinS = bytes32(SECP256K1_N - uint256(s));
        uint8 twinV = v == 27 ? 28 : 27;

        assertEq(ecrecover(hash, twinV, r, twinS), vm.addr(pk), "raw ecrecover accepts the twin");
        (address recovered, ECDSA.RecoverError err, bytes32 errArg) = harness.tryRecover(hash, twinV, r, twinS);
        assertEq(recovered, address(0), "twin recovers nothing");
        assertEq(uint8(err), uint8(ECDSA.RecoverError.InvalidSignatureS), "twin rejected as high-S");
        assertEq(errArg, twinS, "error carries s");
    }

    /// @notice The EIP-2098 compact form `(r, yParity << 255 | s)`, raw or as 64 bytes, recovers the same as the
    ///         expanded `(27 + yParity, r, s)` — for any r and any 255-bit s.
    function testFuzz_CompactFormMatchesExpanded(bytes32 hash, bool yParity, bytes32 r, uint256 s) public view {
        s = s >> 1;
        uint8 v = yParity ? 28 : 27;
        bytes32 vs = bytes32((yParity ? uint256(1) << 255 : 0) | s);

        _assertTryRecover(
            abi.encodeCall(harness.tryRecoverBytes, (hash, abi.encodePacked(r, vs))), hash, v, r, bytes32(s), "64-byte"
        );
        _assertRecover(abi.encodeCall(harness.recoverCompact, (hash, r, vs)), hash, v, r, bytes32(s), "compact");
    }

    /// @notice A real signature round-trips through all three encodings to the signer.
    function testFuzz_SignedEncodingsAgree(bytes32 hash, uint256 pkSeed) public view {
        uint256 pk = bound(pkSeed, 1, SECP256K1_N - 1);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        bytes32 vs = bytes32((uint256(v - 27) << 255) | uint256(s));
        address signer = vm.addr(pk);

        assertEq(harness.recoverBytes(hash, abi.encodePacked(r, s, v)), signer, "65-byte form");
        assertEq(harness.recoverBytes(hash, abi.encodePacked(r, vs)), signer, "64-byte form");
        assertEq(harness.recoverCompact(hash, r, vs), signer, "compact (r, vs)");
    }

    /// @notice Any signature length other than 64 or 65 bytes is rejected with its length.
    function testFuzz_InvalidLengthRejected(bytes32 hash, bytes memory signature) public view {
        vm.assume(signature.length != 64 && signature.length != 65);
        (address recovered, ECDSA.RecoverError err, bytes32 errArg) = harness.tryRecoverBytes(hash, signature);
        assertEq(recovered, address(0), "nothing recovered");
        assertEq(uint8(err), uint8(ECDSA.RecoverError.InvalidSignatureLength), "length error");
        assertEq(uint256(errArg), signature.length, "error carries length");
    }

    /// @dev The reference rules, applied in OpenZeppelin's order: high-S first, then ecrecover's zero address.
    function _reference(bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        internal
        pure
        returns (address, ECDSA.RecoverError, bytes32)
    {
        if (uint256(s) > SECP256K1_N / 2) return (address(0), ECDSA.RecoverError.InvalidSignatureS, s);
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) return (address(0), ECDSA.RecoverError.InvalidSignature, bytes32(0));
        return (signer, ECDSA.RecoverError.NoError, bytes32(0));
    }

    function _assertMatchesReference(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal view {
        _assertTryRecover(abi.encodeCall(harness.tryRecover, (hash, v, r, s)), hash, v, r, s, "tryRecover");
        _assertRecover(abi.encodeCall(harness.recover, (hash, v, r, s)), hash, v, r, s, "recover");
    }

    /// @dev A `tryRecover` call returns the reference (signer, error, error argument) for the expanded `(v, r, s)`.
    function _assertTryRecover(bytes memory data, bytes32 hash, uint8 v, bytes32 r, bytes32 s, string memory label)
        internal
        view
    {
        (address expected, ECDSA.RecoverError expectedErr, bytes32 expectedArg) = _reference(hash, v, r, s);
        (bool ok, bytes memory ret) = address(harness).staticcall(data);
        assertTrue(ok, string.concat(label, ": tryRecover never reverts"));
        (address got, ECDSA.RecoverError err, bytes32 errArg) = abi.decode(ret, (address, ECDSA.RecoverError, bytes32));
        assertEq(got, expected, string.concat(label, ": signer"));
        assertEq(uint8(err), uint8(expectedErr), string.concat(label, ": error"));
        assertEq(errArg, expectedArg, string.concat(label, ": error argument"));
    }

    /// @dev A `recover` call returns the reference signer on NoError, else reverts with the matching custom error.
    function _assertRecover(bytes memory data, bytes32 hash, uint8 v, bytes32 r, bytes32 s, string memory label)
        internal
        view
    {
        (address expected, ECDSA.RecoverError expectedErr,) = _reference(hash, v, r, s);
        (bool ok, bytes memory ret) = address(harness).staticcall(data);
        assertEq(ok, expectedErr == ECDSA.RecoverError.NoError, string.concat(label, ": revert domain"));
        if (ok) {
            assertEq(abi.decode(ret, (address)), expected, string.concat(label, ": signer"));
        } else if (expectedErr == ECDSA.RecoverError.InvalidSignatureS) {
            assertEq(ret, abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, s), label);
        } else {
            assertEq(ret, abi.encodeWithSelector(ECDSA.ECDSAInvalidSignature.selector), label);
        }
    }
}
