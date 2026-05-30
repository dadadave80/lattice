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
}
