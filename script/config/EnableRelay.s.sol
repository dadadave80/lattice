// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAggregatorExecAdapter} from "@lattice/interfaces/defi/IAggregatorExecAdapter.sol";
import {Script} from "forge-std/Script.sol";

/// @title RelayConfig
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Relay (https://github.com/relayprotocol/relay-periphery)
/// @notice The ONE source of truth for enabling Reservoir's Relay (solver-intent bridging/execution) on the
///         {IAggregatorExecAdapter} type-(C) base — shared by the {EnableRelay} broadcast script and the
///         `RelayEnablementTest` integration proof. NO NEW FACET: Relay is an allow-list configuration of the
///         sub-task-7 adapter (canonical `(contract, selector)` pairs + quote-API opaque calldata).
/// @dev TRUST MODEL (solver intents — disclose to integrators):
///      - The user pays in on the origin chain; a SOLVER fronts the destination fill within seconds; solvers
///        settle off-chain via Relay's depository/settlement/oracle infrastructure — none of which Lattice
///        touches on-chain. There is NO inbound surface, NO `receiveId`, and NO on-chain completion signal:
///        source-tx success does NOT prove the destination fill (issue #77 Q3/Q12) — reconciliation is the
///        integrator's off-chain responsibility against Relay's API.
///      - Calldata comes from Relay's quote API and is OPAQUE — all security is the base adapter's outbound
///        machinery: the `(aggregator, selector)` allow-list, pull-from-caller, exact-approve→0 reset, and
///        delta sweeps. A quote's embedded `refundTo` may point at the diamond: leftovers land mid-call and
///        the base's input/native delta sweeps forward them to the calling user automatically.
///      CANONICAL SURFACE (relay-periphery, MIT — signatures pinned 2026-07-07; addresses are per-chain
///      deployment facts supplied at broadcast time, NOT constants: Relay ships v3 AND legacy v2.1 routers,
///      each in tstore and non-tstore variants per chain — pin the exact variant from Relay's deployment
///      registry at config time and re-verify):
///      - `RelayApprovalProxyV3.transferAndMulticall(tokens, amounts, calls, refundTo, nftRecipient, metadata)`
///        — the ERC-20 entry: pulls the approved input tokens from the caller (the diamond) and routes the
///        multicall through the router. The `permit*TransferAndMulticall` variants are EOA-signature paths and
///        are deliberately NOT allow-listed (the adapter pre-approves; permits would be a foreign trust path).
///      - `RelayRouterV3.multicall(calls, refundTo, nftRecipient, metadata)` — the native/value entry
///        (stateless Multicall3 router, holds no balances; `msg.value` rides the adapter's payable execute).
///      - `RelayReceiver.forward(bytes data)` — the plain native transfer-to-solver entry (emits the request
///        id; the receiver's raw `fallback()` path cannot be allow-listed — the base dispatches on
///        `bytes4(callData)` — so quotes MUST use `forward(bytes)`, document this to integrators).
library RelayConfig {
    /// @dev `bytes4(keccak256("transferAndMulticall(address[],uint256[],(address,bool,uint256,bytes)[],address,address,bytes)"))`
    ///      — `Call3Value { address target; bool allowFailure; uint256 value; bytes callData; }`.
    bytes4 internal constant TRANSFER_AND_MULTICALL_SELECTOR = bytes4(
        keccak256("transferAndMulticall(address[],uint256[],(address,bool,uint256,bytes)[],address,address,bytes)")
    );

    /// @dev `bytes4(keccak256("multicall((address,bool,uint256,bytes)[],address,address,bytes)"))`.
    bytes4 internal constant MULTICALL_SELECTOR =
        bytes4(keccak256("multicall((address,bool,uint256,bytes)[],address,address,bytes)"));

    /// @dev `bytes4(keccak256("forward(bytes)"))`.
    bytes4 internal constant FORWARD_SELECTOR = bytes4(keccak256("forward(bytes)"));

    /// @notice Applies the three canonical Relay allow-list pairs to `adapter` (admin-gated on the diamond).
    /// @param adapter        The diamond hosting the {IAggregatorExecAdapter} facet.
    /// @param approvalProxy  The chain's canonical `RelayApprovalProxy` (v3/v2.1 + tstore variant — pinned).
    /// @param router         The chain's canonical `RelayRouter` (same variant discipline).
    /// @param receiver       The chain's canonical `RelayReceiver` (solver-bound native forwarder).
    function configure(IAggregatorExecAdapter adapter, address approvalProxy, address router, address receiver)
        internal
    {
        adapter.setAllowedCall(approvalProxy, TRANSFER_AND_MULTICALL_SELECTOR, true);
        adapter.setAllowedCall(router, MULTICALL_SELECTOR, true);
        adapter.setAllowedCall(receiver, FORWARD_SELECTOR, true);
    }
}

/// @title EnableRelay
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Broadcasts the Relay allow-list configuration against a live diamond hosting the
///         {IAggregatorExecAdapter} facet. Run with the diamond admin account:
///         `forge script script/config/EnableRelay.s.sol --account <admin> --sender <admin-addr> --broadcast`
/// @dev Env parameters (per-chain canonical addresses from Relay's deployment registry — verify the
///      v3-vs-v2.1 and tstore-vs-non-tstore variant for the target chain at broadcast time):
///      DIAMOND, RELAY_APPROVAL_PROXY, RELAY_ROUTER, RELAY_RECEIVER.
contract EnableRelay is Script {
    function run() external {
        IAggregatorExecAdapter adapter = IAggregatorExecAdapter(vm.envAddress("DIAMOND"));
        vm.startBroadcast();
        RelayConfig.configure(
            adapter,
            vm.envAddress("RELAY_APPROVAL_PROXY"),
            vm.envAddress("RELAY_ROUTER"),
            vm.envAddress("RELAY_RECEIVER")
        );
        vm.stopBroadcast();
    }
}
