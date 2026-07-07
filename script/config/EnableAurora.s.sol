// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IChainRegistry} from "@lattice/interfaces/crosschain/IChainRegistry.sol";
import {Script} from "forge-std/Script.sol";

/// @title AuroraConfig
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The ONE source of truth for enabling Aurora (EVM-on-NEAR) as an M=2 destination — shared by the
///         {EnableAurora} broadcast script and the `AuroraEnablementTest` integration proof.
/// @dev ROUTE FACTS (verified 2026-07-07 against the live canonical registries — re-verify at broadcast time):
///      - **Axelar REMOVED Aurora** (absent from the Axelarscan chain API, `axelar-contract-deployments`
///        mainnet registry, and `axelar-configs`) — the `axelar` section must NEVER be enabled for Aurora.
///      - **Wormhole deprecated Aurora** — never wire the `wormhole` section.
///      - **CCIP does not support Aurora** — never wire the `ccip` section.
///      - **LayerZero v2 is LIVE**: eid `30211`, EndpointV2 `0x1a44076050125825900e736c501f859c50fE728c`
///        (LayerZero metadata API; the endpoint address is the AURORA-side deployment, informational here).
///      - **Hyperlane is DEPLOYED**: mailbox `0x7f50C5776722630a0024fAE05fDe8b47571D7B39`, domain
///        `1313161554` (hyperlane-xyz/hyperlane-registry).
///      Aurora therefore ships as REAL M=2 (two direct gateways) — no `minDirectCoverage` M=1 waiver needed.
///      Standard 20-byte EVM addressing: `InteroperableAddress.formatEvmV1(1313161554, addr)` works unchanged.
library AuroraConfig {
    /// @notice Aurora mainnet EVM chainId.
    uint256 internal constant CHAIN_ID = 1_313_161_554;

    /// @notice Aurora's LayerZero v2 endpoint id (verified via the LayerZero metadata API).
    uint32 internal constant LZ_EID = 30_211;

    /// @notice Aurora's Hyperlane domain (equals the chainId, per hyperlane-registry — registered, not inferred).
    uint32 internal constant HYPERLANE_DOMAIN = 1_313_161_554;

    /// @notice Aurora-side LayerZero EndpointV2 (informational pin; the LOCAL adapter talks to the local endpoint).
    address internal constant AURORA_LZ_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;

    /// @notice Aurora-side Hyperlane Mailbox (informational pin; the LOCAL adapter talks to the local mailbox).
    address internal constant AURORA_HYPERLANE_MAILBOX = 0x7f50C5776722630a0024fAE05fDe8b47571D7B39;

    /// @notice Builds the one-action {IChainRegistry.addEvmChain} config enabling Aurora over LayerZero +
    ///         Hyperlane with 2-of-N direct coverage. Deployment-specific inputs stay parameters; the
    ///         chain-identity constants above are baked in.
    /// @param lzPeer            The counterpart LayerZero gateway adapter on Aurora (bytes32).
    /// @param lzGas             Per-destination LayerZero executor gas.
    /// @param hyperlaneRemote   The counterpart Hyperlane gateway adapter on Aurora (bytes32).
    /// @param hyperlaneGasLimit Per-destination Hyperlane handle gas limit.
    /// @param lzGateway         The LOCAL LayerZero gateway address enrolled in OpenBridge (coverage record).
    /// @param hyperlaneGateway  The LOCAL Hyperlane gateway address enrolled in OpenBridge (coverage record).
    function build(
        bytes32 lzPeer,
        uint128 lzGas,
        bytes32 hyperlaneRemote,
        uint256 hyperlaneGasLimit,
        address lzGateway,
        address hyperlaneGateway
    ) internal pure returns (IChainRegistry.AddEvmChainConfig memory cfg) {
        cfg.chainId = CHAIN_ID;
        cfg.layerZero =
            IChainRegistry.LayerZeroSection({enabled: true, eid: LZ_EID, peer: lzPeer, gas: lzGas, msgValue: 0});
        cfg.hyperlane = IChainRegistry.HyperlaneSection({
            enabled: true, domain: HYPERLANE_DOMAIN, remote: hyperlaneRemote, gasLimit: hyperlaneGasLimit
        });
        // Both paths are DIRECT (peer-to-peer gateways, no hub indirection) => real M=2 coverage.
        cfg.coverage.gateways = new address[](2);
        cfg.coverage.hubRouted = new bool[](2);
        cfg.coverage.gateways[0] = lzGateway;
        cfg.coverage.gateways[1] = hyperlaneGateway;
    }
}

/// @title EnableAurora
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Broadcasts the one-action Aurora enablement against a live diamond hosting the {ChainRegistry}
///         fan-out + the LayerZero and Hyperlane gateway adapter facets. Run with the diamond admin account:
///         `forge script script/config/EnableAurora.s.sol --account <admin> --sender <admin-addr> --broadcast`
/// @dev Env parameters (deployment-specific; the chain-identity constants live in {AuroraConfig}):
///      DIAMOND, AURORA_LZ_PEER (bytes32), AURORA_LZ_GAS, AURORA_HYPERLANE_REMOTE (bytes32),
///      AURORA_HYPERLANE_GAS, LZ_GATEWAY, HYPERLANE_GATEWAY.
contract EnableAurora is Script {
    function run() external {
        IChainRegistry registry = IChainRegistry(vm.envAddress("DIAMOND"));
        IChainRegistry.AddEvmChainConfig memory cfg = AuroraConfig.build(
            vm.envBytes32("AURORA_LZ_PEER"),
            uint128(vm.envUint("AURORA_LZ_GAS")),
            vm.envBytes32("AURORA_HYPERLANE_REMOTE"),
            vm.envUint("AURORA_HYPERLANE_GAS"),
            vm.envAddress("LZ_GATEWAY"),
            vm.envAddress("HYPERLANE_GATEWAY")
        );
        vm.startBroadcast();
        registry.addEvmChain(cfg);
        vm.stopBroadcast();
    }
}
