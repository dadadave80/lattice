// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {INonces} from "@lattice/interfaces/utils/INonces.sol";
import {Nonces} from "@lattice/utils/Nonces.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockNoncesContract
/// @notice Mock contract that inherits the Nonces facet and exposes init + internal helpers.
contract MockNoncesContract is Nonces {
    /// @notice Initializes the Nonces module.
    function initialize() external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        NoncesLib.__Nonces_init();
        InitializableLib.postInitializer(s);
    }

    /// @notice Test helper that exposes NoncesLib.useNonce.
    function useNonceFor(address owner) external returns (uint256) {
        return NoncesLib.useNonce(owner);
    }

    /// @notice Test helper that exposes NoncesLib.useCheckedNonce.
    function useCheckedNonceFor(address owner, uint256 nonce) external {
        NoncesLib.useCheckedNonce(owner, nonce);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

contract NoncesTest is Test {
    MockNoncesContract noncesContract;

    address alice = address(0x1);
    address bob = address(0x2);

    function setUp() public {
        noncesContract = new MockNoncesContract();
        noncesContract.initialize();
    }

    // -------------------------------------------------------------------------
    // Initial state
    // -------------------------------------------------------------------------

    function test_NoncesStartsAtZero() public view {
        assertEq(noncesContract.nonces(alice), 0);
        assertEq(noncesContract.nonces(bob), 0);
    }

    // -------------------------------------------------------------------------
    // useNonce increments
    // -------------------------------------------------------------------------

    function test_UseNonce_ReturnsZeroThenBumpsToOne() public {
        // First use returns 0 (current value before increment)
        uint256 first = noncesContract.useNonceFor(alice);
        assertEq(first, 0);
        // Nonce is now 1
        assertEq(noncesContract.nonces(alice), 1);
    }

    function test_UseNonce_MultipleUsesIncrementMonotonically() public {
        uint256 n0 = noncesContract.useNonceFor(alice);
        uint256 n1 = noncesContract.useNonceFor(alice);
        uint256 n2 = noncesContract.useNonceFor(alice);

        assertEq(n0, 0);
        assertEq(n1, 1);
        assertEq(n2, 2);
        assertEq(noncesContract.nonces(alice), 3);
    }

    function test_UseNonce_IndependentPerAccount() public {
        noncesContract.useNonceFor(alice);
        noncesContract.useNonceFor(alice);
        noncesContract.useNonceFor(bob);

        assertEq(noncesContract.nonces(alice), 2);
        assertEq(noncesContract.nonces(bob), 1);
    }

    // -------------------------------------------------------------------------
    // useCheckedNonce
    // -------------------------------------------------------------------------

    function test_UseCheckedNonce_CorrectNonceSucceeds() public {
        // nonce(alice) = 0, expect 0 → succeeds
        noncesContract.useCheckedNonceFor(alice, 0);
        assertEq(noncesContract.nonces(alice), 1);
    }

    function test_UseCheckedNonce_DoubleZeroReverts() public {
        // Consume nonce 0 successfully
        noncesContract.useCheckedNonceFor(alice, 0);

        // Now alice's nonce is 1; using 0 again should revert with InvalidAccountNonce(alice, 1)
        vm.expectRevert(abi.encodeWithSelector(INonces.InvalidAccountNonce.selector, alice, uint256(1)));
        noncesContract.useCheckedNonceFor(alice, 0);
    }

    function test_UseCheckedNonce_WrongNonceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(INonces.InvalidAccountNonce.selector, alice, uint256(0)));
        noncesContract.useCheckedNonceFor(alice, 5);
    }

    function test_UseCheckedNonce_SequentialSuccess() public {
        noncesContract.useCheckedNonceFor(alice, 0);
        noncesContract.useCheckedNonceFor(alice, 1);
        noncesContract.useCheckedNonceFor(alice, 2);
        assertEq(noncesContract.nonces(alice), 3);
    }

    // -------------------------------------------------------------------------
    // ERC-165 interface registration
    // -------------------------------------------------------------------------

    function test_SupportsINoncesInterface() public view {
        assertTrue(noncesContract.supportsInterface(type(INonces).interfaceId));
    }
}
