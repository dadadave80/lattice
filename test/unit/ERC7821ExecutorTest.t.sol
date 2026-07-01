// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {SessionKey} from "@lattice/accounts/SessionKey.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {ERC7579ModuleConfig} from "@lattice/accounts/erc7579/ERC7579ModuleConfig.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";
import {ERC7579ModuleConfigLib} from "@lattice/accounts/erc7579/libraries/ERC7579ModuleConfigLib.sol";
import {ERC7821ExecutorLib} from "@lattice/accounts/erc7579/libraries/ERC7821ExecutorLib.sol";
import {AccountSignerLib} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {ANY_SELECTOR, ANY_TARGET, SessionKeyLib} from "@lattice/accounts/libraries/SessionKeyLib.sol";
import {IERC7821Executor} from "@lattice/interfaces/accounts/IERC7821Executor.sol";
import {ISessionKey} from "@lattice/interfaces/accounts/ISessionKey.sol";
import {IERC7579Hook, MODULE_TYPE_HOOK} from "@lattice/interfaces/external/IERC7579.sol";
import {Call} from "@lattice/interfaces/external/IERC7821.sol";
import {INonces} from "@lattice/interfaces/utils/INonces.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Harness: executor + 4337 validation + signer + session keys + module config (to install hooks).
contract MockERC7821 is
    AccessControl,
    AccountSigner,
    ERC4337Validation,
    ERC7821Executor,
    SessionKey,
    ERC7579ModuleConfig
{
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
        ERC7579ModuleConfigLib.__ERC7579ModuleConfig_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

/// @dev Global ERC-7579 hook: counts pre/postCheck, threads context, and can block by reverting in preCheck.
contract MockHook is IERC7579Hook {
    bool public blocks;
    uint256 public pre;
    uint256 public post;
    address public lastSender;
    bytes public lastCtx;

    function setBlocks(bool b) external {
        blocks = b;
    }

    function onInstall(bytes calldata) external {}
    function onUninstall(bytes calldata) external {}

    function isModuleType(uint256 t) external pure returns (bool) {
        return t == MODULE_TYPE_HOOK;
    }

    function preCheck(address msgSender, uint256, bytes calldata) external returns (bytes memory) {
        require(!blocks, "hook: blocked");
        lastSender = msgSender;
        return abi.encode(++pre);
    }

    function postCheck(bytes calldata hookData) external {
        ++post;
        lastCtx = hookData;
    }
}

/// @dev Call target that records the last value + total ETH received, and a reverting function.
contract Target {
    uint256 public value;
    uint256 public received;

    function setValue(uint256 v) external payable {
        value = v;
        received += msg.value;
    }

    function boom() external pure {
        revert("boom");
    }
}

/// @dev Minimal ERC-20 for spend-accounting tests.
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function approve(address sp, uint256 amt) external returns (bool) {
        allowance[msg.sender][sp] = amt;
        return true;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function transferFrom(address from, address to, uint256 amt) external returns (bool) {
        allowance[from][msg.sender] -= amt;
        balanceOf[from] -= amt;
        balanceOf[to] += amt;
        return true;
    }
}

/// @dev Pulls tokens from its caller via a prior approval — an INDIRECT spend (no transfer selector in the
///      account's own batch calldata).
contract Puller {
    function pull(address token, uint256 amt) external {
        MockERC20(token).transferFrom(msg.sender, address(this), amt);
    }
}

/// @dev A token that transfers fine but whose `balanceOf` reverts — must not brick balance-diff settlement.
contract RevertingBalanceToken {
    mapping(address => uint256) internal _bal;

    function mint(address to, uint256 amt) external {
        _bal[to] += amt;
    }

    function transfer(address to, uint256 amt) external returns (bool) {
        _bal[msg.sender] -= amt;
        _bal[to] += amt;
        return true;
    }

    function balanceOf(address) external pure returns (uint256) {
        revert("no balanceOf");
    }
}

contract ERC7821ExecutorTest is Test {
    MockERC7821 account;
    Target target;
    address admin = address(0x1);
    address entryPointAddr = address(0xE47);
    address ownerAddr;
    uint256 ownerPk;
    address stranger;
    uint256 strangerPk;

    string constant NAME = "LatticeAccount";
    string constant VERSION = "1";

    bytes32 constant BATCH = 0x0100000000000000000000000000000000000000000000000000000000000000;
    bytes32 constant BATCH_OPDATA = 0x0100000000007821000100000000000000000000000000000000000000000000;
    bytes32 constant BAD_MODE = 0x0200000000000000000000000000000000000000000000000000000000000000;
    bytes4 constant IERC7821_ID = 0x39922547;
    bytes32 constant EXECUTE_TYPEHASH = 0xb63526befbf5b966e64c36954eb12c5d09096e0b0a8a06e90bd0c857b842ebcb;
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public {
        (ownerAddr, ownerPk) = makeAddrAndKey("owner");
        (stranger, strangerPk) = makeAddrAndKey("stranger");
        account = new MockERC7821();
        account.initialize(admin, ownerAddr, entryPointAddr);
        target = new Target();
    }

    function _oneCall(uint256 v, uint256 weiValue) internal view returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = Call({target: address(target), value: weiValue, data: abi.encodeCall(Target.setValue, (v))});
    }

    function _accountSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(account)
            )
        );
    }

    /// @dev Builds the owner-signed opData envelope `abi.encode(nonce, signature)` for a batch.
    function _signOpData(uint256 pk, bytes32 mode, Call[] memory calls, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(EXECUTE_TYPEHASH, mode, keccak256(abi.encode(calls)), nonce));
        bytes32 digest = keccak256(abi.encodePacked(hex"1901", _accountSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encode(nonce, abi.encodePacked(r, s, v));
    }

    // ---- direct authorization (unchanged behavior) ----

    function test_SupportsMode() public view {
        assertTrue(account.supportsExecutionMode(BATCH), "batch unsupported");
        assertTrue(account.supportsExecutionMode(BATCH_OPDATA), "opData batch unsupported");
        assertFalse(account.supportsExecutionMode(BAD_MODE), "bad mode reported supported");
    }

    function test_SupportsInterface() public view {
        assertTrue(account.supportsInterface(IERC7821_ID), "IERC7821 not registered");
    }

    function test_ExecuteBatch_AsAdmin() public {
        vm.expectEmit(true, false, false, true, address(account));
        emit IERC7821Executor.BatchExecuted(BATCH, 1);
        vm.prank(admin);
        account.execute(BATCH, abi.encode(_oneCall(42, 0)));
        assertEq(target.value(), 42, "call not executed");
    }

    function test_ExecuteBatch_AsEntryPoint() public {
        vm.prank(entryPointAddr);
        account.execute(BATCH, abi.encode(_oneCall(7, 0)));
        assertEq(target.value(), 7, "entryPoint call not executed");
    }

    function test_ExecuteBatch_AsSelf() public {
        vm.prank(address(account));
        account.execute(BATCH, abi.encode(_oneCall(9, 0)));
        assertEq(target.value(), 9, "self call not executed");
    }

    function test_ExecuteBatch_ForwardsValue() public {
        vm.deal(address(account), 1 ether);
        vm.prank(admin);
        account.execute(BATCH, abi.encode(_oneCall(5, 0.5 ether)));
        assertEq(target.value(), 5, "value call not executed");
        assertEq(target.received(), 0.5 ether, "ETH not forwarded");
    }

    /// @dev An admin is directly authorized, so opData is ignored even when present (here empty).
    function test_ExecuteBatch_OpData_DirectAdmin() public {
        Call[] memory calls = _oneCall(11, 0);
        vm.prank(admin);
        account.execute(BATCH_OPDATA, abi.encode(calls, bytes("")));
        assertEq(target.value(), 11, "opData batch not executed");
    }

    function test_Execute_RevertUnauthorized() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC7821Executor.UnauthorizedExecutor.selector, stranger));
        account.execute(BATCH, abi.encode(_oneCall(1, 0)));
    }

    function test_Execute_RevertUnsupportedMode() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IERC7821Executor.UnsupportedExecutionMode.selector, BAD_MODE));
        account.execute(BAD_MODE, abi.encode(_oneCall(1, 0)));
    }

    function test_Execute_BubblesRevert() public {
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.boom, ())});
        vm.prank(admin);
        vm.expectRevert(bytes("boom"));
        account.execute(BATCH, abi.encode(calls));
    }

    // ---- signed opData (relayer-submitted, owner-authorized) ----

    function test_SignedOpData_AsRelayer() public {
        Call[] memory calls = _oneCall(77, 0);
        bytes memory opData = _signOpData(ownerPk, BATCH_OPDATA, calls, 0);
        vm.prank(stranger); // an unauthorized relayer
        account.execute(BATCH_OPDATA, abi.encode(calls, opData));
        assertEq(target.value(), 77, "owner-signed batch not executed by relayer");
    }

    /// @dev A non-owner signer is treated as a session key; an unregistered one is rejected.
    function test_SignedOpData_RejectsUnknownSigner() public {
        Call[] memory calls = _oneCall(1, 0);
        bytes memory opData = _signOpData(strangerPk, BATCH_OPDATA, calls, 0); // neither owner nor a session key
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISessionKey.SessionKeyNotActive.selector, stranger));
        account.execute(BATCH_OPDATA, abi.encode(calls, opData));
    }

    function test_SignedOpData_RejectsReplay() public {
        Call[] memory calls = _oneCall(1, 0);
        bytes memory opData = _signOpData(ownerPk, BATCH_OPDATA, calls, 0);
        vm.prank(stranger);
        account.execute(BATCH_OPDATA, abi.encode(calls, opData)); // nonce 0 consumed
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(INonces.InvalidAccountNonce.selector, address(account), 1));
        account.execute(BATCH_OPDATA, abi.encode(calls, opData)); // replay: account nonce is now 1
    }

    function test_SignedOpData_RejectsWrongNonce() public {
        Call[] memory calls = _oneCall(1, 0);
        bytes memory opData = _signOpData(ownerPk, BATCH_OPDATA, calls, 5); // wrong nonce (current is 0)
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(INonces.InvalidAccountNonce.selector, address(account), 0));
        account.execute(BATCH_OPDATA, abi.encode(calls, opData));
    }

    // ---- session-key spend limits: balance-diff accounting (follow-on) ----

    address sessionKey;
    uint256 sessionKeyPk;
    MockERC20 token;
    Puller puller;
    address dest = address(0xD357);

    /// @dev Registers a wildcard session key with a `cap` on `token`, and mints 1000 to the account.
    function _setupSessionKey(uint256 cap) internal {
        (sessionKey, sessionKeyPk) = makeAddrAndKey("sessionKey");
        token = new MockERC20();
        puller = new Puller();
        token.mint(address(account), 1000);
        ISessionKey.Permission[] memory perms = new ISessionKey.Permission[](1);
        perms[0] = ISessionKey.Permission({target: ANY_TARGET, selector: ANY_SELECTOR});
        vm.startPrank(admin);
        account.registerSessionKey(sessionKey, 0, uint48(1_000_000), perms);
        account.setSpendLimit(sessionKey, address(token), cap);
        vm.stopPrank();
    }

    /// @dev A batch that spends `amt` of `token` INDIRECTLY: approve a puller, which then pulls — no transfer
    ///      selector appears in the account's own calldata.
    function _indirectSpendBatch(uint256 amt) internal view returns (Call[] memory calls) {
        calls = new Call[](2);
        calls[0] =
            Call({target: address(token), value: 0, data: abi.encodeCall(MockERC20.approve, (address(puller), amt))});
        calls[1] = Call({target: address(puller), value: 0, data: abi.encodeCall(Puller.pull, (address(token), amt))});
    }

    /// @notice The headline: an indirect over-spend that the calldata-sum alone would miss is caught by the
    ///         balance decrease, and the whole batch reverts.
    function test_SessionKey_IndirectSpend_Caught() public {
        _setupSessionKey(50);
        Call[] memory calls = _indirectSpendBatch(100); // 100 > cap, but only approve/pull selectors
        bytes memory opData = _signOpData(sessionKeyPk, BATCH_OPDATA, calls, 0);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(ISessionKey.SpendLimitExceeded.selector, sessionKey, address(token), 50, 100)
        );
        account.execute(BATCH_OPDATA, abi.encode(calls, opData));
        assertEq(token.balanceOf(address(account)), 1000, "over-spend not rolled back");
    }

    /// @notice An indirect spend within cap succeeds and accrues the balance decrease.
    function test_SessionKey_IndirectSpend_WithinCap() public {
        _setupSessionKey(100);
        Call[] memory calls = _indirectSpendBatch(80);
        bytes memory opData = _signOpData(sessionKeyPk, BATCH_OPDATA, calls, 0);
        vm.prank(stranger);
        account.execute(BATCH_OPDATA, abi.encode(calls, opData));
        (, uint256 spent) = account.spendLimit(sessionKey, address(token));
        assertEq(spent, 80, "balance-diff spend not accrued");
        assertEq(token.balanceOf(address(account)), 920, "tokens not moved");
    }

    /// @notice A direct transfer is counted once — the calldata sum equals the balance decrease, no double-count.
    function test_SessionKey_DirectSpend_NoDoubleCount() public {
        _setupSessionKey(100);
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(token), value: 0, data: abi.encodeCall(MockERC20.transfer, (dest, 40))});
        bytes memory opData = _signOpData(sessionKeyPk, BATCH_OPDATA, calls, 0);
        vm.prank(stranger);
        account.execute(BATCH_OPDATA, abi.encode(calls, opData));
        (, uint256 spent) = account.spendLimit(sessionKey, address(token));
        assertEq(spent, 40, "direct transfer double-counted");
    }

    /// @notice A capped token whose `balanceOf` reverts does NOT brick the key: snapshot/settle skip it and the
    ///         calldata sum still caps direct transfers.
    function test_SessionKey_RevertingBalanceOf_FallsBackToCalldata() public {
        (sessionKey, sessionKeyPk) = makeAddrAndKey("sessionKey");
        RevertingBalanceToken rtok = new RevertingBalanceToken();
        rtok.mint(address(account), 1000);
        ISessionKey.Permission[] memory perms = new ISessionKey.Permission[](1);
        perms[0] = ISessionKey.Permission({target: ANY_TARGET, selector: ANY_SELECTOR});
        vm.startPrank(admin);
        account.registerSessionKey(sessionKey, 0, uint48(1_000_000), perms);
        account.setSpendLimit(sessionKey, address(rtok), 100);
        vm.stopPrank();

        Call[] memory calls = new Call[](1);
        calls[0] =
            Call({target: address(rtok), value: 0, data: abi.encodeCall(RevertingBalanceToken.transfer, (dest, 40))});
        bytes memory opData = _signOpData(sessionKeyPk, BATCH_OPDATA, calls, 0);
        vm.prank(stranger);
        account.execute(BATCH_OPDATA, abi.encode(calls, opData)); // must not revert on snapshot/settle
        (, uint256 spent) = account.spendLimit(sessionKey, address(rtok));
        assertEq(spent, 40, "calldata sum not accrued for an unmeasurable token");
    }

    // ---- ERC-7579 global hook (type 4) wrapping execute (#58 follow-on) ----

    function _installHook() internal returns (MockHook hook) {
        hook = new MockHook();
        vm.prank(admin);
        account.installModule(MODULE_TYPE_HOOK, address(hook), "");
    }

    function test_Hook_WrapsExecute() public {
        MockHook hook = _installHook();
        vm.prank(admin);
        account.execute(BATCH, abi.encode(_oneCall(7, 0)));
        assertEq(hook.pre(), 1, "preCheck not called");
        assertEq(hook.post(), 1, "postCheck not called");
        assertEq(hook.lastSender(), admin, "preCheck msgSender wrong");
        assertEq(hook.lastCtx(), abi.encode(uint256(1)), "context not threaded pre -> post");
        assertEq(target.value(), 7, "batch not executed under hook");
    }

    function test_Hook_PreCheckRevertBlocksExecution() public {
        MockHook hook = _installHook();
        hook.setBlocks(true);
        vm.prank(admin);
        vm.expectRevert(bytes("hook: blocked"));
        account.execute(BATCH, abi.encode(_oneCall(9, 0)));
        assertEq(target.value(), 0, "execution not blocked by reverting hook");
    }

    function test_Hook_NoHookLeavesExecuteUnchanged() public {
        vm.prank(admin);
        account.execute(BATCH, abi.encode(_oneCall(5, 0)));
        assertEq(target.value(), 5, "execute broken without a hook");
    }

    /// @dev Atomic wrap: a reverting batch under a hook reverts the WHOLE call with the batch's error (preCheck's
    ///      effects roll back and postCheck never runs) — the hook wrap is transparent to reverts.
    function test_Hook_RevertingBatchPropagates() public {
        _installHook();
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.boom, ())});
        vm.prank(admin);
        vm.expectRevert(bytes("boom"));
        account.execute(BATCH, abi.encode(calls));
    }
}
