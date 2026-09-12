// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";
import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @title BaseDeploy
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Generic building blocks every ready-to-deploy Lattice diamond script shares: turn a facet contract
///         into an `Add`/`Replace` {FacetCut}, and assemble a {Diamond} proxy from cuts + an initializer.
///         Two selector sources coexist: the ADDRESS helpers (`_cut(addr)`) read the facet's own
///         {IERC8153-exportSelectors}, so a facet self-reports the selectors it owns with no FFI — since
///         diamond-lib v0.2.0 this covers EVERY production facet, the lib's included ({ERC165Facet},
///         {DiamondCutFacet}, {DiamondLoupeFacet}, `OwnableFacet` all implement `IFacet`, the identical
///         upstream interface); the STRING helpers (`_cut(addr, "Name")`) resolve selectors from the facet's
///         real ABI via the vendored {GetSelectors}/`forge inspect` FFI and remain ONLY for legacy call sites
///         and non-8153 test fixtures (new code should use the address helpers). Both paths strip
///         `exportSelectors()` (0x0ef22643): the diamond never exposes ERC-8153 facet introspection.
///         `_assemble*` create and initialize each proxy in ONE transaction through {LatticeFactory}; concrete
///         scripts wrap their `run()` in `vm.startBroadcast()`, and tests compose via `buildCuts`. Mirrors the intent of
///         diamond-lib's {DeployDiamond} but factored so per-family scripts ({DeployAccount}, {DeployERC20}, …)
///         stay tiny.
abstract contract BaseDeploy is Script, GetSelectors {
    /// @dev `IERC8153.exportSelectors()` selector. The diamond never exposes ERC-8153 introspection, so this
    ///      selector is stripped from every FFI (`forge inspect`) selector set: once a facet implements
    ///      {IERC8153}, `forge inspect` lists `exportSelectors()` in its ABI, and cutting it onto a second facet
    ///      of the same recipe would revert `CannotAddFunctionToDiamondThatAlreadyExists`. The address-based
    ///      helpers read the runtime `exportSelectors()` return, which already excludes it by the ERC-8153 rule.
    bytes4 private constant _EXPORT_SELECTORS = 0x0ef22643;

    /// @dev The factory `_assemble` uses on each chain during this run (multi-fork scripts assemble on several).
    mapping(uint256 chainId => LatticeFactory) private _factories;

    /// @dev Diamonds assembled so far by this script instance — mixed into each diamond's CREATE2 salt.
    uint256 private _assembled;

    //*//////////////////////////////////////////////////////////////////////////
    //                      STRING (forge inspect) CUTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice An `Add` cut for `facet` covering every selector `name`'s ABI declares (minus `exportSelectors()`).
    /// @param facet The deployed facet address.
    /// @param name The facet contract name (for `forge inspect`).
    function _cut(address facet, string memory name) internal returns (FacetCut memory) {
        return FacetCut({
            facetAddress: facet,
            action: FacetCutAction.Add,
            functionSelectors: _withoutExportSelector(_getSelectors(name))
        });
    }

    /// @notice A `Replace` cut for `facet` (its selectors must already exist on the diamond).
    function _replace(address facet, string memory name) internal returns (FacetCut memory) {
        return FacetCut({
            facetAddress: facet,
            action: FacetCutAction.Replace,
            functionSelectors: _withoutExportSelector(_getSelectors(name))
        });
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      ERC-8153 (exportSelectors) CUTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice An `Add` cut for an ERC-8153 `facet`, selectors sourced from its own `exportSelectors()` — no
    ///         `forge inspect`/FFI, no contract name. The facet self-reports exactly the selectors it owns.
    /// @param facet The deployed facet address (MUST implement {IERC8153}).
    function _cut(address facet) internal view returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: _exportedSelectors(facet)});
    }

    /// @notice A `Replace` cut for an ERC-8153 `facet` (its exported selectors must already exist on the diamond).
    function _replace(address facet) internal view returns (FacetCut memory) {
        return
            FacetCut({
                facetAddress: facet, action: FacetCutAction.Replace, functionSelectors: _exportedSelectors(facet)
            });
    }

    /// @notice An `Add` cut of an ERC-8153 `facet`'s exported selectors MINUS `excluded` — for facets whose
    ///         reconciled selectors are owned by a sibling facet (or a reconciliation facet) in a shared diamond.
    /// @param facet The deployed facet address (MUST implement {IERC8153}).
    /// @param excluded The selectors to drop from `facet`'s cut.
    function _cutExcept(address facet, bytes4[] memory excluded) internal view returns (FacetCut memory) {
        bytes4[] memory all = _exportedSelectors(facet);
        bytes4[] memory kept = new bytes4[](all.length);
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            if (!_containsSelector(excluded, all[i])) kept[n++] = all[i];
        }
        assembly ("memory-safe") {
            mstore(kept, n)
        }
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: kept});
    }

    /// @notice Reads, validates, and decodes an ERC-8153 facet's tightly packed `exportSelectors()` bytes.
    /// @dev Staticcalls {IERC8153-exportSelectors}; requires the call to succeed, a non-empty return, and a
    ///      length that is a whole number of 4-byte selectors. Each 4-byte chunk becomes one `bytes4` selector.
    /// @param facet The deployed facet address (MUST implement {IERC8153}).
    /// @return selectors The decoded selectors, one per packed 4-byte chunk.
    function _exportedSelectors(address facet) internal view returns (bytes4[] memory selectors) {
        (bool ok, bytes memory ret) = facet.staticcall(abi.encodeCall(IERC8153.exportSelectors, ()));
        require(ok, "BaseDeploy: exportSelectors() staticcall reverted");
        bytes memory packed = abi.decode(ret, (bytes));
        uint256 len = packed.length;
        require(len != 0, "BaseDeploy: exportSelectors() returned no selectors");
        require(len % 4 == 0, "BaseDeploy: exportSelectors() length not a multiple of 4");

        uint256 count = len / 4;
        selectors = new bytes4[](count);
        for (uint256 i; i < count; ++i) {
            bytes4 sel;
            assembly ("memory-safe") {
                sel := mload(add(add(packed, 0x20), mul(i, 4)))
            }
            selectors[i] = sel;
        }
    }

    /// @dev Returns `sels` without the ERC-8153 `exportSelectors()` selector (never cut onto the diamond).
    function _withoutExportSelector(bytes4[] memory sels) private pure returns (bytes4[] memory kept) {
        kept = new bytes4[](sels.length);
        uint256 n;
        for (uint256 i; i < sels.length; ++i) {
            if (sels[i] != _EXPORT_SELECTORS) kept[n++] = sels[i];
        }
        assembly ("memory-safe") {
            mstore(kept, n)
        }
    }

    /// @dev True if `set` contains `sel`.
    function _containsSelector(bytes4[] memory set, bytes4 sel) private pure returns (bool) {
        for (uint256 i; i < set.length; ++i) {
            if (set[i] == sel) return true;
        }
        return false;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            RELEASED FACETS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The {FacetInventory} facet `name` at its release address (see {DeployRelease}): reused when code
    ///         already lives there, otherwise deployed there through CreateX — or, on a chain CreateX never
    ///         reached, through the {CreateXDeployer.ARACHNID_PROXY} fallback at that chain's own release
    ///         address. Only a chain with NEITHER deployer gets a plain CREATE instead — rarer than it sounds,
    ///         since Anvil and Foundry's test EVM both pre-deploy that proxy as their default CREATE2 deployer.
    /// @dev The address commits to the initcode, so a facet compiled from code that differs from the release
    ///      at {LatticeVersion.VERSION} lands at an unrelated address instead of colliding with it. Anyone may
    ///      deploy a missing facet; {DeployRelease} later skips it and registers it.
    /// @param name The facet contract name exactly as listed in {FacetInventory}.
    function _facet(string memory name) internal returns (address facet) {
        string memory path = _inventoryPath(name);
        if (!CreateXDeployer.hasRawDeployer()) return deployCode(path);
        bytes memory initCode = vm.getCode(path);
        bytes32 salt = keccak256(abi.encodePacked("lattice.", name, ".", LatticeVersion.VERSION));
        facet = CreateXDeployer.predictRaw(salt, keccak256(initCode));
        if (facet.code.length == 0) {
            require(CreateXDeployer.deployRaw(salt, initCode) == facet, "BaseDeploy: facet deployed != predicted");
        }
    }

    /// @dev The `vm.getCode` artifact path of {FacetInventory} entry `name`.
    function _inventoryPath(string memory name) private pure returns (string memory) {
        (string[] memory names, string[] memory paths) = FacetInventory.inventory();
        for (uint256 i; i < names.length; ++i) {
            if (keccak256(bytes(names[i])) == keccak256(bytes(name))) return paths[i];
        }
        revert(string.concat("BaseDeploy: ", name, " is not in FacetInventory"));
    }

    /// @notice Deploys a {Lattice} proxy and initializes it with `cuts` + a single `init` delegatecall in ONE
    ///         transaction, through {LatticeFactory}.
    /// @dev The proxy's initializer is first-caller-wins, so deploying the proxy and initializing it in separate
    ///      broadcast transactions would let anyone initialize it in between. The factory does both atomically.
    ///      Diamond `i` of a run uses salt `keccak256(abi.encode(LATTICE_SALT, i))`, which the factory binds to
    ///      its caller. An occupied address reverts here instead of taking the factory's idempotent return,
    ///      which would silently ignore these cuts. Broadcast-free — a production `run()` wraps the call in
    ///      `vm.startBroadcast()`.
    function _assemble(FacetCut[] memory cuts, address init, bytes memory initCalldata)
        internal
        returns (address diamond)
    {
        address broadcaster = _broadcaster();
        LatticeFactory factory = _latticeFactory();
        bytes32 baseSalt = broadcaster == address(0) ? bytes32(0) : vm.envOr("LATTICE_SALT", bytes32(0));
        bytes32 salt = keccak256(abi.encode(baseSalt, _assembled++));
        address caller = broadcaster == address(0) ? address(this) : broadcaster;
        require(
            factory.predict(caller, salt).code.length == 0,
            "BaseDeploy: diamond already deployed for this caller and salt; set a new LATTICE_SALT"
        );
        diamond = factory.deploy(new RecipeEntry[](0), cuts, init, initCalldata, salt);
    }

    /// @notice The {LatticeFactory} `_assemble` deploys through: `LATTICE_FACTORY` while broadcasting, else a
    ///         {LatticeRegistry} + {LatticeFactory} pair created once per chain for this run.
    /// @dev Tests never read the environment, so a developer's `.env` cannot change test deployments.
    function _latticeFactory() internal virtual returns (LatticeFactory factory) {
        address broadcaster = _broadcaster();
        address configured = broadcaster == address(0) ? address(0) : vm.envOr("LATTICE_FACTORY", address(0));
        if (configured != address(0)) {
            require(configured.code.length != 0, "BaseDeploy: LATTICE_FACTORY has no code on this chain");
            return LatticeFactory(configured);
        }
        factory = _factories[block.chainid];
        if (address(factory).code.length == 0) {
            address registryOwner = broadcaster == address(0) ? address(this) : broadcaster;
            factory = new LatticeFactory(new LatticeRegistry(registryOwner), address(0), address(0));
            _factories[block.chainid] = factory;
        }
    }

    /// @dev The active broadcaster, or `address(0)` outside `vm.startBroadcast()` (tests call recipes directly).
    function _broadcaster() private view returns (address broadcaster) {
        (VmSafe.CallerMode mode, address sender,) = vm.readCallers();
        if (mode == VmSafe.CallerMode.Broadcast || mode == VmSafe.CallerMode.RecurrentBroadcast) {
            broadcaster = sender;
        }
    }

    /// @notice Deploys a {Diamond} whose init runs SEVERAL initializers in order via {MultiInit} — the way to
    ///         seed a multi-facet diamond (e.g. a permit token: ERC-20 + EIP-712 + Nonces) without a bespoke
    ///         per-recipe init contract. Each `inits[i]` is delegatecalled inside the same initializing window.
    /// @param cuts The facet cuts.
    /// @param inits The initializer contracts, run in order.
    /// @param initCalldatas The calldata for each initializer (must match `inits` length).
    function _assembleMulti(FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
        internal
        returns (address diamond)
    {
        MultiInit multiInit = new MultiInit();
        diamond = _assemble(cuts, address(multiInit), abi.encodeCall(MultiInit.multiInit, (inits, initCalldatas)));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      INTROSPECTION INIT CHAINING
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Chains a recipe's module init with {DiamondIntrospectionInit.initUpgradeable} (IDiamondCut +
    ///         IDiamondLoupe ERC-165 flags) behind ONE `MultiInit`-wrapped (init, calldata) pair — for
    ///         recipes that cut `DiamondLoupeFacet` + a `diamondCut`-carrying facet. Keeps `buildCuts`'s
    ///         single-init return shape so extension recipes and testbases compose unchanged.
    /// @param moduleInit The recipe's own initializer contract.
    /// @param moduleCalldata The calldata for `moduleInit`.
    /// @return init The wrapping {MultiInit} address.
    /// @return initCalldata The `multiInit([moduleInit, introspection], [moduleCalldata, initUpgradeable()])`.
    function _withUpgradeableIntrospection(address moduleInit, bytes memory moduleCalldata)
        internal
        returns (address init, bytes memory initCalldata)
    {
        return _withIntrospection(moduleInit, moduleCalldata, true);
    }

    /// @notice Same chaining with {DiamondIntrospectionInit.initImmutable} (IDiamondLoupe flag ONLY) — for
    ///         immutable-by-design recipes that cut `DiamondLoupeFacet` but deliberately no cut facet.
    function _withImmutableIntrospection(address moduleInit, bytes memory moduleCalldata)
        internal
        returns (address init, bytes memory initCalldata)
    {
        return _withIntrospection(moduleInit, moduleCalldata, false);
    }

    /// @notice Chains a recipe's module init with {AccessControlInit} (seeding `admin` as
    ///         `DEFAULT_ADMIN_ROLE`) and {DiamondIntrospectionInit.initUpgradeable} — the init shape of a
    ///         Class-Z recipe's ADMIN overload, where the otherwise-immutable diamond additionally cuts
    ///         `AccessControl` + `AccessControlDiamondCut` so `admin` can upgrade it.
    /// @param moduleInit The recipe's own initializer contract.
    /// @param moduleCalldata The calldata for `moduleInit`.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE` (the upgrade authority).
    function _withAdminUpgradeableIntrospection(address moduleInit, bytes memory moduleCalldata, address admin)
        internal
        returns (address init, bytes memory initCalldata)
    {
        address[] memory inits = new address[](3);
        inits[0] = moduleInit;
        inits[1] = address(new AccessControlInit());
        inits[2] = address(new DiamondIntrospectionInit());
        bytes[] memory calldatas = new bytes[](3);
        calldatas[0] = moduleCalldata;
        calldatas[1] = abi.encodeCall(AccessControlInit.init, (admin));
        calldatas[2] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
        init = address(new MultiInit());
        initCalldata = abi.encodeCall(MultiInit.multiInit, (inits, calldatas));
    }

    /// @dev Shared body: wraps `[moduleInit, DiamondIntrospectionInit]` in a fresh {MultiInit}.
    function _withIntrospection(address moduleInit, bytes memory moduleCalldata, bool upgradeable)
        private
        returns (address init, bytes memory initCalldata)
    {
        address[] memory inits = new address[](2);
        inits[0] = moduleInit;
        inits[1] = address(new DiamondIntrospectionInit());
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = moduleCalldata;
        calldatas[1] = upgradeable
            ? abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ())
            : abi.encodeCall(DiamondIntrospectionInit.initImmutable, ());
        init = address(new MultiInit());
        initCalldata = abi.encodeCall(MultiInit.multiInit, (inits, calldatas));
    }
}
