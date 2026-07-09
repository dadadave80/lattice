// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICreateX} from "@lattice/interfaces/external/ICreateX.sol";

/// @title CreateXDeployer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Thin Foundry helper around the canonical CreateX singleton, offering two deterministic paths:
///         (1) the sender-guarded + cross-chain-protected CREATE3 path ({deploy}/{predict}) — the address
///         depends on `(CreateX, deployer, block.chainid, salt)` and NOT on the contract's initcode, so it
///         survives bytecode/compiler changes but lands at a DIFFERENT address on every chain (that is what
///         cross-chain redeploy protection means: byte 20 = `0x01` folds `block.chainid` into the guarded
///         salt); (2) the raw-salt CREATE2 release path ({deployRaw}/{predictRaw}) — deployer- AND
///         chain-independent, so a facet lands at the SAME address on every chain, and the address commits
///         to `keccak256(initCode)`, so anyone can permissionlessly complete a release yet only with the
///         canonical bytecode.
/// @dev Stateless utility library (internal functions run in the caller script's context, so `msg.sender`
///      inside CreateX is the script's broadcasting address). CREATE3 salts are sender-guarded + cross-chain
///      redeploy-protected; raw CREATE2 salts must have first 20 bytes that are neither the caller nor zero
///      (any keccak-derived protocol salt). `predict`/`predictRaw` reproduce CreateX's internal `_guard`
///      transforms because the public `computeCreate3Address(salt)`/`computeCreate2Address(salt, hash)` do
///      not re-guard the salt they are given.
library CreateXDeployer {
    /// @notice The canonical CreateX deployer, identical on every supported chain.
    ICreateX internal constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    /// @notice Builds a sender-guarded, cross-chain-redeploy-protected salt for `deployer`.
    /// @dev Layout matches CreateX `_parseSalt`: bytes[0..19] = `deployer` (permissioned deploy),
    ///      byte[20] = `0x01` (enable cross-chain redeploy protection), bytes[21..31] = `entropy`.
    /// @param deployer The address that will call CreateX (the broadcasting EOA/script).
    /// @param entropy  11 bytes of caller-chosen entropy distinguishing independent deployments.
    /// @return salt The 32-byte guarded salt to pass to {deploy}/{predict}.
    function _guardedSalt(address deployer, bytes11 entropy) internal pure returns (bytes32 salt) {
        salt = bytes32(bytes20(deployer)) | (bytes32(bytes1(0x01)) >> 160) | (bytes32(entropy) >> 168);
    }

    /// @notice Reproduces CreateX's internal `_guard` transform for a sender-guarded + cross-chain
    ///         protected salt: `keccak256(abi.encode(deployer, block.chainid, salt))`.
    /// @dev Used by {predict} so the off-chain address matches the on-chain `deployCreate3` derivation.
    ///      `deployer` MUST equal the address that will broadcast the deploy (CreateX's `msg.sender`).
    function _guardTransform(address deployer, bytes32 salt) internal view returns (bytes32) {
        return keccak256(abi.encode(deployer, block.chainid, salt));
    }

    /// @notice Deploys `initCode` deterministically via CreateX CREATE3 using the guarded `salt`.
    /// @param salt     A guarded salt from {_guardedSalt} (first 20 bytes MUST equal the broadcaster).
    /// @param initCode The full creation bytecode (e.g. `abi.encodePacked(type(C).creationCode, args)`).
    /// @return deployed The address the contract was deployed to (== {predict} for the same salt).
    function deploy(bytes32 salt, bytes memory initCode) internal returns (address deployed) {
        deployed = CREATEX.deployCreate3(salt, initCode);
    }

    /// @notice Predicts the CREATE3 address for the guarded `salt`, as broadcast by `msg.sender`.
    /// @dev Reproduces CreateX's guard transform, then asks CreateX to compute the address for that
    ///      guarded salt (the public `computeCreate3Address(salt)` does not re-guard).
    /// @param salt A guarded salt from {_guardedSalt}; its first 20 bytes are the broadcasting deployer.
    /// @return predicted The deterministic address the matching {deploy} call will produce.
    function predict(bytes32 salt) internal view returns (address predicted) {
        bytes32 guarded = _guardTransform(address(bytes20(salt)), salt);
        predicted = CREATEX.computeCreate3Address(guarded, address(CREATEX));
    }

    /// @notice Deploys `initCode` via CreateX CREATE2 using a RAW protocol salt (the release path).
    /// @dev For a raw salt (first 20 bytes neither the caller nor zero) CreateX applies the deployer- and
    ///      chain-independent guard `keccak256(abi.encode(salt))`, so the address is the SAME on every chain
    ///      and commits to `keccak256(initCode)` — anyone can complete a release, but a squatter can only
    ///      ever deploy the canonical bytecode at the canonical address.
    /// @param salt     A raw protocol salt (e.g. `keccak256("lattice.<Name>.<version>")`).
    /// @param initCode The full creation bytecode (e.g. `abi.encodePacked(type(C).creationCode, args)`).
    /// @return deployed The address the contract was deployed to (== {predictRaw} for the same inputs).
    function deployRaw(bytes32 salt, bytes memory initCode) internal returns (address deployed) {
        deployed = CREATEX.deployCreate2(salt, initCode);
    }

    /// @notice Predicts the CREATE2 address {deployRaw} produces for a raw `salt` and `initCodeHash`.
    /// @dev Reproduces CreateX's raw-salt `_guard` transform (`keccak256(abi.encode(salt))`) because the
    ///      public `computeCreate2Address(salt, initCodeHash)` does not re-guard the salt it is given.
    /// @param salt         The raw protocol salt passed to {deployRaw}.
    /// @param initCodeHash `keccak256` of the full creation bytecode incl. constructor args.
    /// @return predicted The deterministic address the matching {deployRaw} call will produce.
    function predictRaw(bytes32 salt, bytes32 initCodeHash) internal view returns (address predicted) {
        predicted = CREATEX.computeCreate2Address(keccak256(abi.encode(salt)), initCodeHash);
    }
}
