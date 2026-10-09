// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";

/// @title LatticeRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Two-tier, immutable, deploy-once on-chain registry of canonical Lattice facets (issue #118). Tier A
///         is a permissionless, self-verifying codehash → first-attested-address index (code identity only,
///         never a selector source; see {ILatticeRegistry}); Tier B is a curated, append-only
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

    /// @dev Gas forwarded to every `exportSelectors()` call (finding R-2). A compiled `pure` exporter returns a
    ///      constant blob: every release facet's export runs in at most 2,233 gas (AccessManager; measured over
    ///      the whole release inventory), so this leaves over 40x headroom while bounding what a looping or
    ///      gas-burning exporter can take from the caller (a `register` transaction, a `getCut` read, or every
    ///      factory deploy resolving it).
    uint256 private constant EXPORT_GAS = 100_000;

    /// @dev Largest `exportSelectors()` return the registry copies (finding R-2): 8,192 bytes, room for 2,032
    ///      selectors in the canonical encoding (64-byte head + data). The largest release export is 224 bytes
    ///      (Governor, 36 selectors), and EIP-170 caps a facet at 24,576 bytes of code with every routed
    ///      selector costing a dispatcher several bytes, so no real facet comes close. The cap stops a
    ///      return-data bomb from taxing every live read: a larger return is never copied at all.
    uint256 private constant MAX_EXPORT_SIZE = 8192;

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
    function getMany(RecordKey[] calldata keys) external view returns (Record[] memory records) {
        uint256 n = keys.length;
        records = new Record[](n);
        for (uint256 i; i < n; ++i) {
            RecordKey calldata key = keys[i];
            records[i] = key.version == 0 ? _latest(key.nameHash) : _get(key.nameHash, key.version);
        }
    }

    /// @inheritdoc ILatticeRegistry
    function latestMany(bytes32[] calldata nameHashes) external view returns (Record[] memory records) {
        uint256 n = nameHashes.length;
        records = new Record[](n);
        for (uint256 i; i < n; ++i) {
            records[i] = _latest(nameHashes[i]);
        }
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
        address pending = pendingOwner;
        // A zero pending owner means no handover is open (never started, or cancelled), so nobody may accept.
        if (pending == address(0) || msg.sender != pending) revert LatticeRegistry__NotPendingOwner(msg.sender);
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

    /// @dev Read `IERC8153(facet).exportSelectors()` through {_exportedBlob} and enforce the ERC-8153 contract
    ///      at registration: the blob must be non-empty, 4-aligned, duplicate-free, and must not self-include
    ///      `exportSelectors()`. Reverts {LatticeRegistry__NotERC8153} on any violation, including every call or
    ///      decoding failure {_exportedBlob} reports as an empty blob. Returns the packed blob (to be pinned).
    function _fetchSelectors(address facet) private view returns (bytes memory blob) {
        blob = _exportedBlob(facet);
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

        // A failed or malformed read returns an empty blob, whose hash never equals a pin (pins are of
        // non-empty blobs), so every live-read failure surfaces as SelectorDrift.
        bytes memory blob = _exportedBlob(facet);
        if (keccak256(blob) != record.selectorsHash) revert LatticeRegistry__SelectorDrift(facet);
        selectors = _unpack(blob);
    }

    /// @dev Bounded read of `exportSelectors()` (findings R-1 and R-2). Staticcalls `facet` with at most
    ///      {EXPORT_GAS} gas, copies nothing until the return size is known, and refuses a return shorter than an
    ///      ABI `bytes` encoding (64 bytes) or longer than {MAX_EXPORT_SIZE}. The encoding is then decoded by hand
    ///      with exactly the acceptance rule of `abi.decode(ret, (bytes))`: the offset word must leave room for the
    ///      length word, and the declared length must fit in the bytes that follow it (no padding is required,
    ///      trailing bytes are ignored). Returns the decoded blob, or EMPTY bytes on any failure, so no hostile
    ///      return can make the caller revert with empty data or a Panic.
    function _exportedBlob(address facet) private view returns (bytes memory blob) {
        assembly ("memory-safe") {
            blob := 0x60 // empty `bytes` (the zero slot) unless a valid encoding is found below
            mstore(0x00, shl(224, 0x0ef22643)) // exportSelectors()
            let ok := staticcall(EXPORT_GAS, facet, 0x00, 0x04, 0x00, 0x00)
            let size := returndatasize()
            if and(ok, and(gt(size, 0x3f), iszero(gt(size, MAX_EXPORT_SIZE)))) {
                returndatacopy(0x00, 0x00, 0x20)
                let offset := mload(0x00)
                // The length word must lie inside the return: offset + 32 <= size.
                if iszero(gt(offset, sub(size, 0x20))) {
                    returndatacopy(0x00, offset, 0x20)
                    let len := mload(0x00)
                    // The data must lie inside the return: offset + 32 + len <= size.
                    if iszero(gt(len, sub(sub(size, offset), 0x20))) {
                        blob := mload(0x40)
                        mstore(blob, len)
                        returndatacopy(add(blob, 0x20), add(offset, 0x20), len)
                        mstore(0x40, add(add(blob, 0x20), and(add(len, 0x1f), not(0x1f))))
                    }
                }
            }
        }
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
