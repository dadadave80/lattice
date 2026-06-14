// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedDiamondCut} from "@lattice/governance/GovernedDiamondCut.sol";
import {
    GOVERNED_DIAMOND_CUT_STORAGE_SLOT,
    GovernedDiamondCutLib,
    UPGRADE_EXECUTOR_ROLE
} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IEmergencyStop} from "@lattice/interfaces/IEmergencyStop.sol";
import {IFrozenSelectors} from "@lattice/interfaces/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/IGovernedDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/IUpgradeRegistry.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice A minimal self-contained Diamond used to exercise the governed cut wrapper.
/// @dev Stacks GovernedDiamondCut + AccessControl + EmergencyStop facet logic and registers
///      UPGRADE_EXECUTOR_ROLE to address(this) at init (matching production wiring). Exposes a
///      view to read the facet bound to a selector so tests can assert a cut took effect.
contract MockGovernedDiamond is GovernedDiamondCut, AccessControl, EmergencyStop {
    function initialize(address _admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        EmergencyStopLib.__EmergencyStop_init();
        DiamondLib.registerInterface(); // sets ERC-165 flag for IDiamondCut (0x1f931c1c) + loupe
        GovernedDiamondCutLib.__GovernedDiamondCut_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _id) external view returns (bool) {
        return ERC165Lib.supportsInterface(_id);
    }

    function facetOf(bytes4 _selector) external view returns (address) {
        return DiamondLib.diamondStorage().selectorToFacetAndPosition[_selector].facetAddress;
    }

    /// @dev Real Diamond fallback: routes any selector Added via a cut to its facet by delegatecall,
    ///      so an applied cut (e.g. `ping`) is callable through the proxy (matches diamond-lib's
    ///      `Diamond.fallback`). Without this the freshly-bound selector would have no router.
    fallback() external payable {
        address implementation = DiamondLib.selectorToFacet(msg.sig);
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

/// @notice A trivial facet whose selector we will Add via a governed cut, to prove the cut applied.
contract DummyFacet {
    function ping() external pure returns (uint256) {
        return 7;
    }
}

/// @title GovernedDiamondCutTester
/// @notice Unit tests for the GovernedDiamondCut module.
contract GovernedDiamondCutTester is Test {
    MockGovernedDiamond internal diamond;
    DummyFacet internal dummy;
    address internal admin = address(0xA1);
    address internal stranger = address(0xBEEF);

    function setUp() public {
        diamond = new MockGovernedDiamond();
        diamond.initialize(admin);
        dummy = new DummyFacet();
    }

    function _addPingCut() internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.ping.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
    }

    /// @notice The interface exposes exactly one function (`diamondCut`), so its interfaceId
    ///         equals that function's selector — which is the canonical EIP-2535 cut selector
    ///         0x1f931c1c, identical to IDiamondCut. This is intentional: GovernedDiamondCut
    ///         replaces the stock DiamondCutFacet at the same selector.
    function test_InterfaceIdIsCutSelector() public pure {
        assertEq(
            type(IGovernedDiamondCut).interfaceId,
            bytes4(0x1f931c1c),
            "GovernedDiamondCut iface id must be the cut selector"
        );
    }

    /// @notice The facet's `diamondCut` selector is the canonical EIP-2535 cut selector, so it
    ///         occupies the same selector slot as diamond-lib's stock `DiamondCutFacet`.
    function test_FacetSelectorIsCutSelector() public pure {
        assertEq(GovernedDiamondCut.diamondCut.selector, bytes4(0x1f931c1c), "facet selector mismatch");
    }

    function _erc7201Slot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_StorageSlotDerivation() public pure {
        assertEq(
            GOVERNED_DIAMOND_CUT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.GovernedDiamondCut"),
            "GovernedDiamondCut storage slot mismatch"
        );
    }

    function test_UpgradeExecutorRoleConstant() public pure {
        assertEq(UPGRADE_EXECUTOR_ROLE, keccak256("UPGRADE_EXECUTOR_ROLE"), "role constant mismatch");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            GUARDED CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Role is granted to the diamond itself, never to an EOA.
    function test_RoleHeldByDiamondNotAdmin() public view {
        assertTrue(diamond.hasRole(UPGRADE_EXECUTOR_ROLE, address(diamond)));
        assertFalse(diamond.hasRole(UPGRADE_EXECUTOR_ROLE, admin));
    }

    /// @notice A stranger (no role) calling diamondCut reverts with the unauthorized role error.
    function test_UnauthorizedCallerReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, UPGRADE_EXECUTOR_ROLE
            )
        );
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice Even the admin (DEFAULT_ADMIN_ROLE) cannot cut — the role lives only on address(this).
    function test_AdminCannotCut() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, UPGRADE_EXECUTOR_ROLE
            )
        );
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice The authorized caller (the diamond itself) applies a real cut: ping selector is bound.
    function test_AuthorizedSelfCallAppliesCut() public {
        FacetCut[] memory cuts = _addPingCut();
        // Impersonate the diamond calling its own diamondCut (this is exactly what the timelock relay
        // achieves in production: msg.sender == address(this)).
        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy), "ping selector not bound");
        // ping() is now callable through the diamond fallback.
        (bool ok, bytes memory ret) = address(diamond).call(abi.encodeWithSelector(DummyFacet.ping.selector));
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), 7);
    }

    /// @notice Emergency stop is the OUTER guard: when stopped, even the authorized caller is blocked,
    ///         and the revert is EmergencyStopActive (not the role error) — proving guard ordering.
    function test_EmergencyStopBlocksAuthorizedCut() public {
        // Make admin a guardian, then trip the stop.
        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("freeze upgrades");

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice After resume, the authorized cut succeeds again.
    function test_CutSucceedsAfterResume() public {
        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("freeze");
        vm.prank(admin);
        diamond.emergencyResume();

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy));
    }

    /// @notice The UpgradeExecuted event fires on a successful cut.
    function test_UpgradeExecutedEventEmitted() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IGovernedDiamondCut.UpgradeExecuted(address(diamond), 1, address(0));
        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(0), "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          UPGRADE REGISTRY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Adds a `replace` cut that re-points the ping selector to a second facet, so we can
    ///         apply a *second* distinct cut (Add then Replace) and assert monotonic versioning.
    function _replacePingCut(address _facet) internal pure returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.ping.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: _facet, action: FacetCutAction.Replace, functionSelectors: sels});
    }

    /// @notice Before any cut, the registry is empty: cutCount() == 0 and version 1 is unwritten.
    function test_RegistryEmptyBeforeAnyCut() public view {
        assertEq(diamond.cutCount(), 0, "cutCount must start at 0");
        IUpgradeRegistry.CutRecord memory rec = diamond.getCutRecord(1);
        assertEq(rec.cutHash, bytes32(0));
        assertEq(rec.executor, address(0));
        assertEq(rec.executedAt, 0);
        assertEq(rec.facetCutCount, 0);
        assertEq(rec.init, address(0));
    }

    /// @notice An authorized cut records version 1 with the exact cutHash / executor / timestamp /
    ///         facetCutCount / init. cutHash == keccak256(abi.encode(cuts, init, calldata)).
    function test_RegistryRecordsVersionOne() public {
        vm.warp(123_456);
        FacetCut[] memory cuts = _addPingCut();
        bytes memory cd = bytes("");
        bytes32 expectedHash = keccak256(abi.encode(cuts, address(0), cd));

        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(0), cd);

        assertEq(diamond.cutCount(), 1, "cutCount must be 1 after first cut");
        IUpgradeRegistry.CutRecord memory rec = diamond.getCutRecord(1);
        assertEq(rec.cutHash, expectedHash, "cutHash mismatch");
        assertEq(rec.executor, address(diamond), "executor must be the caller");
        assertEq(rec.executedAt, uint48(123_456), "executedAt must be block.timestamp");
        assertEq(rec.facetCutCount, uint32(1), "facetCutCount must equal cuts.length");
        assertEq(rec.init, address(0), "init must be recorded");
    }

    /// @notice The init address (non-zero) is captured in the record.
    function test_RegistryRecordsInitAddress() public {
        // Init that adds ping AND delegatecalls a self-call doing nothing harmful: use the diamond
        // itself as init with empty calldata is rejected by diamond-lib (non-empty calldata required
        // for non-zero init), so use a no-op init contract.
        NoopInit noop = new NoopInit();
        FacetCut[] memory cuts = _addPingCut();
        bytes memory cd = abi.encodeWithSelector(NoopInit.run.selector);

        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(noop), cd);

        IUpgradeRegistry.CutRecord memory rec = diamond.getCutRecord(1);
        assertEq(rec.init, address(noop), "init address must be recorded");
        assertEq(rec.cutHash, keccak256(abi.encode(cuts, address(noop), cd)), "cutHash must bind init+calldata");
    }

    /// @notice A second cut records version 2 (monotonic), distinct from version 1, and both records
    ///         persist independently.
    function test_RegistryMonotonicSecondVersion() public {
        FacetCut[] memory addCut = _addPingCut();
        vm.prank(address(diamond));
        diamond.diamondCut(addCut, address(0), "");

        // Second cut: replace ping with a fresh facet.
        DummyFacet dummy2 = new DummyFacet();
        FacetCut[] memory replaceCut = _replacePingCut(address(dummy2));
        bytes32 expectedHash2 = keccak256(abi.encode(replaceCut, address(0), bytes("")));
        vm.prank(address(diamond));
        diamond.diamondCut(replaceCut, address(0), "");

        assertEq(diamond.cutCount(), 2, "cutCount must be 2 after second cut");

        IUpgradeRegistry.CutRecord memory rec1 = diamond.getCutRecord(1);
        IUpgradeRegistry.CutRecord memory rec2 = diamond.getCutRecord(2);
        assertEq(rec1.cutHash, keccak256(abi.encode(addCut, address(0), bytes(""))), "v1 hash preserved");
        assertEq(rec2.cutHash, expectedHash2, "v2 hash mismatch");
        assertTrue(rec1.cutHash != rec2.cutHash, "the two versions must differ");
        assertEq(rec2.facetCutCount, uint32(1));
    }

    /// @notice The CutRecorded event fires with (version, cutHash, executor) on a successful cut.
    function test_RegistryCutRecordedEventEmitted() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 expectedHash = keccak256(abi.encode(cuts, address(0), bytes("")));
        // version indexed, executor indexed; cutHash is in data.
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IUpgradeRegistry.CutRecorded(1, expectedHash, address(diamond));
        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice A blocked cut (emergency-stopped) records NOTHING — no phantom version, cutCount stays 0.
    function test_RegistryBlockedCutRecordsNothing() public {
        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("freeze");

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        diamond.diamondCut(cuts, address(0), "");

        assertEq(diamond.cutCount(), 0, "blocked cut must not bump the version counter");
        IUpgradeRegistry.CutRecord memory rec = diamond.getCutRecord(1);
        assertEq(rec.executor, address(0), "blocked cut must leave version 1 unwritten");
        assertEq(rec.cutHash, bytes32(0));
    }

    /// @notice An unauthorized cut (no role) records NOTHING — no phantom version.
    function test_RegistryUnauthorizedCutRecordsNothing() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, UPGRADE_EXECUTOR_ROLE
            )
        );
        diamond.diamondCut(cuts, address(0), "");

        assertEq(diamond.cutCount(), 0, "unauthorized cut must not record a version");
        assertEq(diamond.getCutRecord(1).executor, address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          FROZEN SELECTORS
    //////////////////////////////////////////////////////////////////////////*//

    bytes4 internal constant PING_SEL = DummyFacet.ping.selector;
    bytes4 internal constant OTHER_SEL = bytes4(0xDEADBEEF);

    /// @dev A remove cut: facetAddress MUST be address(0) per EIP-2535 remove semantics.
    function _removeCut(bytes4 _sel) internal pure returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(0), action: FacetCutAction.Remove, functionSelectors: sels});
    }

    /// @dev A replace cut targeting `_sel` (re-points it at `dummy`).
    function _replaceCut(bytes4 _sel) internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Replace, functionSelectors: sels});
    }

    function _freeze(bytes4 _sel) internal {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        vm.prank(address(diamond));
        diamond.freezeSelectors(sels);
    }

    /// @notice Freezing reflects in isSelectorFrozen / frozenSelectors and is idempotent.
    function test_FreezeReflectsInViews() public {
        assertFalse(diamond.isSelectorFrozen(PING_SEL), "not frozen initially");
        assertEq(diamond.frozenSelectors().length, 0, "set empty initially");

        _freeze(PING_SEL);

        assertTrue(diamond.isSelectorFrozen(PING_SEL), "must be frozen after freeze");
        bytes4[] memory frozen = diamond.frozenSelectors();
        assertEq(frozen.length, 1, "one frozen selector");
        assertEq(frozen[0], PING_SEL, "frozen selector recorded");

        // Re-freezing the same selector is an idempotent no-op (no duplicate entry).
        _freeze(PING_SEL);
        assertEq(diamond.frozenSelectors().length, 1, "no duplicate on re-freeze");
    }

    /// @notice freezeSelectors is governance-gated: a stranger without the role reverts.
    function test_FreezeSelectorsGovernanceGated() public {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = PING_SEL;
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, UPGRADE_EXECUTOR_ROLE
            )
        );
        diamond.freezeSelectors(sels);

        // Even the admin cannot freeze (role lives only on the diamond identity).
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, UPGRADE_EXECUTOR_ROLE
            )
        );
        diamond.freezeSelectors(sels);
    }

    /// @notice freezeSelectors emits SelectorsFrozen with the caller + argument array.
    function test_FreezeSelectorsEmitsEvent() public {
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = PING_SEL;
        sels[1] = OTHER_SEL;
        vm.expectEmit(true, false, false, true, address(diamond));
        emit IFrozenSelectors.SelectorsFrozen(address(diamond), sels);
        vm.prank(address(diamond));
        diamond.freezeSelectors(sels);
        assertTrue(diamond.isSelectorFrozen(PING_SEL));
        assertTrue(diamond.isSelectorFrozen(OTHER_SEL));
    }

    /// @notice A governed cut that REMOVES a frozen selector reverts FrozenSelectorProtected,
    ///         BEFORE diamond-lib runs (so the selector need not even be bound).
    function test_FrozenSelectorBlocksRemove() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, PING_SEL));
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice A governed cut that REPLACES a frozen selector reverts FrozenSelectorProtected.
    function test_FrozenSelectorBlocksReplace() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _replaceCut(PING_SEL);
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, PING_SEL));
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice The frozen guard fires even when the frozen selector is one entry in a multi-cut batch.
    function test_FrozenSelectorBlocksReplaceWithinBatch() public {
        _freeze(OTHER_SEL);
        // First cut Adds ping (fine), second cut Replaces the frozen OTHER_SEL (must revert).
        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = _addPingCut()[0];
        cuts[1] = _replaceCut(OTHER_SEL)[0];
        vm.prank(address(diamond));
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, OTHER_SEL));
        diamond.diamondCut(cuts, address(0), "");
        // The whole cut reverted: ping was NOT added.
        assertEq(diamond.facetOf(PING_SEL), address(0), "reverted cut applies nothing");
    }

    /// @notice ADD of a frozen selector is unaffected: only Replace/Remove are protected.
    function test_FrozenSelectorDoesNotBlockAdd() public {
        _freeze(PING_SEL);
        // Adding the (frozen) ping selector still works — Add is not a protected action.
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.facetOf(PING_SEL), address(dummy), "Add of a frozen selector must succeed");
    }

    /// @notice An Add of an UNRELATED selector still works while another selector is frozen.
    function test_UnrelatedAddWorksWhileFrozen() public {
        _freeze(OTHER_SEL);
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(diamond));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.facetOf(PING_SEL), address(dummy), "unrelated Add must succeed while frozen");
    }

    /// @notice A non-frozen Remove proceeds (and reaches diamond-lib): removing a bound, non-frozen
    ///         selector succeeds and unbinds it.
    function test_NonFrozenRemoveWorks() public {
        // Bind ping first.
        FacetCut[] memory addCut = _addPingCut();
        vm.prank(address(diamond));
        diamond.diamondCut(addCut, address(0), "");
        assertEq(diamond.facetOf(PING_SEL), address(dummy), "ping bound");

        // Freeze an unrelated selector, then remove the (non-frozen) ping — must succeed.
        _freeze(OTHER_SEL);
        FacetCut[] memory removeCut = _removeCut(PING_SEL);
        vm.prank(address(diamond));
        diamond.diamondCut(removeCut, address(0), "");
        assertEq(diamond.facetOf(PING_SEL), address(0), "non-frozen remove must unbind selector");
    }

    /// @notice previewCut returns ok=false + the offending selector for a frozen-touching Replace.
    function test_PreviewCutDetectsFrozenReplace() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _replaceCut(PING_SEL);
        (bool ok, bytes4 offending) = diamond.previewCut(cuts);
        assertFalse(ok, "preview must flag a frozen Replace");
        assertEq(offending, PING_SEL, "preview must return the offending selector");
    }

    /// @notice previewCut returns ok=false + the offending selector for a frozen-touching Remove.
    function test_PreviewCutDetectsFrozenRemove() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        (bool ok, bytes4 offending) = diamond.previewCut(cuts);
        assertFalse(ok);
        assertEq(offending, PING_SEL);
    }

    /// @notice previewCut returns ok=true (zero offending) for a clean cut (Add, or non-frozen).
    function test_PreviewCutCleanReturnsOk() public {
        _freeze(OTHER_SEL);
        // An Add of the frozen selector is still ok (Add unaffected).
        (bool okAdd, bytes4 offAdd) = diamond.previewCut(_addPingCut());
        assertTrue(okAdd, "Add must preview ok");
        assertEq(offAdd, bytes4(0), "no offending selector for ok preview");

        // A Remove of a NON-frozen selector is ok.
        (bool okRm, bytes4 offRm) = diamond.previewCut(_removeCut(PING_SEL));
        assertTrue(okRm, "non-frozen Remove must preview ok");
        assertEq(offRm, bytes4(0));
    }

    /// @notice previewCut is a pure read: it does NOT mutate the frozen set or apply the cut.
    function test_PreviewCutDoesNotMutate() public {
        _freeze(PING_SEL);
        diamond.previewCut(_replaceCut(PING_SEL));
        // State unchanged: still exactly one frozen selector, ping still unbound.
        assertEq(diamond.frozenSelectors().length, 1, "preview must not mutate frozen set");
        assertEq(diamond.facetOf(PING_SEL), address(0), "preview must not apply the cut");
    }

    /// @notice verifyInterfaceRegistered is true for a registered interface and false otherwise.
    function test_VerifyInterfaceRegistered() public view {
        // IDiamondCut (0x1f931c1c) is registered by DiamondLib.registerInterface() in init.
        assertTrue(diamond.verifyInterfaceRegistered(bytes4(0x1f931c1c)), "IDiamondCut must be advertised");
        // IDiamondLoupe (0x48e2b093) is also registered.
        assertTrue(diamond.verifyInterfaceRegistered(bytes4(0x48e2b093)), "IDiamondLoupe must be advertised");
        // An arbitrary unregistered id is not advertised.
        assertFalse(diamond.verifyInterfaceRegistered(bytes4(0x12345678)), "unknown interface must be false");
        // Mirrors supportsInterface exactly.
        assertEq(
            diamond.verifyInterfaceRegistered(bytes4(0x1f931c1c)),
            diamond.supportsInterface(bytes4(0x1f931c1c)),
            "must mirror supportsInterface"
        );
    }
}

/// @notice A no-op init target for exercising the recorded `init` address on a cut.
contract NoopInit {
    function run() external pure {}
}
