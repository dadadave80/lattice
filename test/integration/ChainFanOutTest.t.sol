// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ChainRegistry} from "@lattice/crosschain/ChainRegistry.sol";
import {ChainRegistryInit} from "@lattice/crosschain/ChainRegistryInit.sol";
import {AxelarGatewayAdapter} from "@lattice/crosschain/axelar/AxelarGatewayAdapter.sol";
import {CCIPGatewayAdapter} from "@lattice/crosschain/chainlink/CCIPGatewayAdapter.sol";
import {CCTPBridgeAdapter} from "@lattice/crosschain/circle/CCTPBridgeAdapter.sol";
import {HyperbridgeGatewayAdapter} from "@lattice/crosschain/hyperbridge/HyperbridgeGatewayAdapter.sol";
import {HyperlaneGatewayAdapter} from "@lattice/crosschain/hyperlane/HyperlaneGatewayAdapter.sol";
import {LayerZeroGatewayAdapter} from "@lattice/crosschain/layerzero/LayerZeroGatewayAdapter.sol";
import {StargateBridgeAdapter} from "@lattice/crosschain/layerzero/StargateBridgeAdapter.sol";
import {StargateBridgeAdapterLib} from "@lattice/crosschain/layerzero/StargateBridgeAdapterLib.sol";
import {
    L2ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/crosschain/optimism/L2ToL2CrossDomainMessengerGatewayAdapter.sol";
import {WormholeGatewayAdapter} from "@lattice/crosschain/wormhole/WormholeGatewayAdapter.sol";
import {WormholeGatewayAdapterLib} from "@lattice/crosschain/wormhole/WormholeGatewayAdapterLib.sol";
import {ZetaChainGatewayAdapter} from "@lattice/crosschain/zetachain/ZetaChainGatewayAdapter.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IChainRegistry} from "@lattice/interfaces/crosschain/IChainRegistry.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Test-only read probe. In this ALL-adapters composition the `getRemoteGateway(uint256)` selector is
///         owned by the CCIP facet (a production diamond mounts at most one ERC-7786 gateway adapter, so the
///         collision is an artifact of the composability proof) — this facet re-exposes the Wormhole adapter's
///         own lib read under a unique selector so the assertion still goes through the adapter's read surface.
contract WormholeRemoteReadProbe {
    function wormholeRemoteGatewayOf(uint256 chainId) external view returns (address) {
        return WormholeGatewayAdapterLib.getRemoteGateway(chainId);
    }
}

/// @notice THE COMPOSABILITY PROOF for the chain-registry fan-out (#77 sub-task 10): ONE diamond cuts the
///         chain registry alongside ALL TEN gateway/bridge adapters, `addEvmChain` is called ONCE as the
///         admin, and each adapter's OWN read surface must show its hot-path config landed — proving the
///         fan-out reaches every adapter lib's ERC-7201 storage through direct internal calls (msg.sender
///         stays the admin for each lib's own role check; never external self-calls).
/// @dev The gateway facets all expose the shared `IERC7786GatewaySource` surface (`sendMessage`,
///      `supportsAttribute`), so cutting them into one diamond needs first-wins selector dedupe
///      ({_cutUnique}); duplicated selectors are send-path only and irrelevant here — every asserted READ
///      selector below is uniquely owned, except the Wormhole remote-gateway read (see
///      {WormholeRemoteReadProbe}). Adapter inits are deliberately NOT run: the fan-out writes admin config
///      only, which never touches the endpoint/router wiring.
contract ChainFanOutTest is Test, GetSelectors {
    address diamond;
    ChainRegistry registry;

    address admin = address(0x1);
    address user = address(0x2);

    // Base mainnet fixture: chainId 8453 (reference 0x2105).
    uint256 constant BASE_CHAIN_ID = 8453;
    uint64 constant CCIP_SELECTOR = 15971525489660198786;
    uint32 constant LZ_EID = 30184;
    uint16 constant WORMHOLE_ID = 30;
    uint32 constant CCTP_DOMAIN = 6;
    uint32 constant HYPERLANE_DOMAIN = 8453; // Hyperlane's Base domain HAPPENS to equal the chainId
    uint32 constant STARGATE_EID = LZ_EID; // Stargate rides LayerZero — the eid IS the LZ eid (own map)

    address ccipRemote = address(0xCC1);
    bytes32 lzPeer = bytes32(uint256(uint160(address(0x1AE0))));
    address wormholeRemote = address(0x3011);
    address axelarRemote = address(0xA8e1);
    address zetaApp = address(0x2E7A);
    address opRemoteAdapter = address(0x0FF2);
    bytes32 hyperlaneRemote = bytes32(uint256(uint160(address(0x437E))));
    bytes hyperbridgeModule = abi.encodePacked(address(0x15D1)); // counterpart ISMP module on Base
    uint64 constant HYPERBRIDGE_TIMEOUT = 3600;

    address covDirect1 = address(0xAD01);
    address covDirect2 = address(0xAD02);
    address covHub = address(0xAD03);

    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    mapping(bytes4 selector => bool taken) internal _seen;

    /// @notice An `Add` cut keeping only the selectors no earlier facet in this composition claimed.
    function _cutUnique(address facet, string memory name) internal returns (FacetCut memory) {
        bytes4[] memory selectors = _getSelectors(name);
        bytes4[] memory keep = new bytes4[](selectors.length);
        uint256 kept;
        for (uint256 i; i < selectors.length; ++i) {
            // Never cut the ERC-8153 `exportSelectors()` selector (0x0ef22643) onto a diamond.
            if (selectors[i] == bytes4(0x0ef22643)) continue;
            if (_seen[selectors[i]]) continue;
            _seen[selectors[i]] = true;
            keep[kept++] = selectors[i];
        }
        assembly ("memory-safe") {
            mstore(keep, kept)
        }
        return FacetCut(facet, FacetCutAction.Add, keep);
    }

    function setUp() public {
        FacetCut[] memory cuts = new FacetCut[](14);
        cuts[0] = _cutUnique(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cutUnique(address(new AccessControl()), "AccessControl");
        cuts[2] = _cutUnique(address(new ChainRegistry()), "ChainRegistry");
        cuts[3] = _cutUnique(address(new CCIPGatewayAdapter()), "CCIPGatewayAdapter");
        cuts[4] = _cutUnique(address(new LayerZeroGatewayAdapter()), "LayerZeroGatewayAdapter");
        cuts[5] = _cutUnique(address(new WormholeGatewayAdapter()), "WormholeGatewayAdapter");
        cuts[6] = _cutUnique(address(new AxelarGatewayAdapter()), "AxelarGatewayAdapter");
        cuts[7] = _cutUnique(address(new ZetaChainGatewayAdapter()), "ZetaChainGatewayAdapter");
        cuts[8] = _cutUnique(
            address(new L2ToL2CrossDomainMessengerGatewayAdapter()), "L2ToL2CrossDomainMessengerGatewayAdapter"
        );
        cuts[9] = _cutUnique(address(new CCTPBridgeAdapter()), "CCTPBridgeAdapter");
        cuts[10] = _cutUnique(address(new HyperlaneGatewayAdapter()), "HyperlaneGatewayAdapter");
        cuts[11] = _cutUnique(address(new StargateBridgeAdapter()), "StargateBridgeAdapter");
        cuts[12] = _cutUnique(address(new HyperbridgeGatewayAdapter()), "HyperbridgeGatewayAdapter");
        cuts[13] = _cutUnique(address(new WormholeRemoteReadProbe()), "WormholeRemoteReadProbe");

        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, address(new ChainRegistryInit()), abi.encodeCall(ChainRegistryInit.init, (admin)));
        diamond = address(d);
        registry = ChainRegistry(diamond);
    }

    function _fullConfig() internal view returns (IChainRegistry.AddEvmChainConfig memory cfg) {
        cfg.chainId = BASE_CHAIN_ID;
        cfg.ccip = IChainRegistry.CcipSection({
            enabled: true,
            selector: CCIP_SELECTOR,
            remoteGateway: ccipRemote,
            gasLimit: 300_000,
            allowOutOfOrderExecution: true
        });
        cfg.layerZero =
            IChainRegistry.LayerZeroSection({enabled: true, eid: LZ_EID, peer: lzPeer, gas: 200_000, msgValue: 1e15});
        cfg.wormhole = IChainRegistry.WormholeSection({enabled: true, wormholeId: WORMHOLE_ID, remote: wormholeRemote});
        cfg.axelar = IChainRegistry.AxelarSection({
            enabled: true,
            axelarName: "base",
            remote7930: InteroperableAddress.formatEvmV1(BASE_CHAIN_ID, axelarRemote),
            chain7930: InteroperableAddress.formatEvmV1(BASE_CHAIN_ID)
        });
        cfg.zeta = IChainRegistry.ZetaSection({enabled: true, remoteApp: zetaApp});
        cfg.opL2ToL2 = IChainRegistry.OpL2ToL2Section({enabled: true, remoteAdapter: opRemoteAdapter});
        cfg.cctp = IChainRegistry.CctpSection({
            enabled: true, domain: CCTP_DOMAIN, maxFee: 500, minFinalityThreshold: 2000, destinationCaller: bytes32(0)
        });
        cfg.hyperlane = IChainRegistry.HyperlaneSection({
            enabled: true, domain: HYPERLANE_DOMAIN, remote: hyperlaneRemote, gasLimit: 400_000
        });
        cfg.stargate = IChainRegistry.StargateSection({enabled: true, eid: STARGATE_EID});
        cfg.hyperbridge = IChainRegistry.HyperbridgeSection({
            enabled: true, remoteModule: hyperbridgeModule, timeout: HYPERBRIDGE_TIMEOUT
        });
        cfg.coverage.gateways = new address[](3);
        cfg.coverage.hubRouted = new bool[](3);
        cfg.coverage.gateways[0] = covDirect1;
        cfg.coverage.gateways[1] = covDirect2;
        cfg.coverage.gateways[2] = covHub;
        cfg.coverage.hubRouted[2] = true; // e.g. the ZetaChain adapter: reaches Base only via the ZEVM hub
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            FULL FAN-OUT (ONE CALL)
    //////////////////////////////////////////////////////////////////////////*//

    function test_AddEvmChainFansOutToEveryAdapter() public {
        bytes32 chainKey = registry.chainKeyEvm(BASE_CHAIN_ID);

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit IChainRegistry.ChainAdded(chainKey, BASE_CHAIN_ID);
        registry.addEvmChain(_fullConfig());

        // Assert THROUGH EACH ADAPTER'S OWN READ SURFACE that its hot-path config landed (split into
        // per-adapter helpers to stay under the non-via-IR stack limit).
        _assertCcipLanded();
        _assertLayerZeroLanded();
        _assertWormholeLanded();
        _assertAxelarLanded();
        _assertZetaAndOpLanded();
        _assertCctpLanded();
        _assertHyperlaneLanded();
        _assertStargateLanded();
        _assertHyperbridgeLanded();
        _assertRegistryLanded(chainKey);
    }

    /// @dev CCIP: selector map + remote gateway + destination config, through the CCIP facet.
    function _assertCcipLanded() internal view {
        CCIPGatewayAdapter ccip = CCIPGatewayAdapter(diamond);
        assertEq(ccip.getChainSelector(BASE_CHAIN_ID), CCIP_SELECTOR, "ccip selector");
        assertEq(ccip.getChainId(CCIP_SELECTOR), BASE_CHAIN_ID, "ccip reverse selector");
        assertEq(ccip.getRemoteGateway(BASE_CHAIN_ID), ccipRemote, "ccip remote");
        assertEq(ccip.getDestinationGasLimit(BASE_CHAIN_ID), 300_000, "ccip gas limit");
        assertTrue(ccip.getAllowOutOfOrderExecution(BASE_CHAIN_ID), "ccip out-of-order");
    }

    /// @dev LayerZero: eid + peer + destination config, through the LayerZero facet.
    function _assertLayerZeroLanded() internal view {
        LayerZeroGatewayAdapter lz = LayerZeroGatewayAdapter(diamond);
        assertEq(lz.getEid(BASE_CHAIN_ID), LZ_EID, "lz eid");
        assertEq(lz.getChainId(LZ_EID), BASE_CHAIN_ID, "lz reverse eid");
        assertEq(lz.getPeer(BASE_CHAIN_ID), lzPeer, "lz peer");
        assertEq(lz.getDestinationGas(BASE_CHAIN_ID), 200_000, "lz gas");
        assertEq(lz.getDestinationMsgValue(BASE_CHAIN_ID), 1e15, "lz msgValue");
    }

    /// @dev Wormhole: chain equivalence through the Wormhole facet; remote via its lib-read probe.
    function _assertWormholeLanded() internal view {
        WormholeGatewayAdapter wormhole = WormholeGatewayAdapter(diamond);
        assertEq(wormhole.getWormholeChain(BASE_CHAIN_ID), WORMHOLE_ID, "wormhole id");
        assertEq(wormhole.getChainId(WORMHOLE_ID), BASE_CHAIN_ID, "wormhole reverse id");
        assertEq(
            WormholeRemoteReadProbe(diamond).wormholeRemoteGatewayOf(BASE_CHAIN_ID), wormholeRemote, "wormhole remote"
        );
    }

    /// @dev Axelar: both equivalence directions + remote gateway, through the Axelar facet.
    function _assertAxelarLanded() internal view {
        AxelarGatewayAdapter axelar = AxelarGatewayAdapter(diamond);
        bytes memory chain7930 = InteroperableAddress.formatEvmV1(BASE_CHAIN_ID);
        assertEq(axelar.getAxelarChain(chain7930), "base", "axelar name");
        assertEq(axelar.getErc7930Chain("base"), chain7930, "axelar reverse chain");
        assertEq(axelar.getRemoteGateway(chain7930), abi.encodePacked(axelarRemote), "axelar remote");
    }

    /// @dev ZetaChain: remote universal app (both maps); OP L2-to-L2: remote sibling adapter.
    function _assertZetaAndOpLanded() internal view {
        ZetaChainGatewayAdapter zeta = ZetaChainGatewayAdapter(diamond);
        assertEq(zeta.getRemoteApp(BASE_CHAIN_ID), zetaApp, "zeta remote app");
        assertEq(zeta.getChainIdForApp(zetaApp), BASE_CHAIN_ID, "zeta reverse app");
        assertEq(
            L2ToL2CrossDomainMessengerGatewayAdapter(diamond).getRemoteAdapter(BASE_CHAIN_ID),
            opRemoteAdapter,
            "op remote adapter"
        );
    }

    /// @dev CCTP: domain map + per-domain config, through the CCTP facet.
    function _assertCctpLanded() internal view {
        CCTPBridgeAdapter cctp = CCTPBridgeAdapter(diamond);
        assertTrue(cctp.isChainRegistered(BASE_CHAIN_ID), "cctp registered");
        assertEq(cctp.getDomain(BASE_CHAIN_ID), CCTP_DOMAIN, "cctp domain");
        (uint256 maxFee, uint32 minFinality, bytes32 destCaller) = cctp.getDomainConfig(CCTP_DOMAIN);
        assertEq(maxFee, 500, "cctp maxFee");
        assertEq(minFinality, 2000, "cctp finality");
        assertEq(destCaller, bytes32(0), "cctp destinationCaller");
    }

    /// @dev Hyperlane: domain map (both directions) + trusted remote + destination gas, through the
    ///      Hyperlane facet.
    function _assertHyperlaneLanded() internal view {
        HyperlaneGatewayAdapter hyperlane = HyperlaneGatewayAdapter(diamond);
        assertEq(hyperlane.domainOf(BASE_CHAIN_ID), HYPERLANE_DOMAIN, "hyperlane domain");
        assertEq(hyperlane.chainIdOf(HYPERLANE_DOMAIN), BASE_CHAIN_ID, "hyperlane reverse domain");
        assertEq(hyperlane.trustedRemoteOf(BASE_CHAIN_ID), hyperlaneRemote, "hyperlane remote");
        assertEq(hyperlane.destGasLimitOf(BASE_CHAIN_ID), 400_000, "hyperlane gas limit");
    }

    /// @dev Stargate: chainId ⇄ eid map (both directions) landed in the Stargate adapter's OWN storage —
    ///      same eid value as LayerZero's (Stargate rides LayerZero) but a SEPARATE ERC-7201 map (adapters
    ///      never share hot-path storage), through the Stargate facet; the reverse map via its lib-read probe
    ///      (the `stargateChainIdOf(uint32)` selector is owned by the Hyperlane facet in this composition).
    function _assertStargateLanded() internal view {
        assertEq(StargateBridgeAdapter(diamond).stargateEidOf(BASE_CHAIN_ID), STARGATE_EID, "stargate eid");
        assertEq(StargateBridgeAdapter(diamond).stargateChainIdOf(STARGATE_EID), BASE_CHAIN_ID, "stargate reverse eid");
    }

    /// @dev Hyperbridge: the state machine id must equal the HAND-BUILT canonical `bytes("EVM-8453")` — the
    ///      fan-out derives it from `cfg.chainId`, never from caller-supplied bytes — plus the reverse map,
    ///      trusted remote module and dispatch timeout, through the Hyperbridge facet.
    function _assertHyperbridgeLanded() internal view {
        HyperbridgeGatewayAdapter hyperbridge = HyperbridgeGatewayAdapter(payable(diamond));
        assertEq(hyperbridge.stateMachineIdOf(BASE_CHAIN_ID), bytes("EVM-8453"), "hyperbridge derived id");
        assertEq(hyperbridge.chainIdOfStateMachine(bytes("EVM-8453")), BASE_CHAIN_ID, "hyperbridge reverse id");
        assertEq(hyperbridge.hyperbridgeRemoteModuleOf(BASE_CHAIN_ID), hyperbridgeModule, "hyperbridge module");
        assertEq(hyperbridge.hyperbridgeDestTimeoutOf(BASE_CHAIN_ID), HYPERBRIDGE_TIMEOUT, "hyperbridge timeout");
    }

    /// @dev Registry: identity + native ids + coverage math (hub-routed excluded from direct).
    function _assertRegistryLanded(bytes32 chainKey) internal view {
        assertTrue(registry.isRegistered(chainKey));
        (bytes2 chainType, bytes memory chainReference, uint256 evmChainId) = registry.chainInfoOf(chainKey);
        assertEq(chainType, bytes2(0x0000));
        assertEq(chainReference, hex"2105", "canonical minimal big-endian reference");
        assertEq(evmChainId, BASE_CHAIN_ID);

        IChainRegistry.NativeIds memory ids = registry.nativeIdsOf(chainKey);
        assertEq(ids.ccipSelector, CCIP_SELECTOR);
        assertEq(ids.lzEid, LZ_EID);
        assertEq(ids.wormholeId, WORMHOLE_ID);
        assertEq(ids.cctpDomain, CCTP_DOMAIN);
        assertEq(ids.axelarName, "base");
        assertEq(ids.hyperlaneDomain, HYPERLANE_DOMAIN);

        assertEq(registry.coverageOf(chainKey), 3, "total coverage");
        assertEq(registry.directCoverageOf(chainKey), 2, "hub-routed never counts as direct");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              PARTIAL FAN-OUT
    //////////////////////////////////////////////////////////////////////////*//

    function test_PartialFanOutOnlyTouchesEnabledSections() public {
        // Arbitrum One fixture (chainId 42161 = 0xa4b1): only LayerZero + CCTP enabled.
        uint256 chainId = 42161;
        IChainRegistry.AddEvmChainConfig memory cfg;
        cfg.chainId = chainId;
        cfg.layerZero =
            IChainRegistry.LayerZeroSection({enabled: true, eid: 30110, peer: lzPeer, gas: 150_000, msgValue: 0});
        cfg.cctp = IChainRegistry.CctpSection({
            enabled: true, domain: 3, maxFee: 100, minFinalityThreshold: 1000, destinationCaller: bytes32(0)
        });
        cfg.coverage.gateways = new address[](1);
        cfg.coverage.hubRouted = new bool[](1);
        cfg.coverage.gateways[0] = covDirect1;

        vm.prank(admin);
        registry.addEvmChain(cfg);

        // Enabled sections landed…
        assertEq(LayerZeroGatewayAdapter(diamond).getEid(chainId), 30110);
        assertEq(LayerZeroGatewayAdapter(diamond).getPeer(chainId), lzPeer);
        assertTrue(CCTPBridgeAdapter(diamond).isChainRegistered(chainId));
        assertEq(CCTPBridgeAdapter(diamond).getDomain(chainId), 3);

        // …disabled sections left every other adapter untouched.
        assertEq(CCIPGatewayAdapter(diamond).getChainSelector(chainId), 0, "ccip untouched");
        assertEq(CCIPGatewayAdapter(diamond).getRemoteGateway(chainId), address(0), "ccip remote untouched");
        assertEq(WormholeGatewayAdapter(diamond).getWormholeChain(chainId), 0, "wormhole untouched");
        assertEq(AxelarGatewayAdapter(diamond).getAxelarChain(InteroperableAddress.formatEvmV1(chainId)), "");
        assertEq(ZetaChainGatewayAdapter(diamond).getRemoteApp(chainId), address(0), "zeta untouched");
        assertEq(
            L2ToL2CrossDomainMessengerGatewayAdapter(diamond).getRemoteAdapter(chainId), address(0), "op untouched"
        );
        assertEq(HyperlaneGatewayAdapter(diamond).domainOf(chainId), 0, "hyperlane untouched");
        assertEq(HyperlaneGatewayAdapter(diamond).trustedRemoteOf(chainId), bytes32(0), "hyperlane remote untouched");
        assertEq(StargateBridgeAdapter(diamond).stargateEidOf(chainId), 0, "stargate untouched");
        assertEq(StargateBridgeAdapter(diamond).stargateChainIdOf(30110), 0, "stargate reverse map untouched");
        assertEq(
            HyperbridgeGatewayAdapter(payable(diamond)).stateMachineIdOf(chainId).length, 0, "hyperbridge untouched"
        );
        assertEq(
            HyperbridgeGatewayAdapter(payable(diamond)).hyperbridgeRemoteModuleOf(chainId).length,
            0,
            "hyperbridge module untouched"
        );

        // Registry: only the enabled sections' native ids are set.
        bytes32 chainKey = registry.chainKeyEvm(chainId);
        IChainRegistry.NativeIds memory ids = registry.nativeIdsOf(chainKey);
        assertEq(ids.ccipSelector, 0);
        assertEq(ids.lzEid, 30110);
        assertEq(ids.wormholeId, 0);
        assertEq(ids.cctpDomain, 3);
        assertEq(ids.axelarName, "");
        assertEq(ids.hyperlaneDomain, 0);
        assertEq(registry.coverageOf(chainKey), 1);
        assertEq(registry.directCoverageOf(chainKey), 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  GUARDS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice CCTP LOUD-DUPLICATE REGRESSION (review MEDIUM): a second chain fat-fingering an already-owned
    ///         CCTP domain must revert CCTPDomainAlreadyRegistered instead of silently remapping USDC burns and
    ///         clobbering the first chain's domain config — CCTP now fails loudly like every other section.
    function test_AddEvmChainCctpDuplicateDomainReverts() public {
        vm.prank(admin);
        registry.addEvmChain(_fullConfig());

        // A different chain claiming the SAME domain: loud revert, nothing overwritten.
        IChainRegistry.AddEvmChainConfig memory dup;
        dup.chainId = 42_161; // Arbitrum, but with Base's domain by mistake
        dup.cctp = IChainRegistry.CctpSection({
            enabled: true, domain: CCTP_DOMAIN, maxFee: 1, minFinalityThreshold: 1000, destinationCaller: bytes32(0)
        });
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(ICCTPBridgeAdapter.CCTPDomainAlreadyRegistered.selector, CCTP_DOMAIN, BASE_CHAIN_ID)
        );
        registry.addEvmChain(dup);

        // First chain's identity and config are untouched.
        CCTPBridgeAdapter cctp = CCTPBridgeAdapter(diamond);
        assertEq(cctp.getDomain(BASE_CHAIN_ID), CCTP_DOMAIN);
        (uint256 maxFee,,) = cctp.getDomainConfig(CCTP_DOMAIN);
        assertEq(maxFee, 500, "original domain config not clobbered");
        assertEq(cctp.domainOwner(CCTP_DOMAIN), BASE_CHAIN_ID, "domain owner is the first chain");
    }

    /// @notice STARGATE/LZ EID CROSS-CHECK (review finding): a typoed Stargate eid contradicting the
    ///         layerZero section fails loudly instead of silently routing funds to the wrong chain.
    function test_AddEvmChainStargateEidMismatchReverts() public {
        IChainRegistry.AddEvmChainConfig memory cfg = _fullConfig();
        cfg.stargate.eid = STARGATE_EID + 1; // contradicts cfg.layerZero.eid
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IChainRegistry.ChainRegistryStargateEidMismatch.selector, STARGATE_EID, STARGATE_EID + 1
            )
        );
        registry.addEvmChain(cfg);
    }

    function test_AddEvmChainNonAdminReverts() public {
        IChainRegistry.AddEvmChainConfig memory cfg = _fullConfig();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        registry.addEvmChain(cfg);
    }

    function test_AddEvmChainAxelarChainEncodingMismatchReverts() public {
        IChainRegistry.AddEvmChainConfig memory cfg;
        cfg.chainId = BASE_CHAIN_ID;
        cfg.axelar = IChainRegistry.AxelarSection({
            enabled: true,
            axelarName: "base",
            remote7930: InteroperableAddress.formatEvmV1(BASE_CHAIN_ID, axelarRemote),
            chain7930: InteroperableAddress.formatEvmV1(1) // wrong chain — not the canonical Base encoding
        });

        vm.prank(admin);
        vm.expectRevert(IChainRegistry.ChainRegistryAxelarChainMismatch.selector);
        registry.addEvmChain(cfg);
    }

    function test_AddEvmChainAxelarRemoteEncodingMismatchReverts() public {
        IChainRegistry.AddEvmChainConfig memory cfg;
        cfg.chainId = BASE_CHAIN_ID;
        cfg.axelar = IChainRegistry.AxelarSection({
            enabled: true,
            axelarName: "base",
            remote7930: InteroperableAddress.formatEvmV1(1, axelarRemote), // remote addressed to the wrong chain
            chain7930: InteroperableAddress.formatEvmV1(BASE_CHAIN_ID)
        });

        vm.prank(admin);
        vm.expectRevert(IChainRegistry.ChainRegistryAxelarRemoteMismatch.selector);
        registry.addEvmChain(cfg);
    }
}
