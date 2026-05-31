// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDefaultAdminRulesLib} from "@lattice/access/libraries/AccessControlDefaultAdminRulesLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IAccessControlDefaultAdminRules} from "@lattice/interfaces/IAccessControlDefaultAdminRules.sol";

/// @title AccessControlDefaultAdminRules
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/extensions/AccessControlDefaultAdminRules.sol)
/// @notice Diamond facet: timelocked DEFAULT_ADMIN_ROLE transfer + configurable delay.
///         REQUIRES the consumer Diamond to also include `OwnableFacet` from diamond-lib.
contract AccessControlDefaultAdminRules is AccessControl, IAccessControlDefaultAdminRules {
    function defaultAdmin() external view virtual override returns (address) {
        return AccessControlDefaultAdminRulesLib.defaultAdmin();
    }

    function pendingDefaultAdmin() external view virtual override returns (address, uint48) {
        return AccessControlDefaultAdminRulesLib.pendingDefaultAdmin();
    }

    function defaultAdminDelay() external view virtual override returns (uint48) {
        return AccessControlDefaultAdminRulesLib.defaultAdminDelay();
    }

    function pendingDefaultAdminDelay() external view virtual override returns (uint48, uint48) {
        return AccessControlDefaultAdminRulesLib.pendingDefaultAdminDelay();
    }

    function defaultAdminDelayIncreaseWait() external pure virtual override returns (uint48) {
        return AccessControlDefaultAdminRulesLib.defaultAdminDelayIncreaseWait();
    }

    function beginDefaultAdminTransfer(address newAdmin) external virtual override {
        AccessControlDefaultAdminRulesLib.beginDefaultAdminTransfer(newAdmin);
    }

    function cancelDefaultAdminTransfer() external virtual override {
        AccessControlDefaultAdminRulesLib.cancelDefaultAdminTransfer();
    }

    function acceptDefaultAdminTransfer() external virtual override {
        AccessControlDefaultAdminRulesLib.acceptDefaultAdminTransfer();
    }

    function changeDefaultAdminDelay(uint48 newDelay) external virtual override {
        AccessControlDefaultAdminRulesLib.changeDefaultAdminDelay(newDelay);
    }

    function rollbackDefaultAdminDelay() external virtual override {
        AccessControlDefaultAdminRulesLib.rollbackDefaultAdminDelay();
    }

    /// @inheritdoc IAccessControl
    function hasRole(bytes32 _role, address _account)
        public
        view
        virtual
        override(AccessControl, IAccessControl)
        returns (bool)
    {
        if (_role == 0x00) {
            return _account == AccessControlDefaultAdminRulesLib.defaultAdmin();
        }
        return AccessControlLib.hasRole(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function getRoleAdmin(bytes32 _role) public view virtual override(AccessControl, IAccessControl) returns (bytes32) {
        return AccessControlLib.getRoleAdmin(_role);
    }

    /// @inheritdoc IAccessControl
    function grantRole(bytes32 _role, address _account) public virtual override(AccessControl, IAccessControl) {
        if (_role == 0x00) {
            revert IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUseAdminTransfer();
        }
        super.grantRole(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function revokeRole(bytes32 _role, address _account) public virtual override(AccessControl, IAccessControl) {
        if (_role == 0x00) {
            revert IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUseAdminTransfer();
        }
        super.revokeRole(_role, _account);
    }

    /// @inheritdoc IAccessControl
    function renounceRole(bytes32 _role, address _callerConfirmation)
        public
        virtual
        override(AccessControl, IAccessControl)
    {
        if (_role == 0x00) {
            revert IAccessControlDefaultAdminRules.AccessControlDefaultAdminRulesUseAdminTransfer();
        }
        super.renounceRole(_role, _callerConfirmation);
    }
}
