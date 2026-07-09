// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {IERC8153} from "@lattice/interfaces/external/IERC8153.sol";
import {IDiamondFactory, RecipeEntry} from "@lattice/interfaces/factory/IDiamondFactory.sol";
import {ILatticeRegistry} from "@lattice/interfaces/registry/ILatticeRegistry.sol";

/// @title DiamondFactory
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless factory that assembles a complete EIP-2535 {Diamond} in ONE transaction from cuts
///         resolved out of the deploy-once {ILatticeRegistry} (issue #120). Recipe entries become
///         live-verified `Add` cuts straight off the registry — no facet re-`CREATE`, no FFI — classic
///         custom cuts are appended for facets outside the curated catalog, and the proxy is
///         CREATE2-deployed and initialized atomically.
/// @dev The proxy has no constructor args, so its initcode hash is constant and every diamond address
///      depends only on `(factory, keccak256(msg.sender, salt))`. Because the initcode commits to nothing, a
///      raw salt alone would let anyone front-run a counterfactual address with arbitrary cuts; folding the
///      sender into the salt binds each address to its deployer, which also makes the idempotent
///      already-deployed return sound (only the same sender can have occupied it, with cuts of their own
///      choosing). The flip side: the address never commits to the RECIPE — a repeat `deploy` for an occupied
///      `(sender, salt)` returns the existing diamond unchanged and ignores the call's entries/cuts/init, so
///      use a distinct salt per distinct recipe. Registry reverts (drift, missing records, unset `latest`)
///      bubble unchanged — the factory adds no drift handling of its own. Not a Diamond facet — a standalone,
///      stateless singleton.
/// @custom:lattice-version 0.1.0
contract DiamondFactory is IDiamondFactory {
    /// @inheritdoc IDiamondFactory
    ILatticeRegistry public immutable registry;

    /// @dev `keccak256(type(Diamond).creationCode)` — the CREATE2 initcode hash, fixed at construction.
    bytes32 private immutable _diamondInitCodeHash;

    /// @dev The ERC-8153 `exportSelectors()` self-selector (`0x0ef22643`). It is never cut into a diamond:
    ///      {ILatticeRegistry} registration rejects it, and {deploy} refuses any custom cut carrying it.
    bytes4 private constant EXPORT_SELECTOR = IERC8153.exportSelectors.selector;

    /// @param _registry The deploy-once {ILatticeRegistry} recipe entries are resolved against; non-zero.
    constructor(ILatticeRegistry _registry) {
        if (address(_registry) == address(0)) revert DiamondFactory__ZeroRegistry();
        registry = _registry;
        _diamondInitCodeHash = keccak256(type(Diamond).creationCode);
    }

    /// @inheritdoc IDiamondFactory
    function deploy(
        RecipeEntry[] calldata entries,
        FacetCut[] calldata customCuts,
        address init,
        bytes calldata initCalldata,
        bytes32 salt
    ) external returns (address diamond) {
        uint256 entriesLength = entries.length;
        uint256 customCutsLength = customCuts.length;
        uint256 totalCuts = entriesLength + customCutsLength;
        if (totalCuts == 0) revert DiamondFactory__EmptyRecipe();

        // Argument validation runs on EVERY call — including ones that take the idempotent return below — so
        // a recipe that would be refused fresh is never quietly "accepted" against an occupied address.
        // Refuse — never strip — any custom cut carrying `exportSelectors()`; registry-resolved cuts can
        // never contain it (registration rejects it).
        for (uint256 i; i < customCutsLength; ++i) {
            bytes4[] calldata selectors = customCuts[i].functionSelectors;
            for (uint256 j; j < selectors.length; ++j) {
                if (selectors[j] == EXPORT_SELECTOR) revert DiamondFactory__ExportSelectorForbidden();
            }
        }

        bytes32 s = _saltFor(msg.sender, salt);
        diamond = _predict(s);
        if (diamond.code.length != 0) return diamond; // already deployed — idempotent (recipe ignored, see @dev)

        FacetCut[] memory cuts = new FacetCut[](totalCuts);

        // Registry-resolved recipe cuts first. getCut live-re-verifies the code + selector pins and returns
        // an Add cut; any registry revert (drift, missing record, unset latest) bubbles unchanged.
        for (uint256 i; i < entriesLength; ++i) {
            RecipeEntry calldata entry = entries[i];
            uint64 version = entry.version;
            if (version == 0) version = registry.latest(entry.nameHash).version;
            cuts[i] = registry.getCut(entry.nameHash, version);
        }

        // Custom cuts appended after the registry cuts, order preserved — a deliberate custom `Replace` may
        // therefore re-point a selector a registry cut just added (the deployer's own diamond, by design).
        for (uint256 i; i < customCutsLength; ++i) {
            cuts[entriesLength + i] = customCuts[i];
        }

        Diamond proxy = new Diamond{salt: s}();
        proxy.initialize(cuts, init, initCalldata);

        emit DiamondDeployed(diamond, msg.sender, salt);
    }

    /// @inheritdoc IDiamondFactory
    function predict(address deployer, bytes32 salt) external view returns (address diamond) {
        diamond = _predict(_saltFor(deployer, salt));
    }

    /// @dev Binds the diamond address to its deployer: `keccak256(deployer, salt)`.
    function _saltFor(address deployer, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encode(deployer, salt));
    }

    /// @dev Standard CREATE2 address derivation for the {Diamond} proxy.
    function _predict(bytes32 s) private view returns (address) {
        return
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), s, _diamondInitCodeHash)))));
    }
}
