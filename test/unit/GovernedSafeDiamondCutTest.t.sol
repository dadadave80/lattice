// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedSafeDiamondCut} from "@lattice/governance/GovernedSafeDiamondCut.sol";
import {
    GOVERNED_SAFE_DIAMOND_CUT_STORAGE_SLOT,
    GovernedSafeDiamondCutLib
} from "@lattice/governance/libraries/GovernedSafeDiamondCutLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedSafeDiamondCut} from "@lattice/interfaces/governance/IGovernedSafeDiamondCut.sol";
import {ISafeAuthority} from "@lattice/interfaces/governance/ISafeAuthority.sol";
import {ISafeDiamondCut} from "@lattice/interfaces/governance/ISafeDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {EMERGENCY_GUARDIAN_ROLE, EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Tiny mock standing in for a Gnosis Safe (read-only surface used to validate the authority).
contract MockSafe {
    uint256 internal _threshold;
    address[] internal _owners;
    uint256 internal _nonce;

    constructor(uint256 threshold_, address[] memory owners_) {
        _threshold = threshold_;
        _owners = owners_;
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

/// @notice A minimal self-contained Diamond used to exercise the timelocked Safe-gated cut wrapper.
contract MockGovernedSafeDiamond is GovernedSafeDiamondCut, AccessControl, EmergencyStop {
    function initialize(address _admin, address _safe, uint256 _minThreshold, uint256 _minDelay) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(_admin);
        EmergencyStopLib.__EmergencyStop_init();
        DiamondLib.registerInterface();
        GovernedSafeDiamondCutLib.__GovernedSafeDiamondCut_init(_safe, _minThreshold, _minDelay);
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

contract DummyFacet {
    function ping() external pure returns (uint256) {
        return 7;
    }
}

/// @title GovernedSafeDiamondCutTest
/// @notice Unit tests for the GovernedSafeDiamondCut (Safe + built-in timelock) module.
contract GovernedSafeDiamondCutTest is Test {
    MockGovernedSafeDiamond internal diamond;
    MockSafe internal safe;
    DummyFacet internal dummy;
    address internal admin = address(0xA1);
    address internal stranger = address(0xBEEF);
    uint256 internal constant MIN_THRESHOLD = 2;
    uint256 internal constant MIN_DELAY = 2 days;
    bytes32 internal constant SALT = bytes32(uint256(0x5A17));

    function setUp() public {
        address[] memory owners = new address[](3);
        owners[0] = address(0x1);
        owners[1] = address(0x2);
        owners[2] = address(0x3);
        safe = new MockSafe(MIN_THRESHOLD, owners);
        diamond = new MockGovernedSafeDiamond();
        diamond.initialize(admin, address(safe), MIN_THRESHOLD, MIN_DELAY);
        dummy = new DummyFacet();
        vm.warp(1_000_000); // sane baseline timestamp
    }

    function _addPingCut() internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.ping.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
    }

    function _opId(FacetCut[] memory cuts, address init, bytes memory cd, bytes32 salt)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(cuts, init, cd, salt));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SELECTOR / SLOT / ERC-165 INVARIANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The module deliberately does NOT serve the canonical cut selector — every cut is delayed.
    function test_DoesNotServeCanonicalCutSelector() public view {
        assertEq(diamond.facetOf(bytes4(0x1f931c1c)), address(0), "must not bind synchronous diamondCut");
    }

    function _erc7201Slot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_StorageSlotDerivation() public pure {
        assertEq(
            GOVERNED_SAFE_DIAMOND_CUT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.GovernedSafeDiamondCut"),
            "GovernedSafeDiamondCut storage slot mismatch"
        );
    }

    /// @notice The scheduling ABI is a genuinely new interface with its own ERC-165 id (0xacb1aeb6),
    ///         registered at init.
    function test_InterfaceIdRegistered() public view {
        bytes4 id = type(IGovernedSafeDiamondCut).interfaceId;
        assertEq(id, bytes4(0xacb1aeb6), "IGovernedSafeDiamondCut interfaceId comment is stale");
        assertTrue(diamond.supportsInterface(id), "interface must be advertised via ERC-165");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitPinsSafeAndDelay() public view {
        assertEq(diamond.safe(), address(safe), "safe must be pinned");
        assertEq(diamond.minDelay(), MIN_DELAY, "minDelay must be pinned");
    }

    function test_InitRejectsZeroSafe() public {
        MockGovernedSafeDiamond d = new MockGovernedSafeDiamond();
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutZeroSafe.selector));
        d.initialize(admin, address(0), MIN_THRESHOLD, MIN_DELAY);
    }

    function test_InitRejectsThresholdTooLow() public {
        MockGovernedSafeDiamond d = new MockGovernedSafeDiamond();
        vm.expectRevert(
            abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutThresholdTooLow.selector, uint256(2), uint256(3))
        );
        d.initialize(admin, address(safe), 3, MIN_DELAY);
    }

    /// @notice minDelay may be 0 (documented risk): init succeeds.
    function test_InitAllowsZeroDelay() public {
        MockGovernedSafeDiamond d = new MockGovernedSafeDiamond();
        d.initialize(admin, address(safe), MIN_THRESHOLD, 0);
        assertEq(d.minDelay(), 0, "zero delay must be permitted");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SCHEDULE -> DELAY -> EXECUTE
    //////////////////////////////////////////////////////////////////////////*//

    function test_ScheduleSetsEtaAndEmits() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        uint256 expectedEta = block.timestamp + MIN_DELAY;

        vm.expectEmit(true, true, false, true, address(diamond));
        emit IGovernedSafeDiamondCut.CutScheduled(id, 1, address(0), SALT, expectedEta);
        vm.prank(address(safe));
        bytes32 returnedId = diamond.scheduleCut(cuts, address(0), "", SALT);

        assertEq(returnedId, id, "returned id mismatch");
        assertEq(diamond.getTimestamp(id), expectedEta, "eta must be stored");
        assertTrue(diamond.isOperationPending(id), "operation must be pending before eta");
        assertFalse(diamond.isOperationReady(id), "operation must not be ready before eta");
    }

    function test_ScheduleUnauthorizedReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        diamond.scheduleCut(cuts, address(0), "", SALT);
    }

    function test_ScheduleBlockedWhileStopped() public {
        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("freeze");

        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        diamond.scheduleCut(cuts, address(0), "", SALT);
    }

    function test_ScheduleDuplicateReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IGovernedSafeDiamondCut.CutAlreadyScheduled.selector, id));
        diamond.scheduleCut(cuts, address(0), "", SALT);
    }

    /// @notice Executing before eta reverts CutNotReady(id, eta).
    function test_ExecuteTooEarlyReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
        uint256 eta = diamond.getTimestamp(id);

        // Warp to one second before eta.
        vm.warp(eta - 1);
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IGovernedSafeDiamondCut.CutNotReady.selector, id, eta));
        diamond.executeCut(cuts, address(0), "", SALT);
    }

    /// @notice Executing an unscheduled id reverts CutNotScheduled(id).
    function test_ExecuteUnscheduledReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IGovernedSafeDiamondCut.CutNotScheduled.selector, id));
        diamond.executeCut(cuts, address(0), "", SALT);
    }

    /// @notice Full happy path: schedule, wait out the delay, execute — selector is bound and the
    ///         operation is cleared (done) and recorded in the registry.
    function test_ScheduleDelayExecute() public {
        vm.warp(2_000_000);
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);

        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
        uint256 eta = diamond.getTimestamp(id);

        vm.warp(eta); // exactly ready
        assertTrue(diamond.isOperationReady(id), "operation must be ready at eta");

        vm.expectEmit(true, false, false, false, address(diamond));
        emit IGovernedSafeDiamondCut.CutExecuted(id);
        vm.prank(address(safe));
        diamond.executeCut(cuts, address(0), "", SALT);

        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy), "ping selector must be bound");
        // Operation cleared: not pending, not ready, done.
        assertEq(diamond.getTimestamp(id), 0, "eta must be cleared after execute");
        assertFalse(diamond.isOperationPending(id));
        assertFalse(diamond.isOperationReady(id));
        assertTrue(diamond.isOperationDone(id), "operation must report done after execute");

        // Registry recorded.
        assertEq(diamond.cutCount(), 1, "cut must be recorded");
        IUpgradeRegistry.CutRecord memory rec = diamond.getCutRecord(1);
        assertEq(rec.executor, address(safe), "executor must be the Safe");
        assertEq(rec.cutHash, keccak256(abi.encode(cuts, address(0), bytes(""))), "cutHash must bind payload");
    }

    /// @notice Execute is Safe-gated even after maturity: a stranger reverts.
    function test_ExecuteUnauthorizedReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
        vm.warp(diamond.getTimestamp(id));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        diamond.executeCut(cuts, address(0), "", SALT);
    }

    /// @notice Execute is blocked while emergency-stopped (even after maturity).
    function test_ExecuteBlockedWhileStopped() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
        vm.warp(diamond.getTimestamp(id));

        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("freeze");

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IEmergencyStop.EmergencyStopActive.selector));
        diamond.executeCut(cuts, address(0), "", SALT);
    }

    /// @notice An execute that touches a frozen selector reverts FrozenSelectorProtected.
    function test_ExecuteFrozenSelectorReverts() public {
        bytes4 sel = DummyFacet.ping.selector;
        // Freeze the selector first.
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;
        vm.prank(address(safe));
        diamond.freezeSelectors(sels);

        // Schedule a REMOVE of the frozen selector, mature it, then execute -> revert.
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(0), action: FacetCutAction.Remove, functionSelectors: sels});
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
        vm.warp(diamond.getTimestamp(id));

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, sel));
        diamond.executeCut(cuts, address(0), "", SALT);
    }

    /// @notice The same payload can be re-scheduled under a different salt (distinct operation ids).
    function test_SaltDisambiguatesPayloads() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 salt2 = bytes32(uint256(0xBEEF));
        vm.prank(address(safe));
        bytes32 id1 = diamond.scheduleCut(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        bytes32 id2 = diamond.scheduleCut(cuts, address(0), "", salt2);
        assertTrue(id1 != id2, "distinct salts must yield distinct ids");
        assertTrue(diamond.isOperationPending(id1) && diamond.isOperationPending(id2), "both scheduled");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CANCEL
    //////////////////////////////////////////////////////////////////////////*//

    function test_CancelClearsPendingOperation() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
        assertTrue(diamond.isOperationPending(id), "scheduled");

        vm.expectEmit(true, false, false, false, address(diamond));
        emit IGovernedSafeDiamondCut.CutCancelled(id);
        vm.prank(address(safe));
        diamond.cancelCut(id);

        assertEq(diamond.getTimestamp(id), 0, "eta must be cleared after cancel");
        assertFalse(diamond.isOperationPending(id), "must not be pending after cancel");

        // A cancelled operation cannot be executed even after the original eta passes.
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IGovernedSafeDiamondCut.CutNotScheduled.selector, id));
        diamond.executeCut(cuts, address(0), "", SALT);
    }

    function test_CancelUnauthorizedReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        diamond.cancelCut(id);
    }

    function test_CancelUnscheduledReverts() public {
        bytes32 id = bytes32(uint256(0xDEAD));
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(IGovernedSafeDiamondCut.CutNotScheduled.selector, id));
        diamond.cancelCut(id);
    }

    /// @notice After cancel, the same payload+salt can be re-scheduled and executed cleanly.
    function test_CanRescheduleAfterCancel() public {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.cancelCut(id);

        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
        vm.warp(diamond.getTimestamp(id));
        vm.prank(address(safe));
        diamond.executeCut(cuts, address(0), "", SALT);
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy), "re-scheduled cut must apply");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       SET MIN DELAY / SAFE ROTATION
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetMinDelay() public {
        vm.expectEmit(false, false, false, true, address(diamond));
        emit IGovernedSafeDiamondCut.MinDelayChanged(MIN_DELAY, 5 days);
        vm.prank(address(safe));
        diamond.setMinDelay(5 days);
        assertEq(diamond.minDelay(), 5 days, "minDelay must update");

        // New schedule uses the new delay.
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
        assertEq(diamond.getTimestamp(id), block.timestamp + 5 days, "new schedule must use new delay");
    }

    function test_SetMinDelayUnauthorizedReverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        diamond.setMinDelay(1 days);
    }

    function test_SetSafeRotatesAuthority() public {
        address[] memory owners = new address[](2);
        owners[0] = address(0x4);
        owners[1] = address(0x5);
        MockSafe newSafe = new MockSafe(2, owners);

        vm.expectEmit(true, true, false, false, address(diamond));
        emit ISafeAuthority.SafeRotated(address(safe), address(newSafe));
        vm.prank(address(safe));
        diamond.setSafe(address(newSafe));
        assertEq(diamond.safe(), address(newSafe), "safe must rotate");

        // New Safe can schedule; old Safe cannot.
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, address(safe)));
        diamond.scheduleCut(cuts, address(0), "", SALT);

        vm.prank(address(newSafe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
    }

    function test_SetSafeUnauthorizedReverts() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(ISafeAuthority.SafeDiamondCutUnauthorized.selector, stranger));
        diamond.setSafe(address(0xCAFE));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       EMERGENCY REMOVAL-ONLY CUT
    //////////////////////////////////////////////////////////////////////////*//

    address internal guardian = address(0x6044D1A11);

    function _bindPingViaTimelock() internal {
        FacetCut[] memory cuts = _addPingCut();
        bytes32 id = _opId(cuts, address(0), "", SALT);
        vm.prank(address(safe));
        diamond.scheduleCut(cuts, address(0), "", SALT);
        vm.warp(diamond.getTimestamp(id));
        vm.prank(address(safe));
        diamond.executeCut(cuts, address(0), "", SALT);
    }

    function _removeCut(bytes4 _sel) internal pure returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = _sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(0), action: FacetCutAction.Remove, functionSelectors: sels});
    }

    /// @notice Guardian emergency removal bypasses the timelock entirely (zero-delay), even mid-stop.
    function test_EmergencyRemove_ZeroDelayBypassesTimelock() public {
        _bindPingViaTimelock();
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy), "ping must be live");

        vm.prank(admin);
        diamond.addGuardian(guardian);
        FacetCut[] memory cuts = _removeCut(DummyFacet.ping.selector);
        vm.prank(guardian);
        diamond.emergencyRemoveCut(cuts);
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(0), "emergency removal must unbind instantly");
    }

    function test_EmergencyRemove_StrangerReverts() public {
        _bindPingViaTimelock();
        FacetCut[] memory cuts = _removeCut(DummyFacet.ping.selector);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, EMERGENCY_GUARDIAN_ROLE
            )
        );
        diamond.emergencyRemoveCut(cuts);
    }

    function test_EmergencyRemove_RejectsAdd() public {
        vm.prank(admin);
        diamond.addGuardian(guardian);
        FacetCut[] memory cuts = _addPingCut(); // Add
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IEmergencyCut.EmergencyCutMustBeRemoveOnly.selector, uint8(FacetCutAction.Add))
        );
        diamond.emergencyRemoveCut(cuts);
    }

    function test_EmergencyRemove_WorksWhileStopped() public {
        _bindPingViaTimelock();
        vm.prank(admin);
        diamond.addGuardian(admin);
        vm.prank(admin);
        diamond.emergencyStop("incident");

        FacetCut[] memory cuts = _removeCut(DummyFacet.ping.selector);
        vm.prank(admin);
        diamond.emergencyRemoveCut(cuts);
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(0), "emergency removal must work during a stop");
    }
}
