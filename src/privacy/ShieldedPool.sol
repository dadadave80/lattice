// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IShieldedPool} from "@lattice/interfaces/privacy/IShieldedPool.sol";
import {ShieldedPoolLib} from "@lattice/privacy/libraries/ShieldedPoolLib.sol";

/// @title ShieldedPool
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Stateless Diamond facet for fixed-denomination shielded (private) ERC-20 transfers
///         (Tornado-style): deposit a commitment, then withdraw to an arbitrary recipient by proving
///         membership in zero knowledge and burning a one-time nullifier hash.
/// @dev All logic lives in {ShieldedPoolLib}. The withdraw circuit + verifier are consumer-supplied per
///      pool. SECURITY: escrows funds — deploy only with an AUDITED circuit/verifier and honest trusted
///      setup before any mainnet-with-funds use.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original (Tornado-style; consumer-supplied audited circuit)
contract ShieldedPool is IShieldedPool {
    /// @inheritdoc IShieldedPool
    function createPool(address token, uint256 denomination, address verifier) external virtual returns (uint256) {
        return ShieldedPoolLib.createPool(token, denomination, verifier);
    }

    /// @inheritdoc IShieldedPool
    function deposit(uint256 poolId, uint256 commitment) external virtual {
        ShieldedPoolLib.deposit(poolId, commitment);
    }

    /// @inheritdoc IShieldedPool
    function withdraw(
        uint256 poolId,
        WithdrawProof calldata proof,
        uint256 root,
        uint256 nullifierHash,
        address recipient,
        address relayer,
        uint256 fee
    ) external virtual {
        ShieldedPoolLib.withdraw(poolId, proof, root, nullifierHash, recipient, relayer, fee);
    }

    /// @inheritdoc IShieldedPool
    function poolCount() external view virtual returns (uint256) {
        return ShieldedPoolLib.poolCount();
    }

    /// @inheritdoc IShieldedPool
    function getPool(uint256 poolId)
        external
        view
        virtual
        returns (address token, uint256 denomination, address verifier, uint256 merkleRoot, uint256 numLeaves)
    {
        return ShieldedPoolLib.getPool(poolId);
    }

    /// @inheritdoc IShieldedPool
    function isSpent(uint256 poolId, uint256 nullifierHash) external view virtual returns (bool) {
        return ShieldedPoolLib.isSpent(poolId, nullifierHash);
    }

    /// @inheritdoc IShieldedPool
    function isKnownRoot(uint256 poolId, uint256 root) external view virtual returns (bool) {
        return ShieldedPoolLib.isKnownRoot(poolId, root);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ShieldedPool methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `createPool(address,uint256,address)` 0x9bb62b76
    ///      `deposit(uint256,uint256)` 0xe2bbb158
    ///      `getPool(uint256)` 0x068bcd8d
    ///      `isKnownRoot(uint256,uint256)` 0xc17d30f1
    ///      `isSpent(uint256,uint256)` 0xe1056c3e
    ///      `poolCount()` 0xf525cb68
    ///      `withdraw(uint256,(uint256[2],uint256[2][2],uint256[2]),uint256,uint256,address,address,uint256)` 0x258702c3
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"9bb62b76e2bbb158068bcd8dc17d30f1e1056c3ef525cb68258702c3";
    }
}
