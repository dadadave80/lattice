// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Selectors} from "@diamond-test/helpers/Selectors.sol";
import {
    AddressAndCalldataLengthMismatch,
    MultiInit,
    MultiInit__StepFailed,
    MultiInit__ZeroInit,
    NoBytecodeAtAddress
} from "@diamond/initializers/MultiInit.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {ArachnidProxy} from "@lattice-test/helpers/ArachnidProxy.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IAccessControlDiamondCut} from "@lattice/interfaces/governance/IAccessControlDiamondCut.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {IInitializable} from "@lattice/interfaces/utils/IInitializable.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {PausableInit} from "@lattice/security/PausableInit.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ReinitMultiInit} from "@lattice/utils/ReinitMultiInit.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";
import {IERC165} from "forge-std/interfaces/IERC165.sol";

contract ReinitFailureFixture {
    error StepFailed(uint256 value);

    function failWithData() external pure {
        revert StepFailed(7);
    }

    function failEmpty() external pure {
        assembly ("memory-safe") { revert(0, 0) }
    }

    function failWithString() external pure {
        revert("reinit diagnostic witness");
    }

    function failWithPanic() external pure {
        assert(false);
    }

    function failWithValue(uint256 value) external pure {
        revert StepFailed(value);
    }
}

/// @notice Exercises upgrade batches through the production factory, admin recipe and authorized cut.
contract ReinitMultiInitTest is Test {
    address internal constant ADMIN = address(0xAD);
    bytes32 internal constant SLOT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132;
    address internal diamond;
    Pausable internal pausable;
    PausableInit internal moduleInit;
    ReinitMultiInit internal batch;
    ReinitFailureFixture internal failure;

    function setUp() public {
        vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME);
        DeployERC20 recipe = new DeployERC20();
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts("Upgrade Token", "UP", ADMIN);
        LatticeFactory factory = new LatticeFactory(new LatticeRegistry(address(this)), address(0), address(0));
        diamond = factory.deploy(new RecipeEntry[](0), cuts, init, data, bytes32(uint256(1)));
        pausable = new Pausable();
        moduleInit = new PausableInit();
        batch = new ReinitMultiInit();
        failure = new ReinitFailureFixture();
        vm.prank(ADMIN);
        ERC20(diamond).approve(address(0xBEEF), 123);
        _assertVersion(1);
    }

    function _cuts() internal view returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(pausable), FacetCutAction.Add, Selectors.decode(pausable.exportSelectors()));
    }

    function _steps() internal view returns (address[] memory targets, bytes[] memory data) {
        targets = new address[](1);
        data = new bytes[](1);
        targets[0] = address(moduleInit);
        data[0] = abi.encodeCall(PausableInit.init, (ADMIN));
    }

    function _execute(uint64 version, FacetCut[] memory cuts, address[] memory targets, bytes[] memory data) internal {
        bytes memory payload = abi.encodeCall(ReinitMultiInit.reinitMulti, (version, targets, data));
        vm.prank(ADMIN);
        IAccessControlDiamondCut(diamond).diamondCut(cuts, address(batch), payload);
    }

    function _addModule(uint64 version) internal {
        (address[] memory targets, bytes[] memory data) = _steps();
        _execute(version, _cuts(), targets, data);
    }

    function _assertVersion(uint64 expected) internal view {
        assertEq(InitializableLib.initializableSlot(), SLOT, "documented slot");
        uint256 word = uint256(vm.load(diamond, SLOT));
        assertEq(word & 1, 0, "window must close");
        assertEq(uint64(word >> 1), expected);
    }

    function _assertRollback() internal view {
        _assertVersion(1);
        assertEq(IDiamondLoupe(diamond).facetAddress(Pausable.paused.selector), address(0));
        assertFalse(IERC165(diamond).supportsInterface(type(IPausable).interfaceId));
        assertEq(ERC20(diamond).allowance(ADMIN, address(0xBEEF)), 123);
    }

    function test_AddsAndInitializesModuleAtVersion2() public {
        (address[] memory targets, bytes[] memory data) = _steps();
        FacetCut[] memory cuts = _cuts();
        vm.expectEmit(false, false, false, true, diamond);
        emit IInitializable.Initialized(2);
        _execute(2, cuts, targets, data);
        _assertVersion(2);
        assertEq(IDiamondLoupe(diamond).facetAddress(Pausable.paused.selector), address(pausable));
        assertEq(IDiamondLoupe(diamond).facetAddress(ReinitMultiInit.reinitMulti.selector), address(0));
        assertTrue(IERC165(diamond).supportsInterface(type(IPausable).interfaceId));
        assertEq(ERC20(diamond).name(), "Upgrade Token");
        assertEq(ERC20(diamond).allowance(ADMIN, address(0xBEEF)), 123);
        vm.prank(ADMIN);
        Pausable(diamond).pause();
        assertTrue(Pausable(diamond).paused());
    }

    function test_ReplayAndLowerVersionRevert() public {
        _addModule(2);
        vm.prank(ADMIN);
        Pausable(diamond).pause();
        vm.expectRevert(IInitializable.InvalidInitialization.selector);
        _execute(2, new FacetCut[](0), new address[](0), new bytes[](0));
        vm.expectRevert(IInitializable.InvalidInitialization.selector);
        _execute(1, new FacetCut[](0), new address[](0), new bytes[](0));
        _assertVersion(2);
        assertTrue(Pausable(diamond).paused());
    }

    function test_ExistingUpgradeAuthorityIsRequired() public {
        (address[] memory targets, bytes[] memory data) = _steps();
        FacetCut[] memory cuts = _cuts();
        bytes memory payload = abi.encodeCall(ReinitMultiInit.reinitMulti, (2, targets, data));
        vm.prank(address(0xBAD));
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(0xBAD), bytes32(0))
        );
        IAccessControlDiamondCut(diamond).diamondCut(cuts, address(batch), payload);
        _assertRollback();
    }

    function test_DirectHelperStateCannotConsumeDiamondVersion() public {
        batch.reinitMulti(100, new address[](0), new bytes[](0));
        _assertVersion(1);
        _addModule(2);
        _assertVersion(2);
    }

    function test_DirectReleasedModuleInitNeedsWindow() public {
        FacetCut[] memory cuts = _cuts();
        bytes memory data = abi.encodeCall(PausableInit.init, (ADMIN));
        vm.prank(ADMIN);
        vm.expectRevert(IInitializable.NotInitializing.selector);
        IAccessControlDiamondCut(diamond).diamondCut(cuts, address(moduleInit), data);
        _assertRollback();
    }

    function test_LengthMismatchRollsBackCutAndVersion() public {
        FacetCut[] memory cuts = _cuts();
        address[] memory targets = new address[](1);
        vm.expectRevert(AddressAndCalldataLengthMismatch.selector);
        _execute(2, cuts, targets, new bytes[](0));
        _assertRollback();
    }

    function _failedStep(address target, bytes memory payload, bytes memory expected) internal {
        address[] memory targets = new address[](2);
        bytes[] memory data = new bytes[](2);
        targets[0] = address(moduleInit);
        targets[1] = target;
        data[0] = abi.encodeCall(PausableInit.init, (ADMIN));
        data[1] = payload;
        FacetCut[] memory cuts = _cuts();
        vm.expectRevert(expected);
        _execute(2, cuts, targets, data);
        _assertRollback();
        _addModule(2);
        _assertVersion(2);
    }

    function test_NoCodeTargetRollsBackEarlierStep() public {
        _failedStep(address(0xBEEF), "", abi.encodeWithSelector(NoBytecodeAtAddress.selector, 1, address(0xBEEF)));
    }

    function test_StepRevertDataRetainsIndexTargetAndInnerBytes() public {
        _failedStep(
            address(failure),
            abi.encodeCall(ReinitFailureFixture.failWithData, ()),
            _stepError(1, address(failure), abi.encodeWithSelector(ReinitFailureFixture.StepFailed.selector, 7))
        );
    }

    function test_EmptyStepRevertNamesTheFailedTarget() public {
        bytes memory data = abi.encodeCall(ReinitFailureFixture.failEmpty, ());
        _failedStep(address(failure), data, _stepError(1, address(failure), ""));
    }

    function test_NestedReinitializerRollsBack() public {
        bytes memory nested = abi.encodeCall(ReinitMultiInit.reinitMulti, (3, new address[](0), new bytes[](0)));
        _failedStep(
            address(batch),
            nested,
            _stepError(1, address(batch), abi.encodeWithSelector(IInitializable.InvalidInitialization.selector))
        );
    }

    function test_ZeroTargetRollsBackEarlierStepAndCanRetryVersion() public {
        _failedStep(address(0), "", abi.encodeWithSelector(MultiInit__ZeroInit.selector, 1));
    }

    function test_MaximumVersionIsTerminal() public {
        _execute(type(uint64).max, new FacetCut[](0), new address[](0), new bytes[](0));
        _assertVersion(type(uint64).max);
        vm.expectRevert(IInitializable.InvalidInitialization.selector);
        _execute(type(uint64).max, new FacetCut[](0), new address[](0), new bytes[](0));
    }

    function testFuzz_ModuleUpgradeWithHigherVersion(uint64 version) public {
        version = uint64(bound(uint256(version), 2, type(uint64).max));
        _addModule(version);
        _assertVersion(version);
        assertTrue(IERC165(diamond).supportsInterface(type(IPausable).interfaceId));
    }

    function test_ExplicitEmptyBatchAdvancesVersion() public {
        _execute(2, new FacetCut[](0), new address[](0), new bytes[](0));
        _assertVersion(2);
        assertEq(ERC20(diamond).allowance(ADMIN, address(0xBEEF)), 123);
    }

    function test_StringStepRetainsExactInnerReason() public {
        _failedStep(
            address(failure),
            abi.encodeCall(ReinitFailureFixture.failWithString, ()),
            _stepError(1, address(failure), abi.encodeWithSignature("Error(string)", "reinit diagnostic witness"))
        );
    }

    function test_PanicStepRetainsExactInnerReason() public {
        _failedStep(
            address(failure),
            abi.encodeCall(ReinitFailureFixture.failWithPanic, ()),
            _stepError(1, address(failure), abi.encodeWithSignature("Panic(uint256)", uint256(1)))
        );
    }

    function testFuzz_CustomStepRetainsAllInnerBytes(uint256 value) public {
        _failedStep(
            address(failure),
            abi.encodeCall(ReinitFailureFixture.failWithValue, (value)),
            _stepError(1, address(failure), abi.encodeWithSelector(ReinitFailureFixture.StepFailed.selector, value))
        );
    }

    function testFuzz_ZeroAtAnyIndexRollsBackCutAndVersion(uint8 index) public {
        index = uint8(bound(uint256(index), 0, 2));
        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);
        for (uint256 i; i < targets.length; ++i) {
            targets[i] = address(moduleInit);
            data[i] = abi.encodeCall(PausableInit.init, (ADMIN));
        }
        targets[index] = address(0);
        FacetCut[] memory cuts = _cuts();
        vm.expectRevert(abi.encodeWithSelector(MultiInit__ZeroInit.selector, uint256(index)));
        _execute(2, cuts, targets, data);
        _assertRollback();
        _addModule(2);
        _assertVersion(2);
    }

    function _stepError(uint256 index, address target, bytes memory inner) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(MultiInit__StepFailed.selector, index, target, inner);
    }

    function _nestedFailure(address last, bytes memory lastData, bytes memory expectedInner) internal {
        MultiInit inner = new MultiInit();
        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);
        for (uint256 i; i < 2; ++i) {
            targets[i] = address(moduleInit);
            data[i] = abi.encodeCall(PausableInit.init, (ADMIN));
        }
        targets[2] = last;
        data[2] = lastData;
        _failedStep(
            address(inner),
            abi.encodeCall(MultiInit.multiInit, (targets, data)),
            _stepError(1, address(inner), expectedInner)
        );
    }

    function test_NestedMultiInitRetainsOuterAndInnerFailurePath() public {
        _nestedFailure(
            address(failure),
            abi.encodeCall(ReinitFailureFixture.failWithData, ()),
            _stepError(2, address(failure), abi.encodeWithSelector(ReinitFailureFixture.StepFailed.selector, 7))
        );
    }

    function test_NestedMultiInitRetainsInnerZeroIndex() public {
        _nestedFailure(address(0), "", abi.encodeWithSelector(MultiInit__ZeroInit.selector, 2));
    }

    function test_NestedMultiInitRetainsInnerMissingCodeIndex() public {
        _nestedFailure(address(0xBEEF), "", abi.encodeWithSelector(NoBytecodeAtAddress.selector, 2, address(0xBEEF)));
    }
}
