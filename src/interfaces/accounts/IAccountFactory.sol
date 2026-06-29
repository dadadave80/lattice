// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IAccountFactory
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Deterministic factory for EIP-2535 Diamond smart accounts. Each account address is a pure
///         function of `(factory, owner, salt)` and the fixed proxy initcode, so it can be computed
///         off-chain before deployment — enabling counterfactual ERC-4337 `initCode` onboarding.
/// @dev The `owner` is folded into the CREATE2 salt, so a given counterfactual address can only ever be
///      realized with the owner it was derived from (no third party can pre-deploy your address under a
///      different owner). Deployment is idempotent: re-running `createAccount` for an already-deployed
///      `(owner, salt)` returns the existing account instead of reverting.
interface IAccountFactory {
    /// @notice Thrown when constructing a factory with an empty facet blueprint (would yield accounts with
    ///         no callable functions — a permanent, silent misconfiguration since the factory is immutable).
    error EmptyBlueprint();

    /// @notice Emitted once when an account is deployed (not re-emitted on idempotent re-calls).
    /// @param account The deployed Diamond account.
    /// @param owner The account's initial signing owner.
    /// @param salt The caller-chosen salt distinguishing accounts for the same owner.
    event AccountCreated(address indexed account, address indexed owner, bytes32 salt);

    /// @notice Deploys (or returns the existing) Diamond account for `(owner, salt)` and initializes it
    ///         with the factory's fixed facet blueprint and the owner.
    /// @param owner The initial signing owner of the account.
    /// @param salt Caller-chosen salt; distinct salts yield distinct accounts for the same owner.
    /// @return account The deterministic account address (equals {getAddress}).
    function createAccount(address owner, bytes32 salt) external returns (address account);

    /// @notice The counterfactual address `createAccount(owner, salt)` will deploy to.
    /// @param owner The prospective owner.
    /// @param salt The prospective salt.
    /// @return account The deterministic CREATE2 address.
    function getAddress(address owner, bytes32 salt) external view returns (address account);

    /// @notice The initializer contract delegatecalled during each account's `diamondCut` initialization.
    function accountInit() external view returns (address);
}
