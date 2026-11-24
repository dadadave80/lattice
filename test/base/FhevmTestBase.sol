// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FhevmTest} from "@lattice-test/helpers/fhevm/FhevmTest.sol";
import {hcuLimitAdd} from "@lattice-test/helpers/fhevm/fhevm-host/addresses/FHEVMHostAddresses.sol";
import {IHCULimit} from "@lattice-test/helpers/fhevm/generated/interfaces/IHCULimit.sol";

/// @title FhevmTestBase
/// @notice Test-only base over the vendored FHEVM (Fully Homomorphic Encryption Virtual Machine) harness.
abstract contract FhevmTestBase is FhevmTest {
    function setUp() public virtual override {
        super.setUp();
        vm.prank(PROXY_OWNER);
        IHCULimit(hcuLimitAdd).setHCUPerBlock(type(uint48).max);
    }
}
