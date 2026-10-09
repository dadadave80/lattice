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
    CoreValueFacet
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
///         binding, recipe kinds and selector collisions, CREATE2 prediction against the real {Lattice}
///         creation code, caller/salt isolation, occupied-address reuse, initialization authority, and malicious
///         init callbacks.
/// @dev Tests named `test_Finding_*` pin behaviour the #176 design work should change (most of it is what the
///      joint `deployStrict` PR addresses). They pass today on purpose; see
///      docs/security/registry-factory-threat-model.md.
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
        e[0] = RecipeEntry({nameHash: LOUPE, version: V1});
        e[1] = RecipeEntry({nameHash: a, version: va});
    }

    function _entries3(bytes32 a, uint64 va, bytes32 b, uint64 vb) internal pure returns (RecipeEntry[] memory e) {
        e = new RecipeEntry[](3);
        e[0] = RecipeEntry({nameHash: LOUPE, version: V1});
        e[1] = RecipeEntry({nameHash: a, version: va});
        e[2] = RecipeEntry({nameHash: b, version: vb});
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

    //*//////////////////////////////////////////////////////////////////////////
    //                            REGISTRY BINDING
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice FINDING (F-1): the constructor rejects only the zero registry, not a CODELESS one. Such a factory
    ///         deploys custom-only recipes, but every recipe entry reverts with empty data (Solidity's
    ///         no-code check on the `latest`/`getCut` call). It is a permanent misconfiguration of an immutable
    ///         contract; the joint PR can add a code-length check next to {LatticeFactory__ZeroRegistry}.
    function test_Finding_ConstructorAcceptsCodelessRegistry() public {
        LatticeFactory broken = new LatticeFactory(ILatticeRegistry(makeAddr("noRegistry")), address(0), address(0));

        address diamond = broken.deploy(
            new RecipeEntry[](0), _cut(loupeFacet, FacetCutAction.Add, _loupeSelectors()), address(0), "", SALT
        );
        assertTrue(diamond.code.length != 0, "custom-only recipes still deploy");

        RecipeEntry[] memory entries = new RecipeEntry[](1);
        entries[0] = RecipeEntry({nameHash: LOUPE, version: V1});
        vm.expectRevert(bytes(""));
        broken.deploy(entries, _noCuts(), address(0), "", keccak256("other"));
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
        entries[0] = RecipeEntry({nameHash: PING, version: 0});
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

    /// @notice FINDING (F-2): `init == address(0)` with NON-empty calldata succeeds and the calldata is silently
    ///         dropped (DiamondLib returns early on a zero init). A recipe that forgot its init address deploys
    ///         an uninitialized diamond without an error.
    function test_Finding_ZeroInitSilentlyDropsCalldata() public {
        address diamond =
            factory.deploy(_entries(VALUE, V1), _noCuts(), address(0), abi.encodeCall(CoreMarkerInit.init, (7)), SALT);
        assertEq(_marker(diamond), 0, "calldata dropped, nothing initialized");
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
    ///         also confirms the factory's private initcode hash (the value a `diamondInitCodeHash()` view would
    ///         return).
    function test_PredictMatchesCreate2OverLatticeCreationCode() public view {
        bytes32 s = keccak256(abi.encode(address(this), SALT));
        bytes32 initCodeHash = keccak256(type(Lattice).creationCode);
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
    //                   OCCUPIED ADDRESSES (deployStrict inputs)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice FINDING (F-3, what `deployStrict` addresses): a repeat call for an occupied `(sender, salt)` with a
    ///         DIFFERENT recipe and a DIFFERENT init returns the existing diamond, runs neither the new cuts nor
    ///         the new init, emits nothing, and leaves the loupe unchanged. The caller cannot tell from the call
    ///         that its recipe was ignored.
    function test_Finding_OccupiedAddressIgnoresNewRecipeAndInit() public {
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

    /// @notice FINDING (F-4, residual (b) in #176): every user behind one shared forwarder reaches the factory
    ///         with the same `msg.sender`, so they share one salt namespace. The second user's deploy returns the
    ///         FIRST user's diamond, silently, with the first user's admin.
    function test_Finding_SharedForwarderCallersShareOneNamespace() public {
        CoreForwarder forwarder = new CoreForwarder();
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        address aci = address(new AccessControlInit());

        bytes memory aliceCall = abi.encodeCall(
            ILatticeFactory.deploy,
            (_entries(ACCESS, V1), _noCuts(), aci, abi.encodeCall(AccessControlInit.init, (alice)), SALT)
        );
        bytes memory bobCall = abi.encodeCall(
            ILatticeFactory.deploy,
            (_entries(ACCESS, V1), _noCuts(), aci, abi.encodeCall(AccessControlInit.init, (bob)), SALT)
        );

        vm.prank(alice);
        address aliceDiamond = abi.decode(forwarder.forward(address(factory), aliceCall), (address));
        vm.prank(bob);
        address bobDiamond = abi.decode(forwarder.forward(address(factory), bobCall), (address));

        assertEq(bobDiamond, aliceDiamond, "bob receives alice's diamond");
        assertTrue(AccessControl(bobDiamond).hasRole(DEFAULT_ADMIN_ROLE, alice), "alice is the admin");
        assertFalse(AccessControl(bobDiamond).hasRole(DEFAULT_ADMIN_ROLE, bob), "bob holds nothing");
    }

    /// @notice FINDING (F-5, residual (a) in #176): a `version == 0` entry resolves `latest` when the transaction
    ///         EXECUTES. If the curator moves `latest` between signing and inclusion, the diamond gets the new
    ///         version, and `DiamondDeployed` carries only `(diamond, deployer, salt)`, so an indexer cannot tell
    ///         which version was cut.
    function test_Finding_LatestMovedBeforeInclusionIsInvisibleInTheEvent() public {
        RecipeEntry[] memory signed = _entries(VALUE, 0); // signed while latest(VALUE) == v1

        vm.prank(owner);
        registry.setLatest(VALUE, V2); // moved before the deploy is included

        vm.recordLogs();
        address diamond = factory.deploy(signed, _noCuts(), address(0), "", SALT);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory deployed = logs[logs.length - 1];

        assertEq(CoreValueFacet(diamond).value(), 2, "the diamond got v2, not the v1 the signer saw");
        assertEq(deployed.topics[0], ILatticeFactory.DiamondDeployed.selector, "last log is DiamondDeployed");
        assertEq(deployed.data, abi.encode(SALT), "event data carries only the salt: no recipe or version");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    INITIALIZATION AUTHORITY AND CALLBACKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice FINDING (F-6): {Lattice.initialize} is called BY THE FACTORY, so an init that grants `msg.sender`
    ///         grants the factory. The factory has no call surface to use the role, so the diamond ends up with
    ///         an admin nobody can exercise, and the deployer holds nothing. No shipped Init does this (they take
    ///         an explicit admin); it is a footgun for consumer inits.
    function test_Finding_InitGrantingMsgSenderGrantsTheFactory() public {
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

    /// @notice FINDING (F-7): an init that self-destructs the diamond is accepted, and `deploy` still returns the
    ///         address and emits `DiamondDeployed`; the factory never checks that the diamond survives its own
    ///         initialization. The diamond was created in the same transaction, so EIP-6780 deletes it when that
    ///         transaction ends. Forge runs each top-level call as its own transaction (`isolate`, on by
    ///         default), so the next `deploy` for the same `(sender, salt)` sees the empty address, creates the
    ///         diamond AGAIN with another recipe, and emits a second `DiamondDeployed` for the same address.
    ///         The test contract's own `code.length` read is not a reliable witness of the deletion, so the test
    ///         asserts on the two events and on the second recipe's routing.
    function test_Finding_SelfDestructingInitStillEmitsDiamondDeployed() public {
        address init = address(new CoreSelfDestructInit());
        address predicted = factory.predict(address(this), SALT);

        vm.expectEmit(true, true, false, true, address(factory));
        emit ILatticeFactory.DiamondDeployed(predicted, address(this), SALT);
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
