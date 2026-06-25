// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC1271Signature} from "@lattice/accounts/ERC1271Signature.sol";
import {SignerECDSA} from "@lattice/accounts/SignerECDSA.sol";
import {ERC1271SignatureLib} from "@lattice/accounts/libraries/ERC1271SignatureLib.sol";
import {SignerECDSALib} from "@lattice/accounts/libraries/SignerECDSALib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Harness: 1271 facet + signer facet + access facet, with an `initialize` that runs the module inits.
contract MockERC1271 is AccessControl, SignerECDSA, ERC1271Signature {
    function initialize(address admin_, address owner_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        SignerECDSALib.__SignerECDSA_init(owner_);
        ERC1271SignatureLib.__ERC1271Signature_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract ERC1271SignatureTester is Test {
    MockERC1271 account;
    address admin = address(0x1);
    address ownerAddr;
    uint256 ownerPk;
    address stranger;
    uint256 strangerPk;

    bytes4 constant MAGIC = 0x1626ba7e;
    bytes4 constant INVALID = 0xffffffff;

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
        account = new MockERC1271();
        account.initialize(admin, ownerAddr);
    }

    function test_ValidOwnerSig() public view {
        bytes32 hash = keccak256("permit");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, hash);
        assertEq(account.isValidSignature(hash, abi.encodePacked(r, s, v)), MAGIC, "valid owner sig rejected");
    }

    function test_InvalidSig() public view {
        bytes32 hash = keccak256("permit");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerPk, hash);
        assertEq(account.isValidSignature(hash, abi.encodePacked(r, s, v)), INVALID, "stranger sig accepted");
    }

    function test_SupportsInterface() public view {
        assertTrue(account.supportsInterface(MAGIC), "IERC1271 not registered");
    }
}
