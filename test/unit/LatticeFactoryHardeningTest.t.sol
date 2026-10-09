// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {
    CannotAddFunctionToDiamondThatAlreadyExists,
    FacetCut,
    FacetCutAction,
    NoBytecodeAtAddress,
    NoSelectorsGivenToAdd
} from "@diamond/libraries/DiamondLib.sol";
import {
    CoreFlippingExporter,
    CoreForwarder,
    CoreGrantSenderInit,
    CoreHostileRegistry,
    CoreMarkerInit,
    CoreNestedDeployInit,
    CorePingFacet,
    CorePongFacet,
    CoreReinitializeInit,
    CoreRevertingInit,
    CoreSelfDestructInit,
    CoreShadowedSelectorFacet,
    CoreValueCollidingFacet,
    CoreValueFacet,
    RawCode
} from "@lattice-test/helpers/LatticeCoreMocks.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ILatticeFactory, RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {InvalidInitialization} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test, Vm} from "forge-std/Test.sol";

/// @title LatticeFactoryHardeningTest
/// @notice #176: adversarial and edge-case coverage for {LatticeFactory} on top of {LatticeFactoryTest}: registry
///         binding, recipe kinds and selector collisions, entry exclusions, CREATE2 prediction against the real
///         {Lattice} creation code, caller/salt isolation, occupied-address reuse through `deploy` and
///         `deployStrict`, the recipe hash in `DiamondDeployed`, initialization authority, and malicious init
///         callbacks.
/// @dev The findings F-1 to F-7 in docs/security/registry-factory-threat-model.md are each covered here: F-1, F-2
///      and F-5 by tests of the fix, F-3 and F-4 by `deployStrict` tests next to the documented `deploy`
///      behaviour, and F-6 and F-7 by tests of the documented behaviour.
contract LatticeFactoryHardeningTest is Test {
    LatticeRegistry internal registry;
    LatticeFactory internal factory;

    address internal owner = makeAddr("registryOwner");
    address internal admin = makeAddr("admin");

    bytes32 internal constant LOUPE = keccak256("lattice.DiamondLoupeFacet");
    bytes32 internal constant VALUE = keccak256("lattice.CoreValue");
    bytes32 internal constant PING = keccak256("lattice.CorePing");
    bytes32 internal constant COLLIDE = keccak256("lattice.CoreValueColliding");
    bytes32 internal constant ACCESS = keccak256("lattice.AccessControl");
    bytes32 internal constant FLIP = keccak256("lattice.CoreFlipping");
    bytes32 internal constant SHADOW = keccak256("lattice.CoreShadowed");

    uint64 internal constant V1 = 1 << 48;
    uint64 internal constant V2 = 2 << 48;

    bytes32 internal constant SALT = keccak256("hardening");
    bytes4 internal constant EXPORT_SELECTOR = 0x0ef22643;

    address internal loupeFacet;
    address internal valueV1;
    address internal valueV2;
    CoreFlippingExporter internal flipping;

    function setUp() public {
        registry = new LatticeRegistry(owner);
        factory = new LatticeFactory(registry, address(0), address(0));

        loupeFacet = address(new DiamondLoupeFacet());
        valueV1 = address(new CoreValueFacet(1));
        valueV2 = address(new CoreValueFacet(2));
        flipping = new CoreFlippingExporter();

        vm.startPrank(owner);
        registry.register(LOUPE, V1, loupeFacet);
        registry.register(VALUE, V1, valueV1);
        registry.register(VALUE, V2, valueV2);
        registry.register(PING, V1, address(new CorePingFacet()));
        registry.register(COLLIDE, V1, address(new CoreValueCollidingFacet()));
        registry.register(ACCESS, V1, address(new AccessControl()));
        registry.register(FLIP, V1, address(flipping));
        registry.register(SHADOW, V1, address(new CoreShadowedSelectorFacet()));
        registry.setLatest(VALUE, V1);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    function _entries(bytes32 a, uint64 va) internal pure returns (RecipeEntry[] memory e) {
        e = new RecipeEntry[](2);
        e[0] = RecipeEntry({nameHash: LOUPE, version: V1, exclude: new bytes4[](0)});
        e[1] = RecipeEntry({nameHash: a, version: va, exclude: new bytes4[](0)});
    }

    function _entries3(bytes32 a, uint64 va, bytes32 b, uint64 vb) internal pure returns (RecipeEntry[] memory e) {
        e = new RecipeEntry[](3);
        e[0] = RecipeEntry({nameHash: LOUPE, version: V1, exclude: new bytes4[](0)});
        e[1] = RecipeEntry({nameHash: a, version: va, exclude: new bytes4[](0)});
        e[2] = RecipeEntry({nameHash: b, version: vb, exclude: new bytes4[](0)});
    }

    function _noCuts() internal pure returns (FacetCut[] memory) {
        return new FacetCut[](0);
    }

    function _one(bytes4 s) internal pure returns (bytes4[] memory a) {
        a = new bytes4[](1);
        a[0] = s;
    }

    function _cut(address facet, FacetCutAction action, bytes4[] memory selectors)
        internal
        pure
        returns (FacetCut[] memory cuts)
    {
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: facet, action: action, functionSelectors: selectors});
    }

    function _loupeSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = 0x7a0ed627;
        s[1] = 0xadfca15e;
        s[2] = 0x52ef6b2c;
        s[3] = 0xcdffacc6;
    }

    function _facetsHash(address diamond) internal view returns (bytes32) {
        return keccak256(abi.encode(IDiamondLoupe(diamond).facets()));
    }

    function _marker(address diamond) internal view returns (uint256) {
        return uint256(vm.load(diamond, keccak256("lattice.test.core.marker")));
    }

    function _entry(bytes32 name, uint64 version, bytes4[] memory exclude) internal pure returns (RecipeEntry memory) {
        return RecipeEntry({nameHash: name, version: version, exclude: exclude});
    }

    /// @dev The `recipeHash` {ILatticeFactory.DiamondDeployed} carries for a loupe entry plus one registry
    ///      record, with no init: `keccak256(abi.encode(cuts, init, initCalldata))` over the applied cuts.
    function _recipeHash(bytes32 name, uint64 version) internal view returns (bytes32) {
        FacetCut[] memory applied = new FacetCut[](2);
        applied[0] = registry.getCut(LOUPE, V1);
        applied[1] = registry.getCut(name, version);
        return keccak256(abi.encode(applied, address(0), bytes("")));
    }

    /// @dev The `recipeHash` topic of the last {ILatticeFactory.DiamondDeployed} in `logs`.
    function _lastRecipeHash(Vm.Log[] memory logs) internal view returns (bytes32 recipeHash) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(factory) && logs[i].topics[0] == ILatticeFactory.DiamondDeployed.selector) {
                recipeHash = logs[i].topics[3];
            }
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            REGISTRY BINDING
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice F-1 (fixed): a registry address without code is refused at construction, like the zero address.
    ///         Such a factory could deploy custom-only recipes, but every recipe entry would revert with empty data,
    ///         a permanent misconfiguration of an immutable contract.
    function test_ConstructorRejectsCodelessRegistry() public {
        address codeless = makeAddr("noRegistry");
        vm.expectRevert(abi.encodeWithSelector(ILatticeFactory.LatticeFactory__InvalidRegistry.selector, codeless));
        new LatticeFactory(ILatticeRegistry(codeless), address(0), address(0));
    }

    /// @notice Registry-resolved cuts are TRUSTED: the factory refuses `exportSelectors()` only in custom cuts.
    ///         A factory bound to a non-canonical registry routes whatever that registry returns, including the
    ///         forbidden ERC-8153 selector. The trust boundary is the registry address fixed at construction.
    function test_HostileRegistryCutBypassesExportSelectorRefusal() public {
        CoreHostileRegistry hostile = new CoreHostileRegistry();
        address ping = address(new CorePingFacet());
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = CorePingFacet.ping.selector;
        selectors[1] = EXPORT_SELECTOR;
        hostile.configure(ping, FacetCutAction.Add, selectors);
        LatticeFactory hostileFactory = new LatticeFactory(ILatticeRegistry(address(hostile)), address(0), address(0));

        RecipeEntry[] memory entries = new RecipeEntry[](1);
        entries[0] = RecipeEntry({nameHash: PING, version: 0, exclude: new bytes4[](0)});
        address diamond = hostileFactory.deploy(
            entries, _cut(loupeFacet, FacetCutAction.Add, _loupeSelectors()), address(0), "", SALT
        );
        assertEq(IDiamondLoupe(diamond).facetAddress(EXPORT_SELECTOR), ping, "forbidden selector routed");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    RECIPE KINDS, COLLISIONS, CUT ORDER
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Two registry entries exporting the same selector abort the whole deploy.
    function test_RegistryRegistryCollisionReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(CannotAddFunctionToDiamondThatAlreadyExists.selector, CoreValueFacet.value.selector)
        );
        factory.deploy(_entries3(VALUE, V1, COLLIDE, V1), _noCuts(), address(0), "", SALT);
    }

    /// @notice The same entry twice collides with itself.
    function test_DuplicateEntryReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(CannotAddFunctionToDiamondThatAlreadyExists.selector, CoreValueFacet.value.selector)
        );
        factory.deploy(_entries3(VALUE, V1, VALUE, V1), _noCuts(), address(0), "", SALT);
    }

    /// @notice A pinned and a `latest` entry of one name collide even when they resolve to different versions.
    function test_PinnedAndLatestOfOneNameCollide() public {
        vm.prank(owner);
        registry.setLatest(VALUE, V2);
        vm.expectRevert(
            abi.encodeWithSelector(CannotAddFunctionToDiamondThatAlreadyExists.selector, CoreValueFacet.value.selector)
        );
        factory.deploy(_entries3(VALUE, V1, VALUE, 0), _noCuts(), address(0), "", SALT);
    }

    /// @notice A selector repeated inside ONE custom cut collides with itself.
    function test_DuplicateSelectorInsideOneCustomCutReverts() public {
        bytes4[] memory twice = new bytes4[](2);
        twice[0] = CorePongFacet.pong.selector;
        twice[1] = CorePongFacet.pong.selector;
        FacetCut[] memory cuts = _cut(address(new CorePongFacet()), FacetCutAction.Add, twice);
        vm.expectRevert(
            abi.encodeWithSelector(CannotAddFunctionToDiamondThatAlreadyExists.selector, CorePongFacet.pong.selector)
        );
        factory.deploy(_entries(PING, V1), cuts, address(0), "", SALT);
    }

    /// @notice Custom cuts run after registry cuts, so a custom `Remove` can drop a registry-added selector
    ///         (any selector but the four loupe selectors).
    function test_CustomRemoveDropsRegistrySelector() public {
        FacetCut[] memory cuts = _cut(address(0), FacetCutAction.Remove, _one(CoreValueFacet.value.selector));
        address diamond = factory.deploy(_entries(VALUE, V1), cuts, address(0), "", SALT);
        assertEq(IDiamondLoupe(diamond).facetAddress(CoreValueFacet.value.selector), address(0), "removed");
    }

    /// @notice A custom cut pointing at an address without code aborts the deploy.
    function test_CustomCutToCodelessFacetReverts() public {
        address ghost = makeAddr("ghostFacet");
        FacetCut[] memory cuts = _cut(ghost, FacetCutAction.Add, _one(CorePongFacet.pong.selector));
        vm.expectRevert(abi.encodeWithSelector(NoBytecodeAtAddress.selector, ghost));
        factory.deploy(_entries(PING, V1), cuts, address(0), "", SALT);
    }

    /// @notice A custom cut with no selectors aborts the deploy.
    function test_CustomCutWithNoSelectorsReverts() public {
        FacetCut[] memory cuts = _cut(address(new CorePongFacet()), FacetCutAction.Add, new bytes4[](0));
        vm.expectRevert(NoSelectorsGivenToAdd.selector);
        factory.deploy(_entries(PING, V1), cuts, address(0), "", SALT);
    }

    /// @notice A registry entry may export the proxy's own `initialize` selector. The cut records it in the
    ///         loupe, but the proxy's own function shadows it: a call reaches {Lattice.initialize}, which refuses
    ///         a second initialization. Neither the registry nor the factory flags the shadowed selector.
    function test_ProxyShadowedSelectorIsCutButUnreachable() public {
        address diamond = factory.deploy(_entries(SHADOW, V1), _noCuts(), address(0), "", SALT);
        address shadowFacet = registry.get(SHADOW, V1).facet;

        assertEq(IDiamondLoupe(diamond).facetAddress(Lattice.initialize.selector), shadowFacet, "loupe lists it");
        assertEq(CoreShadowedSelectorFacet(diamond).shadowPing(), 31, "the facet's other selector routes");
        vm.expectRevert(InvalidInitialization.selector);
        Lattice(payable(diamond)).initialize(new FacetCut[](0), address(0), "");
    }

    /// @notice Registry drift in ANY entry of a mixed recipe aborts the deploy; the address stays free and the
    ///         same `(sender, salt)` deploys once the drift clears.
    function test_DriftMidRecipeRollsBackAndStaysRetryable() public {
        address predicted = factory.predict(address(this), SALT);
        flipping.flip();
        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__SelectorDrift.selector, address(flipping))
        );
        factory.deploy(_entries3(VALUE, V1, FLIP, V1), _noCuts(), address(0), "", SALT);
        assertEq(predicted.code.length, 0, "no code after a failed deploy");

        flipping.flip();
        assertEq(factory.deploy(_entries3(VALUE, V1, FLIP, V1), _noCuts(), address(0), "", SALT), predicted, "retry");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    INIT ADDRESS AND CALLDATA HANDLING
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice F-2 (fixed): `init == address(0)` with NON-empty calldata is refused by both entry points, so a
    ///         recipe that forgot its init address no longer deploys an uninitialized diamond. The check is argument
    ///         validation, so it also runs on `deploy`'s idempotent path.
    function test_ZeroInitWithCalldataReverts() public {
        bytes memory data = abi.encodeCall(CoreMarkerInit.init, (7));
        vm.expectRevert(ILatticeFactory.LatticeFactory__InitCalldataWithoutInit.selector);
        factory.deploy(_entries(VALUE, V1), _noCuts(), address(0), data, SALT);
        vm.expectRevert(ILatticeFactory.LatticeFactory__InitCalldataWithoutInit.selector);
        factory.deployStrict(_entries(VALUE, V1), _noCuts(), address(0), data, SALT);

        factory.deploy(_entries(VALUE, V1), _noCuts(), address(0), "", SALT);
        vm.expectRevert(ILatticeFactory.LatticeFactory__InitCalldataWithoutInit.selector);
        factory.deploy(_entries(VALUE, V1), _noCuts(), address(0), data, SALT);
    }

    /// @notice An init address without code aborts the deploy.
    function test_CodelessInitReverts() public {
        address ghost = makeAddr("ghostInit");
        vm.expectRevert(abi.encodeWithSelector(NoBytecodeAtAddress.selector, ghost));
        factory.deploy(_entries(VALUE, V1), _noCuts(), ghost, abi.encodeCall(CoreMarkerInit.init, (7)), SALT);
    }

    /// @notice An init's custom error bubbles out of the factory byte for byte, and nothing is left behind.
    function test_InitCustomErrorBubblesAndLeavesNoCode() public {
        address init = address(new CoreRevertingInit());
        vm.expectRevert(abi.encodeWithSelector(CoreRevertingInit.CoreInitRefused.selector, 42));
        factory.deploy(_entries(VALUE, V1), _noCuts(), init, abi.encodeCall(CoreRevertingInit.init, (42)), SALT);
        assertEq(factory.predict(address(this), SALT).code.length, 0, "rolled back");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                  CREATE2 PREDICTION AND CALLER ISOLATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice `predict` equals the standard CREATE2 formula over `keccak256(type(Lattice).creationCode)`, which
    ///         is exactly what `diamondInitCodeHash()` returns.
    function test_PredictMatchesCreate2OverLatticeCreationCode() public view {
        bytes32 s = keccak256(abi.encode(address(this), SALT));
        bytes32 initCodeHash = keccak256(type(Lattice).creationCode);
        assertEq(factory.diamondInitCodeHash(), initCodeHash, "diamondInitCodeHash");
        address expected =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), s, initCodeHash)))));
        assertEq(factory.predict(address(this), SALT), expected, "predict != CREATE2(keccak(creationCode))");
    }

    /// @notice ETH sent to a predicted address before deployment does not block the CREATE2, and the diamond
    ///         keeps it.
    function test_PrefundedPredictedAddressDeploysAndKeepsBalance() public {
        address predicted = factory.predict(address(this), SALT);
        vm.deal(predicted, 1 ether);
        address diamond = factory.deploy(_entries(VALUE, V1), _noCuts(), address(0), "", SALT);
        assertEq(diamond, predicted, "deployed at the prefunded address");
        assertEq(diamond.balance, 1 ether, "balance kept");
    }

    /// @notice A competing caller that reuses the victim's salt lands at its OWN address; the victim's predicted
    ///         address stays empty and deployable by the victim alone.
    function test_CompetingCallerCannotOccupyAnotherCallersAddress() public {
        address victim = makeAddr("victim");
        address attacker = makeAddr("attacker");
        address victimAddress = factory.predict(victim, SALT);

        vm.prank(attacker);
        address attackerDiamond = factory.deploy(_entries(VALUE, V2), _noCuts(), address(0), "", SALT);
        assertTrue(attackerDiamond != victimAddress, "salt is bound to the caller");
        assertEq(victimAddress.code.length, 0, "victim address untouched");

        vm.prank(victim);
        assertEq(factory.deploy(_entries(VALUE, V1), _noCuts(), address(0), "", SALT), victimAddress, "victim");
        assertEq(CoreValueFacet(victimAddress).value(), 1, "victim's own recipe");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                 OCCUPIED ADDRESSES, deployStrict AND THE RECIPE HASH
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice F-3 (by design for `deploy`): a repeat call for an occupied `(sender, salt)` with a DIFFERENT
    ///         recipe and a DIFFERENT init returns the existing diamond, runs neither the new cuts nor the new
    ///         init, emits nothing, and leaves the loupe unchanged. `deployStrict` is the entry point that reports
    ///         it (next test).
    function test_DeployOccupiedAddressIgnoresNewRecipeAndInit() public {
        address marker = address(new CoreMarkerInit());
        address first =
            factory.deploy(_entries(VALUE, V1), _noCuts(), marker, abi.encodeCall(CoreMarkerInit.init, (1)), SALT);
        bytes32 facetsBefore = _facetsHash(first);

        vm.recordLogs();
        address second = factory.deploy(
            _entries3(VALUE, V2, PING, V1), _noCuts(), marker, abi.encodeCall(CoreMarkerInit.init, (2)), SALT
        );

        assertEq(second, first, "same address returned");
        assertEq(vm.getRecordedLogs().length, 0, "no event");
        assertEq(_marker(first), 1, "second init never ran");
        assertEq(CoreValueFacet(first).value(), 1, "v1 still routed");
        assertEq(IDiamondLoupe(first).facetAddress(CorePingFacet.ping.selector), address(0), "new entry not cut");
        assertEq(_facetsHash(first), facetsBefore, "loupe unchanged");
    }

    /// @notice F-3 (fixed for strict callers): `deployStrict` on an occupied `(sender, salt)` reverts
    ///         `AlreadyDeployed(diamond)`, whichever entry point occupied it, and changes nothing.
    function test_DeployStrictRevertsOnOccupiedAddress() public {
        address first = factory.deployStrict(_entries(VALUE, V1), _noCuts(), address(0), "", SALT);
        assertEq(first, factory.predict(address(this), SALT), "strict deploy == predict");
        bytes32 facetsBefore = _facetsHash(first);

        vm.expectRevert(abi.encodeWithSelector(ILatticeFactory.LatticeFactory__AlreadyDeployed.selector, first));
        factory.deployStrict(_entries(VALUE, V1), _noCuts(), address(0), "", SALT);
        vm.expectRevert(abi.encodeWithSelector(ILatticeFactory.LatticeFactory__AlreadyDeployed.selector, first));
        factory.deployStrict(_entries3(VALUE, V2, PING, V1), _noCuts(), address(0), "", SALT);

        address other = factory.deploy(_entries(VALUE, V1), _noCuts(), address(0), "", keccak256("other"));
        vm.expectRevert(abi.encodeWithSelector(ILatticeFactory.LatticeFactory__AlreadyDeployed.selector, other));
        factory.deployStrict(_entries(VALUE, V1), _noCuts(), address(0), "", keccak256("other"));
        assertEq(_facetsHash(first), facetsBefore, "loupe unchanged");
    }

    /// @notice F-4 (#176 residual (b)): every user behind one shared forwarder reaches the factory with the same
    ///         `msg.sender`, so they share one salt namespace. Through `deploy` the second user silently receives
    ///         the FIRST user's diamond and admin (documented on {ILatticeFactory}); through `deployStrict` the
    ///         second user's call reverts instead.
    function test_SharedForwarderCallersShareOneNamespace() public {
        CoreForwarder forwarder = new CoreForwarder();
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address aci = address(new AccessControlInit());

        bytes memory aliceCall = abi.encodeCall(
            ILatticeFactory.deployStrict,
            (_entries(ACCESS, V1), _noCuts(), aci, abi.encodeCall(AccessControlInit.init, (alice)), SALT)
        );
        bytes memory bobStrict = abi.encodeCall(
            ILatticeFactory.deployStrict,
            (_entries(ACCESS, V1), _noCuts(), aci, abi.encodeCall(AccessControlInit.init, (bob)), SALT)
        );
        bytes memory bobLegacy = abi.encodeCall(
            ILatticeFactory.deploy,
            (_entries(ACCESS, V1), _noCuts(), aci, abi.encodeCall(AccessControlInit.init, (bob)), SALT)
        );

        vm.prank(alice);
        address aliceDiamond = abi.decode(forwarder.forward(address(factory), aliceCall), (address));

        vm.expectRevert(abi.encodeWithSelector(ILatticeFactory.LatticeFactory__AlreadyDeployed.selector, aliceDiamond));
        vm.prank(bob);
        forwarder.forward(address(factory), bobStrict);

        vm.prank(bob);
        address bobDiamond = abi.decode(forwarder.forward(address(factory), bobLegacy), (address));
        assertEq(bobDiamond, aliceDiamond, "deploy hands bob alice's diamond");
        assertTrue(AccessControl(bobDiamond).hasRole(DEFAULT_ADMIN_ROLE, alice), "alice is the admin");
        assertFalse(AccessControl(bobDiamond).hasRole(DEFAULT_ADMIN_ROLE, bob), "bob holds nothing");
    }

    /// @notice F-5 (fixed, #176 residual (a)): a `version == 0` entry still resolves `latest` when the transaction
    ///         EXECUTES through `deploy`, but `DiamondDeployed` now carries the hash of the applied cuts, so an
    ///         indexer sees that v2 was cut although the signer saw v1. `deployStrict` refuses the unpinned entry.
    function test_LatestMovedBeforeInclusionShowsInTheRecipeHash() public {
        RecipeEntry[] memory signed = _entries(VALUE, 0); // signed while latest(VALUE) == v1
        bytes32 signerExpected = _recipeHash(VALUE, V1);

        vm.prank(owner);
        registry.setLatest(VALUE, V2); // moved before the deploy is included

        vm.expectRevert(abi.encodeWithSelector(ILatticeFactory.LatticeFactory__UnpinnedEntry.selector, VALUE));
        factory.deployStrict(signed, _noCuts(), address(0), "", SALT);

        vm.recordLogs();
        address diamond = factory.deploy(signed, _noCuts(), address(0), "", SALT);
        bytes32 emitted = _lastRecipeHash(vm.getRecordedLogs());

        assertEq(CoreValueFacet(diamond).value(), 2, "the diamond got v2");
        assertEq(emitted, _recipeHash(VALUE, V2), "the event names the applied recipe");
        assertTrue(emitted != signerExpected, "and it differs from the one the signer expected");
    }

    /// @notice The recipe hash commits to the applied cuts, the init and the init calldata: the same cuts with
    ///         another init argument give another hash, and the event's `init` and `salt` are the call's.
    function test_RecipeHashCommitsToCutsInitAndCalldata() public {
        address marker = address(new CoreMarkerInit());
        FacetCut[] memory applied = new FacetCut[](2);
        applied[0] = registry.getCut(LOUPE, V1);
        applied[1] = registry.getCut(VALUE, V1);

        for (uint256 m = 1; m <= 2; ++m) {
            bytes memory data = abi.encodeCall(CoreMarkerInit.init, (m));
            bytes32 salt = bytes32(m);
            address predicted = factory.predict(address(this), salt);
            vm.expectEmit(true, true, true, true, address(factory));
            emit ILatticeFactory.DiamondDeployed(
                predicted, address(this), keccak256(abi.encode(applied, marker, data)), salt, marker
            );
            factory.deployStrict(_entries(VALUE, V1), _noCuts(), marker, data, salt);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         RECIPE ENTRY EXCLUSIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice An excluded selector is not cut; the entry's other selectors are, in export order, and the
    ///         recipe hash covers the post-exclusion cut.
    function test_ExcludeDropsSelectorsFromARegistryEntry() public {
        bytes4[] memory exclude = _one(Lattice.initialize.selector);
        RecipeEntry[] memory entries = new RecipeEntry[](2);
        entries[0] = _entry(LOUPE, V1, new bytes4[](0));
        entries[1] = _entry(SHADOW, V1, exclude);

        FacetCut[] memory applied = new FacetCut[](2);
        applied[0] = registry.getCut(LOUPE, V1);
        applied[1] = registry.getCut(SHADOW, V1);
        applied[1].functionSelectors = _one(CoreShadowedSelectorFacet.shadowPing.selector);

        vm.recordLogs();
        address diamond = factory.deployStrict(entries, _noCuts(), address(0), "", SALT);
        assertEq(_lastRecipeHash(vm.getRecordedLogs()), keccak256(abi.encode(applied, address(0), bytes(""))));

        address shadowFacet = registry.get(SHADOW, V1).facet;
        assertEq(IDiamondLoupe(diamond).facetAddress(Lattice.initialize.selector), address(0), "excluded");
        assertEq(IDiamondLoupe(diamond).facetAddress(CoreShadowedSelectorFacet.shadowPing.selector), shadowFacet);
        assertEq(IDiamondLoupe(diamond).facetFunctionSelectors(shadowFacet).length, 1, "one selector left");
    }

    /// @notice Exclusion lets two registry entries that export one selector coexist: the entry that does not
    ///         serve it excludes it. Without the exclusion the deploy aborts on the collision; excluding every
    ///         selector of an entry leaves an empty `Add` cut, which DiamondLib refuses.
    function test_ExcludeResolvesARegistryRegistryCollision() public {
        bytes32 superset = keccak256("lattice.CoreValueSuperset");
        address supersetFacet = RawCode.exporter(abi.encodePacked(CoreValueFacet.value.selector, bytes4(0x22222222)));
        vm.prank(owner);
        registry.register(superset, V1, supersetFacet);

        RecipeEntry[] memory entries = new RecipeEntry[](3);
        entries[0] = _entry(LOUPE, V1, new bytes4[](0));
        entries[1] = _entry(VALUE, V1, new bytes4[](0));
        entries[2] = _entry(superset, V1, new bytes4[](0));
        vm.expectRevert(
            abi.encodeWithSelector(CannotAddFunctionToDiamondThatAlreadyExists.selector, CoreValueFacet.value.selector)
        );
        factory.deploy(entries, _noCuts(), address(0), "", SALT);

        entries[2] = _entry(COLLIDE, V1, _one(CoreValueFacet.value.selector)); // COLLIDE exports only `value()`
        vm.expectRevert(NoSelectorsGivenToAdd.selector);
        factory.deploy(entries, _noCuts(), address(0), "", SALT);

        entries[2] = _entry(superset, V1, _one(CoreValueFacet.value.selector));
        address diamond = factory.deployStrict(entries, _noCuts(), address(0), "", SALT);
        assertEq(CoreValueFacet(diamond).value(), 1, "VALUE serves value()");
        assertEq(IDiamondLoupe(diamond).facetAddress(0x22222222), supersetFacet, "the rest of the superset is cut");
    }

    /// @notice A selector the entry's pinned export does not contain, or the same selector excluded twice, is
    ///         refused on both entry points: a typo never silently leaves a selector cut.
    function test_ExcludeOfASelectorNotExportedReverts() public {
        RecipeEntry[] memory entries = new RecipeEntry[](2);
        entries[0] = _entry(LOUPE, V1, new bytes4[](0));
        entries[1] = _entry(VALUE, V1, _one(CorePingFacet.ping.selector));
        vm.expectRevert(
            abi.encodeWithSelector(
                ILatticeFactory.LatticeFactory__ExcludedSelectorNotExported.selector, VALUE, CorePingFacet.ping.selector
            )
        );
        factory.deployStrict(entries, _noCuts(), address(0), "", SALT);

        bytes4[] memory twice = new bytes4[](2);
        twice[0] = Lattice.initialize.selector;
        twice[1] = Lattice.initialize.selector;
        entries[1] = _entry(SHADOW, V1, twice);
        vm.expectRevert(
            abi.encodeWithSelector(
                ILatticeFactory.LatticeFactory__ExcludedSelectorNotExported.selector,
                SHADOW,
                Lattice.initialize.selector
            )
        );
        factory.deploy(entries, _noCuts(), address(0), "", SALT);
        assertEq(factory.predict(address(this), SALT).code.length, 0, "nothing deployed");
    }

    /// @notice Excluding a loupe selector from the loupe entry leaves it uncovered, so the deploy is refused.
    function test_ExcludeOfALoupeSelectorFailsLoupeCoverage() public {
        RecipeEntry[] memory entries = new RecipeEntry[](1);
        entries[0] = _entry(LOUPE, V1, _one(0x52ef6b2c));
        vm.expectRevert(
            abi.encodeWithSelector(ILatticeFactory.LatticeFactory__MissingLoupeCoverage.selector, bytes4(0x52ef6b2c))
        );
        factory.deployStrict(entries, _noCuts(), address(0), "", SALT);
    }

    /// @notice Exclusions apply to `latest` entries too, against the version `latest` resolves to: the
    ///         exclusion sits on a version-0 entry, and the excluded selector is not routed.
    function test_ExcludeAppliesToLatestEntries() public {
        vm.prank(owner);
        registry.setLatest(SHADOW, V1);

        RecipeEntry[] memory entries = new RecipeEntry[](3);
        entries[0] = _entry(LOUPE, V1, new bytes4[](0));
        entries[1] = _entry(VALUE, 0, new bytes4[](0));
        entries[2] = _entry(SHADOW, 0, _one(Lattice.initialize.selector));
        address diamond = factory.deploy(entries, _noCuts(), address(0), "", SALT);
        assertEq(CoreValueFacet(diamond).value(), 1, "latest resolved");
        assertEq(IDiamondLoupe(diamond).facetAddress(Lattice.initialize.selector), address(0), "excluded");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    INITIALIZATION AUTHORITY AND CALLBACKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice F-6 (documented on {ILatticeFactory.deploy}): {Lattice.initialize} is called BY THE FACTORY, so an
    ///         init that grants `msg.sender` grants the factory. The factory has no call surface to use the role,
    ///         so the diamond ends up with an admin nobody can exercise, and the deployer holds nothing. No shipped
    ///         Init does this (they take an explicit admin); it is a footgun for consumer inits.
    function test_InitGrantingMsgSenderGrantsTheFactory() public {
        address init = address(new CoreGrantSenderInit());
        address diamond =
            factory.deploy(_entries(ACCESS, V1), _noCuts(), init, abi.encodeCall(CoreGrantSenderInit.init, ()), SALT);

        assertTrue(AccessControl(diamond).hasRole(DEFAULT_ADMIN_ROLE, address(factory)), "factory became admin");
        assertFalse(AccessControl(diamond).hasRole(DEFAULT_ADMIN_ROLE, address(this)), "deployer is not admin");
    }

    /// @notice With an explicit admin (the shipped pattern), the factory ends up holding no role.
    function test_ExplicitAdminInitLeavesFactoryWithoutRole() public {
        address init = address(new AccessControlInit());
        address diamond = factory.deploy(
            _entries(ACCESS, V1), _noCuts(), init, abi.encodeCall(AccessControlInit.init, (admin)), SALT
        );

        assertTrue(AccessControl(diamond).hasRole(DEFAULT_ADMIN_ROLE, admin), "admin seeded");
        assertFalse(AccessControl(diamond).hasRole(DEFAULT_ADMIN_ROLE, address(factory)), "factory holds no role");
    }

    /// @notice F-7 (documented on {ILatticeFactory.DiamondDeployed}): an init that self-destructs the diamond is
    ///         accepted, and `deploy` still returns the address and emits `DiamondDeployed`. No in-transaction
    ///         check can see the deletion: the diamond was created in the same transaction, so EIP-6780 deletes
    ///         it only when that transaction ends, after `deploy` returns. Forge runs each top-level call as its
    ///         own transaction (`isolate`, on by default), so the next `deploy` for the same `(sender, salt)`
    ///         sees the empty address, creates the diamond AGAIN with another recipe, and emits a second
    ///         `DiamondDeployed` for the same address.
    ///         The test contract's own `code.length` read is not a reliable witness of the deletion, so the test
    ///         asserts on the two events and on the second recipe's routing.
    function test_SelfDestructingInitCanEmitDiamondDeployedTwice() public {
        address init = address(new CoreSelfDestructInit());
        address predicted = factory.predict(address(this), SALT);

        vm.expectEmit(true, true, false, true, address(factory));
        emit ILatticeFactory.DiamondDeployed(predicted, address(this), bytes32(0), SALT, init);
        address diamond =
            factory.deploy(_entries(VALUE, V1), _noCuts(), init, abi.encodeCall(CoreSelfDestructInit.init, ()), SALT);
        assertEq(diamond, predicted, "address returned as if deployed");

        // Same sender and salt, another recipe and no init: the address was emptied at the end of the first
        // transaction, so this is a fresh CREATE2, not the idempotent return.
        vm.recordLogs();
        address again = factory.deploy(_entries(VALUE, V2), _noCuts(), address(0), "", SALT);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(again, predicted, "same address");
        uint256 deployedEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(factory) && logs[i].topics[0] == ILatticeFactory.DiamondDeployed.selector) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), predicted, "second event names the address");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), address(this), "same deployer");
                ++deployedEvents;
            }
        }
        assertEq(deployedEvents, 1, "a second DiamondDeployed for the same address");
        assertEq(CoreValueFacet(again).value(), 2, "the second recipe (v2) is live at the address");
    }

    /// @notice An init that re-enters the proxy's `initialize` is refused by the initializer guard, and the whole
    ///         deploy rolls back.
    function test_ReinitializeFromInitRollsBackTheDeploy() public {
        address init = address(new CoreReinitializeInit());
        FacetCut[] memory extra =
            _cut(address(new CorePongFacet()), FacetCutAction.Add, _one(CorePongFacet.pong.selector));
        vm.expectRevert(InvalidInitialization.selector);
        factory.deploy(_entries(VALUE, V1), _noCuts(), init, abi.encodeCall(CoreReinitializeInit.init, (extra)), SALT);
        assertEq(factory.predict(address(this), SALT).code.length, 0, "rolled back");
    }

    /// @notice An init that re-enters `factory.deploy` deploys a CHILD whose salt is bound to the new diamond (the
    ///         nested `msg.sender`), never to the outer deployer, so it cannot land on the outer address or on any
    ///         address the deployer could predict for itself. The factory keeps no state, so re-entry is benign.
    function test_NestedDeployFromInitIsBoundToTheDiamond() public {
        address init = address(new CoreNestedDeployInit());
        FacetCut[] memory childCuts = _cut(loupeFacet, FacetCutAction.Add, _loupeSelectors());
        address outer = factory.deploy(
            _entries(VALUE, V1),
            _noCuts(),
            init,
            abi.encodeCall(CoreNestedDeployInit.init, (ILatticeFactory(address(factory)), childCuts, SALT)),
            SALT
        );

        address child = address(uint160(uint256(vm.load(outer, keccak256("lattice.test.core.child")))));
        assertEq(child, factory.predict(outer, SALT), "child salt bound to the outer diamond");
        assertTrue(child != outer && child != factory.predict(address(this), keccak256("anything")), "isolated");
        assertTrue(child.code.length != 0, "child deployed");
        assertEq(CoreValueFacet(outer).value(), 1, "outer diamond intact");
    }
}
