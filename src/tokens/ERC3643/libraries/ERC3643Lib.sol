// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC3643AgentRoleLib} from "@lattice/tokens/ERC3643/libraries/ERC3643AgentRoleLib.sol";
import {ERC3643ComplianceLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ComplianceLib.sol";
import {ERC3643ExecutionLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";
import {ERC3643IdentityRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643IdentityRegistryLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC3643")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC3643_STORAGE_SLOT = 0xd2596bdadf56df9c4b979459dbbea8fd215833aab674547a3f07281f92ff8400;
/// @dev 0xb97d944c is `type(IERC3643).interfaceId` (inherited IERC20 selectors excluded).
/// `keccak256(abi.encode(bytes4(0xb97d944c), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC3643_SLOT = 0xcc87e7afa96fdc55152180e6574a08d5c0d5b11e49e549f6bafca01a76c4354f;

/// @custom:storage-location erc7201:lattice.storage.ERC3643
struct ERC3643Storage {
    address _identityRegistry;
    address _compliance;
    address _onchainID;
    uint8 _decimals;
    bool _paused;
    mapping(address wallet => bool) _frozen;
    mapping(address wallet => uint256) _frozenTokens;
}

/// @title ERC3643Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Fresh permissioned accounting logic for the reviewed closed immutable profile.
/// @dev No T-REX implementation is used. Privileged entrypoints apply the EIP's operation-specific
///      exceptions; all lifecycle callbacks remain atomic. Existing ERC20Lib has no new global hook.
library ERC3643Lib {
    function erc3643Storage() internal pure returns (ERC3643Storage storage s) {
        assembly ("memory-safe") { s.slot := ERC3643_STORAGE_SLOT }
    }

    function __ERC3643_init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address onchainID_,
        address registry_,
        address compliance_
    ) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC3643Storage storage s = erc3643Storage();
        s._decimals = decimals_;
        s._onchainID = onchainID_;
        s._paused = true;
        _setIdentityRegistry(registry_);
        _setCompliance(compliance_);
        registerInterface();
        _emitInformation();
        emit IERC3643.Paused(msg.sender);
    }

    function registerInterface() internal {
        assembly ("memory-safe") { sstore(ERC165_MAP_IERC3643_SLOT, true) }
    }

    function version() internal pure returns (string memory) {
        return LatticeVersion.VERSION;
    }

    function decimals() internal view returns (uint8) {
        return erc3643Storage()._decimals;
    }

    function onchainID() internal view returns (address) {
        return erc3643Storage()._onchainID;
    }

    function identityRegistry() internal view returns (address) {
        return erc3643Storage()._identityRegistry;
    }

    function compliance() internal view returns (address) {
        return erc3643Storage()._compliance;
    }

    function paused() internal view returns (bool) {
        return erc3643Storage()._paused;
    }

    function isFrozen(address wallet) internal view returns (bool) {
        return erc3643Storage()._frozen[wallet];
    }

    function getFrozenTokens(address wallet) internal view returns (uint256) {
        return erc3643Storage()._frozenTokens[wallet];
    }

    function transfer(address to, uint256 amount) internal returns (bool) {
        ERC3643ExecutionLib.enter();
        _transfer(msg.sender, to, amount);
        ERC3643ExecutionLib.exit();
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) internal returns (bool) {
        ERC3643ExecutionLib.enter();
        _checkNormal(from, to, amount);
        ERC20Lib._spendAllowance(from, msg.sender, amount);
        ERC20Lib._transfer(from, to, amount);
        _transferred(from, to, amount);
        ERC3643ExecutionLib.exit();
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        _checkNormal(from, to, amount);
        ERC20Lib._transfer(from, to, amount);
        _transferred(from, to, amount);
    }

    function _checkNormal(address from, address to, uint256 amount) private view {
        _requireInitialized();
        if (from == address(0)) revert IERC20.ERC20InvalidSender(from);
        if (to == address(0)) revert IERC20.ERC20InvalidReceiver(to);
        ERC3643Storage storage s = erc3643Storage();
        if (s._paused) revert IERC3643.ERC3643TokenPaused();
        if (s._frozen[from]) revert IERC3643.ERC3643WalletFrozen(from);
        if (s._frozen[to]) revert IERC3643.ERC3643WalletFrozen(to);
        uint256 balance = ERC20Lib.balanceOf(from);
        uint256 frozen = s._frozenTokens[from];
        if (frozen > balance) revert IERC3643.ERC3643FrozenBalanceInvariant(from);
        uint256 available = balance - frozen;
        if (amount > available) revert IERC3643.ERC3643InsufficientFreeBalance(from, available, amount);
        _requireVerified(to);
        if (!_staticBool(s._compliance, abi.encodeCall(ICompliance.canTransfer, (from, to, amount)))) {
            revert IERC3643.ERC3643ComplianceRejected();
        }
    }

    function mint(address to, uint256 amount) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _mint(to, amount);
        ERC3643ExecutionLib.exit();
    }

    function _mint(address to, uint256 amount) private {
        _requireInitialized();
        if (to == address(0)) revert IERC20.ERC20InvalidReceiver(to);
        _requireVerified(to);
        ERC20Lib._mint(to, amount);
        _created(to, amount);
    }

    function burn(address from, uint256 amount) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _burn(from, amount);
        ERC3643ExecutionLib.exit();
    }

    function _burn(address from, uint256 amount) private {
        _requireInitialized();
        if (from == address(0)) revert IERC20.ERC20InvalidSender(from);
        _thawDeficit(from, amount);
        ERC20Lib._burn(from, amount);
        _destroyed(from, amount);
    }

    function forcedTransfer(address from, address to, uint256 amount) internal returns (bool) {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _forcedTransfer(from, to, amount);
        ERC3643ExecutionLib.exit();
        return true;
    }

    function _forcedTransfer(address from, address to, uint256 amount) private {
        _requireInitialized();
        if (from == address(0)) revert IERC20.ERC20InvalidSender(from);
        if (to == address(0)) revert IERC20.ERC20InvalidReceiver(to);
        _requireVerified(to);
        _thawDeficit(from, amount);
        ERC20Lib._transfer(from, to, amount);
        _transferred(from, to, amount);
    }

    function _thawDeficit(address from, uint256 amount) private {
        uint256 balance = ERC20Lib.balanceOf(from);
        if (balance < amount) revert IERC20.ERC20InsufficientBalance(from, balance, amount);
        ERC3643Storage storage s = erc3643Storage();
        uint256 frozen = s._frozenTokens[from];
        if (frozen > balance) revert IERC3643.ERC3643FrozenBalanceInvariant(from);
        uint256 remaining = balance - amount;
        if (frozen > remaining) {
            s._frozenTokens[from] = remaining;
            emit IERC3643.TokensUnfrozen(from, frozen - remaining);
        }
    }

    function recoveryAddress(address lost, address target, address investorIdentity) internal returns (bool) {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _requireInitialized();
        if (lost == address(0) || target == address(0) || lost == target) {
            revert IERC3643.ERC3643InvalidRecovery(lost, target);
        }
        address actual = _identity(lost);
        if (actual == address(0) || actual != investorIdentity) {
            revert IERC3643.ERC3643RecoveryIdentityMismatch(lost, investorIdentity, actual);
        }
        address targetIdentity = _identity(target);
        if (targetIdentity != address(0) && targetIdentity != investorIdentity) {
            revert IERC3643.ERC3643RecoveryIdentityMismatch(target, investorIdentity, targetIdentity);
        }
        if (!_staticBool(
                investorIdentity,
                abi.encodeCall(IERC3643Identity.keyHasPurpose, (keccak256(abi.encode(target)), uint256(1)))
            )) revert IERC3643.ERC3643RecoveryKeyMissing(investorIdentity, target);
        if (targetIdentity == address(0)) _registerIdentity(target, investorIdentity, _country(lost));
        _requireVerified(target);
        ERC3643Storage storage s = erc3643Storage();
        uint256 amount = ERC20Lib.balanceOf(lost);
        uint256 lostFrozen = s._frozenTokens[lost];
        bool targetFreeze = s._frozen[target] || s._frozen[lost];
        if (lostFrozen > amount || s._frozenTokens[target] > ERC20Lib.balanceOf(target)) {
            revert IERC3643.ERC3643FrozenBalanceInvariant(lost);
        }
        ERC20Lib._transfer(lost, target, amount);
        s._frozenTokens[lost] = 0;
        s._frozenTokens[target] += lostFrozen;
        if (lostFrozen != 0) {
            emit IERC3643.TokensUnfrozen(lost, lostFrozen);
            emit IERC3643.TokensFrozen(target, lostFrozen);
        }
        if (s._frozen[target] != targetFreeze) {
            s._frozen[target] = targetFreeze;
            emit IERC3643.AddressFrozen(target, targetFreeze, msg.sender);
        }
        if (!s._frozen[lost]) {
            s._frozen[lost] = true;
            emit IERC3643.AddressFrozen(lost, true, msg.sender);
        }
        _deleteIdentity(lost);
        _transferred(lost, target, amount);
        emit IERC3643.RecoverySuccess(lost, target, investorIdentity);
        ERC3643ExecutionLib.exit();
        return true;
    }

    function pause() internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _requireInitialized();
        erc3643Storage()._paused = true;
        emit IERC3643.Paused(msg.sender);
        ERC3643ExecutionLib.exit();
    }

    function unpause() internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _requireInitialized();
        erc3643Storage()._paused = false;
        emit IERC3643.Unpaused(msg.sender);
        ERC3643ExecutionLib.exit();
    }

    function setAddressFrozen(address wallet, bool freeze) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _setAddressFrozen(wallet, freeze);
        ERC3643ExecutionLib.exit();
    }

    function _setAddressFrozen(address wallet, bool freeze) private {
        _requireInitialized();
        if (wallet == address(0)) revert IERC20.ERC20InvalidSender(wallet);
        erc3643Storage()._frozen[wallet] = freeze;
        emit IERC3643.AddressFrozen(wallet, freeze, msg.sender);
    }

    function freezePartialTokens(address wallet, uint256 amount) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _freezePartialTokens(wallet, amount);
        ERC3643ExecutionLib.exit();
    }

    function _freezePartialTokens(address wallet, uint256 amount) private {
        _requireInitialized();
        if (wallet == address(0)) revert IERC20.ERC20InvalidSender(wallet);
        uint256 balance = ERC20Lib.balanceOf(wallet);
        uint256 frozen = getFrozenTokens(wallet);
        if (frozen > balance) revert IERC3643.ERC3643FrozenBalanceInvariant(wallet);
        uint256 free = balance - frozen;
        if (amount > free) revert IERC3643.ERC3643InsufficientFreeBalance(wallet, free, amount);
        erc3643Storage()._frozenTokens[wallet] = frozen + amount;
        emit IERC3643.TokensFrozen(wallet, amount);
    }

    function unfreezePartialTokens(address wallet, uint256 amount) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _unfreezePartialTokens(wallet, amount);
        ERC3643ExecutionLib.exit();
    }

    function _unfreezePartialTokens(address wallet, uint256 amount) private {
        _requireInitialized();
        if (wallet == address(0)) revert IERC20.ERC20InvalidSender(wallet);
        uint256 frozen = getFrozenTokens(wallet);
        if (amount > frozen) revert IERC3643.ERC3643InsufficientFrozenTokens(wallet, frozen, amount);
        erc3643Storage()._frozenTokens[wallet] = frozen - amount;
        emit IERC3643.TokensUnfrozen(wallet, amount);
    }

    function setName(string memory name_) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        ERC20Lib.erc20Storage()._name = name_;
        _emitInformation();
        ERC3643ExecutionLib.exit();
    }

    function setSymbol(string memory symbol_) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        ERC20Lib.erc20Storage()._symbol = symbol_;
        _emitInformation();
        ERC3643ExecutionLib.exit();
    }

    function setOnchainID(address identity_) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        erc3643Storage()._onchainID = identity_;
        _emitInformation();
        ERC3643ExecutionLib.exit();
    }

    function _emitInformation() private {
        emit IERC3643.UpdatedTokenInformation(ERC20Lib.name(), ERC20Lib.symbol(), decimals(), version(), onchainID());
    }

    function setIdentityRegistry(address registry) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        _setIdentityRegistry(registry);
        ERC3643ExecutionLib.exit();
    }

    function _setIdentityRegistry(address registry) private {
        _requireCode(registry);
        erc3643Storage()._identityRegistry = registry;
        emit IERC3643.IdentityRegistryAdded(registry);
    }

    function setCompliance(address next) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        _setCompliance(next);
        ERC3643ExecutionLib.exit();
    }

    function _setCompliance(address next) private {
        _requireCode(next);
        address previous = compliance();
        if (previous != next && previous != address(0)) {
            address bound = _bound(previous);
            if (bound != address(0)) {
                if (bound != address(this)) revert IERC3643.ERC3643ComplianceBinding(previous, bound);
                if (previous == address(this)) ERC3643ComplianceLib._unbindToken(address(this));
                else ICompliance(previous).unbindToken(address(this));
                bound = _bound(previous);
                if (bound != address(0)) revert IERC3643.ERC3643ComplianceBinding(previous, bound);
            }
        }
        address binding = _bound(next);
        if (binding == address(0)) {
            if (next == address(this)) ERC3643ComplianceLib._bindToken(address(this));
            else ICompliance(next).bindToken(address(this));
            binding = _bound(next);
        }
        if (binding != address(this)) revert IERC3643.ERC3643ComplianceBinding(next, binding);
        erc3643Storage()._compliance = next;
        emit IERC3643.ComplianceAdded(next);
    }

    function _bound(address endpoint) private view returns (address) {
        return endpoint == address(this) ? ERC3643ComplianceLib.getTokenBound() : ICompliance(endpoint).getTokenBound();
    }

    function _requireInitialized() private view {
        if (identityRegistry() == address(0) || compliance() == address(0)) revert IERC3643.ERC3643NotInitialized();
    }

    function _requireCode(address endpoint) private view {
        if (endpoint == address(0) || endpoint.code.length == 0) revert IERC3643.ERC3643InvalidDependency(endpoint);
    }

    function _requireVerified(address wallet) private view {
        // The read-only registry route is already mandatory in the closed profile. Reuse that facet
        // instead of duplicating its complete claim-verification graph into the token's runtime.
        if (!_staticBool(identityRegistry(), abi.encodeCall(IIdentityRegistry.isVerified, (wallet)))) {
            revert IERC3643.ERC3643UnverifiedIdentity(wallet);
        }
    }

    function _staticBool(address endpoint, bytes memory data) private view returns (bool) {
        (bool ok, bytes memory result) = endpoint.staticcall(data);
        if (!ok || result.length != 32) return false;
        uint256 word;
        assembly ("memory-safe") { word := mload(add(result, 32)) }
        return word == 1;
    }

    function _identity(address wallet) private view returns (address) {
        address registry = identityRegistry();
        return registry == address(this)
            ? address(ERC3643IdentityRegistryLib.identity(wallet))
            : address(IIdentityRegistry(registry).identity(wallet));
    }

    function _country(address wallet) private view returns (uint16) {
        address registry = identityRegistry();
        return registry == address(this)
            ? ERC3643IdentityRegistryLib.investorCountry(wallet)
            : IIdentityRegistry(registry).investorCountry(wallet);
    }

    function _registerIdentity(address wallet, address identity_, uint16 country) private {
        address registry = identityRegistry();
        if (registry == address(this)) {
            ERC3643IdentityRegistryLib._registerIdentity(wallet, IERC3643Identity(identity_), country);
        } else {
            IIdentityRegistry(registry).registerIdentity(wallet, IERC3643Identity(identity_), country);
        }
    }

    function _deleteIdentity(address wallet) private {
        address registry = identityRegistry();
        if (registry == address(this)) ERC3643IdentityRegistryLib._deleteIdentity(wallet);
        else IIdentityRegistry(registry).deleteIdentity(wallet);
    }

    function _transferred(address from, address to, uint256 amount) private {
        address endpoint = compliance();
        if (endpoint == address(this)) ERC3643ComplianceLib._transferred(from, to, amount);
        else ICompliance(endpoint).transferred(from, to, amount);
    }

    function _created(address to, uint256 amount) private {
        address endpoint = compliance();
        if (endpoint == address(this)) ERC3643ComplianceLib._created(to, amount);
        else ICompliance(endpoint).created(to, amount);
    }

    function _destroyed(address from, uint256 amount) private {
        address endpoint = compliance();
        if (endpoint == address(this)) ERC3643ComplianceLib._destroyed(from, amount);
        else ICompliance(endpoint).destroyed(from, amount);
    }

    function batchTransfer(address[] memory to, uint256[] memory amounts) internal {
        ERC3643ExecutionLib.enter();
        _requireInitialized();
        if (to.length != amounts.length) revert IERC3643.ERC3643InvalidArrayLengths();
        for (uint256 i; i < to.length; ++i) {
            _transfer(msg.sender, to[i], amounts[i]);
        }
        ERC3643ExecutionLib.exit();
    }

    function batchForcedTransfer(address[] memory from, address[] memory to, uint256[] memory amounts) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _requireInitialized();
        if (from.length != to.length || from.length != amounts.length) revert IERC3643.ERC3643InvalidArrayLengths();
        for (uint256 i; i < from.length; ++i) {
            _forcedTransfer(from[i], to[i], amounts[i]);
        }
        ERC3643ExecutionLib.exit();
    }

    function batchMint(address[] memory to, uint256[] memory amounts) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _requireInitialized();
        if (to.length != amounts.length) revert IERC3643.ERC3643InvalidArrayLengths();
        for (uint256 i; i < to.length; ++i) {
            _mint(to[i], amounts[i]);
        }
        ERC3643ExecutionLib.exit();
    }

    function batchBurn(address[] memory from, uint256[] memory amounts) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _requireInitialized();
        if (from.length != amounts.length) revert IERC3643.ERC3643InvalidArrayLengths();
        for (uint256 i; i < from.length; ++i) {
            _burn(from[i], amounts[i]);
        }
        ERC3643ExecutionLib.exit();
    }

    function batchSetAddressFrozen(address[] memory wallets, bool[] memory freeze) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _requireInitialized();
        if (wallets.length != freeze.length) revert IERC3643.ERC3643InvalidArrayLengths();
        for (uint256 i; i < wallets.length; ++i) {
            _setAddressFrozen(wallets[i], freeze[i]);
        }
        ERC3643ExecutionLib.exit();
    }

    function batchFreezePartialTokens(address[] memory wallets, uint256[] memory amounts) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _requireInitialized();
        if (wallets.length != amounts.length) revert IERC3643.ERC3643InvalidArrayLengths();
        for (uint256 i; i < wallets.length; ++i) {
            _freezePartialTokens(wallets[i], amounts[i]);
        }
        ERC3643ExecutionLib.exit();
    }

    function batchUnfreezePartialTokens(address[] memory wallets, uint256[] memory amounts) internal {
        ERC3643ExecutionLib.enter();
        ERC3643AgentRoleLib.checkAgent();
        _requireInitialized();
        if (wallets.length != amounts.length) revert IERC3643.ERC3643InvalidArrayLengths();
        for (uint256 i; i < wallets.length; ++i) {
            _unfreezePartialTokens(wallets[i], amounts[i]);
        }
        ERC3643ExecutionLib.exit();
    }
}
