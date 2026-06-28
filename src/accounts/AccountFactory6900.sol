// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ModularAccount6900} from "@lattice/accounts/ModularAccount6900.sol";
import {IAccountFactory} from "@lattice/interfaces/IAccountFactory.sol";

/// @title AccountFactory6900
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Deterministic factory for ERC-6900 modular Diamond smart accounts, suitable for ERC-4337
///         counterfactual `initCode` onboarding. Mirrors {AccountFactory} but CREATE2-deploys a
///         {ModularAccount6900} proxy (the 6900 fallback that dispatches installed execution modules) instead of
///         the ERC-7579 `AccountDiamond`, and wires it with the 6900 facet blueprint + {AccountInit6900}.
/// @dev The proxy has no constructor args, so its initcode hash is constant and the CREATE2 address depends only
///      on `(factory, keccak256(owner, salt))`. A different blueprint ⇒ a different factory ⇒ a different address
///      set. Not a Diamond facet — a standalone singleton with its own storage.
contract AccountFactory6900 is IAccountFactory {
    /// @inheritdoc IAccountFactory
    address public immutable accountInit;

    /// @dev `keccak256(type(ModularAccount6900).creationCode)` — the CREATE2 initcode hash, fixed at construction.
    bytes32 private immutable _proxyInitCodeHash;

    /// @dev The facet cuts applied to every account. Fixed at construction.
    FacetCut[] private _blueprint;

    /// @param __blueprint The facet cuts (Add) wiring a complete ERC-6900 account.
    /// @param _accountInit Initializer delegatecalled during `diamondCut`; MUST expose `init(address owner)`.
    constructor(FacetCut[] memory __blueprint, address _accountInit) {
        uint256 blueprintLength = __blueprint.length;
        if (blueprintLength == 0) revert EmptyBlueprint();
        accountInit = _accountInit;
        _proxyInitCodeHash = keccak256(type(ModularAccount6900).creationCode);
        for (uint256 i; i < blueprintLength; ++i) {
            _blueprint.push(__blueprint[i]);
        }
    }

    /// @inheritdoc IAccountFactory
    function createAccount(address owner, bytes32 salt) external returns (address account) {
        bytes32 s = _saltFor(owner, salt);
        account = _predict(s);
        if (account.code.length != 0) return account; // already deployed — idempotent

        FacetCut[] memory cuts = _blueprint;
        ModularAccount6900 proxy = new ModularAccount6900{salt: s}();
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

    /// @dev Standard CREATE2 address derivation for the {ModularAccount6900} proxy.
    function _predict(bytes32 s) private view returns (address) {
        return
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), s, _proxyInitCodeHash)))));
    }
}
