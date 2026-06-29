// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {UniswapV3AdapterLib} from "@lattice/defi/libraries/UniswapV3AdapterLib.sol";
import {IAdapterOperator} from "@lattice/interfaces/defi/IAdapterOperator.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IUniswapV3Adapter} from "@lattice/interfaces/defi/IUniswapV3Adapter.sol";
import {IStrategy} from "@lattice/interfaces/external/IStrategy.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

/// @title UniswapV3Adapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Diamond facet adapting a **full-range** Uniswap V3 LP position into a Lattice vault
///         strategy. Implements `IStrategy` (funds routing), `IProtocolAdapter` (sidecar), and
///         `IUniswapV3Adapter` (Uniswap config). This is a **CUSTOM** adapter: a v3 LP is a
///         two-token, NFT-wrapped concentrated-liquidity position that does not fit the single-asset
///         `IStrategy` surface cleanly. Compromises (all documented in `UniswapV3AdapterLib`):
///         full-range only (no active range management), swap-free (the keeper funds both tokens),
///         `asset` == token0, and NAV valued from the pool **TWAP** (`observe`), never `slot0` spot.
///         All logic lives in UniswapV3AdapterLib.
/// @dev Provenance: Uniswap V3 core (https://github.com/Uniswap/v3-core) + periphery
///      NonfungiblePositionManager (https://github.com/Uniswap/v3-periphery). The facet implements
///      `onERC721Received` so the NFPM can safe-mint the position NFT to it.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract UniswapV3Adapter is IStrategy, IProtocolAdapter, IAdapterOperator, IUniswapV3Adapter {
    //*//////////////////////////////////////////////////////////////////////////
    //                              IStrategy
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IStrategy
    function asset() external view virtual override returns (address) {
        return UniswapV3AdapterLib.asset();
    }

    /// @inheritdoc IStrategy
    function totalAssetsManaged() external view virtual override returns (uint256) {
        return UniswapV3AdapterLib.totalAssetsManaged();
    }

    /// @inheritdoc IStrategy
    function withdraw(uint256 amount, address to) external virtual override returns (uint256 withdrawn) {
        return UniswapV3AdapterLib.withdraw(amount, to);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IProtocolAdapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IProtocolAdapter
    function deploy() external virtual override returns (uint256 deployed) {
        return UniswapV3AdapterLib.deploy();
    }

    /// @inheritdoc IProtocolAdapter
    function harvest() external virtual override {
        UniswapV3AdapterLib.harvest();
    }

    /// @inheritdoc IProtocolAdapter
    function emergencyWithdraw() external virtual override returns (uint256 recovered) {
        return UniswapV3AdapterLib.emergencyWithdraw();
    }

    /// @inheritdoc IProtocolAdapter
    function isPaused() external view virtual override returns (bool) {
        return UniswapV3AdapterLib.isPaused();
    }

    /// @inheritdoc IProtocolAdapter
    function healthFactor() external view virtual override returns (uint256) {
        return UniswapV3AdapterLib.healthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function minHealthFactor() external view virtual override returns (uint256) {
        return UniswapV3AdapterLib.minHealthFactor();
    }

    /// @inheritdoc IProtocolAdapter
    function rewardRecipient() external view virtual override returns (address) {
        return UniswapV3AdapterLib.rewardRecipient();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            IAdapterOperator
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IAdapterOperator
    function setOperator(address operator_) external virtual override {
        UniswapV3AdapterLib.setOperator(operator_);
    }

    /// @inheritdoc IAdapterOperator
    function operator() external view virtual override returns (address) {
        return UniswapV3AdapterLib.operator();
    }

    /// @notice True while a guarded op is executing — mirrors StrategyManager so VaultCore can
    ///         reject share-price-sensitive ops mid-deploy/withdraw (read-only reentrancy guard).
    function reentrancyGuardEntered() external view virtual returns (bool) {
        return ReentrancyGuardLib.reentrancyGuardEntered();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          IUniswapV3Adapter
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IUniswapV3Adapter
    function positionManager() external view virtual override returns (address) {
        return UniswapV3AdapterLib.positionManager();
    }

    /// @inheritdoc IUniswapV3Adapter
    function pool() external view virtual override returns (address) {
        return UniswapV3AdapterLib.pool();
    }

    /// @inheritdoc IUniswapV3Adapter
    function token0() external view virtual override returns (address) {
        return UniswapV3AdapterLib.token0();
    }

    /// @inheritdoc IUniswapV3Adapter
    function token1() external view virtual override returns (address) {
        return UniswapV3AdapterLib.token1();
    }

    /// @inheritdoc IUniswapV3Adapter
    function fee() external view virtual override returns (uint24) {
        return UniswapV3AdapterLib.fee();
    }

    /// @inheritdoc IUniswapV3Adapter
    function tokenId() external view virtual override returns (uint256) {
        return UniswapV3AdapterLib.tokenId();
    }

    /// @inheritdoc IUniswapV3Adapter
    function vault() external view virtual override returns (address) {
        return UniswapV3AdapterLib.vault();
    }

    /// @inheritdoc IUniswapV3Adapter
    function twapWindow() external view virtual override returns (uint32) {
        return UniswapV3AdapterLib.twapWindow();
    }

    /// @inheritdoc IUniswapV3Adapter
    function slippageBps() external view virtual override returns (uint256) {
        return UniswapV3AdapterLib.slippageBps();
    }

    /// @inheritdoc IUniswapV3Adapter
    function setTwapWindow(uint32 twapWindow_) external virtual override {
        UniswapV3AdapterLib.setTwapWindow(twapWindow_);
    }

    /// @inheritdoc IUniswapV3Adapter
    function setSlippageBps(uint256 slippageBps_) external virtual override {
        UniswapV3AdapterLib.setSlippageBps(slippageBps_);
    }

    /// @inheritdoc IUniswapV3Adapter
    function setRewardRecipient(address recipient) external virtual override {
        UniswapV3AdapterLib.setRewardRecipient(recipient);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            ERC-721 RECEIVER
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Accepts the Uniswap V3 position NFT safe-minted by the NonfungiblePositionManager.
    /// @dev Returns the `IERC721Receiver.onERC721Received` selector so `_safeMint` succeeds. The
    ///      adapter is the position custodian; it never expects any other NFT, but this handler is
    ///      intentionally permissive (returns the magic value unconditionally) so the mint path on the
    ///      real NFPM cannot revert.
    function onERC721Received(address, address, uint256, bytes calldata) external virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
