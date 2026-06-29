// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {SafeDiamondCut} from "@lattice/governance/SafeDiamondCut.sol";
import {SAFE_DIAMOND_CUT_STORAGE_SLOT, SafeDiamondCutLib} from "@lattice/governance/libraries/SafeDiamondCutLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {ISafeAuthority} from "@lattice/interfaces/governance/ISafeAuthority.sol";
import {ISafeDiamondCut} from "@lattice/interfaces/governance/ISafeDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {EMERGENCY_GUARDIAN_ROLE, EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Tiny mock standing in for a Gnosis Safe: exposes the read-only surface the cut facet uses to
///         validate the pinned authority. Tests act AS the Safe via `vm.prank(address(safe))`, exactly
///         as a real Safe does when it dispatches `execTransaction` with `operation = Call`.
contract MockSafe {
    uint256 internal _threshold;
    address[] internal _owners;
    uint256 internal _nonce;

    constructor(uint256 threshold_, address[] memory owners_) {
        _threshold = threshold_;
        _owners = owners_;
    }

    function setThreshold(uint256 t) external {
        _threshold = t;
    }

    function getThreshold() external view returns (uint256) {
        return _threshold;
    }

    function getOwners() external view returns (address[] memory) {
        return _owners;
    }

    function isOwner(address a) external view returns (bool) {
        for (uint256 i; i < _owners.length; ++i) {
            if (_owners[i] == a) return true;
        }
        return false;
    }

    function nonce() external view returns (uint256) {
        return _nonce;
    }
}

/// @notice A minimal self-contained Diamond used to exercise the Safe-gated cut wrapper.
contract MockSafeDiamond is SafeDiamondCut, AccessControl, EmergencyStop {
    function initialize(address _admin, address _safe, uint256 _minThreshold) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        EmergencyStopLib.__EmergencyStop_init();
        DiamondLib.registerInterface(); // ERC-165 flag for IDiamondCut (0x1f931c1c) + loupe
        SafeDiamondCutLib.__SafeDiamondCut_init(_safe, _minThreshold);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 _id) external view returns (bool) {
        return ERC165Lib.supportsInterface(_id);
    }

    function facetOf(bytes4 _selector) external view returns (address) {
        return DiamondLib.diamondStorage().selectorToFacetAndPosition[_selector].facetAddress;
    }

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

/// @notice A trivial facet whose selector we Add via a Safe-gated cut, to prove the cut applied.
contract DummyFacet {
    function ping() external pure returns (uint256) {
        return 7;
    }
}

/// @notice A no-op init target for exercising the recorded `init` address on a cut.
contract NoopInit {
    function run() external pure {}
}

/// @title SafeDiamondCutTester
/// @notice Unit tests for the SafeDiamondCut module.
contract SafeDiamondCutTester is Test {
    MockSafeDiamond internal diamond;
    MockSafe internal safe;
    DummyFacet internal dummy;
    address internal admin = address(0xA1);
    address internal stranger = address(0xBEEF);
    uint256 internal constant MIN_THRESHOLD = 2;

    function setUp() public {
        address[] memory owners = new address[](3);
        owners[0] = address(0x1);
        owners[1] = address(0x2);
        owners[2] = address(0x3);
        safe = new MockSafe(MIN_THRESHOLD, owners);
        diamond = new MockSafeDiamond();
        diamond.initialize(admin, address(safe), MIN_THRESHOLD);
        dummy = new DummyFacet();
    }

    function _addPingCut() internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.ping.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SELECTOR / SLOT INVARIANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The facet's `diamondCut` selector is the canonical EIP-2535 cut selector, so it occupies
    ///         the same selector slot as diamond-lib's stock `DiamondCutFacet`.
    function test_FacetSelectorIsCutSelector() public pure {
        assertEq(SafeDiamondCut.diamondCut.selector, bytes4(0x1f931c1c), "facet selector mismatch");
    }

    function _erc7201Slot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_StorageSlotDerivation() public pure {
        assertEq(
            SAFE_DIAMOND_CUT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.SafeDiamondCut"),
            "SafeDiamondCut storage slot mismatch"
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitPinsSafe() public view {
        assertEq(diamond.safe(), address(safe), "safe must be pinned at init");
    }

    function test_InitRejectsZeroSafe() public {
        MockSafeDiamond d = new MockSafeDiamond();
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutZeroSafe.selector));
        d.initialize(admin, address(0), MIN_THRESHOLD);
    }

    function test_InitRejectsZeroThreshold() public {
        MockSafeDiamond d = new MockSafeDiamond();
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutZeroThreshold.selector));
        d.initialize(admin, address(safe), 0);
    }

    function test_InitRejectsThresholdTooLow() public {
        // Safe enforces threshold 2, but we demand a minimum of 3.
        MockSafeDiamond d = new MockSafeDiamond();
        vm.expectRevert(
            abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutThresholdTooLow.selector, uint256(2), uint256(3))
        );
        d.initialize(admin, address(safe), 3);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SAFE-GATED CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The pinned Safe applies a real cut: ping selector is bound and callable.
    function test_SafeAppliesCut() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy), "ping selector not bound");
        (bool ok, bytes memory ret) = address(diamond).call(abi.encodeWithSelector(DummyFacet.ping.selector));
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), 7);
    }

    /// @notice A non-Safe caller reverts with SafeDiamondCutUnauthorized(caller).
    function test_UnauthorizedCallerReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice Even the admin (DEFAULT_ADMIN_ROLE) cannot cut — only the pinned Safe can.
    function test_AdminCannotCut() public {
        assertTrue(diamond.hasRole(DEFAULT_ADMIN_ROLE, admin), "admin holds DEFAULT_ADMIN_ROLE");
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, admin));
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice Emergency stop is the OUTER guard: when stopped, even the Safe is blocked, and the revert
    ///         is EmergencyStopActive (not the unauthorized error) — proving guard ordering.
    function test_EmergencyStopBlocksCut() public {
        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("freeze upgrades");

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice After resume, the Safe-gated cut succeeds again.
    function test_CutSucceedsAfterResume() public {
        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("freeze");
        vm.prank(admin);
        diamond.emergencyResume();

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy));
    }

    /// @notice The UpgradeExecuted event fires on a successful cut with the Safe as executor.
    function test_UpgradeExecutedEventEmitted() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.expectEmit(true, true, false, true, address(diamond));
        emit ISafeDiamondCut.UpgradeExecuted(address(safe), 1, address(0));
        vm.prank(address(safe));
        diamond.diamondCut(cuts, address(0), "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SAFE ROTATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Only the current Safe can rotate; rotation re-points the authority and emits SafeRotated.
    function test_SetSafeRotatesAuthority() public {
        address[] memory owners = new address[](2);
        owners[0] = address(0x4);
        owners[1] = address(0x5);
        MockSafe newSafe = new MockSafe(2, owners);

        vm.expectEmit(true, true, false, false, address(diamond));
        emit ISafeAuthority.SafeRotated(address(safe), address(newSafe));
        vm.prank(address(safe));
        diamond.setSafe(address(newSafe));

        assertEq(diamond.safe(), address(newSafe), "safe must be rotated");

        // The new Safe can now cut; the old Safe can no longer.
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, address(safe)));
        diamond.diamondCut(cuts, address(0), "");

        vm.prank(address(newSafe));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy), "new safe's cut must apply");
    }

    /// @notice setSafe is gated to the current Safe: a stranger (and the admin) cannot rotate.
    function test_SetSafeUnauthorizedReverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        diamond.setSafe(address(0xCAFE));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, admin));
        diamond.setSafe(address(0xCAFE));
    }

    /// @notice setSafe validates the new Safe: zero address rejected.
    function test_SetSafeRejectsZero() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutZeroSafe.selector));
        diamond.setSafe(address(0));
    }

    /// @notice setSafe validates the new Safe: a Safe reporting threshold 0 is rejected (must be >= 1).
    function test_SetSafeRejectsZeroThresholdSafe() public {
        address[] memory owners = new address[](1);
        owners[0] = address(0x9);
        MockSafe brokenSafe = new MockSafe(0, owners);
        vm.prank(address(safe));
        vm.expectRevert(
            abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutThresholdTooLow.selector, uint256(0), uint256(1))
        );
        diamond.setSafe(address(brokenSafe));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          UPGRADE REGISTRY
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegistryRecordsVersionOne() public {
        vm.warp(123_456);
        FacetCut[] memory cuts = _addPingCut();
        bytes memory cd = bytes("");
        bytes32 expectedHash = keccak256(abi.encode(cuts, address(0), cd));

        vm.prank(address(safe));
        diamond.diamondCut(cuts, address(0), cd);

        assertEq(diamond.cutCount(), 1, "cutCount must be 1 after first cut");
        IUpgradeRegistry.CutRecord memory rec = diamond.getCutRecord(1);
        assertEq(rec.cutHash, expectedHash, "cutHash mismatch");
        assertEq(rec.executor, address(safe), "executor must be the Safe");
        assertEq(rec.executedAt, uint48(123_456), "executedAt must be block.timestamp");
        assertEq(rec.facetCutCount, uint32(1), "facetCutCount must equal cuts.length");
        assertEq(rec.init, address(0), "init must be recorded");
    }

    function test_RegistryRecordsInitAddress() public {
        NoopInit noop = new NoopInit();
        FacetCut[] memory cuts = _addPingCut();
        bytes memory cd = abi.encodeWithSelector(NoopInit.run.selector);

        vm.prank(address(safe));
        diamond.diamondCut(cuts, address(noop), cd);

        IUpgradeRegistry.CutRecord memory rec = diamond.getCutRecord(1);
        assertEq(rec.init, address(noop), "init address must be recorded");
        assertEq(rec.cutHash, keccak256(abi.encode(cuts, address(noop), cd)), "cutHash must bind init+calldata");
    }

    function test_RegistryCutRecordedEventEmitted() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 expectedHash = keccak256(abi.encode(cuts, address(0), bytes("")));
        vm.expectEmit(true, true, false, true, address(diamond));
        emit IUpgradeRegistry.CutRecorded(1, expectedHash, address(safe));
        vm.prank(address(safe));
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice A blocked cut (emergency-stopped) records NOTHING — no phantom version.
    function test_RegistryBlockedCutRecordsNothing() public {
        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("freeze");

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        diamond.diamondCut(cuts, address(0), "");

        assertEq(diamond.cutCount(), 0, "blocked cut must not bump the version counter");
        assertEq(diamond.getCutRecord(1).executor, address(0), "blocked cut must leave version 1 unwritten");
    }

    /// @notice An unauthorized cut records NOTHING.
    function test_RegistryUnauthorizedCutRecordsNothing() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.cutCount(), 0, "unauthorized cut must not record a version");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          FROZEN SELECTORS
    //////////////////////////////////////////////////////////////////////////*//

    bytes4 internal constant PING_SEL = DummyFacet.ping.selector;
    bytes4 internal constant OTHER_SEL = bytes4(0xDEADBEEF);

    function _removeCut(bytes4 _sel) internal pure returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(0), action: FacetCutAction.Remove, functionSelectors: sels});
    }

    function _replaceCut(bytes4 _sel) internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Replace, functionSelectors: sels});
    }

    function _freeze(bytes4 _sel) internal {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        vm.prank(address(safe));
        diamond.freezeSelectors(sels);
    }

    function test_FreezeReflectsInViews() public {
        assertFalse(diamond.isSelectorFrozen(PING_SEL), "not frozen initially");
        _freeze(PING_SEL);
        assertTrue(diamond.isSelectorFrozen(PING_SEL), "must be frozen after freeze");
        bytes4[] memory frozen = diamond.frozenSelectors();
        assertEq(frozen.length, 1, "one frozen selector");
        assertEq(frozen[0], PING_SEL, "frozen selector recorded");
        _freeze(PING_SEL);
        assertEq(diamond.frozenSelectors().length, 1, "no duplicate on re-freeze");
    }

    /// @notice freezeSelectors is Safe-gated: a stranger and the admin both revert.
    function test_FreezeSelectorsSafeGated() public {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = PING_SEL;
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        diamond.freezeSelectors(sels);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, admin));
        diamond.freezeSelectors(sels);
    }

    function test_FreezeSelectorsEmitsEvent() public {
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = PING_SEL;
        sels[1] = OTHER_SEL;
        vm.expectEmit(true, false, false, true, address(diamond));
        emit IFrozenSelectors.SelectorsFrozen(address(safe), sels);
        vm.prank(address(safe));
        diamond.freezeSelectors(sels);
    }

    function test_FrozenSelectorBlocksRemove() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, PING_SEL));
        diamond.diamondCut(cuts, address(0), "");
    }

    function test_FrozenSelectorBlocksReplace() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _replaceCut(PING_SEL);
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, PING_SEL));
        diamond.diamondCut(cuts, address(0), "");
    }

    function test_FrozenSelectorDoesNotBlockAdd() public {
        _freeze(PING_SEL);
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        diamond.diamondCut(cuts, address(0), "");
        assertEq(diamond.facetOf(PING_SEL), address(dummy), "Add of a frozen selector must succeed");
    }

    function test_PreviewCutDetectsFrozenReplace() public {
        _freeze(PING_SEL);
        (bool ok, bytes4 offending) = diamond.previewCut(_replaceCut(PING_SEL));
        assertFalse(ok, "preview must flag a frozen Replace");
        assertEq(offending, PING_SEL, "preview must return the offending selector");
    }

    function test_PreviewCutCleanReturnsOk() public {
        _freeze(OTHER_SEL);
        (bool okAdd, bytes4 offAdd) = diamond.previewCut(_addPingCut());
        assertTrue(okAdd, "Add must preview ok");
        assertEq(offAdd, bytes4(0));
    }

    function test_VerifyInterfaceRegistered() public view {
        assertTrue(diamond.verifyInterfaceRegistered(bytes4(0x1f931c1c)), "IDiamondCut must be advertised");
        assertFalse(diamond.verifyInterfaceRegistered(bytes4(0x12345678)), "unknown interface must be false");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       EMERGENCY REMOVAL-ONLY CUT
    //////////////////////////////////////////////////////////////////////////*//

    address internal guardian = address(0x6044D1A11);

    function _makeGuardian(address _who) internal {
        vm.prank(admin);
        diamond.addGuardian(_who);
    }

    function _bindPing() internal {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        diamond.diamondCut(cuts, address(0), "");
    }

    function _addCut(bytes4 _sel) internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
    }

    function test_EmergencyRemove_ZeroDelayUnbindsLiveSelector() public {
        _bindPing();
        assertEq(diamond.facetOf(PING_SEL), address(dummy), "ping must be live before emergency removal");
        _makeGuardian(guardian);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(guardian);
        diamond.emergencyRemoveCut(cuts);
        assertEq(diamond.facetOf(PING_SEL), address(0), "ping must be unbound after emergency removal");
    }

    function test_EmergencyRemove_StrangerReverts() public {
        _bindPing();
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, EMERGENCY_GUARDIAN_ROLE
            )
        );
        diamond.emergencyRemoveCut(cuts);
    }

    /// @notice The Safe authority is NOT a guardian: it cannot fire the emergency removal — proving the
    ///         emergency path is a distinct, guardian-only authority, not the Safe authority.
    function test_EmergencyRemove_SafeWithoutGuardianReverts() public {
        _bindPing();
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        assertFalse(diamond.hasRole(EMERGENCY_GUARDIAN_ROLE, address(safe)), "safe is not a guardian");
        vm.prank(address(safe));
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(safe), EMERGENCY_GUARDIAN_ROLE
            )
        );
        diamond.emergencyRemoveCut(cuts);
    }

    function test_EmergencyRemove_RejectsAdd() public {
        _makeGuardian(guardian);
        FacetCut[] memory cuts = _addCut(PING_SEL);
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IEmergencyCut.EmergencyCutMustBeRemoveOnly.selector, uint8(FacetCutAction.Add))
        );
        diamond.emergencyRemoveCut(cuts);
    }

    function test_EmergencyRemove_RejectsReplace() public {
        _makeGuardian(guardian);
        FacetCut[] memory cuts = _replaceCut(PING_SEL);
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IEmergencyCut.EmergencyCutMustBeRemoveOnly.selector, uint8(FacetCutAction.Replace))
        );
        diamond.emergencyRemoveCut(cuts);
    }

    function test_EmergencyRemove_FrozenSelectorProtected() public {
        _bindPing();
        _freeze(PING_SEL);
        _makeGuardian(guardian);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, PING_SEL));
        diamond.emergencyRemoveCut(cuts);
        assertEq(diamond.facetOf(PING_SEL), address(dummy), "frozen selector must survive emergency removal");
    }

    function test_EmergencyRemove_WorksWhileEmergencyStopped() public {
        _bindPing();
        _makeGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("incident: facet compromised");
        assertTrue(diamond.isStopped(), "stop must be engaged");

        // The NORMAL Safe-gated cut is blocked while stopped.
        FacetCut[] memory addCut = _addPingCut();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        diamond.diamondCut(addCut, address(0), "");

        // The EMERGENCY removal goes through DESPITE the stop.
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        vm.prank(admin);
        diamond.emergencyRemoveCut(cuts);
        assertEq(diamond.facetOf(PING_SEL), address(0), "emergency removal must work during a stop");
    }

    function test_EmergencyRemove_RecordedAndEmitsEvent() public {
        vm.warp(987_654);
        _bindPing(); // version 1
        assertEq(diamond.cutCount(), 1, "binding cut is version 1");
        _makeGuardian(guardian);
        FacetCut[] memory cuts = _removeCut(PING_SEL);
        bytes32 expectedHash = keccak256(abi.encode(cuts, address(0), bytes("")));

        vm.expectEmit(true, true, false, true, address(diamond));
        emit IEmergencyCut.EmergencyCutExecuted(2, guardian, 1);
        vm.prank(guardian);
        diamond.emergencyRemoveCut(cuts);

        assertEq(diamond.cutCount(), 2, "emergency removal must bump the registry version");
        IUpgradeRegistry.CutRecord memory rec = diamond.getCutRecord(2);
        assertEq(rec.cutHash, expectedHash, "emergency cutHash must bind the removal cut");
        assertEq(rec.executor, guardian, "executor must be the guardian");
        assertEq(rec.init, address(0), "emergency removal records no init (removal-only)");
    }
}
