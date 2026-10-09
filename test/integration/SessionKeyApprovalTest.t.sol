// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {Base} from "@lattice-test/Base.t.sol";
import {SessionKey} from "@lattice/accounts/SessionKey.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";
import {ANY_SELECTOR, ANY_TARGET} from "@lattice/accounts/libraries/SessionKeyLib.sol";
import {ISessionKey} from "@lattice/interfaces/accounts/ISessionKey.sol";
import {Call} from "@lattice/interfaces/external/ercs/IERC7821.sol";

/// @dev ERC-20 with `approve` + `increaseAllowance`; `transferFrom` underflows (reverts) past the allowance.
contract ApprovalToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
    }

    function approve(address sp, uint256 amt) external virtual returns (bool) {
        allowance[msg.sender][sp] = amt;
        return true;
    }

    function increaseAllowance(address sp, uint256 added) external returns (bool) {
        allowance[msg.sender][sp] += added;
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

/// @dev Returns `false` for a zero approval, so the post-batch reset cannot clear the allowance.
contract FalseResetToken is ApprovalToken {
    function approve(address sp, uint256 amt) external override returns (bool) {
        if (amt == 0) return false;
        allowance[msg.sender][sp] = amt;
        return true;
    }
}

/// @dev USDT-style `approve` that returns no data.
contract NoReturnApproveToken {
    mapping(address => mapping(address => uint256)) public allowance;

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function approve(address sp, uint256 amt) external {
        allowance[msg.sender][sp] = amt;
    }
}

/// @dev Pulls tokens from its caller through a prior approval.
contract ApprovalPuller {
    function pull(address token, uint256 amt) external {
        ApprovalToken(token).transferFrom(msg.sender, address(this), amt);
    }
}

/// @dev Permit2's allowance-setting entrypoint (`approve(address,address,uint160,uint48)`, 0x87517c45).
contract MockPermit2 {
    mapping(address => mapping(address => mapping(address => uint160))) public allowanceOf;

    function approve(address token, address spender, uint160 amount, uint48) external {
        allowanceOf[msg.sender][token][spender] = amount;
    }
}

/// @dev Operator-approval surface (`setApprovalForAll(address,bool)`, 0xa22cb465).
contract MockOperatorToken {
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
    }
}

/// @dev Minimal ERC-721 approval surface: `approve(address,uint256)` shares the ERC-20 selector, and there is
///      no `allowance` view.
contract MockNFT {
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) public getApproved;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 id) external {
        ownerOf[id] = to;
        ++balanceOf[to];
    }

    function approve(address sp, uint256 id) external {
        require(ownerOf[id] == msg.sender, "not owner");
        getApproved[id] = sp;
    }

    function transferFrom(address from, address to, uint256 id) external {
        require(ownerOf[id] == from && getApproved[id] == msg.sender, "not approved");
        delete getApproved[id];
        ownerOf[id] = to;
        --balanceOf[from];
        ++balanceOf[to];
    }
}

/// @title SessionKeyApprovalTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice #220 regressions through a real account diamond: the canonical {DeployAccount} blueprint with the
///         `SessionKey` facet cut in by a self-call. A capped session key must not leave a standing allowance on
///         a capped token after its batch, must not set Permit2 or operator approvals on a capped token, and a
///         revoked key must come back with no grants and no caps.
contract SessionKeyApprovalTest is Base {
    bytes32 internal constant BATCH = 0x0100000000000000000000000000000000000000000000000000000000000000;
    bytes32 internal constant BATCH_OPDATA = 0x0100000000007821000100000000000000000000000000000000000000000000;
    bytes32 internal constant EXECUTE_TYPEHASH = 0xb63526befbf5b966e64c36954eb12c5d09096e0b0a8a06e90bd0c857b842ebcb;
    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    address internal sessionKey;
    uint256 internal sessionKeyPk;
    address internal attacker = address(0xA77AC);
    address internal relayer = address(0xBEEF);
    ApprovalToken internal token;

    function setUp() public override {
        super.setUp();
        (sessionKey, sessionKeyPk) = makeAddrAndKey("sessionKey");
        token = new ApprovalToken();
        token.mint(account, 1000);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = ISessionKey.registerSessionKey.selector;
        selectors[1] = ISessionKey.revokeSessionKey.selector;
        selectors[2] = ISessionKey.isSessionKeyActive.selector;
        selectors[3] = ISessionKey.sessionKeyValidity.selector;
        selectors[4] = ISessionKey.isCallPermitted.selector;
        selectors[5] = ISessionKey.setSpendLimit.selector;
        selectors[6] = ISessionKey.spendLimit.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({
            facetAddress: address(new SessionKey()), action: FacetCutAction.Add, functionSelectors: selectors
        });
        vm.prank(account); // the account is its own cut authority and DEFAULT_ADMIN_ROLE holder
        IDiamondCut(account).diamondCut(cuts, address(0), "");
    }

    // ---- helpers ----

    function _register(address permTarget, bytes4 permSelector) internal {
        ISessionKey.Permission[] memory perms = new ISessionKey.Permission[](1);
        perms[0] = ISessionKey.Permission({target: permTarget, selector: permSelector});
        vm.prank(account);
        ISessionKey(account).registerSessionKey(sessionKey, 0, uint48(1_000_000), perms);
    }

    function _setCap(address capped, uint256 cap) internal {
        vm.prank(account);
        ISessionKey(account).setSpendLimit(sessionKey, capped, cap);
    }

    function _revoke() internal {
        vm.prank(account);
        ISessionKey(account).revokeSessionKey(sessionKey);
    }

    function _one(address target, bytes memory data) internal pure returns (Call[] memory calls) {
        calls = new Call[](1);
        calls[0] = Call({target: target, value: 0, data: data});
    }

    /// @dev Signs `calls` with the session key over the account's EIP-712 domain (unnamed in the blueprint, so
    ///      the hashed name and version are zero) and submits them from an unauthorized relayer.
    function _execAsKey(Call[] memory calls, uint256 nonce) internal {
        bytes32 sep = keccak256(abi.encode(DOMAIN_TYPEHASH, bytes32(0), bytes32(0), block.chainid, account));
        bytes32 structHash = keccak256(abi.encode(EXECUTE_TYPEHASH, BATCH_OPDATA, keccak256(abi.encode(calls)), nonce));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sessionKeyPk, keccak256(abi.encodePacked(hex"1901", sep, structHash)));
        bytes memory opData = abi.encode(nonce, abi.encodePacked(r, s, v));
        vm.prank(relayer);
        ERC7821Executor(payable(account)).execute(BATCH_OPDATA, abi.encode(calls, opData));
    }

    // ---- approval reset ----

    /// @notice The #220 scenario: a key granted only `(token, approve)` under a cap approves an address it
    ///         controls for the max, accruing nothing. The allowance must not outlive the batch, so the later
    ///         out-of-band pull fails.
    function test_SessionKey_ApproveThenLaterPull_Blocked() public {
        _register(address(token), ApprovalToken.approve.selector);
        _setCap(address(token), 100);
        _execAsKey(_one(address(token), abi.encodeCall(ApprovalToken.approve, (attacker, type(uint256).max))), 0);

        assertEq(token.allowance(account, attacker), 0, "allowance survived the capped batch");
        vm.prank(attacker);
        vm.expectRevert(); // allowance underflow
        token.transferFrom(account, attacker, 1000);
        assertEq(token.balanceOf(account), 1000, "account drained after the batch");
    }

    /// @notice Same drain through the repo's wildcard fixture shape `(ANY_TARGET, ANY_SELECTOR)` + a cap.
    function test_SessionKey_WildcardApprove_Reset() public {
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(token), 100);
        _execAsKey(_one(address(token), abi.encodeCall(ApprovalToken.approve, (attacker, 1000))), 0);
        assertEq(token.allowance(account, attacker), 0, "wildcard approval survived the capped batch");
    }

    /// @notice `increaseAllowance` on a capped token is reset the same way.
    function test_SessionKey_IncreaseAllowance_Reset() public {
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(token), 100);
        _execAsKey(_one(address(token), abi.encodeCall(ApprovalToken.increaseAllowance, (attacker, 1000))), 0);
        assertEq(token.allowance(account, attacker), 0, "increaseAllowance survived the capped batch");
    }

    /// @notice Approve + pull inside one batch still settles on the balance decrease, and the unused residual
    ///         allowance is cleared afterwards.
    function test_SessionKey_ApproveAndPull_ResidualReset() public {
        ApprovalPuller puller = new ApprovalPuller();
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(token), 100);
        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: address(token), value: 0, data: abi.encodeCall(ApprovalToken.approve, (address(puller), 100))
        });
        calls[1] =
            Call({target: address(puller), value: 0, data: abi.encodeCall(ApprovalPuller.pull, (address(token), 80))});
        _execAsKey(calls, 0);

        (, uint256 spent) = ISessionKey(account).spendLimit(sessionKey, address(token));
        assertEq(spent, 80, "balance decrease not accrued");
        assertEq(token.allowance(account, address(puller)), 0, "residual allowance not reset");
    }

    /// @notice An approval on a token the key has no cap on is left alone (it is uncapped anyway).
    function test_SessionKey_UncappedTokenApproval_Untouched() public {
        ApprovalToken other = new ApprovalToken();
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(token), 100);
        _execAsKey(_one(address(other), abi.encodeCall(ApprovalToken.approve, (attacker, 500))), 0);
        assertEq(other.allowance(account, attacker), 500, "uncapped approval was reset");
    }

    /// @notice If the reset cannot clear the allowance (the token returns `false`), the whole batch reverts.
    function test_SessionKey_ResetFailure_RevertsBatch() public {
        FalseResetToken bad = new FalseResetToken();
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(bad), 100);
        Call[] memory calls = _one(address(bad), abi.encodeCall(ApprovalToken.approve, (attacker, 1000)));
        vm.expectRevert(abi.encodeWithSelector(ISessionKey.ApprovalResetFailed.selector, address(bad), attacker));
        _execAsKey(calls, 0);
        assertEq(bad.allowance(account, attacker), 0, "approval not rolled back");
    }

    /// @notice A USDT-style `approve` with no return data is reset successfully.
    function test_SessionKey_NoReturnApprove_Reset() public {
        NoReturnApproveToken usdt = new NoReturnApproveToken();
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(usdt), 100);
        _execAsKey(_one(address(usdt), abi.encodeCall(NoReturnApproveToken.approve, (attacker, 1000))), 0);
        assertEq(usdt.allowance(account, attacker), 0, "no-return approval not reset");
    }

    /// @notice An `approve` on a capped ERC-721 shares the ERC-20 selector, but the reset would be
    ///         `approve(spender, tokenId 0)`. The reset is verified through `allowance`, which an ERC-721 lacks,
    ///         so the batch fails closed instead of leaving token 5 approved and granting token 0.
    function test_SessionKey_ERC721Approve_FailsClosed() public {
        MockNFT nft = new MockNFT();
        nft.mint(account, 0);
        nft.mint(account, 5);
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(nft), 1);
        Call[] memory calls = _one(address(nft), abi.encodeCall(MockNFT.approve, (attacker, 5)));
        vm.expectRevert(abi.encodeWithSelector(ISessionKey.ApprovalResetFailed.selector, address(nft), attacker));
        _execAsKey(calls, 0);
        assertEq(nft.getApproved(5), address(0), "token 5 approval survived");
        assertEq(nft.getApproved(0), address(0), "reset granted token 0");
    }

    // ---- self-calls ----

    /// @notice A wildcard key cannot nest an `approve` inside a self-`execute`: the inner batch would run as a
    ///         direct self-call with no session-key accounting or reset. `ANY_TARGET` does not match the account.
    function test_SessionKey_Wildcard_NestedSelfExecute_Reverts() public {
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(token), 100);
        Call[] memory inner = _one(address(token), abi.encodeCall(ApprovalToken.approve, (attacker, type(uint256).max)));
        Call[] memory calls = _one(account, abi.encodeCall(ERC7821Executor.execute, (BATCH, abi.encode(inner))));
        vm.expectRevert(
            abi.encodeWithSelector(
                ISessionKey.CallNotPermitted.selector, sessionKey, account, ERC7821Executor.execute.selector
            )
        );
        _execAsKey(calls, 0);
        assertEq(token.allowance(account, attacker), 0, "nested approval survived");
    }

    /// @notice A wildcard key cannot reach the account's admin entrypoints, e.g. lifting its own cap.
    function test_SessionKey_Wildcard_SelfSetSpendLimit_Reverts() public {
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(token), 100);
        Call[] memory calls =
            _one(account, abi.encodeCall(ISessionKey.setSpendLimit, (sessionKey, address(token), type(uint256).max)));
        vm.expectRevert(
            abi.encodeWithSelector(
                ISessionKey.CallNotPermitted.selector, sessionKey, account, ISessionKey.setSpendLimit.selector
            )
        );
        _execAsKey(calls, 0);
        (uint256 cap,) = ISessionKey(account).spendLimit(sessionKey, address(token));
        assertEq(cap, 100, "cap lifted by the key");
    }

    /// @notice An exact `(account, selector)` grant still permits that self-call.
    function test_SessionKey_ExactSelfGrant_Allowed() public {
        _register(account, ISessionKey.isSessionKeyActive.selector);
        assertTrue(
            ISessionKey(account).isCallPermitted(sessionKey, account, ISessionKey.isSessionKeyActive.selector),
            "exact self grant denied"
        );
        _execAsKey(_one(account, abi.encodeCall(ISessionKey.isSessionKeyActive, (sessionKey))), 0);
    }

    // ---- Permit2 / operator approvals ----

    /// @notice A capped key cannot set a Permit2 allowance on a capped token.
    function test_SessionKey_Permit2Approve_CappedToken_Reverts() public {
        MockPermit2 permit2 = new MockPermit2();
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(token), 100);
        Call[] memory calls = _one(
            address(permit2), abi.encodeCall(MockPermit2.approve, (address(token), attacker, type(uint160).max, 0))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                ISessionKey.ApprovalNotPermitted.selector, sessionKey, address(token), MockPermit2.approve.selector
            )
        );
        _execAsKey(calls, 0);
        assertEq(permit2.allowanceOf(account, address(token), attacker), 0, "Permit2 allowance set");
    }

    /// @notice A Permit2 allowance on a token the key has no cap on is still allowed.
    function test_SessionKey_Permit2Approve_UncappedToken_Allowed() public {
        MockPermit2 permit2 = new MockPermit2();
        address other = address(new ApprovalToken());
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(token), 100);
        _execAsKey(_one(address(permit2), abi.encodeCall(MockPermit2.approve, (other, attacker, 5, 0))), 0);
        assertEq(permit2.allowanceOf(account, other, attacker), 5, "uncapped Permit2 approval blocked");
    }

    /// @notice A capped key cannot grant an operator over a capped token with `setApprovalForAll`.
    function test_SessionKey_SetApprovalForAll_CappedToken_Reverts() public {
        MockOperatorToken op = new MockOperatorToken();
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(op), 100);
        Call[] memory calls = _one(address(op), abi.encodeCall(MockOperatorToken.setApprovalForAll, (attacker, true)));
        vm.expectRevert(
            abi.encodeWithSelector(
                ISessionKey.ApprovalNotPermitted.selector,
                sessionKey,
                address(op),
                MockOperatorToken.setApprovalForAll.selector
            )
        );
        _execAsKey(calls, 0);
    }

    // ---- revoke ----

    /// @notice Revoking a wildcard key and re-registering it narrowly leaves no trace of the old wildcard.
    function test_SessionKey_RevokeClearsGrants() public {
        _register(ANY_TARGET, ANY_SELECTOR);
        _revoke();
        _register(address(token), ApprovalToken.transfer.selector);

        assertTrue(
            ISessionKey(account).isCallPermitted(sessionKey, address(token), ApprovalToken.transfer.selector),
            "new grant missing"
        );
        assertFalse(
            ISessionKey(account).isCallPermitted(sessionKey, address(token), ApprovalToken.approve.selector),
            "old wildcard survived revoke"
        );
        Call[] memory calls = _one(address(token), abi.encodeCall(ApprovalToken.approve, (attacker, 1)));
        vm.expectRevert(
            abi.encodeWithSelector(
                ISessionKey.CallNotPermitted.selector, sessionKey, address(token), ApprovalToken.approve.selector
            )
        );
        _execAsKey(calls, 0);
    }

    /// @notice Revoke clears the key's caps and spent counters; a fresh cap after re-registration starts at 0
    ///         and settles each batch once (no duplicate capped-token entry).
    function test_SessionKey_RevokeClearsSpend() public {
        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(token), 100);
        _execAsKey(_one(address(token), abi.encodeCall(ApprovalToken.transfer, (attacker, 60))), 0);
        (, uint256 spentBefore) = ISessionKey(account).spendLimit(sessionKey, address(token));
        assertEq(spentBefore, 60, "pre-revoke spend");

        _revoke();
        (uint256 cap, uint256 spent) = ISessionKey(account).spendLimit(sessionKey, address(token));
        assertEq(cap, 0, "cap survived revoke");
        assertEq(spent, 0, "spent survived revoke");

        _register(ANY_TARGET, ANY_SELECTOR);
        _setCap(address(token), 100);
        ApprovalPuller puller = new ApprovalPuller();
        Call[] memory calls = new Call[](2);
        calls[0] = Call({
            target: address(token), value: 0, data: abi.encodeCall(ApprovalToken.approve, (address(puller), 80))
        });
        calls[1] =
            Call({target: address(puller), value: 0, data: abi.encodeCall(ApprovalPuller.pull, (address(token), 80))});
        _execAsKey(calls, 1);
        (, uint256 spentAfter) = ISessionKey(account).spendLimit(sessionKey, address(token));
        assertEq(spentAfter, 80, "spend settled more than once after re-registration");
    }
}
