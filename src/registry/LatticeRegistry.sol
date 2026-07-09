// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {IERC8153} from "@lattice/interfaces/external/IERC8153.sol";
import {ILatticeRegistry} from "@lattice/interfaces/registry/ILatticeRegistry.sol";

/// @title LatticeRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Two-tier, immutable, deploy-once on-chain registry of canonical Lattice facets (issue #118). Tier A
///         is a permissionless, self-verifying codehash → address resolver; Tier B is a curated, append-only
///         `(name, version)` catalog governed by two-step ownership. Because Lattice facets are stateless (all
///         state lives in the caller diamond's ERC-7201 slots), one deployed facet safely serves unlimited
///         diamonds via `delegatecall`, so recording addresses here replaces re-`CREATE`ing byte-identical
///         bytecode on every deployment.
/// @dev DELIBERATELY NOT A DIAMOND. This is a minimal, standalone, NON-upgradeable plain contract: plain
///      storage (no ERC-7201 — there is no upgrade path by design), no facets, no proxy. It is the single
///      thing every deployment depends on, so it carries the smallest possible trust surface and is meant to
///      be deployed once per chain (via CreateX at a fixed salt → same address everywhere). Only the curated
///      namespace is admin-governed; Tier A and all reads are trustless. Original Lattice work.
/// @custom:lattice-version 0.1.0
contract LatticeRegistry is ILatticeRegistry {
    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev `keccak256("")` — the runtime codehash of an existing-but-codeless account (e.g. a funded EOA).
    ///      Together with `0` (a non-existent account) these are the two "no code" states {_requireCode}
    ///      rejects, so only real contract bytecode is ever attested / registered (invariant I4).
    bytes32 private constant EMPTY_CODE_HASH = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;

    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Owner of the curated Tier-B namespace (two-step; see {transferOwnership} / {acceptOwnership}).
    address public owner;

    /// @notice Address permitted to complete a pending ownership handover (`address(0)` when none pending).
    address public pendingOwner;

    /// @dev Tier A: runtime codehash → first attested address (first-write-wins, immutable once set).
    mapping(bytes32 codehash => address deployed) private _resolver;

    /// @dev Tier B: `keccak256(abi.encode(nameHash, version))` → immutable curated record.
    mapping(bytes32 recordKey => Record record) private _records;

    /// @dev Tier B: name → the version flagged as `latest`. `0` (0.0.0) is the reserved "unset" sentinel.
    mapping(bytes32 nameHash => uint64 version) private _latestVersion;

    //*//////////////////////////////////////////////////////////////////////////
    //                                 MODIFIERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Restricts a call to the current curated-namespace {owner}.
    modifier onlyOwner() {
        if (msg.sender != owner) revert LatticeRegistry__Unauthorized(msg.sender);
        _;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*//

    /// @param initialOwner The first curated-namespace owner (typically a multisig); must be non-zero.
    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert LatticeRegistry__ZeroAddress();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          TIER A — CODEHASH RESOLVER
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc ILatticeRegistry
    function attest(address deployed) external {
        _attest(_requireCode(deployed), deployed);
    }

    /// @inheritdoc ILatticeRegistry
    function resolve(bytes32 codehash) external view returns (address deployed) {
        deployed = _resolver[codehash];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          TIER B — CURATED CATALOG
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc ILatticeRegistry
    function register(bytes32 nameHash, uint64 version, address facet) external onlyOwner {
        _register(nameHash, version, facet);
    }

    /// @inheritdoc ILatticeRegistry
    function setLatest(bytes32 nameHash, uint64 version) external onlyOwner {
        _setLatest(nameHash, version);
    }

    /// @inheritdoc ILatticeRegistry
    function get(bytes32 nameHash, uint64 version) external view returns (Record memory record) {
        record = _get(nameHash, version);
    }

    /// @inheritdoc ILatticeRegistry
    function latest(bytes32 nameHash) external view returns (Record memory record) {
        record = _latest(nameHash);
    }

    /// @inheritdoc ILatticeRegistry
    function getSelectors(bytes32 nameHash, uint64 version) external view returns (bytes4[] memory selectors) {
        (, selectors) = _verifiedSelectors(nameHash, version);
    }

    /// @inheritdoc ILatticeRegistry
    function getCut(bytes32 nameHash, uint64 version) external view returns (FacetCut memory cut) {
        cut = _buildCut(nameHash, version);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                   TIER B — STRING-NAME CONVENIENCE
    //////////////////////////////////////////////////////////////////////////*//

    // Overloads that take a human-readable name for anyone interacting DIRECTLY with the contract (Etherscan,
    // etc.) — no need to compute `keccak256("lattice.<Name>")` off-chain first. Each hashes the RAW string via
    // {nameHash} (no prefix applied) and delegates to the `bytes32` path, so a name and its hash are fully
    // interchangeable. Pass the full canonical name, e.g. "lattice.ERC20".

    /// @inheritdoc ILatticeRegistry
    function register(string calldata name, uint64 version, address facet) external onlyOwner {
        _register(_hashName(name), version, facet);
    }

    /// @inheritdoc ILatticeRegistry
    function setLatest(string calldata name, uint64 version) external onlyOwner {
        _setLatest(_hashName(name), version);
    }

    /// @inheritdoc ILatticeRegistry
    function get(string calldata name, uint64 version) external view returns (Record memory record) {
        record = _get(_hashName(name), version);
    }

    /// @inheritdoc ILatticeRegistry
    function latest(string calldata name) external view returns (Record memory record) {
        record = _latest(_hashName(name));
    }

    /// @inheritdoc ILatticeRegistry
    function getSelectors(string calldata name, uint64 version) external view returns (bytes4[] memory selectors) {
        (, selectors) = _verifiedSelectors(_hashName(name), version);
    }

    /// @inheritdoc ILatticeRegistry
    function getCut(string calldata name, uint64 version) external view returns (FacetCut memory cut) {
        cut = _buildCut(_hashName(name), version);
    }

    /// @inheritdoc ILatticeRegistry
    function nameHash(string calldata name) external pure returns (bytes32) {
        return _hashName(name);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          OWNERSHIP (Ownable2Step)
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc ILatticeRegistry
    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @inheritdoc ILatticeRegistry
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert LatticeRegistry__NotPendingOwner(msg.sender);
        address previousOwner = owner;
        owner = msg.sender;
        delete pendingOwner;
        emit OwnershipTransferred(previousOwner, msg.sender);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Shared body of both {register} overloads: append-only write of a curated `(nameHash, version)`
    ///      record after pulling + validating + pinning the facet's ERC-8153 selectors and codehash.
    function _register(bytes32 nameHash, uint64 version, address facet) private {
        if (version == 0) revert LatticeRegistry__InvalidVersion();

        bytes32 recordKey = _key(nameHash, version);
        if (_records[recordKey].facet != address(0)) revert LatticeRegistry__RecordExists(nameHash, version);

        bytes32 codehash = _requireCode(facet);

        // Pull, validate, and pin the facet's ERC-8153 selectors.
        bytes memory blob = _fetchSelectors(facet);
        bytes32 selectorsHash = keccak256(blob);

        _records[recordKey] = Record({
            facet: facet,
            version: version,
            registeredAt: uint48(block.timestamp),
            codehash: codehash,
            selectorsHash: selectorsHash
        });

        // A curated facet is a canonical deployment — mirror it into the permissionless resolver too.
        _attest(codehash, facet);

        emit Registered(nameHash, version, facet, codehash, selectorsHash);
    }

    /// @dev Shared body of both {setLatest} overloads: point `latest(nameHash)` at an existing version.
    function _setLatest(bytes32 nameHash, uint64 version) private {
        if (_records[_key(nameHash, version)].facet == address(0)) {
            revert LatticeRegistry__RecordNotFound(nameHash, version);
        }
        _latestVersion[nameHash] = version;
        emit LatestSet(nameHash, version);
    }

    /// @dev The registry key for a canonical facet name — the RAW `keccak256(bytes(name))`, no prefix. The
    ///      `"lattice.<Name>"` convention lives in tooling/docs, not here, so the registry stays name-agnostic.
    function _hashName(string calldata name) private pure returns (bytes32) {
        return keccak256(bytes(name));
    }

    /// @dev Shared body of both {get} overloads.
    function _get(bytes32 nameHash, uint64 version) private view returns (Record memory record) {
        record = _records[_key(nameHash, version)];
        if (record.facet == address(0)) revert LatticeRegistry__RecordNotFound(nameHash, version);
    }

    /// @dev Shared body of both {latest} overloads.
    function _latest(bytes32 nameHash) private view returns (Record memory record) {
        uint64 version = _latestVersion[nameHash];
        if (version == 0) revert LatticeRegistry__LatestUnset(nameHash);
        // A set pointer always references an existing record (setLatest requires it), so no re-check needed.
        record = _records[_key(nameHash, version)];
    }

    /// @dev Shared body of both {getCut} overloads: live-verify then assemble an `Add` cut.
    function _buildCut(bytes32 nameHash, uint64 version) private view returns (FacetCut memory cut) {
        (address facet, bytes4[] memory selectors) = _verifiedSelectors(nameHash, version);
        cut = FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: selectors});
    }

    /// @dev Require `target` to carry real contract code and return its codehash (invariant I4).
    function _requireCode(address target) private view returns (bytes32 codehash) {
        codehash = target.codehash;
        if (codehash == 0 || codehash == EMPTY_CODE_HASH) revert LatticeRegistry__EmptyCode(target);
    }

    /// @dev First-write-wins insert into the Tier-A resolver; a duplicate codehash is a silent no-op so that
    ///      {register} auto-attest and any prior permissionless {attest} compose without reverting.
    function _attest(bytes32 codehash, address deployed) private {
        if (_resolver[codehash] == address(0)) {
            _resolver[codehash] = deployed;
            emit Attested(codehash, deployed);
        }
    }

    /// @dev The ERC-8153 `exportSelectors()` self-selector (`0x0ef22643`). A conformant facet MUST exclude it
    ///      from its own export (it is never cut into a diamond); {register} rejects any blob that self-includes
    ///      it, matching `BaseDeploy`'s cut-path strip and the parity gate.
    bytes4 private constant EXPORT_SELECTOR = IERC8153.exportSelectors.selector;

    /// @dev Staticcall `IERC8153(facet).exportSelectors()` and enforce the ERC-8153 contract at registration:
    ///      the call must succeed and return a well-formed, non-empty, 4-aligned, duplicate-free selector blob
    ///      that does not self-include `exportSelectors()`. Reverts {LatticeRegistry__NotERC8153} on any
    ///      violation. Returns the raw packed blob (to be pinned).
    function _fetchSelectors(address facet) private view returns (bytes memory blob) {
        (bool ok, bytes memory ret) = facet.staticcall(abi.encodeCall(IERC8153.exportSelectors, ()));
        // A valid ABI-encoded `bytes` return is at least 64 bytes (offset word + length word).
        if (!ok || ret.length < 64) revert LatticeRegistry__NotERC8153(facet);

        blob = abi.decode(ret, (bytes));
        uint256 len = blob.length;
        if (len == 0 || len % 4 != 0) revert LatticeRegistry__NotERC8153(facet);

        bytes4[] memory selectors = _unpack(blob);
        uint256 n = selectors.length;
        // O(n^2) duplicate scan + self-selector reject — one-time at registration, n is small.
        for (uint256 i; i < n; ++i) {
            if (selectors[i] == EXPORT_SELECTOR) revert LatticeRegistry__NotERC8153(facet);
            for (uint256 j = i + 1; j < n; ++j) {
                if (selectors[i] == selectors[j]) revert LatticeRegistry__NotERC8153(facet);
            }
        }
    }

    /// @dev Load a record and re-verify BOTH pins against the facet's current on-chain state: its `codehash`
    ///      (defends against a metamorphic address swap) and the live `keccak256(exportSelectors())`. Reverts
    ///      {LatticeRegistry__RecordNotFound} if unregistered, {LatticeRegistry__CodeDrift} if the code changed,
    ///      and {LatticeRegistry__SelectorDrift} if the live selector blob no longer matches the pin.
    function _verifiedSelectors(bytes32 nameHash, uint64 version)
        private
        view
        returns (address facet, bytes4[] memory selectors)
    {
        Record storage record = _records[_key(nameHash, version)];
        facet = record.facet;
        if (facet == address(0)) revert LatticeRegistry__RecordNotFound(nameHash, version);

        // Code pin first: a mutated/self-destructed facet fails here even if some blob still decodes.
        if (facet.codehash != record.codehash) revert LatticeRegistry__CodeDrift(facet);

        bytes memory blob = _liveSelectors(facet);
        if (keccak256(blob) != record.selectorsHash) revert LatticeRegistry__SelectorDrift(facet);
        selectors = _unpack(blob);
    }

    /// @dev Best-effort live read of `exportSelectors()`. Returns the raw blob, or empty bytes when the call
    ///      reverts / self-destructs / returns too few bytes to be ABI `bytes`. An empty (or otherwise
    ///      non-matching) blob's hash never equals a pinned `selectorsHash`, so the caller's selector pin
    ///      rejects it with {LatticeRegistry__SelectorDrift}. NOTE: a return that is >= 64 bytes yet not a valid
    ///      ABI `bytes` encoding makes `abi.decode` revert with a Panic that propagates out of the view — still
    ///      fail-closed (no stale cut is ever returned), just not surfaced as {LatticeRegistry__SelectorDrift}.
    function _liveSelectors(address facet) private view returns (bytes memory blob) {
        (bool ok, bytes memory ret) = facet.staticcall(abi.encodeCall(IERC8153.exportSelectors, ()));
        if (ok && ret.length >= 64) blob = abi.decode(ret, (bytes));
    }

    /// @dev Unpack a tightly packed selector blob (`length % 4 == 0`, validated by the caller) to `bytes4[]`.
    function _unpack(bytes memory blob) private pure returns (bytes4[] memory selectors) {
        uint256 n = blob.length / 4;
        selectors = new bytes4[](n);
        for (uint256 i; i < n; ++i) {
            bytes4 selector;
            assembly ("memory-safe") {
                // Each selector is the top 4 bytes of the word at blob data offset i*4.
                selector := mload(add(add(blob, 0x20), mul(i, 4)))
            }
            selectors[i] = selector;
        }
    }

    /// @dev Deterministic record key for a `(nameHash, version)` pair.
    function _key(bytes32 nameHash, uint64 version) private pure returns (bytes32 recordKey) {
        recordKey = keccak256(abi.encode(nameHash, version));
    }
}
