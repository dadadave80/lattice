// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CCTPHookDemo} from "@lattice-script/base/crosschain/CCTPHookDemo.s.sol";
import {CCTPHookVault} from "@lattice/examples/crosschain/CCTPHookVault.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title CCTPHookDemoFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Fork proof of the CCTP v2 hook showcase on Base Sepolia. Env-gated: every test `vm.skip`s cleanly
///         when `BASE_SEPOLIA_RPC_URL` is unset (never fails), and pins a default block (overridable via
///         `BASE_SEPOLIA_FORK_BLOCK`) so the RPC cache hits. The Arc-side burn is NEVER forked/simulated — revm
///         cannot execute Arc's native-USDC precompile (0x1800…); that leg is proven live via `cast send`.
///
///         Enable:  export BASE_SEPOLIA_RPC_URL=… ; forge test --match-path 'test/fork/CCTPHookDemoFork.t.sol'
contract CCTPHookDemoFork is Test {
    uint256 internal constant BASE_SEPOLIA_FORK_BLOCK = 21_000_000;
    address internal constant BASE_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    string internal constant FIXTURE = "test/fixtures/cctp/arc-to-base-hook-v2.json";

    CCTPHookDemo internal demo;

    function setUp() public {
        if (bytes(vm.envOr("BASE_SEPOLIA_RPC_URL", string(""))).length == 0) return;
        demo = new CCTPHookDemo();
        vm.makePersistent(address(demo));
    }

    /// @dev True (and `vm.skip`s) when Base Sepolia RPC is unset — keeps CI green without the secret.
    function _skipped() internal returns (bool skip) {
        if (bytes(vm.envOr("BASE_SEPOLIA_RPC_URL", string(""))).length == 0) {
            vm.skip(true);
            skip = true;
        }
    }

    /// @notice The Base destination diamond + {CCTPHookVault} assemble, and the vault's trust anchor is exactly
    ///         the diamond's own {CCTPHookExecutor}.
    function test_Fork_HookDemoAssemblesDestDiamondAndVault() public {
        if (_skipped()) return;
        vm.createSelectFork("base-sepolia", vm.envOr("BASE_SEPOLIA_FORK_BLOCK", BASE_SEPOLIA_FORK_BLOCK));

        (address diamond, address vault) = demo._setupHookDest(address(this));

        assertEq(
            CCTPHookVault(vault).executor(),
            ICCTPBridgeAdapter(diamond).hookExecutor(),
            "vault trust anchor == the diamond's executor"
        );
        assertEq(CCTPHookVault(vault).usdc(), BASE_USDC, "vault uses Base Sepolia USDC");
        assertEq(ICCTPBridgeAdapter(diamond).usdc(), BASE_USDC, "diamond wired to Base Sepolia USDC");
    }

    /// @notice Replays a REAL captured Arc->Base hook transfer: `relayMessageWithHook` must credit the
    ///         beneficiary the minted amount, and a second relay must revert (the CCTP nonce is consumed). A hook
    ///         fixture only exists AFTER the operator's live run (a synthetic message cannot carry a real Iris
    ///         attestation), so the fixture ships as a placeholder (empty `message`) and this test skips until it
    ///         is filled — see test/fixtures/cctp/arc-to-base-hook-v2.json for the capture instructions.
    function test_Fork_RelayWithHookCreditsVaultFromRealAttestation() public {
        if (_skipped()) return;

        string memory json = vm.readFile(FIXTURE);
        bytes memory message = vm.parseJsonBytes(json, ".message");
        if (message.length == 0) {
            vm.skip(true); // placeholder fixture — not yet captured
            return;
        }

        bytes memory attestation = vm.parseJsonBytes(json, ".attestation");
        address diamond = vm.parseJsonAddress(json, ".baseDiamond");
        address vault = vm.parseJsonAddress(json, ".vault");
        address beneficiary = vm.parseJsonAddress(json, ".beneficiary");
        uint256 amount = vm.parseJsonUint(json, ".amount");
        uint256 receiveBlock = vm.parseJsonUint(json, ".receiveBlock");

        vm.createSelectFork("base-sepolia", receiveBlock - 1);

        uint256 creditBefore = CCTPHookVault(vault).creditOf(beneficiary);
        ICCTPBridgeAdapter(diamond).relayMessageWithHook(message, attestation);
        assertEq(
            CCTPHookVault(vault).creditOf(beneficiary) - creditBefore, amount, "beneficiary credited the minted amount"
        );

        vm.expectRevert(); // second relay: the CCTP nonce is already consumed
        ICCTPBridgeAdapter(diamond).relayMessageWithHook(message, attestation);
    }
}
