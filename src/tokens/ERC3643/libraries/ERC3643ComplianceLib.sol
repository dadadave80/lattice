// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {ERC3643ExecutionLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC3643Compliance")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC3643_COMPLIANCE_STORAGE_SLOT = 0xcfb462e7546f5454efc8beb4ff0c622b5b0701cba309faa31474042e507a7600;
/// @dev 0xa87a1289 is `type(ICompliance).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xa87a1289), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICOMPLIANCE_SLOT = 0x65ca2e039e0fba3681e69e0c954d898b4065522cde366f6f0a523370719acc0d;

/// @custom:storage-location erc7201:lattice.storage.ERC3643Compliance
struct ERC3643ComplianceData {
    address _boundToken;
}

/// @title ERC3643ComplianceLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice The standard default Compliance: owner binding and bound-token callbacks, with no regulatory rule pack.
library ERC3643ComplianceLib {
    function state() internal pure returns (ERC3643ComplianceData storage s) {
        assembly ("memory-safe") { s.slot := ERC3643_COMPLIANCE_STORAGE_SLOT }
    }

    function __ERC3643Compliance_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") { sstore(ERC165_MAP_ICOMPLIANCE_SLOT, true) }
    }

    function bindToken(address token) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        _bindToken(token);
        ERC3643ExecutionLib.exit();
    }

    function _bindToken(address token) internal {
        if (token == address(0)) revert ICompliance.ERC3643InvalidToken(token);
        address previous = getTokenBound();
        if (previous == token) return;
        if (previous != address(0)) revert ICompliance.ERC3643TokenAlreadyBound(previous);
        state()._boundToken = token;
        emit ICompliance.TokenBound(token);
    }

    function unbindToken(address token) internal {
        ERC3643ExecutionLib.enter();
        OwnableLib.checkOwner();
        _unbindToken(token);
        ERC3643ExecutionLib.exit();
    }

    function _unbindToken(address token) internal {
        if (token == address(0) || getTokenBound() != token) revert ICompliance.ERC3643TokenNotBound(token);
        state()._boundToken = address(0);
        emit ICompliance.TokenUnbound(token);
    }

    function getTokenBound() internal view returns (address) {
        return state()._boundToken;
    }

    function canTransfer(address, address, uint256) internal pure returns (bool) {
        return true;
    }

    function transferred(address, address, uint256) internal {
        ERC3643ExecutionLib.enter();
        _checkCaller();
        ERC3643ExecutionLib.exit();
    }

    function created(address, uint256) internal {
        ERC3643ExecutionLib.enter();
        _checkCaller();
        ERC3643ExecutionLib.exit();
    }

    function destroyed(address, uint256) internal {
        ERC3643ExecutionLib.enter();
        _checkCaller();
        ERC3643ExecutionLib.exit();
    }

    function _checkCaller() private view {
        if (msg.sender != getTokenBound() || msg.sender == address(0)) {
            revert ICompliance.ERC3643UnauthorizedToken(msg.sender);
        }
    }

    function _checkLocalToken() private view {
        if (getTokenBound() != address(this)) revert ICompliance.ERC3643TokenNotBound(address(this));
    }

    function _transferred(address, address, uint256) internal view {
        _checkLocalToken();
    }

    function _created(address, uint256) internal view {
        _checkLocalToken();
    }

    function _destroyed(address, uint256) internal view {
        _checkLocalToken();
    }
}
