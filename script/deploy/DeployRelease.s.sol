// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {DiamondFactory} from "@lattice/factory/DiamondFactory.sol";
import {IERC8153} from "@lattice/interfaces/external/IERC8153.sol";
import {ILatticeRegistry} from "@lattice/interfaces/registry/ILatticeRegistry.sol";
import {LatticeRegistry} from "@lattice/registry/LatticeRegistry.sol";
import {Script, console} from "forge-std/Script.sol";

/// @title DeployRelease
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice THE canonical Lattice release script (issue #120): one run deterministically deploys the
///         {LatticeRegistry} singleton, the {DiamondFactory}, and every {FacetInventory} facet through
///         CreateX CREATE2 at raw protocol salts, then registers each facet under
///         `keccak256("lattice.<Name>")` at the semver-packed version and points `latest` at it, and
///         finally writes a per-chain JSON manifest.
///
/// Usage (one release, one chain):
///   forge script script/deploy/DeployRelease.s.sol \
///     --sig "run(string,address)" 0.1.0 <OWNER> \
///     --rpc-url <chain> --account <name> --broadcast
///
/// @dev Salt scheme — raw protocol salts, so every address is deployer- AND chain-independent and commits
///      to the initcode (see {CreateXDeployer.deployRaw}):
///        registry: `keccak256("lattice.LatticeRegistry")` (deploy-once singleton, versionless)
///        factory:  `keccak256("lattice.DiamondFactory")`  (versionless)
///        facet:    `keccak256("lattice.<Name>.<version>")` e.g. `keccak256("lattice.ERC20.0.1.0")`
///
///      IDEMPOTENT + RESUMABLE: every deploy is predict-then-skip-if-code, and registration skips records
///      that already exist, so a run that died halfway (or a release someone else partially completed) is
///      finished by simply re-running the same command. The predict-then-skip guard executes during forge's
///      SIMULATION; if someone lands code at an address between simulation and inclusion, that broadcast tx
///      reverts (CreateX refuses an occupied address) — harmless, re-run and it is skipped. `latest` only
///      ever advances: re-running an older release never downgrades the pointer. PERMISSIONLESS COMPLETION:
///      because each CREATE2 address commits to `keccak256(initCode)`, ANYONE may deploy the missing pieces
///      — a squatter can only ever put the canonical bytecode at the canonical address.
///
///      OWNER IS PART OF THE REGISTRY'S IDENTITY: the registry's CREATE2 address derives from its initcode,
///      which ABI-encodes `owner` — always pass the SAME owner on every chain and every resume. A different
///      owner derives a DIFFERENT registry (a parallel universe, not a resume); when a complete prior
///      release is detectable (all facets exist, registry missing at this owner's address) the run refuses
///      with {DeployRelease__PriorReleaseDetected}.
///
///      REGISTRATION AND THE MULTISIG RULE: `register`/`setLatest` are owner-only, so the phase runs only
///      when `registry.owner() == msg.sender` — run with `--account`/`--sender` so the script's
///      `msg.sender` equals the broadcasting EOA. Repo security policy: the registry admin MUST be a
///      multisig from the first mainnet release, so on mainnet the broadcaster deploys everything, the
///      registration phase logs and skips, and the multisig registers out-of-band (the manifest has every
///      address it needs).
///
///      {release} holds ALL on-chain logic and uses no broadcast/prank cheatcodes (only the read-only
///      `vm.getCode`), so tests drive it exactly as production runs it.
contract DeployRelease is Script {
    //*//////////////////////////////////////////////////////////////////////////
    //                              TYPES / ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Everything a release run produces (all addresses are the deterministic raw-salt ones).
    /// @param registry The {LatticeRegistry} singleton.
    /// @param factory The {DiamondFactory} bound to `registry`.
    /// @param facets The released facet addresses, index-aligned with {FacetInventory.inventory} names.
    struct ReleaseOutput {
        address registry;
        address factory;
        address[] facets;
    }

    /// @notice Thrown when `version` is not a well-formed "MAJOR.MINOR.PATCH" semver string (all-digit,
    ///         non-empty components; major < 2^16, minor/patch < 2^24; "0.0.0" is the registry's reserved
    ///         sentinel and equally refused).
    error DeployRelease__MalformedVersion(string version);

    /// @notice Thrown when every inventory facet already exists at its canonical address but the registry
    ///         does NOT exist at the address derived from THIS run's `owner` — a complete prior release ran
    ///         on this chain under a different owner, and proceeding would silently deploy a parallel
    ///         registry + factory and register the release into the fork. Re-run with the original owner
    ///         (see REGISTRY_DEPLOYMENTS.md), or set `LATTICE_ALLOW_PREDEPLOYED=true` if the facets were
    ///         genuinely pre-deployed by a third party ahead of any release.
    error DeployRelease__PriorReleaseDetected(uint256 skippedFacets);

    /// @notice Thrown when `(nameHash, version)` is already registered but pins a DIFFERENT facet address
    ///         than this run resolved — the registry and the manifest would permanently disagree about what
    ///         the release serves (records are append-only/immutable).
    error DeployRelease__RecordMismatch(bytes32 nameHash, address registered, address released);

    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Raw CREATE2 salt of the deploy-once {LatticeRegistry} singleton (versionless).
    bytes32 internal constant REGISTRY_SALT = keccak256("lattice.LatticeRegistry");

    /// @notice Raw CREATE2 salt of the {DiamondFactory} (versionless).
    bytes32 internal constant FACTORY_SALT = keccak256("lattice.DiamondFactory");

    //*//////////////////////////////////////////////////////////////////////////
    //                                ENTRY POINT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Broadcasts a full release and writes `deployments/<chainid>/release-<version>.json`.
    /// @param version The release semver string, e.g. `"0.1.0"`.
    /// @param owner The {LatticeRegistry} initial owner (multisig on mainnet). Part of the registry's
    ///        CREATE2 identity — pass the SAME owner on every chain and every resume (see the
    ///        contract-level notes); a different owner derives a different, parallel registry.
    function run(string calldata version, address owner) external {
        vm.startBroadcast();
        ReleaseOutput memory out = release(version, owner);
        vm.stopBroadcast();
        _writeManifest("deployments", version, out);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              RELEASE PIPELINE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The whole on-chain release: deploy-or-skip the registry, the factory, and every inventory
    ///         facet at their deterministic addresses, then (broadcaster == registry owner only) register
    ///         each facet and point `latest` at this version.
    /// @dev No broadcast/prank cheatcodes in here — callable from tests exactly as production runs it.
    /// @param version The release semver string (also part of every facet salt).
    /// @param owner The registry's initial owner if the registry is deployed by this run.
    /// @return out The released addresses (see {ReleaseOutput}).
    function release(string calldata version, address owner) public returns (ReleaseOutput memory out) {
        require(
            address(CreateXDeployer.CREATEX).code.length != 0,
            "DeployRelease: CreateX has no code at 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed on this chain; for local/test runs etch test/helpers/MockCreateX.sol at that address first"
        );

        uint64 packed = packVersion(version);

        // --- Phase 1: core singletons -------------------------------------------------------------
        bool deployedNow;
        bool registryDeployedNow;
        (out.registry, registryDeployedNow) = _deployOrSkip(
            REGISTRY_SALT, abi.encodePacked(type(LatticeRegistry).creationCode, abi.encode(owner)), "LatticeRegistry"
        );
        console.log(
            registryDeployedNow ? "LatticeRegistry deployed:" : "LatticeRegistry already deployed:", out.registry
        );

        (out.factory, deployedNow) = _deployOrSkip(
            FACTORY_SALT,
            abi.encodePacked(type(DiamondFactory).creationCode, abi.encode(out.registry)),
            "DiamondFactory"
        );
        console.log(deployedNow ? "DiamondFactory deployed:" : "DiamondFactory already deployed:", out.factory);

        // --- Phase 2: facets ----------------------------------------------------------------------
        (string[] memory names, string[] memory paths) = FacetInventory.inventory();
        uint256 count = names.length;
        out.facets = new address[](count);
        uint256 deployedCount;
        for (uint256 i; i < count; ++i) {
            (out.facets[i], deployedNow) = _deployOrSkip(facetSalt(names[i], version), vm.getCode(paths[i]), names[i]);
            if (deployedNow) ++deployedCount;
        }
        console.log("Facets deployed:", deployedCount, "| skipped (already deployed):", count - deployedCount);

        // The registry address derives from `owner` (it is in the initcode), so a fresh registry alongside
        // ALREADY-deployed facets means a prior run used a DIFFERENT owner — this run just deployed a
        // PARALLEL registry and would register the release into the fork. All 95 skipped = a complete prior
        // release: refuse (re-run with the original owner; LATTICE_ALLOW_PREDEPLOYED=true overrides for
        // genuinely third-party-pre-deployed facets). A partial overlap is legitimate permissionless
        // completion, but gets a loud warning for the same reason.
        if (registryDeployedNow && deployedCount < count) {
            if (deployedCount == 0 && !vm.envOr("LATTICE_ALLOW_PREDEPLOYED", false)) {
                revert DeployRelease__PriorReleaseDetected(count);
            }
            console.log("WARNING: registry freshly deployed but", count - deployedCount, "facet(s) already existed");
            console.log("  -> if a prior release used a DIFFERENT owner, this run created a PARALLEL registry");
        }

        // --- Phase 3: registration (broadcaster must own the registry) -----------------------------
        ILatticeRegistry registry = ILatticeRegistry(out.registry);
        if (registry.owner() != msg.sender) {
            console.log("Registration SKIPPED: broadcaster is not the registry owner", registry.owner());
            console.log("  -> the owner (e.g. the mainnet multisig) registers this release out-of-band");
            return out;
        }

        uint256 registeredCount;
        for (uint256 i; i < count; ++i) {
            bytes32 nameHash = keccak256(abi.encodePacked("lattice.", names[i]));

            try registry.get(nameHash, packed) returns (ILatticeRegistry.Record memory record) {
                // Already registered (a resumed run). Records are append-only/immutable, so the pinned facet
                // MUST be the one this run resolved — otherwise the manifest would lie about what the
                // registry serves.
                if (record.facet != out.facets[i]) {
                    revert DeployRelease__RecordMismatch(nameHash, record.facet, out.facets[i]);
                }
            } catch {
                registry.register(nameHash, packed, out.facets[i]);
                ++registeredCount;
            }

            // `latest` only ever advances (semver packing is numerically ordered): re-running an OLDER
            // release after a newer one shipped must never downgrade the pointer.
            try registry.latest(nameHash) returns (ILatticeRegistry.Record memory latestRecord) {
                if (latestRecord.version < packed) registry.setLatest(nameHash, packed);
            } catch {
                registry.setLatest(nameHash, packed);
            }
        }
        console.log("Facets registered:", registeredCount, "| already registered:", count - registeredCount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SALT / VERSION MATH
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The raw CREATE2 salt of a released facet: `keccak256("lattice.<name>.<version>")`.
    /// @param name The facet contract name from {FacetInventory}, e.g. `"ERC20"`.
    /// @param version The release semver string, e.g. `"0.1.0"`.
    /// @return salt The raw protocol salt to pass to {CreateXDeployer.deployRaw}/{predictRaw}.
    function facetSalt(string memory name, string memory version) public pure returns (bytes32 salt) {
        salt = keccak256(abi.encodePacked("lattice.", name, ".", version));
    }

    /// @notice Packs a "MAJOR.MINOR.PATCH" semver string the way {ILatticeRegistry} orders versions:
    ///         `major<<48 | minor<<24 | patch`.
    /// @dev Reverts {DeployRelease__MalformedVersion} on anything but exactly three non-empty all-digit
    ///      components within field bounds, and on "0.0.0" (the registry's reserved "latest unset" sentinel).
    /// @param version The semver string; multi-digit components supported.
    /// @return packed The semver-packed `uint64` registry version key.
    function packVersion(string memory version) public pure returns (uint64 packed) {
        bytes memory b = bytes(version);
        uint256[3] memory parts;
        uint256 component;
        uint256 digits;
        for (uint256 i; i < b.length; ++i) {
            bytes1 c = b[i];
            if (c == ".") {
                if (digits == 0 || component == 2) revert DeployRelease__MalformedVersion(version);
                ++component;
                digits = 0;
            } else if (c >= "0" && c <= "9") {
                // Leading zeros are refused: "0.01.0" would pack identically to "0.1.0" while deriving
                // DIFFERENT facet salts — a duplicate facet set the registry would never serve.
                if (digits != 0 && parts[component] == 0) revert DeployRelease__MalformedVersion(version);
                parts[component] = parts[component] * 10 + (uint8(c) - 48);
                if (parts[component] > type(uint24).max) revert DeployRelease__MalformedVersion(version);
                ++digits;
            } else {
                revert DeployRelease__MalformedVersion(version);
            }
        }
        if (component != 2 || digits == 0 || parts[0] > type(uint16).max) {
            revert DeployRelease__MalformedVersion(version);
        }
        packed = (uint64(parts[0]) << 48) | (uint64(parts[1]) << 24) | uint64(parts[2]);
        if (packed == 0) revert DeployRelease__MalformedVersion(version);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 MANIFEST
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Serializes the release to `<deploymentsRoot>/<chainid>/release-<version>.json`: top-level
    ///      version / chainid / createx / registry / factory / owner (read live off the registry) /
    ///      timestamp, plus one entry per facet with its name, address, codehash, live
    ///      `keccak256(exportSelectors())`, and salt. `run` passes `"deployments"`; the unit test passes an
    ///      isolated root so a real committed manifest is never touched. Internal (not private) so the unit
    ///      test can drive it directly.
    function _writeManifest(string memory deploymentsRoot, string memory version, ReleaseOutput memory out) internal {
        (string[] memory names,) = FacetInventory.inventory();

        string memory facetsJson;
        for (uint256 i; i < names.length; ++i) {
            string memory key = string.concat("facet:", names[i]);
            vm.serializeString(key, "name", names[i]);
            vm.serializeAddress(key, "address", out.facets[i]);
            vm.serializeBytes32(key, "codehash", out.facets[i].codehash);
            vm.serializeBytes32(key, "selectorsHash", _liveSelectorsHash(out.facets[i]));
            string memory facetJson = vm.serializeBytes32(key, "salt", facetSalt(names[i], version));
            facetsJson = vm.serializeString("facets", names[i], facetJson);
        }

        string memory root = "manifest";
        vm.serializeString(root, "version", version);
        vm.serializeUint(root, "chainid", block.chainid);
        vm.serializeAddress(root, "createx", address(CreateXDeployer.CREATEX));
        vm.serializeAddress(root, "registry", out.registry);
        vm.serializeAddress(root, "factory", out.factory);
        vm.serializeAddress(root, "owner", ILatticeRegistry(out.registry).owner());
        vm.serializeUint(root, "timestamp", block.timestamp);
        string memory json = vm.serializeString(root, "facets", facetsJson);

        string memory dir = string.concat(deploymentsRoot, "/", vm.toString(block.chainid));
        vm.createDir(dir, true);
        string memory path = string.concat(dir, "/release-", version, ".json");
        vm.writeJson(json, path);
        console.log("Manifest written:", path);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             PRIVATE HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Predict the raw-salt CREATE2 address for `initCode`; deploy only if nothing lives there yet
    ///      (idempotent resume + permissionless completion both land on identical addresses).
    function _deployOrSkip(bytes32 salt, bytes memory initCode, string memory label)
        private
        returns (address at, bool deployedNow)
    {
        at = CreateXDeployer.predictRaw(salt, keccak256(initCode));
        if (at.code.length == 0) {
            address deployed = CreateXDeployer.deployRaw(salt, initCode);
            require(deployed == at, string.concat("DeployRelease: ", label, " deployed != predicted"));
            deployedNow = true;
        }
    }

    /// @dev `keccak256` of the facet's LIVE ERC-8153 selector blob — the same pin {LatticeRegistry}
    ///      records, so the manifest can be diffed straight against on-chain state.
    function _liveSelectorsHash(address facet) private view returns (bytes32 selectorsHash) {
        (bool ok, bytes memory ret) = facet.staticcall(abi.encodeCall(IERC8153.exportSelectors, ()));
        require(ok && ret.length >= 64, "DeployRelease: exportSelectors() read failed");
        selectorsHash = keccak256(abi.decode(ret, (bytes)));
    }
}
