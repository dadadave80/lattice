// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CannotAddFunctionToDiamondThatAlreadyExists, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DiamondFactory} from "@lattice/factory/DiamondFactory.sol";
import {IDiamondFactory, RecipeEntry} from "@lattice/interfaces/factory/IDiamondFactory.sol";
import {ILatticeRegistry} from "@lattice/interfaces/registry/ILatticeRegistry.sol";
import {LatticeRegistry} from "@lattice/registry/LatticeRegistry.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                               MOCK FACETS
//////////////////////////////////////////////////////////////////////////*//

/// @dev Shared dispatch surface of the two versioned mock facets below.
interface IMockValue {
    function value() external pure returns (uint256);
}

/// @dev "v1" of a curated ERC-8153 facet: `value()` returns 1. Distinct bytecode (and therefore codehash)
///      from {MockValueV2Facet}, so registering both exercises real two-version registry resolution.
contract MockValueV1Facet {
    function value() external pure returns (uint256) {
        return 1;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(MockValueV1Facet.value.selector);
    }
}

/// @dev "v2" of the same curated facet: `value()` returns 2 — behaviorally distinguishable through a diamond.
contract MockValueV2Facet {
    function value() external pure returns (uint256) {
        return 2;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(MockValueV2Facet.value.selector);
    }
}

/// @dev A plain facet with NO ERC-8153 surface — cut into diamonds the classic way via `customCuts`.
contract MockPongFacet {
    function pong() external pure returns (uint256) {
        return 42;
    }
}

/// @dev A second curated ERC-8153 facet, selector-disjoint from {MockValueV1Facet} — for multi-entry recipes.
contract MockPingFacet {
    function ping() external pure returns (uint256) {
        return 7;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(MockPingFacet.ping.selector);
    }
}

/// @dev A second plain facet with NO ERC-8153 surface — for multi-custom-cut recipes.
contract MockEchoFacet {
    function echo() external pure returns (uint256) {
        return 9;
    }
}

/// @dev IMPURE ERC-8153 facet: {flip} changes the live `exportSelectors()` blob AFTER registration pinned it,
///      without changing the codehash — the exact drift the registry's selector pin (not its code pin) catches.
contract MockFlippingFacet {
    bool public flipped;

    function flip() external {
        flipped = !flipped;
    }

    function exportSelectors() external view returns (bytes memory) {
        return flipped ? abi.encodePacked(bytes4(0xAAAAAAAA)) : abi.encodePacked(bytes4(0x11111111));
    }
}

/// @dev Initializer whose `init()` always reverts — the deploy-atomicity fixture.
contract MockRevertingInit {
    function init() external pure {
        revert("init failed");
    }
}

/// @notice BTT-style unit suite for the stateless {DiamondFactory} (issue #120 PR 1): registry-resolved
///         recipe entries, classic custom cuts, CREATE2 determinism, idempotency, and revert propagation.
contract DiamondFactoryTest is Test {
    LatticeRegistry internal registry;
    DiamondFactory internal factory;

    address internal owner = makeAddr("registryOwner");

    bytes32 internal constant NAME = keccak256("lattice.MockValue");
    bytes32 internal constant NAME_PING = keccak256("lattice.MockPing");
    bytes32 internal constant SALT = keccak256("diamond-factory-salt");

    /// @dev The ERC-8153 `exportSelectors()` selector — forbidden in any custom cut.
    bytes4 internal constant EXPORT_SELECTOR = bytes4(0x0ef22643);

    function setUp() public {
        registry = new LatticeRegistry(owner);
        factory = new DiamondFactory(registry);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Pack a semver triple the way {LatticeRegistry} documents: `major<<48 | minor<<24 | patch`.
    function _v(uint16 major, uint24 minor, uint24 patch) internal pure returns (uint64) {
        return (uint64(major) << 48) | (uint64(minor) << 24) | uint64(patch);
    }

    /// @dev Single-entry recipe for `(NAME, version)`.
    function _entries(uint64 version) internal pure returns (RecipeEntry[] memory entries) {
        entries = new RecipeEntry[](1);
        entries[0] = RecipeEntry({nameHash: NAME, version: version});
    }

    /// @dev Single classic Add cut for `facet` exposing exactly `selectors`.
    function _customCut(address facet, bytes4[] memory selectors) internal pure returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: selectors});
    }

    function _noEntries() internal pure returns (RecipeEntry[] memory entries) {
        entries = new RecipeEntry[](0);
    }

    function _noCuts() internal pure returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](0);
    }

    function _registerV1() internal returns (address facet) {
        facet = address(new MockValueV1Facet());
        vm.prank(owner);
        registry.register(NAME, _v(1, 0, 0), facet);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              CONSTRUCTION
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConstructorSetsRegistry() public view {
        assertEq(address(factory.registry()), address(registry));
    }

    function test_ConstructorRevertsOnZeroRegistry() public {
        vm.expectRevert(IDiamondFactory.DiamondFactory__ZeroRegistry.selector);
        new DiamondFactory(ILatticeRegistry(address(0)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       DEPLOY — registry resolution
    //////////////////////////////////////////////////////////////////////////*//

    function test_DeployResolvesPinnedEntryAndDispatches() public {
        _registerV1();

        address diamond = factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);

        assertEq(diamond, factory.predict(address(this), SALT), "deploy != predict");
        assertTrue(diamond.code.length != 0, "diamond has code");
        assertEq(IMockValue(diamond).value(), 1, "registry-resolved selector dispatches");
    }

    function test_DeployVersionZeroResolvesLatest() public {
        _registerV1();
        address v2Facet = address(new MockValueV2Facet());
        vm.prank(owner);
        registry.register(NAME, _v(2, 0, 0), v2Facet);
        vm.prank(owner);
        registry.setLatest(NAME, _v(2, 0, 0));

        address diamond = factory.deploy(_entries(0), _noCuts(), address(0), "", SALT);

        // The produced diamond dispatches v2 behavior, and the resolved cut is the v2 facet.
        assertEq(IMockValue(diamond).value(), 2, "version 0 resolves latest (v2)");
        assertEq(registry.getCut(NAME, _v(2, 0, 0)).facetAddress, v2Facet, "latest cut is the v2 facet");
    }

    function test_DeployPinnedVersionWinsOverLatest() public {
        _registerV1();
        address v2Facet = address(new MockValueV2Facet());
        vm.prank(owner);
        registry.register(NAME, _v(2, 0, 0), v2Facet);
        vm.prank(owner);
        registry.setLatest(NAME, _v(2, 0, 0));

        // A nonzero pin resolves that exact version even while `latest` points elsewhere.
        address diamond = factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);

        assertEq(IMockValue(diamond).value(), 1, "pinned v1 wins over latest v2");
    }

    function test_DeployMultipleEntriesAndMultipleCustomCuts() public {
        _registerV1();
        address pingFacet = address(new MockPingFacet());
        vm.prank(owner);
        registry.register(NAME_PING, _v(1, 0, 0), pingFacet);

        RecipeEntry[] memory entries = new RecipeEntry[](2);
        entries[0] = RecipeEntry({nameHash: NAME, version: _v(1, 0, 0)});
        entries[1] = RecipeEntry({nameHash: NAME_PING, version: _v(1, 0, 0)});

        bytes4[] memory pongSelectors = new bytes4[](1);
        pongSelectors[0] = MockPongFacet.pong.selector;
        bytes4[] memory echoSelectors = new bytes4[](1);
        echoSelectors[0] = MockEchoFacet.echo.selector;
        FacetCut[] memory customCuts = new FacetCut[](2);
        customCuts[0] = FacetCut(address(new MockPongFacet()), FacetCutAction.Add, pongSelectors);
        customCuts[1] = FacetCut(address(new MockEchoFacet()), FacetCutAction.Add, echoSelectors);

        address diamond = factory.deploy(entries, customCuts, address(0), "", SALT);

        // Every selector from every position of BOTH arrays dispatches — pins the cuts-array index math.
        assertEq(IMockValue(diamond).value(), 1, "entries[0] dispatches");
        assertEq(MockPingFacet(diamond).ping(), 7, "entries[1] dispatches");
        assertEq(MockPongFacet(diamond).pong(), 42, "customCuts[0] dispatches");
        assertEq(MockEchoFacet(diamond).echo(), 9, "customCuts[1] dispatches");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         DEPLOY — custom cuts
    //////////////////////////////////////////////////////////////////////////*//

    function test_DeployCustomCutsOnly() public {
        MockPongFacet pongFacet = new MockPongFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockPongFacet.pong.selector;

        address diamond = factory.deploy(_noEntries(), _customCut(address(pongFacet), selectors), address(0), "", SALT);

        assertEq(MockPongFacet(diamond).pong(), 42, "custom cut dispatches");
    }

    function test_DeployMixedEntriesAndCustomCuts() public {
        _registerV1();
        MockPongFacet pongFacet = new MockPongFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockPongFacet.pong.selector;

        address diamond =
            factory.deploy(_entries(_v(1, 0, 0)), _customCut(address(pongFacet), selectors), address(0), "", SALT);

        assertEq(IMockValue(diamond).value(), 1, "registry entry dispatches");
        assertEq(MockPongFacet(diamond).pong(), 42, "appended custom cut dispatches");
    }

    function test_DeployRevertsOnExportSelectorInCustomCut() public {
        MockPongFacet pongFacet = new MockPongFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = EXPORT_SELECTOR;

        vm.expectRevert(IDiamondFactory.DiamondFactory__ExportSelectorForbidden.selector);
        factory.deploy(_noEntries(), _customCut(address(pongFacet), selectors), address(0), "", SALT);
    }

    function test_DeployRevertsOnBuriedExportSelectorInCustomCut() public {
        MockPongFacet pongFacet = new MockPongFacet();
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = MockPongFacet.pong.selector;
        selectors[1] = EXPORT_SELECTOR; // buried after a legitimate selector — still refused, never stripped

        vm.expectRevert(IDiamondFactory.DiamondFactory__ExportSelectorForbidden.selector);
        factory.deploy(_noEntries(), _customCut(address(pongFacet), selectors), address(0), "", SALT);
    }

    function test_DeployRevertsOnEmptyRecipe() public {
        vm.expectRevert(IDiamondFactory.DiamondFactory__EmptyRecipe.selector);
        factory.deploy(_noEntries(), _noCuts(), address(0), "", SALT);
    }

    function test_DeployRevertsOnSelectorCollisionWithRegistryCut() public {
        _registerV1();

        // A custom Add carrying a selector the registry cut already added — EIP-2535's one-owner-per-selector
        // invariant makes the whole deploy abort, the intended fail-safe.
        address collidingFacet = address(new MockValueV2Facet());
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockValueV1Facet.value.selector;

        vm.expectRevert(
            abi.encodeWithSelector(
                CannotAddFunctionToDiamondThatAlreadyExists.selector, MockValueV1Facet.value.selector
            )
        );
        factory.deploy(_entries(_v(1, 0, 0)), _customCut(collidingFacet, selectors), address(0), "", SALT);
    }

    function test_CustomReplaceCutRePointsRegistrySelector() public {
        _registerV1();

        // Custom cuts run AFTER the registry cuts, so a deliberate custom `Replace` re-points a selector the
        // registry cut just added — the deployer customizing their own diamond, by design.
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = MockValueV1Facet.value.selector;
        FacetCut[] memory customCuts = new FacetCut[](1);
        customCuts[0] = FacetCut(address(new MockValueV2Facet()), FacetCutAction.Replace, selectors);

        address diamond = factory.deploy(_entries(_v(1, 0, 0)), customCuts, address(0), "", SALT);

        assertEq(IMockValue(diamond).value(), 2, "custom Replace re-points the registry selector");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     CREATE2 — idempotency + predict
    //////////////////////////////////////////////////////////////////////////*//

    function test_DeployIsIdempotentForSameSenderAndSalt() public {
        _registerV1();
        address first = factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);

        // Second identical deploy returns the SAME address, does not revert, and emits nothing new.
        vm.recordLogs();
        address second = factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);
        assertEq(second, first, "idempotent return");
        assertEq(vm.getRecordedLogs().length, 0, "re-deploy must not emit");
    }

    function test_IdempotentReturnIgnoresNewRecipeAndSkipsResolution() public {
        _registerV1();
        address first = factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);

        // The CREATE2 address commits to (sender, salt) ONLY, never to the recipe: a repeat call with a
        // recipe that could not deploy fresh (unregistered name) still returns the existing diamond —
        // resolution is skipped entirely and the original wiring is untouched. Distinct recipes need
        // distinct salts.
        RecipeEntry[] memory unregistered = new RecipeEntry[](1);
        unregistered[0] = RecipeEntry({nameHash: keccak256("lattice.Unregistered"), version: _v(9, 0, 0)});
        address second = factory.deploy(unregistered, _noCuts(), address(0), "", SALT);

        assertEq(second, first, "existing diamond returned");
        assertEq(IMockValue(first).value(), 1, "original wiring untouched");
    }

    function test_DeployRefusesExportSelectorEvenWhenAlreadyDeployed() public {
        _registerV1();
        factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);

        // Argument validation precedes the idempotent return: a forbidden custom cut is refused even though
        // the diamond already exists and nothing would be cut — an invalid recipe is never quietly
        // "accepted" against an occupied address.
        address pongFacet = address(new MockPongFacet());
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = EXPORT_SELECTOR;
        vm.expectRevert(IDiamondFactory.DiamondFactory__ExportSelectorForbidden.selector);
        factory.deploy(_entries(_v(1, 0, 0)), _customCut(pongFacet, selectors), address(0), "", SALT);
    }

    function test_PredictParityAcrossSendersAndSalts() public {
        _registerV1();
        address deployed = factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);
        assertEq(deployed, factory.predict(address(this), SALT), "predict parity");

        // A different sender lands at a different address (sender is folded into the salt).
        address other = makeAddr("otherDeployer");
        assertTrue(factory.predict(other, SALT) != deployed, "sender-distinct address");
        vm.prank(other);
        address otherDeployed = factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);
        assertEq(otherDeployed, factory.predict(other, SALT), "predict parity for other sender");

        // A different salt lands at a different address for the same sender.
        assertTrue(factory.predict(address(this), keccak256("another-salt")) != deployed, "salt-distinct address");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     REGISTRY REVERT PROPAGATION
    //////////////////////////////////////////////////////////////////////////*//

    function test_DeployBubblesRecordNotFoundForUnregisteredName() public {
        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordNotFound.selector, NAME, _v(1, 0, 0))
        );
        factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);
    }

    function test_DeployBubblesLatestUnsetForVersionZero() public {
        _registerV1(); // registered, but setLatest never called

        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__LatestUnset.selector, NAME));
        factory.deploy(_entries(0), _noCuts(), address(0), "", SALT);
    }

    function test_DeployBubblesCodeDriftForEtchedFacet() public {
        address facet = _registerV1();

        // Simulate a metamorphic code swap at the registered address — getCut's live code pin must fire.
        vm.etch(facet, hex"600160005500");

        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__CodeDrift.selector, facet));
        factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);
    }

    function test_DeployBubblesSelectorDriftForFlippedFacet() public {
        address facet = address(new MockFlippingFacet());
        vm.prank(owner);
        registry.register(NAME, _v(1, 0, 0), facet); // pins keccak256 of blob A

        // Same codehash, different live export — the selector pin (not the code pin) must fire.
        MockFlippingFacet(facet).flip();

        vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__SelectorDrift.selector, facet));
        factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INIT ATOMICITY
    //////////////////////////////////////////////////////////////////////////*//

    function test_DeployRevertsAtomicallyOnInitRevertAndStaysRetryable() public {
        _registerV1();
        address predicted = factory.predict(address(this), SALT);
        address revertingInit = address(new MockRevertingInit());

        // The init delegatecall reverts inside {Diamond.initialize}; DiamondLib bubbles the raw reason and
        // the whole deploy — CREATE2 included — unwinds.
        vm.expectRevert("init failed");
        factory.deploy(
            _entries(_v(1, 0, 0)), _noCuts(), revertingInit, abi.encodeCall(MockRevertingInit.init, ()), SALT
        );
        assertEq(predicted.code.length, 0, "CREATE2 address left unoccupied");

        // The same (sender, salt) stays retryable with a working recipe, landing at the SAME address.
        address diamond = factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);
        assertEq(diamond, predicted, "retry lands at the predicted address");
        assertEq(IMockValue(diamond).value(), 1, "retried diamond is live");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENT
    //////////////////////////////////////////////////////////////////////////*//

    function test_DeployEmitsDiamondDeployed() public {
        _registerV1();
        address predicted = factory.predict(address(this), SALT);

        vm.expectEmit(true, true, false, true);
        emit IDiamondFactory.DiamondDeployed(predicted, address(this), SALT);
        factory.deploy(_entries(_v(1, 0, 0)), _noCuts(), address(0), "", SALT);
    }
}
