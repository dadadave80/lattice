// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";

/// @notice One line of a diamond recipe: a curated {ILatticeRegistry} Tier-B facet to resolve and cut.
/// @param nameHash The curated name key (by convention `keccak256("lattice.<FacetName>")`).
/// @param version The semver-packed `uint64` to pin (`major<<48 | minor<<24 | patch`). `0` — the registry's
///        reserved sentinel — means "resolve the curator's `latest(nameHash)` pointer when the transaction
///        EXECUTES": the curator can move it between signing and inclusion, so security-critical recipes pin an
///        exact version, and {ILatticeFactory.deployStrict} refuses `0`.
/// @param exclude Selectors to drop from the entry's registry cut (for a facet cut partially, such as the
///        governed vault's ERC20, whose `name()` another facet serves). Each must be in the facet's pinned
///        export, at most once; the remaining selectors keep their export order. Empty for a whole facet.
struct RecipeEntry {
    bytes32 nameHash;
    uint64 version;
    bytes4[] exclude;
}

/// @title ILatticeFactory
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS ReverseRegistrar (https://github.com/ensdomains/ens-contracts)
/// @notice Stateless factory that assembles a complete EIP-2535 {Diamond} in ONE transaction: recipe entries
///         are resolved into live-verified `Add` cuts by the deploy-once {ILatticeRegistry} (no facet
///         re-`CREATE`, no FFI), classic custom cuts are appended for facets outside the curated catalog,
///         and the resulting proxy is CREATE2-deployed and initialized atomically.
/// @dev The deployer (`msg.sender`) is folded into the CREATE2 salt, so a given counterfactual address can
///      only ever be realized by the sender it was derived from. Two entry points share one pipeline:
///      - {deployStrict} reverts {LatticeFactory__AlreadyDeployed} when the address is occupied and refuses
///        `latest` entries (version `0`). It is the entry point for user interfaces and any caller that must
///        know its recipe was applied.
///      - {deploy} is idempotent: re-running it for an already-deployed `(sender, salt)` returns the existing
///        diamond instead of reverting, and ignores the call's entries/cuts/init entirely.
///      The address commits to `(sender, salt)` ONLY, never to the recipe, so a distinct recipe needs a distinct
///      salt; {DiamondDeployed} carries a hash of the applied recipe so indexers can tell recipes apart. Because
///      the salt is bound to `msg.sender`, every user behind one shared forwarder (Multicall3, a relayer) shares
///      one salt namespace: call the factory directly from the deploying account, or use {deployStrict} so a
///      second user's call reverts instead of returning the first user's diamond. All registry drift/lookup
///      failures ({ILatticeRegistry} reverts) bubble unchanged — the factory adds no drift handling of its own.
interface ILatticeFactory {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Thrown when `deploy` is called with no recipe entries AND no custom cuts (would yield a
    ///         diamond with no callable functions).
    error LatticeFactory__EmptyRecipe();

    /// @notice Thrown when a custom cut includes the ERC-8153 `exportSelectors()` selector (`0x0ef22643`) —
    ///         it must never be cut into a diamond. Refused outright, never silently stripped;
    ///         registry-resolved cuts can never contain it because registration rejects it.
    error LatticeFactory__ExportSelectorForbidden();

    /// @notice Thrown when a FRESH deploy's materialized cuts leave an EIP-2535 loupe selector uncovered —
    ///         `facets()` 0x7a0ed627, `facetFunctionSelectors(address)` 0xadfca15e, `facetAddresses()`
    ///         0x52ef6b2c, `facetAddress(bytes4)` 0xcdffacc6 must EACH appear in some `Add` cut.
    /// @dev An un-introspectable diamond is unusable by EIP-2535 tooling (explorers, upgrade dashboards,
    ///      the loupe-driven test harnesses), so the factory requires a routing ENTRY for each loupe
    ///      selector at assembly time — paired with {LatticeFactory__LoupeSelectorNotReplaceable}, which
    ///      forbids undoing that routing within the same deploy. The check is COVERAGE-based, never
    ///      facet-identity-based: any facet may provide the selectors (the stock `DiamondLoupeFacet`, a
    ///      registry-resolved release of it, or a combined facet of the deployer's own). It validates the
    ///      selector SURFACE, not the implementation behind it: registry cuts pin codehash + self-reported
    ///      export blob, custom cuts are unverified — a facet claiming selectors it does not implement is
    ///      the recipe author's responsibility (see `IFacet`'s security note). The CUT facet remains
    ///      optional — immutable-by-design diamonds are legal; blind ones are not. Reported selector = the
    ///      FIRST missing one in the order listed above. Like registry resolution, this check is skipped
    ///      on idempotent re-calls to an occupied `(sender, salt)` (the address never commits to the
    ///      recipe; see {deploy}).
    /// @param missingSelector The first uncovered loupe selector.
    error LatticeFactory__MissingLoupeCoverage(bytes4 missingSelector);

    /// @notice Thrown when a FRESH deploy's cuts contain a `Replace` or `Remove` that touches an EIP-2535
    ///         loupe selector — e.g. `[Add(loupe), Remove(loupe)]`, which would pass a presence-only scan
    ///         yet assemble a loupe-less or mis-routed diamond.
    /// @dev Fresh-deploy recipes may only ADD loupe routing; re-pointing or removing it is a post-deploy
    ///      upgrade decision made through the diamond's own cut facet, never smuggled into assembly.
    /// @param loupeSelector The loupe selector the offending non-`Add` cut touches.
    error LatticeFactory__LoupeSelectorNotReplaceable(bytes4 loupeSelector);

    /// @notice Thrown when constructing a factory with a registry address that holds no code (including
    ///         zero): a permanent, silent misconfiguration, since the factory is immutable and every recipe
    ///         entry would revert with empty data.
    /// @param registry The rejected registry address.
    error LatticeFactory__InvalidRegistry(address registry);

    /// @notice Thrown by {deployStrict} when the `(sender, salt)` address already holds a diamond.
    /// @param diamond The occupied address.
    error LatticeFactory__AlreadyDeployed(address diamond);

    /// @notice Thrown by {deployStrict} for a recipe entry with version `0`, which would resolve the curator's
    ///         movable `latest` pointer at execution time instead of a version the caller signed for.
    /// @param nameHash The entry's curated name key.
    error LatticeFactory__UnpinnedEntry(bytes32 nameHash);

    /// @notice Thrown when a recipe entry excludes a selector its pinned registry export does not contain (or
    ///         excludes one selector twice).
    /// @param nameHash The entry's curated name key.
    /// @param selector The excluded selector that was not found.
    error LatticeFactory__ExcludedSelectorNotExported(bytes32 nameHash, bytes4 selector);

    /// @notice Thrown when `init` is zero but `initCalldata` is not empty: the diamond would deploy without
    ///         running the initialization the caller encoded.
    error LatticeFactory__InitCalldataWithoutInit();

    /// @notice Thrown when exactly one of the reverse registrar and reverse-record owner is zero.
    error LatticeFactory__IncompleteENSConfiguration();

    /// @notice Thrown when ENS naming is enabled but the supplied reverse registrar has no bytecode.
    /// @param registrar The invalid reverse registrar address.
    error LatticeFactory__InvalidReverseRegistrar(address registrar);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Emitted when a diamond is deployed (not re-emitted on idempotent re-calls).
    /// @dev `recipeHash` is `keccak256(abi.encode(cuts, init, initCalldata))` over the MATERIALIZED
    ///      `FacetCut[] cuts` handed to `Lattice.initialize`: the registry-resolved cuts in entry order (with
    ///      each entry's `exclude` applied), then the custom cuts. It records what was applied, including the
    ///      version a `latest` entry resolved to; it is not part of the address. An init that self-destructs
    ///      the diamond leaves the address empty when the transaction ends (EIP-6780), so the same
    ///      `(sender, salt)` can deploy again and emit a second event for the same address: indexers treat the
    ///      LATEST event for an address as authoritative.
    /// @param diamond The deployed {Diamond} proxy.
    /// @param deployer The `msg.sender` folded into the CREATE2 salt.
    /// @param recipeHash The hash of the applied cuts, init and init calldata.
    /// @param salt The caller-chosen salt distinguishing diamonds for the same deployer.
    /// @param init The initializer delegatecalled during initialization (`address(0)` if none).
    event DiamondDeployed(
        address indexed diamond, address indexed deployer, bytes32 indexed recipeHash, bytes32 salt, address init
    );

    //*//////////////////////////////////////////////////////////////////////////
    //                                  DEPLOY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deploys (or returns the existing) {Diamond} for `(msg.sender, salt)` and initializes it with
    ///         the registry-resolved recipe cuts, the appended custom cuts, and the recipe's init.
    /// @dev Recipe entries resolve through {ILatticeRegistry.getCut}, which live-re-verifies the code and
    ///      selector pins and returns an `Add` cut; a `version` of `0` first resolves the curator's
    ///      `latest(nameHash)` pointer, and each entry's `exclude` selectors are then dropped from its cut.
    ///      Custom cuts are appended AFTER the registry cuts, order preserved — a deliberate custom `Replace`
    ///      may therefore re-point a selector a registry cut just added.
    ///      Argument validation ({LatticeFactory__EmptyRecipe}, {LatticeFactory__InitCalldataWithoutInit},
    ///      {LatticeFactory__ExportSelectorForbidden}) runs on every call, including idempotent re-calls;
    ///      registry resolution, exclusion, LOUPE-COVERAGE validation ({LatticeFactory__MissingLoupeCoverage} —
    ///      every fresh deploy must route the four EIP-2535 loupe selectors; the registered
    ///      `lattice.DiamondLoupeFacet` entry is the one-line way) and initialization run only when the diamond
    ///      is actually deployed.
    ///      INIT AUTHORITY: `Lattice.initialize` is called by THIS FACTORY, so inside `init` `msg.sender` is the
    ///      factory, not the deployer. An init that grants `msg.sender` a role or ownership grants it to the
    ///      factory, which has no way to use it: pass the admin explicitly in `initCalldata` (every shipped Init
    ///      does).
    /// @param entries The registry recipe lines to resolve into cuts (may be empty).
    /// @param customCuts Classic cuts appended verbatim after the registry cuts (may be empty).
    /// @param init Initializer delegatecalled during the diamond's initialization (`address(0)` to skip, with
    ///        empty `initCalldata`).
    /// @param initCalldata Calldata for `init`.
    /// @param salt Caller-chosen salt; distinct salts yield distinct diamonds for the same sender.
    /// @return diamond The deterministic diamond address (equals {predict}).
    function deploy(
        RecipeEntry[] calldata entries,
        FacetCut[] calldata customCuts,
        address init,
        bytes calldata initCalldata,
        bytes32 salt
    ) external returns (address diamond);

    /// @notice {deploy}, but it reverts {LatticeFactory__AlreadyDeployed} instead of returning an existing
    ///         diamond, and {LatticeFactory__UnpinnedEntry} for any entry with version `0`.
    /// @dev Every successful call deploys a fresh diamond from exactly this recipe and emits {DiamondDeployed},
    ///      so a double-submitted or replayed transaction fails loudly instead of "succeeding" with another
    ///      recipe. Same validation, resolution, exclusion and init-authority rules as {deploy}.
    /// @param entries The registry recipe lines to resolve into cuts (may be empty; versions must be non-zero).
    /// @param customCuts Classic cuts appended verbatim after the registry cuts (may be empty).
    /// @param init Initializer delegatecalled during the diamond's initialization (`address(0)` to skip).
    /// @param initCalldata Calldata for `init`.
    /// @param salt Caller-chosen salt; distinct salts yield distinct diamonds for the same sender.
    /// @return diamond The newly deployed diamond (equals {predict}).
    function deployStrict(
        RecipeEntry[] calldata entries,
        FacetCut[] calldata customCuts,
        address init,
        bytes calldata initCalldata,
        bytes32 salt
    ) external returns (address diamond);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The counterfactual address `deploy(..., salt)` will land at when called by `deployer`.
    /// @param deployer The prospective `msg.sender`.
    /// @param salt The prospective salt.
    /// @return diamond The deterministic CREATE2 address.
    function predict(address deployer, bytes32 salt) external view returns (address diamond);

    /// @notice The deploy-once {ILatticeRegistry} recipe entries are resolved against.
    function registry() external view returns (ILatticeRegistry);

    /// @notice The CREATE2 initcode hash of every diamond this factory deploys:
    ///         `keccak256(type(Lattice).creationCode)` of the {Lattice} build compiled into the factory.
    /// @dev Lets an off-chain client check which proxy build a factory deploys before it predicts addresses:
    ///      `address = keccak256(0xff ++ factory ++ keccak256(abi.encode(deployer, salt)) ++ hash)[12:]`.
    function diamondInitCodeHash() external view returns (bytes32);
}
