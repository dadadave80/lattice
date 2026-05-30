// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";
import {SignatureChecker} from "@lattice/utils/libraries/SignatureChecker.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Mock ERC-1271 contract that accepts a specific (hash, signature) pair.
contract Mock1271Signer {
    bytes4 private constant ERC1271_MAGIC_VALUE = 0x1626ba7e;
    bytes4 private constant ERC1271_INVALID = 0xffffffff;

    address public immutable signer;

    constructor(address _signer) {
        signer = _signer;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        // Recover the signer and verify it matches the expected signer
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        if (err == ECDSA.RecoverError.NoError && recovered == signer) {
            return ERC1271_MAGIC_VALUE;
        }
        return ERC1271_INVALID;
    }
}

/// @dev Contract that does NOT implement ERC-1271 (returns garbage / reverts)
contract NonERC1271Contract {
    // no isValidSignature function
}

/// @dev Contract that has the function selector but always reverts
contract RevertingERC1271 {
    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        revert("always reverts");
    }
}

/// @dev Harness to test SignatureChecker through external calls
contract SignatureCheckerHarness {
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature) external view returns (bool) {
        return SignatureChecker.isValidSignatureNow(signer, hash, signature);
    }

    function isValidERC1271SignatureNow(address signer, bytes32 hash, bytes memory signature)
        external
        view
        returns (bool)
    {
        return SignatureChecker.isValidERC1271SignatureNow(signer, hash, signature);
    }
}

contract SignatureCheckerTest is Test {
    uint256 constant SIGNER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address constant SIGNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    SignatureCheckerHarness harness;
    Mock1271Signer mock1271;
    NonERC1271Contract nonERC1271;
    RevertingERC1271 revertingERC1271;

    function setUp() public {
        harness = new SignatureCheckerHarness();
        mock1271 = new Mock1271Signer(SIGNER);
        nonERC1271 = new NonERC1271Contract();
        revertingERC1271 = new RevertingERC1271();
    }

    function _sign(bytes32 hash) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, hash);
        return abi.encodePacked(r, s, v);
    }

    // -------------------------------------------------------------------------
    // EOA signatures
    // -------------------------------------------------------------------------

    function test_ValidEOASignatureReturnsTrue() public view {
        bytes32 hash = keccak256("hello from EOA");
        bytes memory sig = _sign(hash);
        assertTrue(harness.isValidSignatureNow(SIGNER, hash, sig));
    }

    function test_InvalidEOASignatureReturnsFalse() public view {
        bytes32 hash = keccak256("valid message");
        bytes32 wrongHash = keccak256("wrong message");
        bytes memory sig = _sign(wrongHash); // signed wrong hash
        assertFalse(harness.isValidSignatureNow(SIGNER, hash, sig));
    }

    function test_WrongSignerReturnsFalse() public view {
        bytes32 hash = keccak256("hello");
        bytes memory sig = _sign(hash);
        // Different signer address
        assertFalse(harness.isValidSignatureNow(address(0xDEAD), hash, sig));
    }

    // -------------------------------------------------------------------------
    // ERC-1271 contract signatures
    // -------------------------------------------------------------------------

    function test_ValidERC1271SignatureReturnsTrue() public view {
        bytes32 hash = keccak256("hello from 1271 contract");
        bytes memory sig = _sign(hash);
        // The mock1271 contract accepts signatures from SIGNER
        assertTrue(harness.isValidSignatureNow(address(mock1271), hash, sig));
    }

    function test_InvalidERC1271SignatureReturnsFalse() public view {
        bytes32 hash = keccak256("valid");
        bytes32 wrongHash = keccak256("wrong");
        bytes memory sig = _sign(wrongHash);
        assertFalse(harness.isValidSignatureNow(address(mock1271), hash, sig));
    }

    function test_ERC1271DirectCall_Valid() public view {
        bytes32 hash = keccak256("direct 1271");
        bytes memory sig = _sign(hash);
        assertTrue(harness.isValidERC1271SignatureNow(address(mock1271), hash, sig));
    }

    function test_ERC1271DirectCall_Invalid() public view {
        bytes32 hash = keccak256("direct 1271 invalid");
        bytes memory sig = _sign(keccak256("different"));
        assertFalse(harness.isValidERC1271SignatureNow(address(mock1271), hash, sig));
    }

    // -------------------------------------------------------------------------
    // Non-1271 contracts return false (don't revert)
    // -------------------------------------------------------------------------

    function test_NonERC1271ContractReturnsFalse() public view {
        bytes32 hash = keccak256("non 1271");
        bytes memory sig = _sign(hash);
        // Contract with no isValidSignature — should return false, not revert
        assertFalse(harness.isValidSignatureNow(address(nonERC1271), hash, sig));
    }

    function test_RevertingERC1271ReturnsFalse() public view {
        bytes32 hash = keccak256("reverting 1271");
        bytes memory sig = _sign(hash);
        // Contract that reverts in isValidSignature — should return false, not propagate revert
        assertFalse(harness.isValidSignatureNow(address(revertingERC1271), hash, sig));
    }

    function test_NonERC1271DirectCallReturnsFalse() public view {
        bytes32 hash = keccak256("direct non 1271");
        bytes memory sig = _sign(hash);
        assertFalse(harness.isValidERC1271SignatureNow(address(nonERC1271), hash, sig));
    }
}
