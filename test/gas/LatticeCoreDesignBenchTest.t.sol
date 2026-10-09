// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {RawCode} from "@lattice-test/helpers/LatticeCoreMocks.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {ILatticeFactory, RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {Test, console2} from "forge-std/Test.sol";

/// @notice Test-only prototype of an in-registry alternative to {LatticeRegistry}'s live export read. It keeps
///         the same register checks (owner, version, first write, code, the ERC-8153 fetch and validation, the
///         resolver mirror and the event) and the same `getSelectors(bytes32,uint64)` read with its record
///         lookup and codehash pin, and changes only where the selectors come from on a read: the subclass
///         stores them at registration. Measured through the same external call as the real registry, from
///         cold state, so the comparison counts the whole read path for every design.
abstract contract SelectorStoreProto {
    struct Record {
        address facet;
        uint64 version;
        uint48 registeredAt;
        // Packs into the registeredAt slot, so the blob design adds no record slot.
        address pointer;
        bytes32 codehash;
        bytes32 selectorsHash;
    }

    error Unauthorized();
    error InvalidVersion();
    error RecordExists();
    error RecordNotFound();
    error EmptyCode();
    error NotERC8153();
    error CodeDrift();

    event Registered(
        bytes32 indexed nameHash, uint64 indexed version, address facet, bytes32 codehash, bytes32 selectorsHash
    );

    address public immutable owner;
    mapping(bytes32 codehash => address deployed) internal _resolver;
    mapping(bytes32 recordKey => Record record) internal _records;

    constructor(address owner_) {
        owner = owner_;
    }

    function register(bytes32 nameHash, uint64 version, address facet) external {
        if (msg.sender != owner) revert Unauthorized();
        if (version == 0) revert InvalidVersion();
        bytes32 key = keccak256(abi.encode(nameHash, version));
        Record storage r = _records[key];
        if (r.facet != address(0)) revert RecordExists();
        bytes32 codehash = facet.codehash;
        if (codehash == 0 || codehash == keccak256("")) revert EmptyCode();

        (bool ok, bytes memory ret) = facet.staticcall(abi.encodeWithSelector(0x0ef22643));
        if (!ok || ret.length < 64) revert NotERC8153();
        bytes memory blob = abi.decode(ret, (bytes));
        uint256 len = blob.length;
        if (len == 0 || len % 4 != 0) revert NotERC8153();
        bytes4[] memory selectors = _unpack(blob);
        uint256 n = selectors.length;
        for (uint256 i; i < n; ++i) {
            if (selectors[i] == 0x0ef22643) revert NotERC8153();
            for (uint256 j = i + 1; j < n; ++j) {
                if (selectors[i] == selectors[j]) revert NotERC8153();
            }
        }
        bytes32 selectorsHash = keccak256(blob);

        r.facet = facet;
        r.version = version;
        r.registeredAt = uint48(block.timestamp);
        r.pointer = _store(key, blob);
        r.codehash = codehash;
        r.selectorsHash = selectorsHash;
        if (_resolver[codehash] == address(0)) _resolver[codehash] = facet;
        emit Registered(nameHash, version, facet, codehash, selectorsHash);
    }

    function getSelectors(bytes32 nameHash, uint64 version) external view returns (bytes4[] memory) {
        bytes32 key = keccak256(abi.encode(nameHash, version));
        Record storage r = _records[key];
        address facet = r.facet;
        if (facet == address(0)) revert RecordNotFound();
        if (facet.codehash != r.codehash) revert CodeDrift();
        return _read(key, r);
    }

    function _store(bytes32 key, bytes memory blob) internal virtual returns (address pointer);

    function _read(bytes32 key, Record storage r) internal view virtual returns (bytes4[] memory);

    function _unpack(bytes memory blob) internal pure returns (bytes4[] memory selectors) {
        uint256 n = blob.length / 4;
        selectors = new bytes4[](n);
        for (uint256 i; i < n; ++i) {
            bytes4 s;
            assembly ("memory-safe") {
                s := mload(add(add(blob, 0x20), mul(i, 4)))
            }
            selectors[i] = s;
        }
    }
}

/// @notice Stores the selector blob as the runtime code of a data contract (SSTORE2-style, leading STOP byte);
///         a read is one `EXTCODECOPY`.
contract BlobRegistryProto is SelectorStoreProto {
    constructor(address owner_) SelectorStoreProto(owner_) {}

    function _store(bytes32, bytes memory blob) internal override returns (address p) {
        bytes memory runtime = abi.encodePacked(hex"00", blob);
        bytes memory init = abi.encodePacked(hex"61", uint16(runtime.length), hex"80600c6000396000f3", runtime);
        assembly ("memory-safe") {
            p := create(0, add(init, 0x20), mload(init))
        }
    }

    function _read(bytes32, Record storage r) internal view override returns (bytes4[] memory) {
        address p = r.pointer;
        uint256 len = p.code.length - 1;
        bytes memory blob = new bytes(len);
        assembly ("memory-safe") {
            extcodecopy(p, add(blob, 0x20), 1, len)
        }
        return _unpack(blob);
    }
}

/// @notice Stores the selectors as a `bytes4[]` in storage (8 selectors per slot plus a length slot).
contract ArrayRegistryProto is SelectorStoreProto {
    mapping(bytes32 key => bytes4[]) internal _arrays;

    constructor(address owner_) SelectorStoreProto(owner_) {}

    function _store(bytes32 key, bytes memory blob) internal override returns (address) {
        _arrays[key] = _unpack(blob);
        return address(0);
    }

    function _read(bytes32 key, Record storage) internal view override returns (bytes4[] memory) {
        return _arrays[key];
    }
}

/// @notice The read surface the three designs share.
interface ISelectorReader {
    function getSelectors(bytes32 nameHash, uint64 version) external view returns (bytes4[] memory);
}

/// @notice Measures the candidates #176 compares with the current {LatticeRegistry}. Every `measure*` function
///         returns the EXECUTION gas of one operation, taken with `gasleft()` inside a single call, so all
///         candidates are measured the same way.
contract DesignBench {
    // ------------------------------------------------------------------ selector reads, whole path

    /// @dev Execution gas of one `getSelectors` read, including the cold call into the registry, the record
    ///      lookup, the codehash pin, the selector source (live export, storage array or code blob), and the
    ///      ABI decode of the returned array. Used for the real registry and both prototypes.
    function measureRead(ISelectorReader registry, bytes32 name, uint64 version) external view returns (uint256) {
        uint256 g = gasleft();
        registry.getSelectors(name, version);
        return g - gasleft();
    }

    // ------------------------------------------------------------------ duplicate validation

    error Rejected();

    /// @dev The registry's current check, written as in `_fetchSelectors`: O(n^2) pairwise scan over a memory
    ///      `bytes4[]` plus the self-selector check.
    function measureQuadratic(bytes4[] memory s) external view returns (uint256) {
        uint256 g = gasleft();
        uint256 n = s.length;
        for (uint256 i; i < n; ++i) {
            if (s[i] == 0x0ef22643) revert Rejected();
            for (uint256 j = i + 1; j < n; ++j) {
                if (s[i] == s[j]) revert Rejected();
            }
        }
        return g - gasleft();
    }

    /// @dev Alternative: require a strictly ascending blob, which also proves uniqueness, in one O(n) pass. Moves
    ///      the sort off-chain (the export order changes; diamond routing does not depend on it).
    function measureSortedLinear(bytes4[] memory s) external view returns (uint256) {
        uint256 g = gasleft();
        uint256 n = s.length;
        for (uint256 i; i < n; ++i) {
            if (s[i] == 0x0ef22643) revert Rejected();
            if (i != 0 && uint32(s[i - 1]) >= uint32(s[i])) revert Rejected();
        }
        return g - gasleft();
    }

    // ------------------------------------------------------------------ whole calls

    /// @dev Execution gas of one call to `target` (used for the REAL factory, not a copy of its code).
    function measureCall(address target, bytes calldata data) external returns (uint256 used) {
        uint256 g = gasleft();
        (bool ok,) = target.call(data);
        used = g - gasleft();
        require(ok, "DesignBench: call failed");
    }
}

/// @title LatticeCoreDesignBenchTest
/// @notice Reproducible measurements behind the #176 design comparison: selector representation (live export
///         plus pin vs stored array vs bytecode blob, each as a whole registry behind the same `getSelectors`
///         interface), duplicate validation (pairwise vs sorted linear), and the factory loupe scan. Not gated:
///         it logs the numbers (`forge test --match-contract LatticeCoreDesignBenchTest -vv`) and asserts only
///         orderings that hold by a wide margin. The live and blob reads are within about 2k gas of each other
///         at every size, so their order is logged, not asserted.
contract LatticeCoreDesignBenchTest is Test {
    DesignBench internal bench;
    LatticeRegistry internal registry;

    function setUp() public {
        bench = new DesignBench();
        registry = new LatticeRegistry(address(this));
    }

    function _sorted(uint256 n) internal pure returns (bytes memory blob) {
        // Ascending by construction: i * step, offset away from 0x0ef22643.
        uint256 step = type(uint32).max / (n + 1);
        for (uint256 i = 1; i <= n; ++i) {
            blob = abi.encodePacked(blob, bytes4(uint32(i * step)));
        }
    }

    /// @notice Whole-path register and read cost of the three selector representations. All three registries are
    ///         owned by the bench, so `register` is measured through the same helper call; every read is a
    ///         separate top-level call (`isolate`), so it starts cold.
    function test_SelectorRepresentationReadAndWrite() public {
        ISelectorReader[3] memory regs = [
            ISelectorReader(address(new LatticeRegistry(address(bench)))),
            ISelectorReader(address(new BlobRegistryProto(address(bench)))),
            ISelectorReader(address(new ArrayRegistryProto(address(bench))))
        ];
        uint16[5] memory ns = [uint16(4), 16, 36, 64, 128];
        for (uint256 k; k < ns.length; ++k) {
            _compareRepresentations(regs, ns[k]);
        }
    }

    /// @dev `regs` = live, blob, array.
    function _compareRepresentations(ISelectorReader[3] memory regs, uint256 n) internal {
        address facet = RawCode.exporter(_sorted(n));
        bytes32 key = bytes32(n);
        bytes memory reg = abi.encodeWithSelector(SelectorStoreProto.register.selector, key, uint64(1), facet);

        uint256[3] memory writes;
        uint256[3] memory reads;
        for (uint256 d; d < 3; ++d) {
            writes[d] = bench.measureCall(address(regs[d]), reg);
        }
        for (uint256 d; d < 3; ++d) {
            reads[d] = bench.measureRead(regs[d], key, 1);
        }
        bytes32 expected = keccak256(abi.encode(regs[0].getSelectors(key, 1)));
        assertEq(keccak256(abi.encode(regs[1].getSelectors(key, 1))), expected, "blob read returns the selectors");
        assertEq(keccak256(abi.encode(regs[2].getSelectors(key, 1))), expected, "array read returns the selectors");

        console2.log("n", n);
        console2.log("  register live / blob / array", writes[0], writes[1], writes[2]);
        console2.log("  read     live / blob / array", reads[0], reads[1], reads[2]);

        if (n >= 16) assertLt(writes[1], writes[2], "from 16 selectors a code blob registers cheaper");
        if (n >= 16) assertLt(reads[1], reads[2], "from 16 selectors a code blob reads cheaper than an array");
    }

    function test_DuplicateValidation() public view {
        uint16[5] memory ns = [uint16(16), 64, 128, 256, 512];
        for (uint256 k; k < ns.length; ++k) {
            bytes4[] memory s = RawCode.unpack(_sorted(ns[k]));
            uint256 quadratic = bench.measureQuadratic(s);
            uint256 linear = bench.measureSortedLinear(s);
            console2.log("n", ns[k]);
            console2.log("  pairwise / sorted linear", quadratic, linear);
            assertLt(linear, quadratic, "sorted linear check is cheaper");
        }
    }

    /// @notice The factory's loupe presence scan stops at the first cut that adds each loupe selector, so its cost
    ///         depends on where the loupe cut sits. Measured on the real factory: the same 16 x 32 custom recipe
    ///         with the loupe cut first and last.
    function test_LoupeScanPosition() public {
        LatticeFactory factory = new LatticeFactory(registry, address(0), address(0));
        address loupe = address(new DiamondLoupeFacet());
        bytes4[] memory loupeSelectors = new bytes4[](4);
        loupeSelectors[0] = 0x7a0ed627;
        loupeSelectors[1] = 0xadfca15e;
        loupeSelectors[2] = 0x52ef6b2c;
        loupeSelectors[3] = 0xcdffacc6;

        FacetCut[] memory first = new FacetCut[](17);
        FacetCut[] memory last = new FacetCut[](17);
        first[0] = FacetCut(loupe, FacetCutAction.Add, loupeSelectors);
        last[16] = first[0];
        for (uint256 i; i < 16; ++i) {
            bytes memory blob = RawCode.selectorBlob(bytes32(i), 32);
            FacetCut memory cut = FacetCut(RawCode.exporter(blob), FacetCutAction.Add, RawCode.unpack(blob));
            first[i + 1] = cut;
            last[i] = cut;
        }
        uint256 loupeFirst = bench.measureCall(
            address(factory),
            abi.encodeCall(ILatticeFactory.deploy, (new RecipeEntry[](0), first, address(0), "", bytes32("first")))
        );
        uint256 loupeLast = bench.measureCall(
            address(factory),
            abi.encodeCall(ILatticeFactory.deploy, (new RecipeEntry[](0), last, address(0), "", bytes32("last")))
        );
        console2.log("16x32 custom deploy, loupe cut first / last", loupeFirst, loupeLast);
        assertLt(loupeFirst, loupeLast, "loupe-first is cheaper");
    }

    /// @notice What the recipe hash `DiamondDeployed` carries costs: `keccak256(abi.encode(cuts, init,
    ///         initCalldata))` over the materialized governed-vault recipe (14 cuts).
    function test_RecipeHashCost() public {
        GovernedVaultParams memory p;
        p.asset = address(0xA55E7);
        p.name = "Bench Vault";
        p.symbol = "bV";
        p.minDelay = 100;
        p.votingDelay = 1;
        p.votingPeriod = 50;
        p.quorumNumerator = 4;
        (FacetCut[] memory cuts, address init, bytes memory data) = new DeployGovernedVault().buildCuts(p);
        uint256 selectors;
        for (uint256 i; i < cuts.length; ++i) {
            selectors += cuts[i].functionSelectors.length;
        }
        uint256 g = gasleft();
        bytes32 h = keccak256(abi.encode(cuts, init, data));
        uint256 used = g - gasleft();
        console2.log("governed vault: cuts / selectors / recipe-hash gas", cuts.length, selectors, used);
        assertTrue(h != bytes32(0));
    }
}
