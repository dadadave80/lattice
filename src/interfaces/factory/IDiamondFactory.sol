// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ILatticeRegistry} from "@lattice/interfaces/registry/ILatticeRegistry.sol";

/// @notice One line of a diamond recipe: a curated {ILatticeRegistry} Tier-B facet to resolve and cut.
/// @param nameHash The curated name key (by convention `keccak256("lattice.<FacetName>")`).
/// @param version The semver-packed `uint64` to pin (`major<<48 | minor<<24 | patch`). `0` — the registry's
///        reserved sentinel — means "resolve the curator's `latest(nameHash)` pointer at deploy time".
struct RecipeEntry {
    bytes32 nameHash;
    uint64 version;
}

/// @title IDiamondFactory
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless factory that assembles a complete EIP-2535 {Diamond} in ONE transaction: recipe entries
///         are resolved into live-verified `Add` cuts by the deploy-once {ILatticeRegistry} (no facet
///         re-`CREATE`, no FFI), classic custom cuts are appended for facets outside the curated catalog,
///         and the resulting proxy is CREATE2-deployed and initialized atomically.
/// @dev The deployer (`msg.sender`) is folded into the CREATE2 salt, so a given counterfactual address can
///      only ever be realized by the sender it was derived from. Deployment is idempotent: re-running
///      `deploy` for an already-deployed `(sender, salt)` returns the existing diamond instead of reverting.
///      NOTE the address commits to `(sender, salt)` ONLY, never to the recipe — an idempotent re-call
///      ignores its entries/cuts/init entirely, so a distinct recipe needs a distinct salt. All registry
///      drift/lookup failures ({ILatticeRegistry} reverts) bubble unchanged — the factory adds no drift
///      handling of its own.
interface IDiamondFactory {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Thrown when `deploy` is called with no recipe entries AND no custom cuts (would yield a
    ///         diamond with no callable functions).
    error DiamondFactory__EmptyRecipe();

    /// @notice Thrown when a custom cut includes the ERC-8153 `exportSelectors()` selector (`0x0ef22643`) —
    ///         it must never be cut into a diamond. Refused outright, never silently stripped;
    ///         registry-resolved cuts can never contain it because registration rejects it.
    error DiamondFactory__ExportSelectorForbidden();

    /// @notice Thrown when constructing a factory with a zero registry (a permanent, silent
    ///         misconfiguration since the factory is immutable).
    error DiamondFactory__ZeroRegistry();

    //*//////////////////////////////////////////////////////////////////////////
    //                                  EVENTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Emitted once when a diamond is deployed (not re-emitted on idempotent re-calls).
    /// @param diamond The deployed {Diamond} proxy.
    /// @param deployer The `msg.sender` folded into the CREATE2 salt.
    /// @param salt The caller-chosen salt distinguishing diamonds for the same deployer.
    event DiamondDeployed(address indexed diamond, address indexed deployer, bytes32 salt);

    //*//////////////////////////////////////////////////////////////////////////
    //                                  DEPLOY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deploys (or returns the existing) {Diamond} for `(msg.sender, salt)` and initializes it with
    ///         the registry-resolved recipe cuts, the appended custom cuts, and the recipe's init.
    /// @dev Recipe entries resolve through {ILatticeRegistry.getCut}, which live-re-verifies the code and
    ///      selector pins and returns an `Add` cut; a `version` of `0` first resolves the curator's
    ///      `latest(nameHash)` pointer. Custom cuts are appended AFTER the registry cuts, order preserved —
    ///      a deliberate custom `Replace` may therefore re-point a selector a registry cut just added.
    ///      Argument validation ({DiamondFactory__EmptyRecipe}, {DiamondFactory__ExportSelectorForbidden})
    ///      runs on every call, including idempotent re-calls; registry resolution and initialization run
    ///      only when the diamond is actually deployed.
    /// @param entries The registry recipe lines to resolve into cuts (may be empty).
    /// @param customCuts Classic cuts appended verbatim after the registry cuts (may be empty).
    /// @param init Initializer delegatecalled during the diamond's initialization (`address(0)` to skip).
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
}
