// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {SignerECDSA} from "@lattice/accounts/SignerECDSA.sol";
import {SignerECDSALib} from "@lattice/accounts/libraries/SignerECDSALib.sol";
import {ISignerECDSA} from "@lattice/interfaces/ISignerECDSA.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Test harness: the signer facet + access facet, with an `initialize` that runs the module inits.
contract MockSignerECDSA is AccessControl, SignerECDSA {
    function initialize(address admin_, address owner_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        SignerECDSALib.__SignerECDSA_init(owner_);
        InitializableLib.postInitializer(s);
    }

    /// @dev Exposes the internal signer seam for direct unit coverage.
    function rawValidate(bytes32 hash, bytes calldata signature) external view returns (bool) {
        return SignerECDSALib.isValidSignatureNow(hash, signature);
    }
}

contract SignerECDSATester is Test {
    MockSignerECDSA signer;
    address admin = address(0x1);
    address ownerAddr;
    uint256 ownerPk;
    address stranger;
    uint256 strangerPk;

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
        signer = new MockSignerECDSA();
        signer.initialize(admin, ownerAddr);
    }

    function test_InitialOwner() public view {
        assertEq(signer.owner(), ownerAddr, "owner not set at init");
    }

    function test_SetOwner() public {
        address newOwner = address(0xBEEF);
        vm.expectEmit(true, true, false, true, address(signer));
        emit ISignerECDSA.OwnerSet(ownerAddr, newOwner);
        vm.prank(admin);
        signer.setOwner(newOwner);
        assertEq(signer.owner(), newOwner, "owner not updated");
    }

    function test_SetOwner_RevertZero() public {
        vm.prank(admin);
        vm.expectRevert(ISignerECDSA.InvalidOwner.selector);
        signer.setOwner(address(0));
    }

    function test_SetOwner_RevertNotAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        signer.setOwner(address(0xBEEF));
    }

    function test_RawValidate_OwnerSig() public view {
        bytes32 digest = keccak256("lattice account message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        assertTrue(signer.rawValidate(digest, abi.encodePacked(r, s, v)), "owner signature rejected");
    }

    function test_RawValidate_WrongSigner() public view {
        bytes32 digest = keccak256("lattice account message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerPk, digest);
        assertFalse(signer.rawValidate(digest, abi.encodePacked(r, s, v)), "stranger signature accepted");
    }
}
