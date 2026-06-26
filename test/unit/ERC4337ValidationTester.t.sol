// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccountSigner} from "@lattice/accounts/AccountSigner.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {DEFAULT_ENTRY_POINT, ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {IERC4337Validation} from "@lattice/interfaces/IERC4337Validation.sol";
import {IAccount, PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Harness: 4337 validation facet + signer facet + access facet.
contract MockERC4337 is AccessControl, AccountSigner, ERC4337Validation {
    function initialize(address admin_, address owner_, address entryPoint_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        AccountSignerLib.__AccountSigner_init(owner_);
        ERC4337ValidationLib.__ERC4337Validation_init(entryPoint_);
        InitializableLib.postInitializer(s);
    }
}

contract ERC4337ValidationTester is Test {
    MockERC4337 account;
    address admin = address(0x1);
    address entryPointAddr = address(0xE47);
    address ownerAddr;
    uint256 ownerPk;
    address stranger;
    uint256 strangerPk;

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
        account = new MockERC4337();
        account.initialize(admin, ownerAddr, entryPointAddr);
    }

    /// @dev The blessed default EntryPoint is finalized (#58 item 9) to ERC-4337 v0.9 (OZ default singleton).
    function test_DefaultEntryPointIsV09() public pure {
        assertEq(DEFAULT_ENTRY_POINT, 0x433709009B8330FDa32311DF1C2AFA402eD8D009, "default EntryPoint != v0.9");
    }

    function _ethHash(bytes32 h) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", h));
    }

    function _op(uint256 pk, bytes32 userOpHash) internal pure returns (PackedUserOperation memory op) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, _ethHash(userOpHash));
        op.signature = abi.encodePacked(r, s, v);
    }

    function test_EntryPointSetAtInit() public view {
        assertEq(account.entryPoint(), entryPointAddr, "entryPoint not set at init");
    }

    function test_SetEntryPoint() public {
        address newEp = address(0xE48);
        vm.expectEmit(true, false, false, true, address(account));
        emit IERC4337Validation.EntryPointSet(newEp);
        vm.prank(admin);
        account.setEntryPoint(newEp);
        assertEq(account.entryPoint(), newEp, "entryPoint not updated");
    }

    function test_SetEntryPoint_RevertZero() public {
        vm.prank(admin);
        vm.expectRevert(IERC4337Validation.InvalidEntryPoint.selector);
        account.setEntryPoint(address(0));
    }

    function test_SetEntryPoint_RevertNotAdmin() public {
        vm.prank(stranger);
        vm.expectRevert();
        account.setEntryPoint(address(0xE48));
    }

    function test_ValidateUserOp_ValidSig() public {
        bytes32 userOpHash = keccak256("userop");
        PackedUserOperation memory op = _op(ownerPk, userOpHash);
        vm.prank(entryPointAddr);
        uint256 validationData = account.validateUserOp(op, userOpHash, 0);
        assertEq(validationData, 0, "valid sig should return 0");
    }

    function test_ValidateUserOp_BadSig() public {
        bytes32 userOpHash = keccak256("userop");
        PackedUserOperation memory op = _op(strangerPk, userOpHash);
        vm.prank(entryPointAddr);
        uint256 validationData = account.validateUserOp(op, userOpHash, 0);
        assertEq(validationData, 1, "bad sig should return 1");
    }

    function test_ValidateUserOp_RevertNotEntryPoint() public {
        bytes32 userOpHash = keccak256("userop");
        PackedUserOperation memory op = _op(ownerPk, userOpHash);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC4337Validation.NotFromEntryPoint.selector, stranger));
        account.validateUserOp(op, userOpHash, 0);
    }

    function test_ValidateUserOp_PaysPrefund() public {
        bytes32 userOpHash = keccak256("userop");
        PackedUserOperation memory op = _op(ownerPk, userOpHash);
        vm.deal(address(account), 1 ether);
        uint256 before = entryPointAddr.balance;
        vm.prank(entryPointAddr);
        account.validateUserOp(op, userOpHash, 0.5 ether);
        assertEq(entryPointAddr.balance - before, 0.5 ether, "prefund not paid to EntryPoint");
    }
}
