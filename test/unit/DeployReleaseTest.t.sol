// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployRelease} from "@lattice-script/deploy/DeployRelease.s.sol";
import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {MockCreateX} from "@lattice-test/helpers/MockCreateX.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {IERC8153} from "@lattice/interfaces/external/IERC8153.sol";
import {Test} from "forge-std/Test.sol";

/// @title DeployReleaseTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Unit gate for the {DeployRelease} pipeline. The test contract INHERITS {DeployRelease} and drives
///         `this.release(...)` as an external self-call so `msg.sender` inside `release` AND the sender the
///         registry sees on `register`/`setLatest` are both this contract — exactly mirroring production,
///         where `--sender`/`--account` makes the script's `msg.sender` equal the broadcasting EOA.
contract DeployReleaseTest is Test, DeployRelease {
    address internal constant CANONICAL = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    string internal constant VERSION = "0.1.0";

    /// @dev `0.1.0` packed as `major<<48 | minor<<24 | patch`.
    uint64 internal constant PACKED = uint64(1) << 24;

    function setUp() public {
        // Etch the faithful CreateX mock at the canonical singleton address so CreateXDeployer.CREATEX
        // resolves to live code under Foundry (no fork needed).
        MockCreateX impl = new MockCreateX();
        vm.etch(CANONICAL, address(impl).code);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              FULL RELEASE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice One release() call deploys the registry (owned), the factory (wired), and EVERY inventory
    ///         facet at its raw-salt CREATE2 address, then registers each and points `latest` at it.
    function test_Release_DeploysAndRegistersEverything() public {
        DeployRelease.ReleaseOutput memory out = this.release(VERSION, address(this));

        // Registry: lands at the raw-salt predicted address, owned by the requested owner.
        bytes memory registryInitCode = abi.encodePacked(type(LatticeRegistry).creationCode, abi.encode(address(this)));
        assertEq(
            out.registry,
            CreateXDeployer.predictRaw(REGISTRY_SALT, keccak256(registryInitCode)),
            "registry not at its predicted raw-salt address"
        );
        ILatticeRegistry registry = ILatticeRegistry(out.registry);
        assertEq(registry.owner(), address(this), "registry owner not wired");

        // Factory: deployed and bound to the registry.
        bytes memory factoryInitCode = abi.encodePacked(type(LatticeFactory).creationCode, abi.encode(out.registry));
        assertEq(
            out.factory,
            CreateXDeployer.predictRaw(FACTORY_SALT, keccak256(factoryInitCode)),
            "factory not at its predicted raw-salt address"
        );
        assertEq(address(LatticeFactory(out.factory).registry()), out.registry, "factory registry not wired");

        // Every inventory facet: deployed at its predicted address, registered, and flagged latest.
        (string[] memory names,) = FacetInventory.inventory();
        assertEq(names.length, 99, "inventory count drifted");
        assertEq(out.facets.length, names.length, "release output facet count mismatch");
        for (uint256 i; i < names.length; ++i) {
            assertGt(out.facets[i].code.length, 0, string.concat(names[i], ": no code at released address"));

            bytes32 nameHash = keccak256(abi.encodePacked("lattice.", names[i]));
            ILatticeRegistry.Record memory record = registry.get(nameHash, PACKED);
            assertEq(record.facet, out.facets[i], string.concat(names[i], ": registered facet != released facet"));
            assertEq(registry.latest(nameHash).version, PACKED, string.concat(names[i], ": latest not set"));
        }
    }

    /// @notice The version-less release() overload pins the release to the library's own
    ///         {LatticeVersion.VERSION} — the Release-Please-bumped single source of truth — so an
    ///         operator-passed string cannot drift from the code actually being released. Assertions
    ///         derive the packed version FROM the library constant, so this test survives version bumps.
    function test_Release_NoVersionOverloadUsesLatticeVersion() public {
        DeployRelease.ReleaseOutput memory out = this.release(address(this));

        ILatticeRegistry registry = ILatticeRegistry(out.registry);
        uint64 packed = packVersion(LatticeVersion.VERSION);
        (string[] memory names,) = FacetInventory.inventory();
        bytes32 nameHash = keccak256(abi.encodePacked("lattice.", names[0]));
        assertEq(
            registry.get(nameHash, packed).facet, out.facets[0], "facet not registered under LatticeVersion.VERSION"
        );
        assertEq(registry.latest(nameHash).version, packed, "latest not pinned to LatticeVersion.VERSION");
    }

    /// @notice A second release() run over an already-complete release succeeds, lands on identical
    ///         addresses, and never trips the registry's append-only RecordExists guard.
    function test_Release_IdempotentResume() public {
        DeployRelease.ReleaseOutput memory first = this.release(VERSION, address(this));
        DeployRelease.ReleaseOutput memory second = this.release(VERSION, address(this));

        assertEq(second.registry, first.registry, "registry address changed on resume");
        assertEq(second.factory, first.factory, "factory address changed on resume");
        for (uint256 i; i < first.facets.length; ++i) {
            assertEq(second.facets[i], first.facets[i], "facet address changed on resume");
        }
    }

    /// @notice A facet someone ELSE already deployed at its canonical raw-salt address is skipped by the
    ///         deploy phase but still registered — permissionless completion composes with registration.
    function test_Release_PartialResumeRegistersPredeployedFacet() public {
        (string[] memory names, string[] memory paths) = FacetInventory.inventory();

        // Pre-deploy one facet (ERC20) at its canonical address; raw salts are deployer-independent, so
        // deploying from the test lands exactly where release() predicts.
        uint256 erc20Index = type(uint256).max;
        for (uint256 i; i < names.length; ++i) {
            if (keccak256(bytes(names[i])) == keccak256("ERC20")) erc20Index = i;
        }
        assertTrue(erc20Index != type(uint256).max, "ERC20 missing from inventory");
        bytes memory initCode = vm.getCode(paths[erc20Index]);
        address predeployed = CreateXDeployer.deployRaw(facetSalt("ERC20", VERSION), initCode);

        DeployRelease.ReleaseOutput memory out = this.release(VERSION, address(this));

        assertEq(out.facets[erc20Index], predeployed, "release did not adopt the pre-deployed facet");
        ILatticeRegistry registry = ILatticeRegistry(out.registry);
        bytes32 nameHash = keccak256(abi.encodePacked("lattice.", names[erc20Index]));
        assertEq(registry.get(nameHash, PACKED).facet, predeployed, "pre-deployed facet not registered");
        for (uint256 i; i < names.length; ++i) {
            assertGt(out.facets[i].code.length, 0, string.concat(names[i], ": missing after partial resume"));
        }
    }

    /// @notice `latest` only ever advances: releasing a newer version moves it forward, and re-running an
    ///         OLDER release afterwards (the documented resume flow) must NOT downgrade it.
    function test_Release_LatestAdvancesAndNeverDowngrades() public {
        this.release("0.1.0", address(this));
        DeployRelease.ReleaseOutput memory out = this.release("0.2.0", address(this));
        ILatticeRegistry registry = ILatticeRegistry(out.registry);

        (string[] memory names,) = FacetInventory.inventory();
        bytes32 nameHash = keccak256(abi.encodePacked("lattice.", names[0]));
        uint64 packed020 = packVersion("0.2.0");
        assertEq(registry.latest(nameHash).version, packed020, "latest did not advance to 0.2.0");

        // Re-running the finished 0.1.0 release deploys/registers nothing new AND leaves latest at 0.2.0.
        this.release("0.1.0", address(this));
        for (uint256 i; i < names.length; ++i) {
            bytes32 nh = keccak256(abi.encodePacked("lattice.", names[i]));
            assertEq(registry.latest(nh).version, packed020, string.concat(names[i], ": latest downgraded"));
        }
    }

    /// @notice A complete prior release under a DIFFERENT owner (all facets already at their canonical
    ///         addresses, but no registry at this owner's derived address) is a misconfiguration, not a
    ///         resume — release() must refuse instead of silently deploying a parallel registry + factory.
    function test_Release_RevertsWhenPriorReleaseUsedDifferentOwner() public {
        this.release(VERSION, address(this));

        (string[] memory names,) = FacetInventory.inventory();
        vm.expectRevert(
            abi.encodeWithSelector(DeployRelease.DeployRelease__PriorReleaseDetected.selector, names.length)
        );
        this.release(VERSION, makeAddr("differentOwner"));
    }

    /// @notice A record that already exists for `(nameHash, version)` but pins a DIFFERENT facet than this
    ///         run resolved means the registry and the manifest would disagree — release() must revert, not
    ///         silently skip.
    function test_Release_RevertsOnRegisteredRecordMismatch() public {
        // Stand the registry up at its canonical address (owner = this) without running a release.
        bytes memory registryInitCode = abi.encodePacked(type(LatticeRegistry).creationCode, abi.encode(address(this)));
        address registry = CreateXDeployer.deployRaw(REGISTRY_SALT, registryInitCode);

        // Register lattice.ERC20@0.1.0 pointing at a DIFFERENT (but valid ERC-8153) facet.
        (string[] memory names, string[] memory paths) = FacetInventory.inventory();
        address wrongFacet;
        bytes32 nameHash = keccak256("lattice.ERC20");
        for (uint256 i; i < names.length; ++i) {
            if (keccak256(bytes(names[i])) == keccak256("AxelarGatewayAdapter")) {
                wrongFacet = CreateXDeployer.deployRaw(keccak256("test.wrong-facet"), vm.getCode(paths[i]));
            }
        }
        ILatticeRegistry(registry).register(nameHash, PACKED, wrongFacet);

        address expectedErc20;
        for (uint256 i; i < names.length; ++i) {
            if (keccak256(bytes(names[i])) == keccak256("ERC20")) {
                expectedErc20 = CreateXDeployer.predictRaw(facetSalt("ERC20", VERSION), keccak256(vm.getCode(paths[i])));
            }
        }

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployRelease.DeployRelease__RecordMismatch.selector, nameHash, wrongFacet, expectedErc20
            )
        );
        this.release(VERSION, address(this));
    }

    /// @notice When the registry's owner is NOT the broadcaster (mainnet multisig flow), release() still
    ///         deploys everything but skips the whole registration phase without reverting.
    function test_Release_NonOwnerBroadcasterSkipsRegistration() public {
        address multisig = makeAddr("multisig");
        DeployRelease.ReleaseOutput memory out = this.release(VERSION, multisig);

        assertEq(ILatticeRegistry(out.registry).owner(), multisig, "registry owner not the multisig");
        for (uint256 i; i < out.facets.length; ++i) {
            assertGt(out.facets[i].code.length, 0, "facet not deployed under non-owner broadcaster");
        }

        (string[] memory names,) = FacetInventory.inventory();
        bytes32 nameHash = keccak256(abi.encodePacked("lattice.", names[0]));
        vm.expectRevert(
            abi.encodeWithSelector(ILatticeRegistry.LatticeRegistry__RecordNotFound.selector, nameHash, PACKED)
        );
        ILatticeRegistry(out.registry).get(nameHash, PACKED);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             VERSION PARSER
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice "MAJOR.MINOR.PATCH" packs to `major<<48 | minor<<24 | patch`, multi-digit included.
    function test_PackVersion_Golden() public view {
        assertEq(packVersion("0.1.0"), PACKED, "0.1.0 mispacked");
        assertEq(
            packVersion("12.34.56"),
            (uint64(12) << 48) | (uint64(34) << 24) | uint64(56),
            "multi-digit version mispacked"
        );
        assertEq(packVersion("1.0.0"), uint64(1) << 48, "1.0.0 mispacked");
    }

    /// @notice Malformed version strings revert instead of silently mispacking a release: wrong shape,
    ///         non-digits, the reserved 0.0.0 sentinel, out-of-range fields (major >= 2^16, minor/patch >=
    ///         2^24), and leading zeros ("0.01.0" would pack identically to "0.1.0" while deriving
    ///         DIFFERENT facet salts — a duplicate parallel facet set the registry never serves).
    function test_PackVersion_RevertsOnMalformed() public {
        string[11] memory bad =
            ["1.2", "a.b.c", "1.2.3.4", "", "1..2", "0.0.0", "65536.0.0", "0.16777216.0", "0.01.0", "00.1.0", "0.1.00"];
        for (uint256 i; i < bad.length; ++i) {
            vm.expectRevert(abi.encodeWithSelector(DeployRelease.DeployRelease__MalformedVersion.selector, bad[i]));
            this.packVersion(bad[i]);
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INVENTORY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Pins the inventory's internal consistency: exactly 99 entries, every path ends with
    ///         `<name>.sol:<name>` (dir-qualified for src/ facets, bare-basename for the diamond-lib core
    ///         facets — a swapped or drifted name<->path pairing fails loudly either way), and no
    ///         duplicate names (duplicate names would collide on nameHash + salt).
    function test_Inventory_NamePathPairingUniqueCount() public pure {
        (string[] memory names, string[] memory paths) = FacetInventory.inventory();
        assertEq(names.length, 99, "inventory count drifted");
        assertEq(paths.length, names.length, "names/paths length mismatch");

        for (uint256 i; i < names.length; ++i) {
            // Dir-qualified paths must end "/<name>.sol:<name>"; bare-basename lib entries ARE exactly
            // "<name>.sol:<name>" (no leading slash to require).
            string memory expected = string.concat(names[i], ".sol:", names[i]);
            bytes memory p = bytes(paths[i]);
            bytes memory s = bytes(expected);
            bool bare = p.length == s.length;
            assertTrue(bare || p.length > s.length, string.concat(names[i], ": path shorter than expected suffix"));
            for (uint256 j; j < s.length; ++j) {
                assertEq(p[p.length - s.length + j], s[j], string.concat(names[i], ": path does not match its name"));
            }
            if (!bare) {
                assertEq(p[p.length - s.length - 1], "/", string.concat(names[i], ": qualified path missing separator"));
            }
            for (uint256 k = i + 1; k < names.length; ++k) {
                assertTrue(
                    keccak256(bytes(names[i])) != keccak256(bytes(names[k])),
                    string.concat(names[i], ": duplicate inventory name")
                );
            }
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             SALT DERIVATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Pins the exact salt strings and the raw-salt guard reproduction: the script's predictRaw math
    ///         must equal CreateX's own `computeCreate2Address(keccak256(abi.encode(salt)), initCodeHash)`,
    ///         and deployRaw must land there.
    function test_SaltDerivationGoldens() public {
        assertEq(REGISTRY_SALT, keccak256("lattice.LatticeRegistry"), "registry salt formula drifted");
        assertEq(FACTORY_SALT, keccak256("lattice.LatticeFactory"), "factory salt formula drifted");

        bytes32 salt = facetSalt("ERC20", "0.1.0");
        assertEq(salt, keccak256(abi.encodePacked("lattice.ERC20.0.1.0")), "facet salt formula drifted");

        bytes memory initCode = vm.getCode("src/tokens/ERC20/ERC20.sol:ERC20");
        bytes32 initCodeHash = keccak256(initCode);
        address predicted = CreateXDeployer.predictRaw(salt, initCodeHash);
        assertEq(
            predicted,
            MockCreateX(CANONICAL).computeCreate2Address(keccak256(abi.encode(salt)), initCodeHash),
            "predictRaw does not reproduce the raw-salt guard"
        );
        assertEq(CreateXDeployer.deployRaw(salt, initCode), predicted, "deployRaw != predictRaw");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                MANIFEST
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The manifest writer produces `<root>/<chainid>/release-<version>.json` with the top-level
    ///         addresses and one entry per facet carrying the two pins the registry records (codehash +
    ///         selectorsHash). Writes under an isolated test root so a REAL committed manifest under
    ///         `deployments/<chainid>/` is never overwritten or deleted, and cleans up only its own tree.
    function test_Manifest_WrittenAndWellFormed() public {
        DeployRelease.ReleaseOutput memory out = this.release(VERSION, address(this));
        string memory testRoot = "deployments/.test-tmp";
        _writeManifest(testRoot, VERSION, out);

        string memory dir = string.concat(testRoot, "/", vm.toString(block.chainid));
        string memory path = string.concat(dir, "/release-", VERSION, ".json");
        assertTrue(vm.exists(path), "manifest file not written");

        string memory json = vm.readFile(path);
        assertEq(vm.parseJsonString(json, ".version"), VERSION, "manifest version");
        assertEq(vm.parseJsonUint(json, ".chainid"), block.chainid, "manifest chainid");
        assertEq(vm.parseJsonAddress(json, ".createx"), CANONICAL, "manifest createx");
        assertEq(vm.parseJsonAddress(json, ".registry"), out.registry, "manifest registry");
        assertEq(vm.parseJsonAddress(json, ".factory"), out.factory, "manifest factory");
        assertEq(vm.parseJsonAddress(json, ".owner"), address(this), "manifest owner");

        (string[] memory names,) = FacetInventory.inventory();
        for (uint256 i; i < names.length; ++i) {
            string memory base = string.concat(".facets.", names[i]);
            assertEq(
                vm.parseJsonAddress(json, string.concat(base, ".address")),
                out.facets[i],
                string.concat(names[i], ": manifest facet address")
            );
            assertEq(
                vm.parseJsonString(json, string.concat(base, ".name")),
                names[i],
                string.concat(names[i], ": manifest facet name")
            );
            assertEq(
                vm.parseJsonBytes32(json, string.concat(base, ".codehash")),
                out.facets[i].codehash,
                string.concat(names[i], ": manifest codehash != live codehash")
            );
            assertEq(
                vm.parseJsonBytes32(json, string.concat(base, ".selectorsHash")),
                keccak256(IERC8153(out.facets[i]).exportSelectors()),
                string.concat(names[i], ": manifest selectorsHash != live export hash")
            );
        }
        assertEq(vm.parseJsonBytes32(json, ".facets.ERC20.salt"), facetSalt("ERC20", VERSION), "manifest facet salt");

        // Remove ONLY the isolated test tree — never the real deployments root or its manifests.
        vm.removeFile(path);
        vm.removeDir(dir, false);
        vm.removeDir(testRoot, false);
    }
}

/// @notice release() without CreateX code at the canonical address must fail loudly and point local runs at
///         the mock helper — separate contract so no setUp etch runs.
contract DeployReleaseNoCreateXTest is Test, DeployRelease {
    function test_Release_RevertsWithoutCreateX() public {
        vm.expectRevert(
            bytes(
                "DeployRelease: CreateX has no code at 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed on this chain; for local/test runs etch test/helpers/MockCreateX.sol at that address first"
            )
        );
        this.release("0.1.0", address(this));
    }
}
