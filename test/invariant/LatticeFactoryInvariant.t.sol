// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {
    CoreFlippingExporter,
    CoreGrantSenderInit,
    CorePongFacet,
    CoreRevertingInit,
    CoreValueFacet,
    RawCode
} from "@lattice-test/helpers/LatticeCoreMocks.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ILatticeFactory, RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Drives {LatticeFactory.deploy} and {LatticeFactory.deployStrict} over 3 callers x 4 salts with four
///         recipe kinds (pinned, latest, custom-only, mixed) and four init kinds (none, reverting, grants
///         `msg.sender`, explicit admin), interleaved with the registry curator moving `latest` and a stateful
///         exporter drifting. Each outcome is predicted from ghost state; expected reverts are asserted with
///         `vm.expectRevert`.
/// @dev The handler is the registry owner, so it can move `latest`. Every recipe cuts AccessControl, so F3 can
///      read roles on every diamond.
contract LatticeFactoryHandler is Test {
    LatticeRegistry public immutable registry;
    LatticeFactory public immutable factory;

    uint256 public constant CALLERS = 3;
    uint256 public constant SALTS = 4;

    bytes32 internal constant LOUPE = keccak256("lattice.DiamondLoupeFacet");
    bytes32 internal constant VALUE = keccak256("lattice.CoreValue");
    bytes32 internal constant ACCESS = keccak256("lattice.AccessControl");
    bytes32 internal constant FLIP = keccak256("lattice.CoreFlipping");
    uint64 internal constant V1 = 1 << 48;
    uint64 internal constant V2 = 2 << 48;

    uint8 public constant INIT_NONE = 0;
    uint8 public constant INIT_REVERTING = 1;
    uint8 public constant INIT_GRANTS_SENDER = 2;
    uint8 public constant INIT_EXPLICIT_ADMIN = 3;

    address public immutable admin = address(0xAD);
    address[CALLERS] internal _callers;
    bytes32[SALTS] internal _salts;

    address internal immutable _loupeFacet;
    address internal immutable _accessFacet;
    address internal immutable _pongFacet;
    address internal immutable _grantSenderInit;
    address internal immutable _revertingInit;
    address internal immutable _adminInit;
    CoreFlippingExporter public immutable flipping;

    struct Slot {
        bool deployed;
        bool attempted;
        address diamond;
        uint8 initKind;
        uint256 expectedValue;
        bytes32 facetsHash;
    }

    mapping(uint256 slot => Slot) internal _slots;
    uint64 public ghostLatestValue = V1;

    constructor() {
        registry = new LatticeRegistry(address(this));
        factory = new LatticeFactory(registry, address(0), address(0));
        _callers = [address(0xCA11E1), address(0xCA11E2), address(0xCA11E3)];
        _salts = [bytes32(0), keccak256("s1"), keccak256("s2"), keccak256("s3")];

        _loupeFacet = address(new DiamondLoupeFacet());
        _accessFacet = address(new AccessControl());
        _pongFacet = address(new CorePongFacet());
        _grantSenderInit = address(new CoreGrantSenderInit());
        _revertingInit = address(new CoreRevertingInit());
        _adminInit = address(new AccessControlInit());
        flipping = new CoreFlippingExporter();

        registry.register(LOUPE, V1, _loupeFacet);
        registry.register(VALUE, V1, address(new CoreValueFacet(1)));
        registry.register(VALUE, V2, address(new CoreValueFacet(2)));
        registry.register(ACCESS, V1, _accessFacet);
        registry.register(FLIP, V1, address(flipping));
        registry.setLatest(VALUE, V1);
    }

    //*////////////////////////////// views for the invariants //////////////////////////////*//

    function slot(uint256 c, uint256 s) external view returns (Slot memory) {
        return _slots[c * SALTS + s];
    }

    function callerOf(uint256 c) external view returns (address) {
        return _callers[c];
    }

    function saltOf(uint256 s) external view returns (bytes32) {
        return _salts[s];
    }

    //*////////////////////////////////////// actions //////////////////////////////////////*//

    /// @dev One deploy call's arguments, grouped to keep the handler under the stack limit.
    struct Call {
        address caller;
        bytes32 salt;
        RecipeEntry[] entries;
        FacetCut[] cuts;
        address init;
        bytes data;
        bool strict;
    }

    function deploy(uint256 callerSeed, uint256 saltSeed, uint256 recipeSeed, uint256 initSeed, bool strict) external {
        uint256 c = callerSeed % CALLERS;
        uint256 s = saltSeed % SALTS;
        Slot storage st = _slots[c * SALTS + s];
        uint8 kind = uint8(recipeSeed % 4);
        uint8 initKind = uint8(initSeed % 4);

        Call memory call_;
        call_.caller = _callers[c];
        call_.salt = _salts[s];
        uint256 expectedValue;
        (call_.entries, call_.cuts, expectedValue) = _recipe(kind);
        (call_.init, call_.data) = _init(initKind, c * SALTS + s);
        call_.strict = strict;

        // deployStrict validates the entries before it looks at the address: a `latest` entry is refused.
        if (strict && kind == 1) {
            vm.expectRevert(abi.encodeWithSelector(ILatticeFactory.LatticeFactory__UnpinnedEntry.selector, VALUE));
            _deploy(call_);
            return;
        }
        if (strict && st.deployed) {
            vm.expectRevert(
                abi.encodeWithSelector(ILatticeFactory.LatticeFactory__AlreadyDeployed.selector, st.diamond)
            );
            _deploy(call_);
            return;
        }
        if (st.deployed) {
            vm.recordLogs();
            assertEq(_deploy(call_), st.diamond, "F4: idempotent return moved");
            assertEq(vm.getRecordedLogs().length, 0, "F4: idempotent return emitted");
            return;
        }

        st.attempted = true;
        bool drifted = kind == 3 && flipping.flipped();
        if (drifted) {
            vm.expectRevert(
                abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__SelectorDrift.selector, address(flipping))
            );
        } else if (initKind == INIT_REVERTING) {
            vm.expectRevert(abi.encodeWithSelector(CoreRevertingInit.CoreInitRefused.selector, c * SALTS + s));
        }
        address diamond = _deploy(call_);
        if (drifted || initKind == INIT_REVERTING) return;

        st.deployed = true;
        st.diamond = diamond;
        st.initKind = initKind;
        st.expectedValue = expectedValue;
        st.facetsHash = keccak256(abi.encode(IDiamondLoupe(diamond).facets()));
    }

    function _deploy(Call memory call_) internal returns (address) {
        vm.prank(call_.caller);
        if (call_.strict) return factory.deployStrict(call_.entries, call_.cuts, call_.init, call_.data, call_.salt);
        return factory.deploy(call_.entries, call_.cuts, call_.init, call_.data, call_.salt);
    }

    function setLatest(bool toV2) external {
        uint64 v = toV2 ? V2 : V1;
        registry.setLatest(VALUE, v);
        ghostLatestValue = v;
    }

    function flip() external {
        flipping.flip();
    }

    //*////////////////////////////////////// helpers //////////////////////////////////////*//

    /// @dev 0 pinned, 1 latest, 2 custom-only, 3 mixed (registry VALUE/ACCESS/FLIP + custom loupe and pong).
    function _recipe(uint8 kind)
        internal
        view
        returns (RecipeEntry[] memory entries, FacetCut[] memory cuts, uint256 expectedValue)
    {
        if (kind == 2) {
            cuts = new FacetCut[](3);
            cuts[0] = _customCut(_loupeFacet);
            cuts[1] = _customCut(_accessFacet);
            cuts[2] = FacetCut(_pongFacet, FacetCutAction.Add, _one(CorePongFacet.pong.selector));
            return (entries, cuts, 0);
        }
        if (kind == 3) {
            entries = new RecipeEntry[](3);
            entries[0] = RecipeEntry(VALUE, V1, new bytes4[](0));
            entries[1] = RecipeEntry(ACCESS, V1, new bytes4[](0));
            entries[2] = RecipeEntry(FLIP, V1, new bytes4[](0));
            cuts = new FacetCut[](2);
            cuts[0] = _customCut(_loupeFacet);
            cuts[1] = FacetCut(_pongFacet, FacetCutAction.Add, _one(CorePongFacet.pong.selector));
            return (entries, cuts, 1);
        }
        entries = new RecipeEntry[](3);
        entries[0] = RecipeEntry(LOUPE, V1, new bytes4[](0));
        entries[1] = RecipeEntry(VALUE, kind == 0 ? V1 : 0, new bytes4[](0));
        entries[2] = RecipeEntry(ACCESS, V1, new bytes4[](0));
        expectedValue = kind == 0 ? 1 : (ghostLatestValue == V1 ? 1 : 2);
    }

    function _init(uint8 initKind, uint256 code) internal view returns (address init, bytes memory data) {
        if (initKind == INIT_REVERTING) return (_revertingInit, abi.encodeCall(CoreRevertingInit.init, (code)));
        if (initKind == INIT_GRANTS_SENDER) return (_grantSenderInit, abi.encodeCall(CoreGrantSenderInit.init, ()));
        if (initKind == INIT_EXPLICIT_ADMIN) return (_adminInit, abi.encodeCall(AccessControlInit.init, (admin)));
    }

    function _customCut(address facet) internal view returns (FacetCut memory) {
        (, bytes memory ret) = facet.staticcall(abi.encodeWithSelector(0x0ef22643));
        return FacetCut(facet, FacetCutAction.Add, RawCode.unpack(abi.decode(ret, (bytes))));
    }

    function _one(bytes4 s) internal pure returns (bytes4[] memory a) {
        a = new bytes4[](1);
        a[0] = s;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title LatticeFactoryInvariant
/// @notice #176's factory invariant set F1-F6 over sequences of deploys, repeat deploys, `latest` moves and
///         selector drift.
/// forge-config: ci.invariant.runs = 64
contract LatticeFactoryInvariant is Test {
    LatticeFactoryHandler internal handler;
    LatticeFactory internal factory;

    bytes4[4] internal LOUPE_SELECTORS =
        [bytes4(0x7a0ed627), bytes4(0xadfca15e), bytes4(0x52ef6b2c), bytes4(0xcdffacc6)];

    function setUp() public {
        handler = new LatticeFactoryHandler();
        factory = handler.factory();
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = LatticeFactoryHandler.deploy.selector;
        selectors[1] = LatticeFactoryHandler.setLatest.selector;
        selectors[2] = LatticeFactoryHandler.flip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice F1: every deployed diamond sits at `predict(caller, salt)` and has code; its registry-resolved
    ///         `value()` is the version resolved when it was deployed, whatever `latest` did afterwards.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_F1_DeployEqualsPredict() public view {
        for (uint256 c; c < handler.CALLERS(); ++c) {
            for (uint256 s; s < handler.SALTS(); ++s) {
                LatticeFactoryHandler.Slot memory st = handler.slot(c, s);
                if (!st.deployed) continue;
                assertEq(st.diamond, factory.predict(handler.callerOf(c), handler.saltOf(s)), "F1 predict");
                assertTrue(st.diamond.code.length != 0, "F1 code");
                if (st.expectedValue != 0) assertEq(CoreValueFacet(st.diamond).value(), st.expectedValue, "F1 value");
            }
        }
    }

    /// @notice F2: a (caller, salt) whose every attempt reverted holds no code, so it stays retryable.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_F2_FailedDeploysLeaveNoCode() public view {
        for (uint256 c; c < handler.CALLERS(); ++c) {
            for (uint256 s; s < handler.SALTS(); ++s) {
                LatticeFactoryHandler.Slot memory st = handler.slot(c, s);
                if (st.attempted && !st.deployed) {
                    assertEq(factory.predict(handler.callerOf(c), handler.saltOf(s)).code.length, 0, "F2 code left");
                }
            }
        }
    }

    /// @notice F3: the factory holds `DEFAULT_ADMIN_ROLE` on a diamond EXACTLY when its init granted `msg.sender`
    ///         (finding F-6); with an explicit-admin init the admin holds it and the factory does not.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_F3_FactoryAuthority() public view {
        for (uint256 c; c < handler.CALLERS(); ++c) {
            for (uint256 s; s < handler.SALTS(); ++s) {
                LatticeFactoryHandler.Slot memory st = handler.slot(c, s);
                if (!st.deployed) continue;
                bool factoryAdmin = AccessControl(st.diamond).hasRole(DEFAULT_ADMIN_ROLE, address(factory));
                assertEq(factoryAdmin, st.initKind == handler.INIT_GRANTS_SENDER(), "F3 factory authority");
                assertFalse(AccessControl(st.diamond).hasRole(DEFAULT_ADMIN_ROLE, handler.callerOf(c)), "F3 caller");
                if (st.initKind == handler.INIT_EXPLICIT_ADMIN()) {
                    assertTrue(AccessControl(st.diamond).hasRole(DEFAULT_ADMIN_ROLE, handler.admin()), "F3 admin");
                }
            }
        }
    }

    /// @notice F4: repeat deploys never change a diamond's loupe (the handler also asserts the same address and
    ///         no event on every repeat).
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_F4_RepeatDeploysLeaveLoupeUnchanged() public view {
        for (uint256 c; c < handler.CALLERS(); ++c) {
            for (uint256 s; s < handler.SALTS(); ++s) {
                LatticeFactoryHandler.Slot memory st = handler.slot(c, s);
                if (!st.deployed) continue;
                assertEq(keccak256(abi.encode(IDiamondLoupe(st.diamond).facets())), st.facetsHash, "F4 loupe moved");
            }
        }
    }

    /// @notice F5 and F6: all four loupe selectors are routed, and `exportSelectors()` never is.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_F5_F6_LoupeRoutedExportNot() public view {
        for (uint256 c; c < handler.CALLERS(); ++c) {
            for (uint256 s; s < handler.SALTS(); ++s) {
                LatticeFactoryHandler.Slot memory st = handler.slot(c, s);
                if (!st.deployed) continue;
                for (uint256 k; k < 4; ++k) {
                    assertTrue(IDiamondLoupe(st.diamond).facetAddress(LOUPE_SELECTORS[k]) != address(0), "F5");
                }
                assertEq(IDiamondLoupe(st.diamond).facetAddress(0x0ef22643), address(0), "F6");
            }
        }
    }
}
