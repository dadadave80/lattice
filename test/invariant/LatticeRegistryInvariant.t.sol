// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {CoreFlippingExporter, RawCode} from "@lattice-test/helpers/LatticeCoreMocks.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Drives every state-changing entry point of {LatticeRegistry} over small pools, predicting each
///         outcome from ghost state and asserting expected reverts with `vm.expectRevert`, so the handler never
///         reverts under `fail_on_revert`.
/// @dev Pools: 5 actors (actor 0 is the first owner), 4 names, versions {0..3} (0 is the reserved sentinel), and
///      8 facets: two byte-identical canonical exporters, a third exporter, two byte-identical
///      {CoreFlippingExporter}s (same codehash, state-dependent export), a duplicate-selector exporter, an
///      exporter with a malformed ABI offset, and a codeless address. With `etchEnabled`, {etchDrift} also
///      swaps the code of facets 0-2 for other valid exporters, to exercise code drift.
contract LatticeRegistryHandler is Test {
    LatticeRegistry public immutable registry;
    bool public immutable etchEnabled;

    uint256 public constant NAMES = 4;
    uint256 public constant VERSIONS = 4;
    uint256 public constant FACETS = 8;

    address[5] internal _actors;
    string[NAMES] internal _names;
    address[FACETS] internal _facets;
    address[2] internal _etchSources;

    address public ghostOwner;
    address public ghostPending;

    struct GhostRecord {
        bool exists;
        address facet;
        uint48 registeredAt;
        bytes32 codehash;
        bytes32 selectorsHash;
    }

    mapping(uint256 nameIdx => mapping(uint64 version => GhostRecord)) internal _records;
    mapping(uint256 nameIdx => uint64) public ghostLatest;
    mapping(bytes32 codehash => address) public ghostResolver;
    bytes32[] internal _codehashes;
    mapping(bytes32 => bool) internal _seenCodehash;

    constructor(LatticeRegistry registry_, address firstOwner, bool etchEnabled_) {
        registry = registry_;
        etchEnabled = etchEnabled_;
        ghostOwner = firstOwner;
        _actors = [firstOwner, address(0xB1), address(0xB2), address(0xB3), address(0xB4)];
        _names = ["lattice.A", "lattice.B", "lattice.C", "lattice.D"];

        bytes memory blobA = abi.encodePacked(bytes4(0x11111111), bytes4(0x22222222));
        _facets[0] = RawCode.exporter(blobA);
        _facets[1] = RawCode.exporter(blobA);
        _facets[2] = RawCode.exporter(abi.encodePacked(bytes4(0x33333333)));
        _facets[3] = address(new CoreFlippingExporter());
        _facets[4] = address(new CoreFlippingExporter());
        _facets[5] = RawCode.exporter(abi.encodePacked(bytes4(0x44444444), bytes4(0x44444444)));
        _facets[6] = RawCode.deploy(abi.encode(uint256(0x1000), uint256(4), bytes32(bytes4(0x55555555))));
        _facets[7] = address(0xC0DE1E55);
        _etchSources[0] = RawCode.exporter(abi.encodePacked(bytes4(0x66666666)));
        _etchSources[1] = RawCode.exporter(abi.encodePacked(bytes4(0x77777777), bytes4(0x88888888)));

        for (uint256 i; i < FACETS; ++i) {
            _track(_facets[i].codehash);
        }
        _track(_etchSources[0].codehash);
        _track(_etchSources[1].codehash);
    }

    //*////////////////////////////// views for the invariants //////////////////////////////*//

    function actors() external view returns (address[5] memory) {
        return _actors;
    }

    function nameOf(uint256 i) external view returns (string memory) {
        return _names[i];
    }

    function facetOf(uint256 i) external view returns (address) {
        return _facets[i];
    }

    function record(uint256 nameIdx, uint64 version) external view returns (GhostRecord memory) {
        return _records[nameIdx][version];
    }

    function codehashes() external view returns (bytes32[] memory) {
        return _codehashes;
    }

    //*////////////////////////////////////// actions //////////////////////////////////////*//

    function attest(uint256 facetSeed) external {
        address facet = _facets[facetSeed % FACETS];
        bytes32 h = facet.codehash;
        if (facet.code.length == 0) {
            vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__EmptyCode.selector, facet));
            registry.attest(facet);
            return;
        }
        registry.attest(facet);
        _track(h);
        if (ghostResolver[h] == address(0)) ghostResolver[h] = facet;
    }

    function register(uint256 actorSeed, uint256 nameSeed, uint256 versionSeed, uint256 facetSeed, bool byString)
        external
    {
        // Three in four calls come from the current owner, so the success path is exercised often.
        address caller = actorSeed % 4 == 0 ? _actors[(actorSeed >> 8) % _actors.length] : ghostOwner;
        uint256 nameIdx = nameSeed % NAMES;
        uint64 version = uint64(versionSeed % VERSIONS);
        uint256 f = facetSeed % FACETS;
        address facet = _facets[f];
        bytes32 nameHash = keccak256(bytes(_names[nameIdx]));

        bytes memory expected;
        bool bare;
        if (caller != ghostOwner) {
            expected = abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__Unauthorized.selector, caller);
        } else if (version == 0) {
            expected = abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__InvalidVersion.selector);
        } else if (_records[nameIdx][version].exists) {
            expected =
                abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordExists.selector, nameHash, version);
        } else if (facet.code.length == 0) {
            expected = abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__EmptyCode.selector, facet);
        } else if (f == 5) {
            expected = abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotERC8153.selector, facet);
        } else if (f == 6) {
            bare = true; // finding R-1: a malformed offset fails inside abi.decode with empty revert data
        }

        if (expected.length != 0 || bare) vm.expectRevert(expected);
        vm.prank(caller);
        if (byString) registry.register(_names[nameIdx], version, facet);
        else registry.register(nameHash, version, facet);
        if (expected.length != 0 || bare) return;

        bytes32 h = facet.codehash;
        _records[nameIdx][version] = GhostRecord({
            exists: true,
            facet: facet,
            registeredAt: uint48(block.timestamp),
            codehash: h,
            selectorsHash: keccak256(_liveExport(facet))
        });
        _track(h);
        if (ghostResolver[h] == address(0)) ghostResolver[h] = facet;
    }

    function setLatest(uint256 actorSeed, uint256 nameSeed, uint256 versionSeed, bool byString) external {
        address caller = actorSeed % 4 == 0 ? _actors[(actorSeed >> 8) % _actors.length] : ghostOwner;
        uint256 nameIdx = nameSeed % NAMES;
        uint64 version = uint64(versionSeed % VERSIONS);
        bytes32 nameHash = keccak256(bytes(_names[nameIdx]));

        bytes memory expected;
        if (caller != ghostOwner) {
            expected = abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__Unauthorized.selector, caller);
        } else if (!_records[nameIdx][version].exists) {
            expected =
                abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordNotFound.selector, nameHash, version);
        }
        if (expected.length != 0) vm.expectRevert(expected);
        vm.prank(caller);
        if (byString) registry.setLatest(_names[nameIdx], version);
        else registry.setLatest(nameHash, version);
        if (expected.length == 0) ghostLatest[nameIdx] = version;
    }

    function transferOwnership(uint256 actorSeed, uint256 targetSeed) external {
        address caller = actorSeed % 2 == 0 ? _actors[(actorSeed >> 8) % _actors.length] : ghostOwner;
        // Targets: any actor, or address(0) to cancel.
        uint256 t = targetSeed % (_actors.length + 1);
        address target = t == _actors.length ? address(0) : _actors[t];
        if (caller != ghostOwner) {
            vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__Unauthorized.selector, caller));
        }
        vm.prank(caller);
        registry.transferOwnership(target);
        if (caller == ghostOwner) ghostPending = target;
    }

    function acceptOwnership(uint256 actorSeed) external {
        address caller = actorSeed % 2 == 0 ? _actors[(actorSeed >> 8) % _actors.length] : ghostPending;
        if (caller == address(0)) caller = _actors[0]; // no transaction is sent from address 0 (see R-4)
        if (caller != ghostPending) {
            vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__NotPendingOwner.selector, caller));
        }
        vm.prank(caller);
        registry.acceptOwnership();
        if (caller == ghostPending) {
            ghostOwner = caller;
            ghostPending = address(0);
        }
    }

    function flip(bool second) external {
        CoreFlippingExporter(_facets[second ? 4 : 3]).flip();
    }

    /// @notice Synthetic code drift (only when enabled): swaps a canonical facet's code for another valid exporter.
    function etchDrift(uint256 facetSeed, bool sourceSeed) external {
        if (!etchEnabled) return;
        address facet = _facets[facetSeed % 3];
        vm.etch(facet, _etchSources[sourceSeed ? 1 : 0].code);
    }

    //*////////////////////////////////////// helpers //////////////////////////////////////*//

    function _liveExport(address facet) internal view returns (bytes memory blob) {
        (bool ok, bytes memory ret) = facet.staticcall(abi.encodeWithSelector(0x0ef22643));
        require(ok && ret.length >= 64, "handler: export read");
        blob = abi.decode(ret, (bytes));
    }

    function _track(bytes32 h) internal {
        if (_seenCodehash[h]) return;
        _seenCodehash[h] = true;
        _codehashes.push(h);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TESTS
//////////////////////////////////////////////////////////////////////////*//

/// @notice Shared R1-R7 checks of #176's registry invariant set, run over a {LatticeRegistryHandler}.
abstract contract LatticeRegistryInvariantBase is Test {
    LatticeRegistry internal registry;
    LatticeRegistryHandler internal handler;
    address internal firstOwner = makeAddr("firstOwner");

    function _setUp(bool etchEnabled) internal {
        registry = new LatticeRegistry(firstOwner);
        handler = new LatticeRegistryHandler(registry, firstOwner, etchEnabled);
        // Seed a few records so every run starts with content to check.
        handler.register(1, 0, 1, 0, false);
        handler.register(1, 1, 2, 3, true);
        handler.register(1, 2, 1, 2, false);
        handler.setLatest(1, 0, 1, false);
        targetContract(address(handler));
    }

    /// @notice R1: a record never changes once written.
    function invariant_R1_RecordsAreImmutable() public view {
        for (uint256 n; n < handler.NAMES(); ++n) {
            bytes32 h = keccak256(bytes(handler.nameOf(n)));
            for (uint64 v = 1; v < handler.VERSIONS(); ++v) {
                LatticeRegistryHandler.GhostRecord memory g = handler.record(n, v);
                if (!g.exists) continue;
                ILatticeRegistry.Record memory r = registry.get(h, v);
                assertEq(r.facet, g.facet, "R1 facet");
                assertEq(r.version, v, "R1 version");
                assertEq(r.registeredAt, g.registeredAt, "R1 registeredAt");
                assertEq(r.codehash, g.codehash, "R1 codehash");
                assertEq(r.selectorsHash, g.selectorsHash, "R1 selectorsHash");
            }
        }
    }

    /// @notice R2: a non-zero `resolve(h)` never changes and is the first address attested (by `attest` or by
    ///         `register`'s auto-attest) with codehash `h`.
    function invariant_R2_ResolverIsFirstWriteWins() public view {
        bytes32[] memory hs = handler.codehashes();
        for (uint256 i; i < hs.length; ++i) {
            assertEq(registry.resolve(hs[i]), handler.ghostResolver(hs[i]), "R2 resolver");
        }
    }

    /// @notice R3: a set `latest(n)` equals `get(n, latest(n).version)`; an unset one reverts.
    function invariant_R3_LatestPointsAtARecord() public {
        for (uint256 n; n < handler.NAMES(); ++n) {
            bytes32 h = keccak256(bytes(handler.nameOf(n)));
            uint64 v = handler.ghostLatest(n);
            if (v == 0) {
                vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__LatestUnset.selector, h));
                registry.latest(h);
                continue;
            }
            assertEq(keccak256(abi.encode(registry.latest(h))), keccak256(abi.encode(registry.get(h, v))), "R3");
        }
    }

    /// @notice R4: the owner is never zero and changes only through `acceptOwnership`; the pending owner matches.
    function invariant_R4_Ownership() public view {
        assertTrue(registry.owner() != address(0), "R4 owner zero");
        assertEq(registry.owner(), handler.ghostOwner(), "R4 owner");
        assertEq(registry.pendingOwner(), handler.ghostPending(), "R4 pending");
    }

    /// @notice R5: the string and hash overloads of `get`, `latest`, `getSelectors` and `getCut` return the same
    ///         data or revert with the same error, for every name and version.
    function invariant_R5_StringHashParity() public view {
        for (uint256 n; n < handler.NAMES(); ++n) {
            string memory s = handler.nameOf(n);
            bytes32 h = keccak256(bytes(s));
            assertEq(registry.nameHash(s), h, "R5 nameHash");
            assertEq(
                _call(abi.encodeWithSignature("latest(string)", s)),
                _call(abi.encodeWithSignature("latest(bytes32)", h)),
                "R5 latest"
            );
            for (uint64 v; v < handler.VERSIONS(); ++v) {
                assertEq(
                    _call(abi.encodeWithSignature("get(string,uint64)", s, v)),
                    _call(abi.encodeWithSignature("get(bytes32,uint64)", h, v)),
                    "R5 get"
                );
                assertEq(
                    _call(abi.encodeWithSignature("getSelectors(string,uint64)", s, v)),
                    _call(abi.encodeWithSignature("getSelectors(bytes32,uint64)", h, v)),
                    "R5 getSelectors"
                );
                assertEq(
                    _call(abi.encodeWithSignature("getCut(string,uint64)", s, v)),
                    _call(abi.encodeWithSignature("getCut(bytes32,uint64)", h, v)),
                    "R5 getCut"
                );
            }
        }
    }

    /// @notice R6: `getCut` returns exactly the pinned selectors, or reverts {LatticeRegistry__CodeDrift} when the
    ///         facet's code changed, else {LatticeRegistry__SelectorDrift}.
    function invariant_R6_GetCutIsPinnedOrDrift() public view {
        for (uint256 n; n < handler.NAMES(); ++n) {
            bytes32 h = keccak256(bytes(handler.nameOf(n)));
            for (uint64 v = 1; v < handler.VERSIONS(); ++v) {
                LatticeRegistryHandler.GhostRecord memory g = handler.record(n, v);
                if (!g.exists) continue;
                try registry.getCut(h, v) returns (FacetCut memory cut) {
                    assertEq(g.facet.codehash, g.codehash, "R6 cut served after code drift");
                    assertEq(keccak256(_pack(cut.functionSelectors)), g.selectorsHash, "R6 unpinned cut");
                } catch (bytes memory err) {
                    bytes4 want = g.facet.codehash != g.codehash
                        ? ILatticeRegistry.LatticeRegistry__CodeDrift.selector
                        : ILatticeRegistry.LatticeRegistry__SelectorDrift.selector;
                    assertEq(keccak256(err), keccak256(abi.encodeWithSelector(want, g.facet)), "R6 wrong revert");
                }
            }
        }
    }

    /// @notice R7: version 0 never holds a record.
    function invariant_R7_VersionZeroNeverRegisters() public {
        for (uint256 n; n < handler.NAMES(); ++n) {
            bytes32 h = keccak256(bytes(handler.nameOf(n)));
            vm.expectRevert(abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordNotFound.selector, h, 0));
            registry.get(h, 0);
        }
    }

    /// @dev Packs selectors 4 bytes each (`abi.encodePacked` would pad every array element to 32 bytes).
    function _pack(bytes4[] memory selectors) internal pure returns (bytes memory blob) {
        for (uint256 i; i < selectors.length; ++i) {
            blob = bytes.concat(blob, selectors[i]);
        }
    }

    /// @dev Static-calls the registry and returns `success ++ returndata` so two overloads compare in one go.
    function _call(bytes memory data) internal view returns (bytes memory) {
        (bool ok, bytes memory ret) = address(registry).staticcall(data);
        return abi.encodePacked(ok, ret);
    }
}

/// @title LatticeRegistryInvariant
/// @notice #176 R1-R7 over realistic EVM behaviour: attest, register and setLatest from owner and strangers by
///         hash and by string, ownership handovers and cancellations, and selector drift from stateful
///         exporters (no cheatcode code swaps).
/// forge-config: ci.invariant.runs = 64
contract LatticeRegistryInvariant is LatticeRegistryInvariantBase {
    function setUp() public {
        _setUp(false);
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = LatticeRegistryHandler.attest.selector;
        selectors[1] = LatticeRegistryHandler.register.selector;
        selectors[2] = LatticeRegistryHandler.setLatest.selector;
        selectors[3] = LatticeRegistryHandler.transferOwnership.selector;
        selectors[4] = LatticeRegistryHandler.acceptOwnership.selector;
        selectors[5] = LatticeRegistryHandler.flip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }
}

/// @title LatticeRegistryCodeDriftInvariant
/// @notice The same R1-R7 set with SYNTHETIC code drift: the handler may `vm.etch` registered facets with other
///         valid exporters, the end state of a metamorphic (CREATE2 + selfdestruct + redeploy) swap. Kept apart
///         from {LatticeRegistryInvariant} so realistic and synthetic behaviour stay distinct.
/// forge-config: ci.invariant.runs = 64
contract LatticeRegistryCodeDriftInvariant is LatticeRegistryInvariantBase {
    function setUp() public {
        _setUp(true);
    }
}
