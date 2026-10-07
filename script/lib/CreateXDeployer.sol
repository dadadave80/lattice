// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICreateX} from "@lattice/interfaces/external/createx/ICreateX.sol";

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
///         canonical bytecode. Path (2) additionally falls back to the {ARACHNID_PROXY} on chains CreateX
///         never reached (Hedera is the motivating case): same permissionless, initcode-committed
///         determinism, at a different deterministic address (see {predictRaw}).
/// @dev Stateless utility library (internal functions run in the caller script's context, so `msg.sender`
///      inside CreateX is the script's broadcasting address). CREATE3 salts are sender-guarded + cross-chain
///      redeploy-protected; raw CREATE2 salts must have first 20 bytes that are neither the caller nor zero
///      (any keccak-derived protocol salt). `predict`/`predictRaw` reproduce CreateX's internal `_guard`
///      transforms because the public `computeCreate3Address(salt)`/`computeCreate2Address(salt, hash)` do
///      not re-guard the salt they are given. The fallback covers the RAW-salt path only — the proxy has no
///      CREATE3 equivalent, so {deploy}/{predict} still require CreateX itself.
library CreateXDeployer {
    /// @notice The canonical CreateX deployer, identical on every supported chain.
    ICreateX internal constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    /// @notice The Arachnid deterministic-deployment proxy — the raw-salt fallback for chains that never got
    ///         CreateX. Hedera is the motivating case: no CreateX on mainnet or testnet, but the proxy is
    ///         there (mainnet entity `0.0.6264020`, testnet `0.0.4283707`).
    /// @dev 69 bytes of runtime: calldata is `salt (32 bytes) ++ initCode`; it CREATE2-deploys, reverts when
    ///      the CREATE2 fails, and otherwise returns the RAW 20-byte address (`return(0x0c, 0x14)`) — NOT an
    ///      ABI-encoded one. It applies NO guard to the salt it is handed.
    address internal constant ARACHNID_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    //*//////////////////////////////////////////////////////////////////////////
    //                           DEPLOYER AVAILABILITY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice True when this chain has a deterministic raw-salt deployer at all: {CREATEX}, or the
    ///         {ARACHNID_PROXY} fallback, has code here.
    /// @dev The gate for callers that hold a non-deterministic alternative — `BaseDeploy._facet` plain-CREATEs
    ///      the facet instead, `DeployRelease.release` refuses to run. Where this is false {deployRaw} and
    ///      {predictRaw} have nothing to call.
    function hasRawDeployer() internal view returns (bool) {
        return address(CREATEX).code.length != 0 || ARACHNID_PROXY.code.length != 0;
    }

    /// @dev True when the raw-salt path must take the Arachnid fallback: CreateX was never deployed here and
    ///      the proxy was. CreateX wins wherever both have code, so no existing chain's addresses move.
    function _useArachnid() internal view returns (bool) {
        return address(CREATEX).code.length == 0 && ARACHNID_PROXY.code.length != 0;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        SENDER-GUARDED CREATE3 PATH
    //////////////////////////////////////////////////////////////////////////*//

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

    //*//////////////////////////////////////////////////////////////////////////
    //                        RAW-SALT CREATE2 RELEASE PATH
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deploys `initCode` via CreateX CREATE2 using a RAW protocol salt (the release path).
    /// @dev For a raw salt (first 20 bytes neither the caller nor zero) CreateX applies the deployer- and
    ///      chain-independent guard `keccak256(abi.encode(salt))`, so the address is the SAME on every chain
    ///      and commits to `keccak256(initCode)` — anyone can complete a release, but a squatter can only
    ///      ever deploy the canonical bytecode at the canonical address. Without CreateX but with the
    ///      {ARACHNID_PROXY}, the identical call is made to the proxy as plain `salt ++ initCode` calldata:
    ///      the proxy CREATE2s and returns the raw 20-byte address, reverting when the CREATE2 fails (the
    ///      address is occupied, or the initcode reverted).
    /// @param salt     A raw protocol salt (e.g. `keccak256("lattice.<Name>.<version>")`).
    /// @param initCode The full creation bytecode (e.g. `abi.encodePacked(type(C).creationCode, args)`).
    /// @return deployed The address the contract was deployed to (== {predictRaw} for the same inputs).
    function deployRaw(bytes32 salt, bytes memory initCode) internal returns (address deployed) {
        if (_useArachnid()) {
            (bool ok, bytes memory ret) = ARACHNID_PROXY.call(abi.encodePacked(salt, initCode));
            require(ok, "CreateXDeployer: Arachnid proxy deployment reverted");
            require(ret.length == 20, "CreateXDeployer: Arachnid proxy returned no address");
            return address(bytes20(ret));
        }
        deployed = CREATEX.deployCreate2(salt, initCode);
    }

    /// @notice Predicts the CREATE2 address {deployRaw} produces for a raw `salt` and `initCodeHash`.
    /// @dev Reproduces CreateX's raw-salt `_guard` transform (`keccak256(abi.encode(salt))`) because the
    ///      public `computeCreate2Address(salt, initCodeHash)` does not re-guard the salt it is given. The
    ///      {ARACHNID_PROXY} guards nothing, so its prediction is the plain EIP-1014 derivation over the RAW,
    ///      UNGUARDED salt with the PROXY as deployer: `keccak256(0xff ++ proxy ++ salt ++ initCodeHash)[12:]`.
    ///      Consequence: the same facet lands at a DIFFERENT address on an Arachnid chain than on a CreateX
    ///      chain — still deterministic, still permissionless, still committed to `keccak256(initCode)`, just
    ///      a different deterministic address (see REGISTRY_DEPLOYMENTS.md).
    /// @param salt         The raw protocol salt passed to {deployRaw}.
    /// @param initCodeHash `keccak256` of the full creation bytecode incl. constructor args.
    /// @return predicted The deterministic address the matching {deployRaw} call will produce.
    function predictRaw(bytes32 salt, bytes32 initCodeHash) internal view returns (address predicted) {
        if (_useArachnid()) {
            return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", ARACHNID_PROXY, salt, initCodeHash)))));
        }
        predicted = CREATEX.computeCreate2Address(keccak256(abi.encode(salt)), initCodeHash);
    }
}
