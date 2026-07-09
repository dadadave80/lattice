// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {ERC7579ModuleConfig} from "@lattice/accounts/erc7579/ERC7579ModuleConfig.sol";
import {ERC7579ModuleConfigLib} from "@lattice/accounts/erc7579/libraries/ERC7579ModuleConfigLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {DEFAULT_ENTRY_POINT, ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {IERC4337Validation} from "@lattice/interfaces/accounts/IERC4337Validation.sol";
import {IAccount, PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";
import {IERC7579Validator, MODULE_TYPE_VALIDATOR} from "@lattice/interfaces/external/IERC7579.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Harness: 4337 validation + signer + access + ERC-7579 module config (to install validators).
contract MockERC4337 is AccessControl, AccountSigner, ERC4337Validation, ERC7579ModuleConfig {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(AccessControl, AccountSigner, ERC4337Validation)
        returns (bytes memory)
    {}

    function initialize(address admin_, address owner_, address entryPoint_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        AccountSignerLib.__AccountSigner_init(owner_);
        ERC4337ValidationLib.__ERC4337Validation_init(entryPoint_);
        ERC7579ModuleConfigLib.__ERC7579ModuleConfig_init();
        InitializableLib.postInitializer(s);
    }
}

/// @dev Configurable ERC-7579 validator module: returns `ret` as the validationData regardless of signature.
contract MockValidator is IERC7579Validator {
    uint256 public ret; // 0 = valid, 1 = sig failure
    uint256 public installs;

    function setRet(uint256 r) external {
        ret = r;
    }

    function onInstall(bytes calldata) external {
        installs++;
    }

    function onUninstall(bytes calldata) external {}

    function isModuleType(uint256 t) external pure returns (bool) {
        return t == MODULE_TYPE_VALIDATOR;
    }

    function validateUserOp(PackedUserOperation calldata, bytes32) external view returns (uint256) {
        return ret;
    }

    function isValidSignatureWithSender(address, bytes32, bytes calldata) external pure returns (bytes4) {
        return 0x1626ba7e;
    }
}

contract ERC4337ValidationTest is Test {
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

    // ---- ERC-7579 validator-module routing (#58 follow-on) ----

    /// @dev The nonce selects a validator by its address in the top 20 bytes.
    function _validatorNonce(address v) internal pure returns (uint256) {
        return uint256(uint160(v)) << 96;
    }

    function test_Validator_InstallRoutesAndPropagatesResult() public {
        MockValidator validator = new MockValidator();
        vm.prank(admin);
        account.installModule(MODULE_TYPE_VALIDATOR, address(validator), "");
        assertTrue(account.isModuleInstalled(MODULE_TYPE_VALIDATOR, address(validator), ""), "not installed");
        assertEq(validator.installs(), 1, "onInstall not called");

        bytes32 h = keccak256("op");
        PackedUserOperation memory op = _op(strangerPk, h); // a sig the OWNER would reject
        op.nonce = _validatorNonce(address(validator));

        // Routed to the validator (which accepts), bypassing the owner — proving the route is taken.
        vm.prank(entryPointAddr);
        assertEq(account.validateUserOp(op, h, 0), 0, "validator accept not routed");

        // The validator's own result propagates.
        validator.setRet(1);
        vm.prank(entryPointAddr);
        assertEq(account.validateUserOp(op, h, 0), 1, "validator reject not propagated");
    }

    function test_Validator_ZeroSelectorUsesOwner() public {
        bytes32 h = keccak256("op");
        PackedUserOperation memory bad = _op(strangerPk, h);
        bad.nonce = 0; // default key → owner path
        vm.prank(entryPointAddr);
        assertEq(account.validateUserOp(bad, h, 0), 1, "owner should reject stranger at key 0");

        PackedUserOperation memory good = _op(ownerPk, h);
        good.nonce = 0;
        vm.prank(entryPointAddr);
        assertEq(account.validateUserOp(good, h, 0), 0, "owner should accept its own sig at key 0");
    }

    function test_Validator_UninstalledSelectorFallsBackToOwner() public {
        bytes32 h = keccak256("op");
        PackedUserOperation memory op = _op(ownerPk, h); // valid owner sig
        op.nonce = _validatorNonce(address(0xDEAD)); // a non-installed "validator"
        vm.prank(entryPointAddr);
        assertEq(account.validateUserOp(op, h, 0), 0, "uninstalled selector should fall back to owner");
    }
}
