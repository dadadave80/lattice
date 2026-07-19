// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICreateX
/// @author Minimal vendored subset of CreateX by pcaversaccio + Matt Solomon
///         (https://github.com/pcaversaccio/createx/blob/main/src/ICreateX.sol). Upstream is
///         AGPL-3.0-only; only the deterministic-deploy ABI Lattice calls is re-declared here.
/// @notice Interface for the canonical CreateX universal deterministic deployer, deployed as a
///         singleton at `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` on every supported chain.
/// @dev Lattice uses the CREATE3 path (address independent of initcode → cross-chain-stable) for the
///      Diamond + facets, plus the CREATE2 helpers for completeness. The `*AndInit` / clone overloads
///      are intentionally omitted. Salt-guarding: first 20 bytes == caller ⇒ permissioned deploy; the
///      21st byte == 0x01 ⇒ cross-chain redeploy protection.
interface ICreateX {
    /// @dev `payable` amounts for a combined deploy-and-initialise call (unused by the CREATE3/CREATE2
    ///      deploy paths Lattice calls, but part of the canonical ABI; retained for signature parity).
    struct Values {
        uint256 constructorAmount;
        uint256 initCallAmount;
    }

    // ----------------------------- CREATE2 -----------------------------

    /// @notice Deploys `initCode` via CREATE2 using `salt` (subject to salt-guarding).
    /// @return newContract The address the contract was deployed to.
    function deployCreate2(bytes32 salt, bytes memory initCode) external payable returns (address newContract);

    /// @notice Deploys `initCode` via CREATE2 with a pseudo-random salt.
    /// @return newContract The address the contract was deployed to.
    function deployCreate2(bytes memory initCode) external payable returns (address newContract);

    /// @notice Computes the CREATE2 address for `salt`/`initCodeHash` deployed by `deployer`.
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash, address deployer)
        external
        pure
        returns (address computedAddress);

    /// @notice Computes the CREATE2 address for `salt`/`initCodeHash` deployed by this CreateX instance.
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address computedAddress);

    // ----------------------------- CREATE3 -----------------------------

    /// @notice Deploys `initCode` via the CREATE3 pattern using `salt` (subject to salt-guarding).
    /// @dev The resulting address depends only on `(CreateX, guardedSalt)`, NOT on `initCode`.
    /// @return newContract The address the contract was deployed to.
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);

    /// @notice Deploys `initCode` via the CREATE3 pattern with a pseudo-random salt.
    /// @return newContract The address the contract was deployed to.
    function deployCreate3(bytes memory initCode) external payable returns (address newContract);

    /// @notice Computes the CREATE3 address for the GUARDED `salt` as deployed by `deployer`.
    /// @dev Does NOT apply salt-guarding — pass the already-guarded salt to predict a guarded deploy.
    function computeCreate3Address(bytes32 salt, address deployer) external pure returns (address computedAddress);

    /// @notice Computes the CREATE3 address for the GUARDED `salt` as deployed by this CreateX instance.
    /// @dev Does NOT apply salt-guarding — pass the already-guarded salt to predict a guarded deploy.
    function computeCreate3Address(bytes32 salt) external view returns (address computedAddress);
}
