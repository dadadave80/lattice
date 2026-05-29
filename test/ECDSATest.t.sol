// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Thin wrapper that exposes ECDSA internal functions as external calls
///      so vm.expectRevert can intercept them at the right call depth.
contract ECDSAHarness {
    function recover(bytes32 hash, bytes memory signature) external pure returns (address) {
        return ECDSA.recover(hash, signature);
    }

    function recoverCompact(bytes32 hash, bytes32 r, bytes32 vs) external pure returns (address) {
        return ECDSA.recover(hash, r, vs);
    }

    function recoverVRS(bytes32 hash, uint8 v, bytes32 r, bytes32 s) external pure returns (address) {
        return ECDSA.recover(hash, v, r, s);
    }

    function tryRecover(bytes32 hash, bytes memory signature)
        external
        pure
        returns (address, ECDSA.RecoverError, bytes32)
    {
        return ECDSA.tryRecover(hash, signature);
    }

    function tryRecoverCompact(bytes32 hash, bytes32 r, bytes32 vs)
        external
        pure
        returns (address, ECDSA.RecoverError, bytes32)
    {
        return ECDSA.tryRecover(hash, r, vs);
    }

    function tryRecoverVRS(bytes32 hash, uint8 v, bytes32 r, bytes32 s)
        external
        pure
        returns (address, ECDSA.RecoverError, bytes32)
    {
        return ECDSA.tryRecover(hash, v, r, s);
    }

    function toEthSignedMessageHash(bytes32 hash) external pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(hash);
    }

    function toEthSignedMessageHashBytes(bytes memory s) external pure returns (bytes32) {
        return ECDSA.toEthSignedMessageHash(s);
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) external pure returns (bytes32) {
        return ECDSA.toTypedDataHash(domainSeparator, structHash);
    }
}

contract ECDSATest is Test {
    // A known private key and its corresponding address for testing
    uint256 constant SIGNER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address constant SIGNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    ECDSAHarness harness;

    function setUp() public {
        harness = new ECDSAHarness();
    }

    // -------------------------------------------------------------------------
    // recover(bytes32, bytes memory) — full 65-byte signature
    // -------------------------------------------------------------------------

    function test_RecoverFullSignature() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, hash);
        bytes memory sig = abi.encodePacked(r, s, v);
        address recovered = ECDSA.recover(hash, sig);
        assertEq(recovered, SIGNER);
    }

    // -------------------------------------------------------------------------
    // recover(bytes32, bytes32 r, bytes32 vs) — EIP-2098 compact signature
    // -------------------------------------------------------------------------

    function test_RecoverCompactSignature() public view {
        bytes32 hash = keccak256("compact test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, hash);
        // Build EIP-2098: yParity in high bit of vs
        bytes32 vs = s | (bytes32(uint256(v - 27)) << 255);
        address recovered = ECDSA.recover(hash, r, vs);
        assertEq(recovered, SIGNER);
    }

    // -------------------------------------------------------------------------
    // recover(bytes32, uint8 v, bytes32 r, bytes32 s)
    // -------------------------------------------------------------------------

    function test_RecoverVRS() public view {
        bytes32 hash = keccak256("vrs test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, hash);
        address recovered = ECDSA.recover(hash, v, r, s);
        assertEq(recovered, SIGNER);
    }

    // -------------------------------------------------------------------------
    // tryRecover — returns (address, NoError)
    // -------------------------------------------------------------------------

    function test_TryRecoverReturnsNoError() public view {
        bytes32 hash = keccak256("tryRecover test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, hash);
        bytes memory sig = abi.encodePacked(r, s, v);
        (address recovered, ECDSA.RecoverError err, bytes32 errArg) = ECDSA.tryRecover(hash, sig);
        assertEq(recovered, SIGNER);
        assertEq(uint8(err), uint8(ECDSA.RecoverError.NoError));
        assertEq(errArg, bytes32(0));
    }

    function test_TryRecoverCompact_ReturnsNoError() public view {
        bytes32 hash = keccak256("tryRecover compact");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, hash);
        bytes32 vs = s | (bytes32(uint256(v - 27)) << 255);
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, r, vs);
        assertEq(recovered, SIGNER);
        assertEq(uint8(err), uint8(ECDSA.RecoverError.NoError));
    }

    function test_TryRecoverVRS_ReturnsNoError() public view {
        bytes32 hash = keccak256("tryRecover vrs");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, hash);
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, v, r, s);
        assertEq(recovered, SIGNER);
        assertEq(uint8(err), uint8(ECDSA.RecoverError.NoError));
    }

    // -------------------------------------------------------------------------
    // Invalid signature length reverts
    // -------------------------------------------------------------------------

    function test_InvalidLengthReverts() public {
        bytes32 hash = keccak256("bad length");
        bytes memory shortSig = new bytes(32);
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, uint256(32)));
        harness.recover(hash, shortSig);
    }

    function test_InvalidLength66Reverts() public {
        bytes32 hash = keccak256("bad length 66");
        bytes memory sig = new bytes(66);
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, uint256(66)));
        harness.recover(hash, sig);
    }

    function test_TryRecover_InvalidLength_ReturnsError() public pure {
        bytes32 hash = keccak256("bad length try");
        bytes memory sig = new bytes(10);
        (address recovered, ECDSA.RecoverError err, bytes32 errArg) = ECDSA.tryRecover(hash, sig);
        assertEq(recovered, address(0));
        assertEq(uint8(err), uint8(ECDSA.RecoverError.InvalidSignatureLength));
        assertEq(uint256(errArg), uint256(10));
    }

    // -------------------------------------------------------------------------
    // High-S signature reverts
    // -------------------------------------------------------------------------

    function test_HighSReverts() public {
        bytes32 hash = keccak256("high s test");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, hash);
        // Compute the high-S counterpart: s' = secp256k1.n - s
        bytes32 highS = bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - uint256(s));
        bytes memory sig = abi.encodePacked(r, highS, v);
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureS.selector, highS));
        harness.recover(hash, sig);
    }

    function test_TryRecover_HighS_ReturnsError() public view {
        bytes32 hash = keccak256("high s tryRecover");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, hash);
        bytes32 highS = bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - uint256(s));
        (address recovered, ECDSA.RecoverError err, bytes32 errArg) = ECDSA.tryRecover(hash, v, r, highS);
        assertEq(recovered, address(0));
        assertEq(uint8(err), uint8(ECDSA.RecoverError.InvalidSignatureS));
        assertEq(errArg, highS);
    }

    // -------------------------------------------------------------------------
    // toEthSignedMessageHash(bytes32)
    // -------------------------------------------------------------------------

    function test_ToEthSignedMessageHashBytes32() public pure {
        bytes32 hash = keccak256("hello");
        bytes32 expected = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        assertEq(ECDSA.toEthSignedMessageHash(hash), expected);
    }

    function test_EthSignedMessageHashRoundtrip() public view {
        bytes32 msgHash = keccak256("round trip message");
        bytes32 ethHash = ECDSA.toEthSignedMessageHash(msgHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, ethHash);
        address recovered = ECDSA.recover(ethHash, v, r, s);
        assertEq(recovered, SIGNER);
    }

    // -------------------------------------------------------------------------
    // toEthSignedMessageHash(bytes memory)
    // -------------------------------------------------------------------------

    function test_ToEthSignedMessageHashBytes() public pure {
        bytes memory message = bytes("Hello, World!");
        bytes32 expected = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n13", message));
        assertEq(ECDSA.toEthSignedMessageHash(message), expected);
    }

    function test_ToEthSignedMessageHashEmptyBytes() public pure {
        bytes memory message = "";
        bytes32 expected = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n0", message));
        assertEq(ECDSA.toEthSignedMessageHash(message), expected);
    }

    // -------------------------------------------------------------------------
    // toTypedDataHash
    // -------------------------------------------------------------------------

    function test_ToTypedDataHash() public pure {
        bytes32 domainSeparator = keccak256("domain");
        bytes32 structHash = keccak256("struct");
        bytes32 expected = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        assertEq(ECDSA.toTypedDataHash(domainSeparator, structHash), expected);
    }

    function test_ToTypedDataHashMatchesEIP712() public pure {
        // Manually constructed EIP-712 domain separator
        bytes32 typeHash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHash = keccak256("TestApp");
        bytes32 versionHash = keccak256("1");
        bytes32 domainSeparator = keccak256(abi.encode(typeHash, nameHash, versionHash, uint256(1), address(0xDEAD)));

        bytes32 structTypeHash = keccak256("Transfer(address to,uint256 amount)");
        bytes32 structHash = keccak256(abi.encode(structTypeHash, address(0xBEEF), uint256(100)));

        bytes32 expected = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        assertEq(ECDSA.toTypedDataHash(domainSeparator, structHash), expected);
    }
}
