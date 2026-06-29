// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {SessionKey} from "@lattice/accounts/SessionKey.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";
import {ERC7821ExecutorLib} from "@lattice/accounts/erc7579/libraries/ERC7821ExecutorLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {SessionKeyLib} from "@lattice/accounts/libraries/SessionKeyLib.sol";
import {ISessionKey} from "@lattice/interfaces/accounts/ISessionKey.sol";
import {Call} from "@lattice/interfaces/external/IERC7821.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Account assembled from the signer + executor + session-key facets (+ EIP-712 domain + nonces).
contract LatticeAccount is AccessControl, AccountSigner, ERC4337Validation, ERC7821Executor, SessionKey {
    function initialize(address admin_, address owner_, address entryPoint_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        EIP712Lib.__EIP712_init("LatticeAccount", "1");
        NoncesLib.__Nonces_init();
        AccountSignerLib.__AccountSigner_init(owner_);
        ERC4337ValidationLib.__ERC4337Validation_init(entryPoint_);
        ERC7821ExecutorLib.__ERC7821Executor_init();
        SessionKeyLib.__SessionKey_init();
        InitializableLib.postInitializer(s);
    }
}

contract Target {
    uint256 public value;

    function setValue(uint256 v) external {
        value = v;
    }

    function other(uint256) external pure {}
}

contract MockToken {
    uint256 public transfers;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        transfers++;
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }
}

contract SessionKeyExecutionIntegration is Test {
    LatticeAccount account;
    Target target;
    MockToken token;
    address dest = address(0xD357);

    address admin = address(0x1);
    address ownerAddr;
    uint256 ownerPk;
    address sessionKeyAddr;
    uint256 sessionKeyPk;
    address relayer = address(0xBEEF);

    bytes32 constant BATCH_OPDATA = 0x0100000000007821000100000000000000000000000000000000000000000000;
    bytes32 constant EXECUTE_TYPEHASH = 0xb63526befbf5b966e64c36954eb12c5d09096e0b0a8a06e90bd0c857b842ebcb;
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        (sessionKeyAddr, sessionKeyPk) = makeAddrAndKey("sessionKey");
        account = new LatticeAccount();
        account.initialize(admin, ownerAddr, address(0xE47));
        target = new Target();
        token = new MockToken();
        token.mint(address(account), 1000); // fund the account so balance-diff spend accounting can measure
        vm.warp(1);
    }

    function _transferCalls(address to, uint256 amount) internal view returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = Call({
            target: address(token), value: 0, data: abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        });
    }

    function _setValueCalls(uint256 v) internal view returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.setValue, (v))});
    }

    function _opData(uint256 pk, Call[] memory calls, uint256 nonce) internal view returns (bytes memory) {
        bytes32 sep = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("LatticeAccount"), keccak256("1"), block.chainid, address(account))
        );
        bytes32 structHash = keccak256(abi.encode(EXECUTE_TYPEHASH, BATCH_OPDATA, keccak256(abi.encode(calls)), nonce));
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", sep, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encode(nonce, abi.encodePacked(r, s, v));
    }

    function _register(uint48 validUntil, address permTarget, bytes4 permSelector) internal {
        ISessionKey.Permission[] memory perms = new ISessionKey.Permission[](1);
        perms[0] = ISessionKey.Permission({target: permTarget, selector: permSelector});
        vm.prank(admin);
        account.registerSessionKey(sessionKeyAddr, 0, validUntil, perms);
    }

    function test_SessionKey_ExecutesPermittedBatch() public {
        _register(1000, address(target), Target.setValue.selector);
        Call[] memory calls = _setValueCalls(123);
        vm.prank(relayer); // unauthorized relayer submits the session-key-signed batch
        account.execute(BATCH_OPDATA, abi.encode(calls, _opData(sessionKeyPk, calls, 0)));
        assertEq(target.value(), 123, "session key batch not executed");
    }

    function test_SessionKey_RejectsNotPermitted() public {
        _register(1000, address(target), Target.other.selector); // permits other(), not setValue()
        Call[] memory calls = _setValueCalls(1);
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISessionKey.CallNotPermitted.selector, sessionKeyAddr, address(target), Target.setValue.selector
            )
        );
        account.execute(BATCH_OPDATA, abi.encode(calls, _opData(sessionKeyPk, calls, 0)));
    }

    function test_SessionKey_RejectsExpired() public {
        _register(1000, address(target), Target.setValue.selector);
        vm.warp(1001);
        Call[] memory calls = _setValueCalls(1);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(ISessionKey.SessionKeyNotActive.selector, sessionKeyAddr));
        account.execute(BATCH_OPDATA, abi.encode(calls, _opData(sessionKeyPk, calls, 0)));
    }

    function test_SessionKey_RejectsUnregistered() public {
        // No registration at all.
        Call[] memory calls = _setValueCalls(1);
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(ISessionKey.SessionKeyNotActive.selector, sessionKeyAddr));
        account.execute(BATCH_OPDATA, abi.encode(calls, _opData(sessionKeyPk, calls, 0)));
    }

    function test_SessionKey_SpendWithinLimit() public {
        _register(1000, address(token), 0xa9059cbb); // permit transfer() on the token
        vm.prank(admin);
        account.setSpendLimit(sessionKeyAddr, address(token), 100);
        Call[] memory calls = _transferCalls(dest, 60);
        vm.prank(relayer);
        account.execute(BATCH_OPDATA, abi.encode(calls, _opData(sessionKeyPk, calls, 0)));
        assertEq(token.transfers(), 1, "transfer not executed");
        (, uint256 spent) = account.spendLimit(sessionKeyAddr, address(token));
        assertEq(spent, 60, "spend not accrued");
    }

    function test_SessionKey_SpendExceedsLimit() public {
        _register(1000, address(token), 0xa9059cbb);
        vm.prank(admin);
        account.setSpendLimit(sessionKeyAddr, address(token), 100);
        Call[] memory calls = _transferCalls(dest, 150);
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(ISessionKey.SpendLimitExceeded.selector, sessionKeyAddr, address(token), 100, 150)
        );
        account.execute(BATCH_OPDATA, abi.encode(calls, _opData(sessionKeyPk, calls, 0)));
        assertEq(token.transfers(), 0, "transfer should not have executed");
    }
}
