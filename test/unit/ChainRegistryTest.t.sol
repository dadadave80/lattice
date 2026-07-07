// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {NotInitializing} from "@diamond/libraries/InitializableLib.sol";
import {ChainRegistryTestBase} from "@lattice-test/base/ChainRegistryTestBase.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ChainRegistry} from "@lattice/crosschain/ChainRegistry.sol";
import {ChainRegistryInit} from "@lattice/crosschain/ChainRegistryInit.sol";
import {ERC7786OpenBridge} from "@lattice/crosschain/ERC7786OpenBridge.sol";
import {ERC7786OpenBridgeInit} from "@lattice/crosschain/ERC7786OpenBridgeInit.sol";
import {IChainRegistry} from "@lattice/interfaces/crosschain/IChainRegistry.sol";
import {IERC7786OpenBridge} from "@lattice/interfaces/crosschain/IERC7786OpenBridge.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/IERC7786.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Unit tests for the chain-registry facet on a REAL diamond (production {DeployChainRegistry} recipe).
contract ChainRegistryTest is ChainRegistryTestBase {
    ChainRegistry registry;
    address diamond;

    address admin = address(0x1);
    address user = address(0x2);

    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    // Base mainnet: chainId 8453 = 0x2105 — the hand-derived canonical minimal big-endian reference.
    uint256 constant BASE_CHAIN_ID = 8453;
    bytes constant BASE_REFERENCE = hex"2105";
    bytes2 constant EVM_CHAIN_TYPE = 0x0000;

    function setUp() public {
        diamond = _deployChainRegistry(admin);
        registry = ChainRegistry(diamond);
    }

    function _registerBase() internal returns (bytes32 chainKey) {
        chainKey = registry.chainKeyEvm(BASE_CHAIN_ID);
        vm.prank(admin);
        registry.registerChain(EVM_CHAIN_TYPE, BASE_REFERENCE, BASE_CHAIN_ID);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                CHAIN KEYS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ChainKeyEvmMatchesChainKeyOf() public view {
        // chainKeyEvm must build the reference EXACTLY the way InteroperableAddress.formatEvmV1 encodes it.
        (, bytes memory parsedReference,) =
            InteroperableAddress.parseV1(InteroperableAddress.formatEvmV1(BASE_CHAIN_ID));
        assertEq(parsedReference, BASE_REFERENCE, "formatEvmV1 reference != hand-derived 0x2105");

        assertEq(registry.chainKeyEvm(BASE_CHAIN_ID), registry.chainKeyOf(EVM_CHAIN_TYPE, BASE_REFERENCE));
        assertEq(registry.chainKeyEvm(BASE_CHAIN_ID), keccak256(abi.encodePacked(EVM_CHAIN_TYPE, BASE_REFERENCE)));
    }

    function test_ChainKeyEvmMinimalBigEndianNoLeadingZeros() public view {
        // chainId 10 (OP) encodes as the single byte 0x0a, never 0x000a.
        assertEq(registry.chainKeyEvm(10), registry.chainKeyOf(EVM_CHAIN_TYPE, hex"0a"));
        assertTrue(registry.chainKeyEvm(10) != registry.chainKeyOf(EVM_CHAIN_TYPE, hex"000a"));
    }

    /// @notice Key equality for a WIDE chainId and one with an INTERIOR zero byte, proven against BOTH a
    ///         hand-derived keccak and the exact send-time derivation (parse a full formatEvmV1 recipient —
    ///         the same path OpenBridge walks before its coverage gate).
    function test_ChainKeyEvmWideAndInteriorZeroByte() public view {
        uint256[2] memory ids = [uint256(34_268_394_551_451), uint256(0xaa00bb)];
        bytes[2] memory refs = [bytes(hex"1f2abb7bf89b"), bytes(hex"aa00bb")];
        for (uint256 i; i < 2; ++i) {
            // hand-derived expectation
            assertEq(
                registry.chainKeyEvm(ids[i]),
                keccak256(abi.encodePacked(EVM_CHAIN_TYPE, refs[i])),
                "hand-derived key mismatch"
            );
            // send-time derivation: parse a FULL recipient exactly like OpenBridge does before its gate
            (, bytes memory sendTimeRef,) =
                InteroperableAddress.parseV1(InteroperableAddress.formatEvmV1(ids[i], address(0xCAFE)));
            assertEq(
                registry.chainKeyEvm(ids[i]),
                registry.chainKeyOf(EVM_CHAIN_TYPE, sendTimeRef),
                "send-time-derived key mismatch"
            );
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              REGISTER CHAIN
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterChain() public {
        bytes32 chainKey = registry.chainKeyEvm(BASE_CHAIN_ID);
        assertFalse(registry.isRegistered(chainKey));

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IChainRegistry.ChainRegistered(chainKey, EVM_CHAIN_TYPE, BASE_REFERENCE, BASE_CHAIN_ID);
        registry.registerChain(EVM_CHAIN_TYPE, BASE_REFERENCE, BASE_CHAIN_ID);

        assertTrue(registry.isRegistered(chainKey));
        (bytes2 chainType, bytes memory chainReference, uint256 evmChainId) = registry.chainInfoOf(chainKey);
        assertEq(chainType, EVM_CHAIN_TYPE);
        assertEq(chainReference, BASE_REFERENCE);
        assertEq(evmChainId, BASE_CHAIN_ID);
    }

    function test_RegisterChainNonEvm() public {
        // A Starknet-style non-EVM identity: arbitrary chainType + UTF-8 reference, evmChainId 0.
        bytes2 starknet = 0x0003;
        bytes memory snReference = bytes("SN_MAIN");
        bytes32 chainKey = registry.chainKeyOf(starknet, snReference);

        vm.prank(admin);
        registry.registerChain(starknet, snReference, 0);

        assertTrue(registry.isRegistered(chainKey));
        (bytes2 chainType, bytes memory chainReference, uint256 evmChainId) = registry.chainInfoOf(chainKey);
        assertEq(chainType, starknet);
        assertEq(chainReference, snReference);
        assertEq(evmChainId, 0);
    }

    function test_RegisterChainTwiceReverts() public {
        bytes32 chainKey = _registerBase();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainRegistry.ChainRegistryAlreadyRegistered.selector, chainKey));
        registry.registerChain(EVM_CHAIN_TYPE, BASE_REFERENCE, BASE_CHAIN_ID);
    }

    function test_RegisterChainEmptyReferenceReverts() public {
        vm.prank(admin);
        vm.expectRevert(IChainRegistry.ChainRegistryEmptyChainReference.selector);
        registry.registerChain(EVM_CHAIN_TYPE, hex"", 0);
    }

    /// @notice FAIL-CLOSED eip-155 canonicality (review finding): a non-minimal reference or an inconsistent /
    ///         zero evmChainId would mint a chainKey the send-time derivation can never match.
    function test_RegisterChainRejectsNonCanonicalEvmReference() public {
        vm.startPrank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(IChainRegistry.ChainRegistryNonCanonicalEvmReference.selector, hex"000a", 10)
        );
        registry.registerChain(EVM_CHAIN_TYPE, hex"000a", 10); // leading zero
        vm.expectRevert(
            abi.encodeWithSelector(IChainRegistry.ChainRegistryNonCanonicalEvmReference.selector, hex"0a", 11)
        );
        registry.registerChain(EVM_CHAIN_TYPE, hex"0a", 11); // reference != evmChainId
        vm.expectRevert(
            abi.encodeWithSelector(IChainRegistry.ChainRegistryNonCanonicalEvmReference.selector, hex"0a", 0)
        );
        registry.registerChain(EVM_CHAIN_TYPE, hex"0a", 0); // zero evmChainId on EVM
        vm.stopPrank();
    }

    function test_RegisterChainRejectsEvmChainIdOnNonEvmChain() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainRegistry.ChainRegistryEvmChainIdOnNonEvmChain.selector, 1));
        registry.registerChain(bytes2(0x0003), bytes(hex"534e5f4d41494e"), 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                NATIVE IDS
    //////////////////////////////////////////////////////////////////////////*//

    function _baseNativeIds() internal pure returns (IChainRegistry.NativeIds memory) {
        return IChainRegistry.NativeIds({
            ccipSelector: 15971525489660198786, lzEid: 30184, wormholeId: 30, cctpDomain: 6, axelarName: "base"
        });
    }

    function test_SetNativeIds() public {
        bytes32 chainKey = _registerBase();
        IChainRegistry.NativeIds memory ids = _baseNativeIds();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IChainRegistry.SetNativeIds(chainKey, ids);
        registry.setNativeIds(chainKey, ids);

        IChainRegistry.NativeIds memory got = registry.nativeIdsOf(chainKey);
        assertEq(got.ccipSelector, ids.ccipSelector);
        assertEq(got.lzEid, ids.lzEid);
        assertEq(got.wormholeId, ids.wormholeId);
        assertEq(got.cctpDomain, ids.cctpDomain);
        assertEq(got.axelarName, ids.axelarName);
    }

    function test_SetNativeIdsUnregisteredReverts() public {
        bytes32 chainKey = registry.chainKeyEvm(BASE_CHAIN_ID);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainRegistry.ChainRegistryNotRegistered.selector, chainKey));
        registry.setNativeIds(chainKey, _baseNativeIds());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 COVERAGE
    //////////////////////////////////////////////////////////////////////////*//

    address gwDirect = address(0xD1);
    address gwHub = address(0xB2);

    function test_CoverageMathAndHubRoutedExclusion() public {
        bytes32 chainKey = _registerBase();

        vm.startPrank(admin);
        vm.expectEmit(true, true, false, true);
        emit IChainRegistry.SetGatewayCoverage(chainKey, gwDirect, true, false);
        registry.setGatewayCoverage(chainKey, gwDirect, true, false);
        registry.setGatewayCoverage(chainKey, gwHub, true, true); // hub-routed: never DIRECT
        vm.stopPrank();

        assertEq(registry.coverageOf(chainKey), 2, "total counts hub-routed");
        assertEq(registry.directCoverageOf(chainKey), 1, "direct excludes hub-routed");

        address[] memory gateways = registry.gatewaysOf(chainKey);
        assertEq(gateways.length, 2);
        assertEq(gateways[0], gwDirect);
        assertEq(gateways[1], gwHub);
    }

    function test_CoverageRemoval() public {
        bytes32 chainKey = _registerBase();
        vm.startPrank(admin);
        registry.setGatewayCoverage(chainKey, gwDirect, true, false);
        registry.setGatewayCoverage(chainKey, gwHub, true, true);
        registry.setGatewayCoverage(chainKey, gwDirect, false, false);
        vm.stopPrank();

        assertEq(registry.coverageOf(chainKey), 1);
        assertEq(registry.directCoverageOf(chainKey), 0, "only the hub-routed gateway remains");
        assertEq(registry.gatewaysOf(chainKey).length, 1);
    }

    function test_CoverageReRecordFlipsHubRoutedFlag() public {
        bytes32 chainKey = _registerBase();
        vm.startPrank(admin);
        registry.setGatewayCoverage(chainKey, gwDirect, true, false);
        assertEq(registry.directCoverageOf(chainKey), 1);
        registry.setGatewayCoverage(chainKey, gwDirect, true, true); // re-record as hub-routed
        vm.stopPrank();

        assertEq(registry.coverageOf(chainKey), 1, "re-record does not duplicate");
        assertEq(registry.directCoverageOf(chainKey), 0, "flag flip demotes to hub-routed");
    }

    function test_SetGatewayCoverageZeroGatewayReverts() public {
        bytes32 chainKey = _registerBase();
        vm.prank(admin);
        vm.expectRevert(IChainRegistry.ChainRegistryZeroGateway.selector);
        registry.setGatewayCoverage(chainKey, address(0), true, false);
    }

    function test_SetGatewayCoverageUnregisteredReverts() public {
        bytes32 chainKey = registry.chainKeyEvm(BASE_CHAIN_ID);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainRegistry.ChainRegistryNotRegistered.selector, chainKey));
        registry.setGatewayCoverage(chainKey, gwDirect, true, false);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         ADD-EVM-CHAIN (SECTIONS OFF)
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev An all-sections-disabled config — the registry-only slice of the fan-out (the full fan-out with
    ///      every adapter facet cut is proven in `test/integration/ChainFanOutTest.t.sol`).
    function _disabledConfig(uint256 chainId) internal pure returns (IChainRegistry.AddEvmChainConfig memory cfg) {
        cfg.chainId = chainId;
        cfg.coverage.gateways = new address[](0);
        cfg.coverage.hubRouted = new bool[](0);
    }

    function test_AddEvmChainRegistersAndRecordsCoverage() public {
        IChainRegistry.AddEvmChainConfig memory cfg = _disabledConfig(BASE_CHAIN_ID);
        cfg.coverage.gateways = new address[](2);
        cfg.coverage.hubRouted = new bool[](2);
        cfg.coverage.gateways[0] = gwDirect;
        cfg.coverage.gateways[1] = gwHub;
        cfg.coverage.hubRouted[1] = true;

        bytes32 chainKey = registry.chainKeyEvm(BASE_CHAIN_ID);
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit IChainRegistry.ChainAdded(chainKey, BASE_CHAIN_ID);
        registry.addEvmChain(cfg);

        assertTrue(registry.isRegistered(chainKey));
        (, bytes memory chainReference, uint256 evmChainId) = registry.chainInfoOf(chainKey);
        assertEq(chainReference, BASE_REFERENCE, "canonical minimal big-endian reference");
        assertEq(evmChainId, BASE_CHAIN_ID);
        assertEq(registry.coverageOf(chainKey), 2);
        assertEq(registry.directCoverageOf(chainKey), 1);
        // disabled sections leave every native id unset
        IChainRegistry.NativeIds memory ids = registry.nativeIdsOf(chainKey);
        assertEq(ids.ccipSelector, 0);
        assertEq(ids.lzEid, 0);
        assertEq(ids.wormholeId, 0);
        assertEq(ids.cctpDomain, 0);
        assertEq(ids.axelarName, "");
    }

    function test_AddEvmChainAlreadyRegisteredReverts() public {
        bytes32 chainKey = _registerBase();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainRegistry.ChainRegistryAlreadyRegistered.selector, chainKey));
        registry.addEvmChain(_disabledConfig(BASE_CHAIN_ID));
    }

    function test_AddEvmChainCoverageLengthMismatchReverts() public {
        IChainRegistry.AddEvmChainConfig memory cfg = _disabledConfig(BASE_CHAIN_ID);
        cfg.coverage.gateways = new address[](2);
        cfg.coverage.hubRouted = new bool[](1);
        cfg.coverage.gateways[0] = gwDirect;
        cfg.coverage.gateways[1] = gwHub;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainRegistry.ChainRegistryCoverageLengthMismatch.selector, 2, 1));
        registry.addEvmChain(cfg);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             ACCESS CONTROL
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterChainNonAdminReverts() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        registry.registerChain(EVM_CHAIN_TYPE, BASE_REFERENCE, BASE_CHAIN_ID);
    }

    function test_SetNativeIdsNonAdminReverts() public {
        bytes32 chainKey = _registerBase();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        registry.setNativeIds(chainKey, _baseNativeIds());
    }

    function test_SetGatewayCoverageNonAdminReverts() public {
        bytes32 chainKey = _registerBase();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        registry.setGatewayCoverage(chainKey, gwDirect, true, false);
    }

    function test_AddEvmChainNonAdminReverts() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        registry.addEvmChain(_disabledConfig(BASE_CHAIN_ID));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 / INIT
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Recomputes the interface-id keccak at runtime through the ERC165 facet's read path — catches a
    ///      wrong precomputed `ERC165_MAP_ICHAINREGISTRY_SLOT` constant.
    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IChainRegistry).interfaceId));
    }

    function test_InitOutsideInitializingWindowReverts() public {
        ChainRegistryInit init = new ChainRegistryInit();
        vm.expectRevert(NotInitializing.selector);
        init.init(admin);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                        OPENBRIDGE COVERAGE GATE
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal ERC-7786 source gateway fixture for the OpenBridge fan-out (mirrors the OpenBridge tests).
contract CoverageGateMockGateway is IERC7786GatewaySource {
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

/// @notice The OpenBridge M-of-N coverage gate against a diamond hosting BOTH the OpenBridge and the chain
///         registry: `_minDirectCoverage == 0` (default) never touches the registry — existing OpenBridge
///         behavior is untouched (the unmodified `ERC7786OpenBridgeTest` suite passing is the primary
///         backwards-compat proof); a non-zero knob hard-refuses destinations whose DIRECT coverage is thin,
///         with hub-routed gateways never counting.
contract ChainRegistryOpenBridgeGateTest is Test, GetSelectors {
    ERC7786OpenBridge bridge;
    ChainRegistry registry;
    address diamond;

    CoverageGateMockGateway g1;
    CoverageGateMockGateway g2;

    address admin = address(0x1);
    address user = address(0x2);

    uint256 constant REMOTE_CHAIN = 10;
    bytes remoteBridge;
    bytes recipient;
    bytes32 chainKey;

    bytes4 constant UNAUTHORIZED_ACCOUNT = bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)"));

    function setUp() public {
        // ONE diamond hosting the OpenBridge AND the chain registry (both admin-seeded via MultiInit).
        FacetCut[] memory cuts = new FacetCut[](4);
        cuts[0] = FacetCut(address(new ERC165Facet()), FacetCutAction.Add, _getSelectors("ERC165Facet"));
        cuts[1] = FacetCut(address(new AccessControl()), FacetCutAction.Add, _getSelectors("AccessControl"));
        cuts[2] = FacetCut(address(new ERC7786OpenBridge()), FacetCutAction.Add, _getSelectors("ERC7786OpenBridge"));
        cuts[3] = FacetCut(address(new ChainRegistry()), FacetCutAction.Add, _getSelectors("ChainRegistry"));

        address[] memory inits = new address[](2);
        bytes[] memory initDatas = new bytes[](2);
        inits[0] = address(new ERC7786OpenBridgeInit());
        initDatas[0] = abi.encodeCall(ERC7786OpenBridgeInit.init, (admin));
        inits[1] = address(new ChainRegistryInit());
        initDatas[1] = abi.encodeCall(ChainRegistryInit.init, (admin));

        Diamond d = new Diamond();
        d.initialize(cuts, address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, initDatas)));
        diamond = address(d);
        bridge = ERC7786OpenBridge(diamond);
        registry = ChainRegistry(diamond);

        g1 = new CoverageGateMockGateway();
        g2 = new CoverageGateMockGateway();
        remoteBridge = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0xB0B));
        recipient = InteroperableAddress.formatEvmV1(REMOTE_CHAIN, address(0xCAFE));
        chainKey = registry.chainKeyEvm(REMOTE_CHAIN);

        vm.startPrank(admin);
        bridge.addGateway(address(g1));
        bridge.addGateway(address(g2));
        bridge.setThreshold(2);
        bridge.registerRemoteBridge(remoteBridge);
        vm.stopPrank();
    }

    function test_DefaultZeroDisablesGateEvenWithoutRegistryRecord() public {
        assertEq(bridge.minDirectCoverage(), 0, "default off");
        // NO registry record exists for REMOTE_CHAIN — sends must keep working exactly as before.
        vm.prank(user);
        bridge.sendMessage(recipient, hex"deadbeef", new bytes[](0));
        assertEq(g1.sends(), 1);
        assertEq(g2.sends(), 1);
    }

    function test_GateRefusesUnregisteredDestination() public {
        vm.prank(admin);
        bridge.setMinDirectCoverage(2);
        // no registry record at all => 0 direct coverage
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC7786OpenBridge.OpenBridgeInsufficientCoverage.selector, 0, 2));
        bridge.sendMessage(recipient, hex"deadbeef", new bytes[](0));
    }

    function test_GateRefusesOneDirectPlusOneHubRouted() public {
        vm.startPrank(admin);
        bridge.setMinDirectCoverage(2);
        registry.registerChain(0x0000, hex"0a", REMOTE_CHAIN);
        registry.setGatewayCoverage(chainKey, address(g1), true, false); // 1 direct
        registry.setGatewayCoverage(chainKey, address(0x2E7A), true, true); // hub-routed NEVER counts
        vm.stopPrank();

        assertEq(registry.coverageOf(chainKey), 2);
        assertEq(registry.directCoverageOf(chainKey), 1);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IERC7786OpenBridge.OpenBridgeInsufficientCoverage.selector, 1, 2));
        bridge.sendMessage(recipient, hex"deadbeef", new bytes[](0));
    }

    function test_GatePassesWithTwoDirect() public {
        vm.startPrank(admin);
        bridge.setMinDirectCoverage(2);
        registry.registerChain(0x0000, hex"0a", REMOTE_CHAIN);
        registry.setGatewayCoverage(chainKey, address(g1), true, false);
        registry.setGatewayCoverage(chainKey, address(g2), true, false);
        vm.stopPrank();

        vm.prank(user);
        bridge.sendMessage(recipient, hex"deadbeef", new bytes[](0));
        assertEq(g1.sends(), 1);
        assertEq(g2.sends(), 1);
    }

    function test_SetMinDirectCoverageEmitsAndReads() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit IERC7786OpenBridge.MinDirectCoverageUpdated(3);
        bridge.setMinDirectCoverage(3);
        assertEq(bridge.minDirectCoverage(), 3);
    }

    function test_SetMinDirectCoverageNonAdminReverts() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(UNAUTHORIZED_ACCOUNT, user, bytes32(0)));
        bridge.setMinDirectCoverage(2);
    }
}
