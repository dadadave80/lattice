// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165_MAP_ILOUPE_SLOT} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {ERC20TemporaryApprovalLib} from "@lattice/tokens/ERC20/libraries/ERC20TemporaryApprovalLib.sol";
import {ERC3643Params} from "@lattice/tokens/ERC3643/ERC3643Params.sol";
import {ERC3643AgentRoleLib} from "@lattice/tokens/ERC3643/libraries/ERC3643AgentRoleLib.sol";
import {ERC3643ClaimTopicsRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ClaimTopicsRegistryLib.sol";
import {ERC3643ComplianceLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ComplianceLib.sol";
import {ERC3643ExecutionLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";
import {ERC3643IdentityRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643IdentityRegistryLib.sol";
import {
    ERC3643IdentityRegistryStorageLib
} from "@lattice/tokens/ERC3643/libraries/ERC3643IdentityRegistryStorageLib.sol";
import {ERC3643Lib} from "@lattice/tokens/ERC3643/libraries/ERC3643Lib.sol";
import {ERC3643ProfileLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ProfileLib.sol";
import {ERC3643TrustedIssuersRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643TrustedIssuersRegistryLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

error ERC3643InvalidOwner();

/// @title ERC3643Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Trusted complete initialization of the closed immutable permissioned-token profile.
/// @dev No caller-provided initializer/allowlist or post-admission delegatecall is accepted. The general
///      LatticeFactory remains general; arbitrary alternative initializers are outside this profile's claim.
/// @custom:lattice-kind bundle
contract ERC3643Init {
    /// @param config Owner, explicit retained agent memberships, metadata, optional external components and ERC7674.
    /// @custom:lattice-initializes Ownable;
    /// @custom:lattice-initializes ERC3643AgentRole;
    /// @custom:lattice-initializes ERC3643ClaimTopicsRegistry;
    /// @custom:lattice-initializes ERC3643TrustedIssuersRegistry;
    /// @custom:lattice-initializes ERC3643IdentityRegistryStorage;
    /// @custom:lattice-initializes ERC3643IdentityRegistry;
    /// @custom:lattice-initializes ERC3643Compliance;
    /// @custom:lattice-initializes ERC20;
    /// @custom:lattice-initializes ERC3643;
    /// @custom:lattice-initializes ERC20TemporaryApproval with condition=config.temporaryApproval;
    /// @custom:lattice-initializes ERC165;
    /// @custom:lattice-initializes DiamondLoupe;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-sequence Ownable;ERC3643AgentRole;ERC3643ClaimTopicsRegistry;ERC3643TrustedIssuersRegistry;ERC3643IdentityRegistryStorage;ERC3643IdentityRegistry;ERC3643Compliance;ERC20;ERC3643;ERC20TemporaryApproval;ERC165;DiamondLoupe;
    /// @custom:lattice-param config rule=closed-immutable-profile;
    /// @custom:lattice-registers-interfaces
    function init(ERC3643Params calldata config) external {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        ERC3643ExecutionLib.enter();
        // Admission must precede external component binding callbacks.
        ERC3643ProfileLib.validate(config.temporaryApproval);
        if (config.owner == address(0)) revert ERC3643InvalidOwner();
        OwnableLib.initializeOwner(config.owner);
        OwnableLib.registerInterface();
        ERC3643AgentRoleLib.__ERC3643AgentRole_init(config.agents);
        ERC3643ClaimTopicsRegistryLib.__ERC3643ClaimTopicsRegistry_init();
        ERC3643TrustedIssuersRegistryLib.__ERC3643TrustedIssuersRegistry_init();
        ERC3643IdentityRegistryStorageLib.__ERC3643IdentityRegistryStorage_init();
        ERC3643IdentityRegistryStorageLib._bindIdentityRegistry(address(this));
        address store = config.identityStorage == address(0) ? address(this) : config.identityStorage;
        ERC3643IdentityRegistryLib.__ERC3643IdentityRegistry_init(store, address(this), address(this));
        ERC3643ComplianceLib.__ERC3643Compliance_init();
        address policy = config.compliance == address(0) ? address(this) : config.compliance;
        ERC3643Lib.__ERC3643_init(config.name, config.symbol, config.decimals, config.onchainID, address(this), policy);
        if (config.temporaryApproval) ERC20TemporaryApprovalLib.__ERC20TemporaryApproval_init();
        ERC165Lib.registerInterface();
        assembly ("memory-safe") { sstore(ERC165_MAP_ILOUPE_SLOT, true) }
        // Recheck the installed profile after component initialization and binding.
        ERC3643ProfileLib.validate(config.temporaryApproval);
        ERC3643ExecutionLib.exit();
    }
}
