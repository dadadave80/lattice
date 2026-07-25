// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {AuroraConfig} from "@lattice-script/config/EnableAurora.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ChainRegistry} from "@lattice/crosschain/ChainRegistry.sol";
import {ChainRegistryInit} from "@lattice/crosschain/ChainRegistryInit.sol";
import {ERC7786OpenBridge} from "@lattice/crosschain/ERC7786OpenBridge.sol";
import {ERC7786OpenBridgeInit} from "@lattice/crosschain/ERC7786OpenBridgeInit.sol";
import {HyperlaneGatewayAdapter} from "@lattice/crosschain/hyperlane/HyperlaneGatewayAdapter.sol";
import {LayerZeroGatewayAdapter} from "@lattice/crosschain/layerzero/LayerZeroGatewayAdapter.sol";
import {IChainRegistry} from "@lattice/interfaces/crosschain/IChainRegistry.sol";
import {IERC7786OpenBridge} from "@lattice/interfaces/crosschain/IERC7786OpenBridge.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal ERC-7786 source gateway fixture for the OpenBridge fan-out (mirrors the gate tests).
contract AuroraMockGateway is IERC7786GatewaySource {
    uint256 public sends;
    uint256 internal _n;

    function supportsAttribute(bytes4) external pure returns (bool) {
        return false;
    }

    function sendMessage(bytes calldata, bytes calldata, bytes[] calldata) external payable returns (bytes32) {
        ++sends;
        return bytes32(++_n);
    }
}

/// @title AuroraEnablementTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice #77 sub-task 11 integration proof: Aurora (EVM-on-NEAR, chainId 1313161554) enabled as a REAL
///         M=2 destination — LayerZero (eid 30211) + Hyperlane (domain 1313161554) — through ONE
///         {IChainRegistry.addEvmChain} call built by {AuroraConfig.build}, on a diamond hosting the registry
///         fan-out, both gateway adapter facets, and the OpenBridge.
/// @dev Route caveats proven by construction (see {AuroraConfig}): Axelar REMOVED Aurora, Wormhole deprecated
///      it, CCIP never supported it — none of those sections are enabled. The `minDirectCoverage` M=1 guard
///      from sub-task 10 is exercised in reverse: Aurora PASSES a hard `minDirectCoverage = 2` gate, and the
///      gate correctly refuses again if one path's coverage is withdrawn. OpenBridge owns the shared
///      `sendMessage` selector in this composition (cut before the adapters); the adapters' admin/read
///      surfaces — all the fan-out touches — keep their unique selectors.
contract AuroraEnablementTest is Test, GetSelectors {
    ChainRegistry registry;
    ERC7786OpenBridge bridge;
    LayerZeroGatewayAdapter lz;
    HyperlaneGatewayAdapter hyperlane;
    address diamond;

    AuroraMockGateway lzGateway;
    AuroraMockGateway hyperlaneGateway;

    address admin = address(0x1);
    address user = address(0x2);

    bytes32 constant LZ_PEER = bytes32(uint256(uint160(address(0xA112))));
    bytes32 constant HYPERLANE_REMOTE = bytes32(uint256(uint160(address(0xA113))));
    uint128 constant LZ_GAS = 250_000;
    uint256 constant HYPERLANE_GAS = 400_000;

    bytes recipient;
    bytes32 chainKey;

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
        // OpenBridge is cut BEFORE the gateway adapters so it owns the shared IERC7786GatewaySource selectors.
        FacetCut[] memory cuts = new FacetCut[](6);
        cuts[0] = _cutUnique(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cutUnique(address(new AccessControl()), "AccessControl");
        cuts[2] = _cutUnique(address(new ERC7786OpenBridge()), "ERC7786OpenBridge");
        cuts[3] = _cutUnique(address(new ChainRegistry()), "ChainRegistry");
        cuts[4] = _cutUnique(address(new LayerZeroGatewayAdapter()), "LayerZeroGatewayAdapter");
        cuts[5] = _cutUnique(address(new HyperlaneGatewayAdapter()), "HyperlaneGatewayAdapter");

        address[] memory inits = new address[](2);
        bytes[] memory initDatas = new bytes[](2);
        inits[0] = address(new ERC7786OpenBridgeInit());
        initDatas[0] = abi.encodeCall(ERC7786OpenBridgeInit.init, (admin));
        inits[1] = address(new ChainRegistryInit());
        initDatas[1] = abi.encodeCall(ChainRegistryInit.init, (admin));

        Lattice d = new Lattice();
        d.initialize(cuts, address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, initDatas)));
        diamond = address(d);
        registry = ChainRegistry(diamond);
        bridge = ERC7786OpenBridge(diamond);
        lz = LayerZeroGatewayAdapter(diamond);
        hyperlane = HyperlaneGatewayAdapter(diamond);

        lzGateway = new AuroraMockGateway();
        hyperlaneGateway = new AuroraMockGateway();

        recipient = InteroperableAddress.formatEvmV1(AuroraConfig.CHAIN_ID, address(0xCAFE));
        chainKey = registry.chainKeyEvm(AuroraConfig.CHAIN_ID);

        vm.startPrank(admin);
        bridge.addGateway(address(lzGateway));
        bridge.addGateway(address(hyperlaneGateway));
        bridge.setThreshold(2);
        bridge.registerRemoteBridge(InteroperableAddress.formatEvmV1(AuroraConfig.CHAIN_ID, address(0xB0B)));
        vm.stopPrank();
    }

    function _enableAurora() internal {
        vm.prank(admin);
        registry.addEvmChain(
            AuroraConfig.build(
                LZ_PEER, LZ_GAS, HYPERLANE_REMOTE, HYPERLANE_GAS, address(lzGateway), address(hyperlaneGateway)
            )
        );
    }

    /// @notice ONE admin call wires Aurora across both live paths — asserted through each adapter's own reads.
    function test_EnableAuroraOneCall() public {
        _enableAurora();

        // LayerZero hot path (the adapter's own reads, not registry state).
        assertEq(lz.getEid(AuroraConfig.CHAIN_ID), AuroraConfig.LZ_EID, "lz eid");
        assertEq(lz.getChainId(AuroraConfig.LZ_EID), AuroraConfig.CHAIN_ID, "lz reverse eid");
        assertEq(lz.getPeer(AuroraConfig.CHAIN_ID), LZ_PEER, "lz peer");
        assertEq(lz.getDestinationGas(AuroraConfig.CHAIN_ID), LZ_GAS, "lz gas");

        // Hyperlane hot path.
        assertEq(hyperlane.domainOf(AuroraConfig.CHAIN_ID), AuroraConfig.HYPERLANE_DOMAIN, "hyperlane domain");
        assertEq(hyperlane.chainIdOf(AuroraConfig.HYPERLANE_DOMAIN), AuroraConfig.CHAIN_ID, "hyperlane reverse");
        assertEq(hyperlane.trustedRemoteOf(AuroraConfig.CHAIN_ID), HYPERLANE_REMOTE, "hyperlane remote");
        assertEq(hyperlane.destGasLimitOf(AuroraConfig.CHAIN_ID), HYPERLANE_GAS, "hyperlane gas");

        // Registry record: identity + native ids + REAL M=2 direct coverage.
        assertTrue(registry.isRegistered(chainKey), "registered");
        IChainRegistry.NativeIds memory ids = registry.nativeIdsOf(chainKey);
        assertEq(ids.lzEid, AuroraConfig.LZ_EID, "registry lz eid");
        assertEq(ids.hyperlaneDomain, AuroraConfig.HYPERLANE_DOMAIN, "registry hyperlane domain");
        assertEq(registry.coverageOf(chainKey), 2, "total coverage");
        assertEq(registry.directCoverageOf(chainKey), 2, "M=2 DIRECT coverage, no hub routing");
    }

    /// @notice Aurora uses standard 20-byte EVM ERC-7930 addressing — `formatEvmV1(1313161554, addr)`
    ///         round-trips unchanged (the issue's original premise, still true).
    function test_AuroraErc7930RoundTrip() public view {
        (uint256 chainId, address addr) = InteroperableAddress.parseEvmV1(recipient);
        assertEq(chainId, AuroraConfig.CHAIN_ID);
        assertEq(addr, address(0xCAFE));
        // 1313161554 = 0x4e454152 — ASCII "NEAR" — the canonical minimal big-endian chain reference.
        assertEq(chainKey, keccak256(abi.encodePacked(bytes2(0x0000), hex"4e454152")), "hand-derived NEAR chainKey");
    }

    /// @notice The sub-task's original ask, inverted: Aurora PASSES a hard `minDirectCoverage = 2` gate —
    ///         real 2-of-N, no M=1 waiver.
    function test_AuroraPassesMinDirectCoverage2() public {
        _enableAurora();
        vm.prank(admin);
        bridge.setMinDirectCoverage(2);

        vm.prank(user);
        bridge.sendMessage(recipient, hex"deadbeef", new bytes[](0));
        assertEq(lzGateway.sends(), 1, "fanned out via the LayerZero path");
        assertEq(hyperlaneGateway.sends(), 1, "fanned out via the Hyperlane path");
    }

    /// @notice And the guard still protects: withdrawing one path's coverage drops Aurora to M=1 and the
    ///         hard gate refuses until coverage is restored (or the knob is lowered).
    function test_AuroraRefusedWhenCoverageDropsToM1() public {
        _enableAurora();
        vm.startPrank(admin);
        bridge.setMinDirectCoverage(2);
        registry.setGatewayCoverage(chainKey, address(hyperlaneGateway), false, false);
        vm.stopPrank();

        assertEq(registry.directCoverageOf(chainKey), 1);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC7786OpenBridge.OpenBridgeInsufficientCoverage.selector, 1, 2));
        bridge.sendMessage(recipient, hex"deadbeef", new bytes[](0));

        // Restoring the second path recovers sends.
        vm.prank(admin);
        registry.setGatewayCoverage(chainKey, address(hyperlaneGateway), true, false);
        vm.prank(user);
        bridge.sendMessage(recipient, hex"deadbeef", new bytes[](0));
        assertEq(lzGateway.sends(), 1);
    }

    function test_EnableAuroraNonAdminReverts() public {
        vm.prank(user);
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        registry.addEvmChain(
            AuroraConfig.build(
                LZ_PEER, LZ_GAS, HYPERLANE_REMOTE, HYPERLANE_GAS, address(lzGateway), address(hyperlaneGateway)
            )
        );
    }
}
