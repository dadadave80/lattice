// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {CoreMarkerInit, CoreRevertingInit, RawCode} from "@lattice-test/helpers/LatticeCoreMocks.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {ILatticeFactory, RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {Test} from "forge-std/Test.sol";

/// @title LatticeFactoryFuzz
/// @notice #176: stateless fuzz properties of {LatticeFactory}: CREATE2 prediction against the real {Lattice}
///         creation code, caller/salt isolation, atomic rollback and retry, the recipe-ignored idempotent return,
///         `deployStrict`'s single deploy, revert on reuse and refusal of `latest` entries, routing of fuzzed
///         pinned/latest/custom/mixed recipes, entry exclusions, loupe coverage, and the custom-cut refusal of
///         `exportSelectors()`.
contract LatticeFactoryFuzz is Test {
    LatticeRegistry internal registry;
    LatticeFactory internal factory;
    address internal owner = makeAddr("registryOwner");

    uint256 internal constant POOL = 6;
    bytes32 internal constant LOUPE = keccak256("lattice.DiamondLoupeFacet");
    uint64 internal constant V1 = 1 << 48;
    uint64 internal constant V2 = 2 << 48;

    bytes32 internal initCodeHash;
    address internal loupeFacet;

    /// @dev Registry facets: name i has v1 and v2 (both export the same `i + 1` selectors), latest = v2.
    bytes32[POOL] internal names;
    address[POOL] internal v1Facets;
    address[POOL] internal v2Facets;
    bytes[POOL] internal entryBlobs;
    /// @dev Custom-cut facets with their own disjoint selector sets.
    address[POOL] internal customFacets;
    bytes[POOL] internal customBlobs;

    function setUp() public {
        registry = new LatticeRegistry(owner);
        factory = new LatticeFactory(registry, address(0), address(0));
        initCodeHash = keccak256(type(Lattice).creationCode);
        loupeFacet = address(new DiamondLoupeFacet());

        vm.startPrank(owner);
        registry.register(LOUPE, V1, loupeFacet);
        for (uint256 i; i < POOL; ++i) {
            names[i] = keccak256(abi.encode("lattice.fuzz", i));
            entryBlobs[i] = RawCode.selectorBlob(keccak256(abi.encode("entry", i)), i + 1);
            v1Facets[i] = RawCode.exporter(entryBlobs[i]);
            v2Facets[i] = RawCode.deploy(abi.encodePacked(abi.encode(entryBlobs[i]), hex"02"));
            registry.register(names[i], V1, v1Facets[i]);
            registry.register(names[i], V2, v2Facets[i]);
            registry.setLatest(names[i], V2);
            customBlobs[i] = RawCode.selectorBlob(keccak256(abi.encode("custom", i)), i + 1);
            customFacets[i] = RawCode.exporter(customBlobs[i]);
        }
        vm.stopPrank();
    }

    function _loupeOnly() internal pure returns (RecipeEntry[] memory e) {
        e = new RecipeEntry[](1);
        e[0] = RecipeEntry({nameHash: LOUPE, version: V1, exclude: new bytes4[](0)});
    }

    function _create2(address deployer, bytes32 salt) internal view returns (address) {
        bytes32 s = keccak256(abi.encode(deployer, salt));
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), s, initCodeHash)))));
    }

    /// @notice deploy == predict == CREATE2(factory, keccak256(caller, salt), keccak256(Lattice creation code)).
    function testFuzz_DeployEqualsPredictEqualsCreate2(address caller, bytes32 salt) public {
        address expected = _create2(caller, salt);
        assertEq(factory.predict(caller, salt), expected, "predict");
        vm.prank(caller);
        address diamond = factory.deploy(_loupeOnly(), new FacetCut[](0), address(0), "", salt);
        assertEq(diamond, expected, "deploy");
        assertTrue(diamond.code.length != 0, "code");
    }

    /// @notice Distinct (caller, salt) pairs never share an address, and each deploys independently.
    function testFuzz_CallerSaltIsolation(address a, address b, bytes32 sa, bytes32 sb) public {
        vm.assume(a != b || sa != sb);
        assertTrue(factory.predict(a, sa) != factory.predict(b, sb), "address collision");
        vm.prank(a);
        address da = factory.deploy(_loupeOnly(), new FacetCut[](0), address(0), "", sa);
        vm.prank(b);
        address db = factory.deploy(_loupeOnly(), new FacetCut[](0), address(0), "", sb);
        assertTrue(da != db, "distinct diamonds");
    }

    /// @notice A failed init leaves the address empty for any (caller, salt), and the retry lands there.
    function testFuzz_FailedInitRollsBackAndRetries(address caller, bytes32 salt, uint256 code) public {
        address init = address(new CoreRevertingInit());
        address predicted = factory.predict(caller, salt);
        vm.expectRevert(abi.encodeWithSelector(CoreRevertingInit.CoreInitRefused.selector, code));
        vm.prank(caller);
        factory.deploy(_loupeOnly(), new FacetCut[](0), init, abi.encodeCall(CoreRevertingInit.init, (code)), salt);
        assertEq(predicted.code.length, 0, "no code after rollback");

        vm.prank(caller);
        assertEq(factory.deploy(_loupeOnly(), new FacetCut[](0), address(0), "", salt), predicted, "retry");
    }

    /// @notice Pinned, latest, custom and mixed recipes chosen by bitmask route every selector to the facet
    ///         that supplied it, with one loupe facet plus one facet per chosen entry or custom cut.
    function testFuzz_MixedRecipesRouteEverySelector(uint8 entryMask, uint8 latestMask, uint8 customMask, bytes32 salt)
        public
    {
        entryMask = uint8(bound(entryMask, 0, 63));
        customMask = uint8(bound(customMask, 0, 63));
        (RecipeEntry[] memory entries, FacetCut[] memory cuts) = _recipe(entryMask, latestMask, customMask);

        address diamond = factory.deploy(entries, cuts, address(0), "", salt);
        IDiamondLoupe loupe = IDiamondLoupe(diamond);
        assertEq(loupe.facetAddresses().length, entries.length + cuts.length, "one facet per cut");

        for (uint256 i; i < POOL; ++i) {
            if (entryMask & (1 << i) != 0) {
                address want = latestMask & (1 << i) != 0 ? v2Facets[i] : v1Facets[i];
                _assertRouted(loupe, entryBlobs[i], want);
            }
            if (customMask & (1 << i) != 0) _assertRouted(loupe, customBlobs[i], customFacets[i]);
        }
        assertEq(loupe.facetAddress(0x0ef22643), address(0), "exportSelectors never routed");
    }

    /// @notice A repeat call for an occupied (caller, salt) returns the same diamond for ANY recipe and init,
    ///         emits nothing, runs no init and leaves the loupe unchanged (the recipe-ignored return).
    function testFuzz_IdempotentReturnIgnoresAnyRecipe(
        address caller,
        bytes32 salt,
        uint8 entryMask,
        uint8 customMask,
        uint256 marker
    ) public {
        vm.prank(caller);
        address first = factory.deploy(_loupeOnly(), new FacetCut[](0), address(0), "", salt);
        bytes32 facetsBefore = keccak256(abi.encode(IDiamondLoupe(first).facets()));

        (RecipeEntry[] memory entries, FacetCut[] memory cuts) =
            _recipe(uint8(bound(entryMask, 0, 63)), 0, uint8(bound(customMask, 0, 63)));
        address init = address(new CoreMarkerInit());
        vm.recordLogs();
        vm.prank(caller);
        address second = factory.deploy(entries, cuts, init, abi.encodeCall(CoreMarkerInit.init, (marker)), salt);

        assertEq(second, first, "same diamond");
        assertEq(vm.getRecordedLogs().length, 0, "no event");
        assertEq(vm.load(first, keccak256("lattice.test.core.marker")), bytes32(0), "init not run");
        assertEq(keccak256(abi.encode(IDiamondLoupe(first).facets())), facetsBefore, "loupe unchanged");
    }

    /// @notice `deployStrict` lands at `predict` for any (caller, salt) and any pinned/custom recipe, emits the hash
    ///         of the applied cuts, and a second strict call for the same (caller, salt) reverts `AlreadyDeployed`
    ///         whatever its recipe; `deploy` still takes the idempotent return there.
    function testFuzz_DeployStrictDeploysOnceThenReverts(
        address caller,
        bytes32 salt,
        uint8 entryMask,
        uint8 customMask,
        uint8 secondMask
    ) public {
        (RecipeEntry[] memory entries, FacetCut[] memory cuts) =
            _recipe(uint8(bound(entryMask, 0, 63)), 0, uint8(bound(customMask, 0, 63)));
        FacetCut[] memory applied = new FacetCut[](entries.length + cuts.length);
        for (uint256 i; i < entries.length; ++i) {
            applied[i] = registry.getCut(entries[i].nameHash, entries[i].version);
        }
        for (uint256 i; i < cuts.length; ++i) {
            applied[entries.length + i] = cuts[i];
        }
        address expected = _create2(caller, salt);

        vm.expectEmit(true, true, true, true, address(factory));
        emit ILatticeFactory.DiamondDeployed(
            expected, caller, keccak256(abi.encode(applied, address(0), bytes(""))), salt, address(0)
        );
        vm.prank(caller);
        assertEq(factory.deployStrict(entries, cuts, address(0), "", salt), expected, "strict deploy == predict");

        (entries, cuts) = _recipe(uint8(bound(secondMask, 0, 63)), 0, 0);
        vm.expectRevert(abi.encodeWithSelector(ILatticeFactory.LatticeFactory__AlreadyDeployed.selector, expected));
        vm.prank(caller);
        factory.deployStrict(entries, cuts, address(0), "", salt);

        vm.prank(caller);
        assertEq(factory.deploy(entries, cuts, address(0), "", salt), expected, "deploy stays idempotent");
    }

    /// @notice `deployStrict` refuses any recipe with a `latest` (version 0) entry, before the address is
    ///         occupied, naming the first unpinned entry.
    function testFuzz_DeployStrictRefusesLatestEntries(uint8 entryMask, uint8 latestMask, bytes32 salt) public {
        entryMask = uint8(bound(entryMask, 1, 63));
        latestMask = uint8(bound(latestMask, 0, 63));
        vm.assume(entryMask & latestMask != 0);
        (RecipeEntry[] memory entries, FacetCut[] memory cuts) = _recipe(entryMask, latestMask, 0);
        bytes32 first;
        for (uint256 i; i < entries.length && first == bytes32(0); ++i) {
            if (entries[i].version == 0) first = entries[i].nameHash;
        }
        vm.expectRevert(abi.encodeWithSelector(ILatticeFactory.LatticeFactory__UnpinnedEntry.selector, first));
        factory.deployStrict(entries, cuts, address(0), "", salt);
        assertEq(factory.predict(address(this), salt).code.length, 0, "nothing deployed");
    }

    /// @notice Excluding any strict subset of an entry's export, listed in any order, cuts exactly the rest of
    ///         the export; nothing excluded is routed. Holds for a pinned entry and for a `latest` entry (which
    ///         resolves to V2 here, so `deploy` is used; `deployStrict` refuses unpinned entries).
    function testFuzz_ExcludeCutsExactlyTheComplement(uint8 mask, bool reversed, bool latest, bytes32 salt) public {
        mask = uint8(bound(mask, 0, 62)); // name 5 exports 6 selectors; excluding all 6 leaves an empty cut
        bytes4[] memory exported = RawCode.unpack(entryBlobs[5]);
        bytes4[] memory exclude = new bytes4[](6);
        uint256 n;
        for (uint256 i; i < 6; ++i) {
            uint256 k = reversed ? 5 - i : i;
            if (mask & (1 << k) != 0) exclude[n++] = exported[k];
        }
        assembly ("memory-safe") {
            mstore(exclude, n)
        }
        RecipeEntry[] memory entries = new RecipeEntry[](2);
        entries[0] = _loupeOnly()[0];
        entries[1] = RecipeEntry({nameHash: names[5], version: latest ? 0 : V1, exclude: exclude});

        IDiamondLoupe loupe = IDiamondLoupe(
            latest
                ? factory.deploy(entries, new FacetCut[](0), address(0), "", salt)
                : factory.deployStrict(entries, new FacetCut[](0), address(0), "", salt)
        );
        address routed = latest ? v2Facets[5] : v1Facets[5];
        for (uint256 k; k < 6; ++k) {
            address want = mask & (1 << k) != 0 ? address(0) : routed;
            assertEq(loupe.facetAddress(exported[k]), want, "excluded iff in the mask");
        }
    }

    /// @notice A fresh deploy needs all four loupe selectors in Add cuts; any strict subset is refused, naming
    ///         the first missing selector in the factory's fixed order.
    function testFuzz_LoupeCoverageNeedsAllFour(uint8 mask) public {
        mask = uint8(bound(mask, 1, 15));
        bytes4[4] memory loupe = [bytes4(0x7a0ed627), bytes4(0xadfca15e), bytes4(0x52ef6b2c), bytes4(0xcdffacc6)];
        bytes4[] memory kept = new bytes4[](4);
        uint256 n;
        bytes4 firstMissing;
        for (uint256 k; k < 4; ++k) {
            if (mask & (1 << k) != 0) kept[n++] = loupe[k];
            else if (firstMissing == bytes4(0)) firstMissing = loupe[k];
        }
        assembly ("memory-safe") {
            mstore(kept, n)
        }
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: loupeFacet, action: FacetCutAction.Add, functionSelectors: kept});

        if (mask != 15) {
            vm.expectRevert(
                abi.encodeWithSelector(ILatticeFactory.LatticeFactory__MissingLoupeCoverage.selector, firstMissing)
            );
        }
        factory.deploy(new RecipeEntry[](0), cuts, address(0), "", bytes32(uint256(mask)));
    }

    /// @notice `exportSelectors()` anywhere in any custom cut is refused, before and after the address is
    ///         occupied.
    function testFuzz_ExportSelectorInCustomCutAlwaysRefused(uint8 len, uint8 pos, bool occupied, bytes32 salt) public {
        len = uint8(bound(len, 1, 16));
        pos = uint8(bound(pos, 0, len - 1));
        bytes4[] memory selectors = RawCode.unpack(RawCode.selectorBlob(salt, len));
        selectors[pos] = 0x0ef22643;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: customFacets[0], action: FacetCutAction.Add, functionSelectors: selectors});

        if (occupied) factory.deploy(_loupeOnly(), new FacetCut[](0), address(0), "", salt);
        vm.expectRevert(ILatticeFactory.LatticeFactory__ExportSelectorForbidden.selector);
        factory.deploy(_loupeOnly(), cuts, address(0), "", salt);
    }

    function _recipe(uint8 entryMask, uint8 latestMask, uint8 customMask)
        internal
        view
        returns (RecipeEntry[] memory entries, FacetCut[] memory cuts)
    {
        uint256 ne = 1;
        uint256 nc;
        for (uint256 i; i < POOL; ++i) {
            if (entryMask & (1 << i) != 0) ++ne;
            if (customMask & (1 << i) != 0) ++nc;
        }
        entries = new RecipeEntry[](ne);
        entries[0] = RecipeEntry({nameHash: LOUPE, version: V1, exclude: new bytes4[](0)});
        cuts = new FacetCut[](nc);
        uint256 e = 1;
        uint256 c;
        for (uint256 i; i < POOL; ++i) {
            if (entryMask & (1 << i) != 0) {
                entries[e++] = RecipeEntry({
                    nameHash: names[i], version: latestMask & (1 << i) != 0 ? 0 : V1, exclude: new bytes4[](0)
                });
            }
            if (customMask & (1 << i) != 0) {
                cuts[c++] = FacetCut({
                    facetAddress: customFacets[i],
                    action: FacetCutAction.Add,
                    functionSelectors: RawCode.unpack(customBlobs[i])
                });
            }
        }
    }

    function _assertRouted(IDiamondLoupe loupe, bytes memory blob, address facet) internal view {
        bytes4[] memory selectors = RawCode.unpack(blob);
        for (uint256 j; j < selectors.length; ++j) {
            assertEq(loupe.facetAddress(selectors[j]), facet, "selector routed to its facet");
        }
    }
}
