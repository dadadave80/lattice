// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {IAccountFactory} from "@lattice/interfaces/IAccountFactory.sol";

/// @title AccountFactory
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Deterministic factory for EIP-2535 Diamond smart accounts, suitable for ERC-4337 counterfactual
///         `initCode` onboarding. Holds a fixed facet blueprint + initializer; each `createAccount` CREATE2-
///         deploys a bare {Diamond} proxy and initializes it with the blueprint and the owner.
/// @dev The proxy has no constructor args, so its initcode hash is constant and the CREATE2 address depends
///      only on `(factory, keccak256(owner, salt))`. Deploy this factory itself deterministically (e.g. via
///      CreateX) and the same `(owner, salt)` lands at the SAME account address on every chain. Folding the
///      owner into the salt binds each counterfactual address to its owner, so no third party can occupy it
///      under a different owner. Not a Diamond facet — a standalone singleton with its own storage.
contract AccountFactory is IAccountFactory {
    /// @inheritdoc IAccountFactory
    address public immutable accountInit;

    /// @dev `keccak256(type(Diamond).creationCode)` — the CREATE2 initcode hash, fixed at construction.
    bytes32 private immutable _proxyInitCodeHash;

    /// @dev The facet cuts applied to every account. Fixed at construction; a different blueprint ⇒ a
    ///      different factory ⇒ a different address set, preserving the counterfactual guarantee.
    FacetCut[] private _blueprint;

    /// @param blueprint_ The facet cuts (Add) wiring a complete account.
    /// @param accountInit_ Initializer delegatecalled during `diamondCut`; MUST expose `init(address owner)`.
    constructor(FacetCut[] memory blueprint_, address accountInit_) {
        if (blueprint_.length == 0) revert EmptyBlueprint();
        accountInit = accountInit_;
        _proxyInitCodeHash = keccak256(type(Diamond).creationCode);
        for (uint256 i; i < blueprint_.length; ++i) {
            _blueprint.push(blueprint_[i]);
        }
    }

    /// @inheritdoc IAccountFactory
    function createAccount(address owner, bytes32 salt) external returns (address account) {
        bytes32 s = _saltFor(owner, salt);
        account = _predict(s);
        if (account.code.length != 0) return account; // already deployed — idempotent

        // ponytail: storage→memory deep-copy of the blueprint per call; fine for a deploy-time factory.
        FacetCut[] memory cuts = _blueprint;
        Diamond proxy = new Diamond{salt: s}();
        proxy.initialize(cuts, accountInit, abi.encodeWithSignature("init(address)", owner));

        emit AccountCreated(account, owner, salt);
    }

    /// @inheritdoc IAccountFactory
    function getAddress(address owner, bytes32 salt) external view returns (address account) {
        account = _predict(_saltFor(owner, salt));
    }

    /// @dev Binds the account address to its owner: `keccak256(owner, salt)`.
    function _saltFor(address owner, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encode(owner, salt));
    }

    /// @dev Standard CREATE2 address derivation for the bare {Diamond} proxy.
    function _predict(bytes32 s) private view returns (address) {
        return
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), s, _proxyInitCodeHash)))));
    }
}
