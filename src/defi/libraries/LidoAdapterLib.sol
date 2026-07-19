// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {WETHUnwrapper} from "@lattice/defi/WETHUnwrapper.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {ILidoAdapter} from "@lattice/interfaces/defi/ILidoAdapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {ILido} from "@lattice/interfaces/external/lido/ILido.sol";
import {ILidoWithdrawalQueue} from "@lattice/interfaces/external/lido/ILidoWithdrawalQueue.sol";
import {IWstETH} from "@lattice/interfaces/external/lido/IWstETH.sol";
import {IWETH9} from "@lattice/interfaces/external/weth/IWETH9.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.LidoAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
/// Precomputed: 0x3d4dff0246f0af54636d62603e75b921d2876c293bb97376b20bb8265ecb3900
bytes32 constant LIDO_ADAPTER_STORAGE_SLOT = 0x3d4dff0246f0af54636d62603e75b921d2876c293bb97376b20bb8265ecb3900;

/// @dev ERC-165 storage location (shared across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant LIDO_ADAPTER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x8f7783e6 is `type(IProtocolAdapter).interfaceId` (same value the Aave/Compound/ERC4626/Curve
/// adapters register; the ERC-165 map slot is shared because the interface ID is identical).
/// `keccak256(abi.encode(bytes4(0x8f7783e6), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPROTOCOLADAPTER_SLOT = 0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77;

/// @dev 0x83d0afd2 is `type(ILidoAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x83d0afd2), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ILIDOADAPTER_SLOT = 0x6167b6f3924e213fbc2c85ec2d6ca3e7f5267a73935588adb9fb05f57a52b315;

/// @dev `keccak256("lattice.LidoAdapter.WETHUnwrapper")` — CREATE2 salt for the per-diamond {WETHUnwrapper}.
bytes32 constant _WETH_UNWRAPPER_SALT = 0x564152588ece721544930d70d150570f94d5fc5c0638cf70676b240372aabb9c;

/// @notice ERC-7201 namespaced storage for the Lido staking (buffer-model) adapter.
/// @custom:storage-location erc7201:lattice.storage.LidoAdapter
struct LidoAdapterStorage {
    /// @dev WETH — the adapter's asset and idle buffer (the synchronous withdraw is served from it).
    address _weth;
    /// @dev Lido stETH token (`submit` mints it; an intermediate hop, always wrapped immediately).
    address _lido;
    /// @dev wstETH wrapper the staked position is held as (non-rebasing; yield via its rising rate).
    address _wstETH;
    /// @dev Lido withdrawal queue the slow async-exit leg routes through.
    address _withdrawalQueue;
    /// @dev The Lattice vault funds are returned to on withdraw/emergency.
    address _vault;
    /// @dev Reward recipient for stray-token sweeps (Lido has no claimable reward token).
    address _rewardRecipient;
    /// @dev Total stETH currently locked across all pending (unclaimed) withdrawal requests. Counted
    ///      in NAV so funds in-flight through the queue are not lost from accounting.
    uint256 _pendingAssets;
    /// @dev Set of pending Lido withdrawal-request ids (added on request, removed on claim).
    EnumerableSet.UintSet _pendingRequests;
    /// @dev Per-request stETH amount, used to decrement `_pendingAssets` on claim.
    mapping(uint256 => uint256) _requestAssets;
    /// @dev Authorized operator: the SOLE caller permitted to invoke `deploy`/`withdraw`/`harvest`
    ///      (the StrategyManager in the live system). Zero until wired ⇒ that trio reverts.
    ///      APPENDED last (append-only ERC-7201 rule — never reorder/insert).
    address _operator;
}

/// @title LidoAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Lido (https://github.com/lidofinance/core)
/// @notice Logic for a Lido staking strategy under the **buffer model**. The asset is WETH; on
///         `deploy` idle WETH is unwrapped to ETH, staked via `Lido.submit`, and the resulting stETH
///         wrapped into wstETH (held). The synchronous `IStrategy.withdraw` is served **only** from
///         the idle WETH buffer and is shortfall-honest. The slow Lido-queue exit runs out-of-band
///         via `requestWithdrawal` (wstETH → stETH → enqueue) and `claimWithdrawal` (finalized
///         request → ETH → re-wrap into the buffer). Reentrancy-gated, pause/emergency-aware.
/// @dev **De-peg risk (documented, not corrected):** `totalAssetsManaged` values stETH 1:1 with
///      ETH/WETH via Lido's `getStETHByWstETH`. A stETH/ETH secondary-market de-peg is not
///      oracle-corrected here; a future oracle hook (haircut on de-peg) is a follow-up.
/// @dev **Async limitation:** because Lido withdrawals are a queue, the adapter cannot instantly
///      fully exit — `emergencyWithdraw` drains the buffer now and enqueues the rest, which completes
///      only once the request finalizes and `claimWithdrawal` is run.
library LidoAdapterLib {
    using EnumerableSet for EnumerableSet.UintSet;

    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function lidoAdapterStorage() internal pure returns (LidoAdapterStorage storage $) {
        assembly {
            $.slot := LIDO_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function __LidoAdapter_init(
        address weth_,
        address lido_,
        address wstETH_,
        address withdrawalQueue_,
        address vault_,
        address recipient_
    ) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (
            weth_ == address(0) || lido_ == address(0) || wstETH_ == address(0) || withdrawalQueue_ == address(0)
                || vault_ == address(0) || recipient_ == address(0)
        ) {
            revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        }

        LidoAdapterStorage storage $ = lidoAdapterStorage();
        $._weth = weth_;
        $._lido = lido_;
        $._wstETH = wstETH_;
        $._withdrawalQueue = withdrawalQueue_;
        $._vault = vault_;
        $._rewardRecipient = recipient_;

        registerInterface();
        emit ILidoAdapter.LidoAdapterConfigured(weth_, lido_, wstETH_, vault_);
        emit IProtocolAdapter.RewardRecipientSet(recipient_);
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPROTOCOLADAPTER_SLOT, true)
            sstore(ERC165_MAP_ILIDOADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    function asset() internal view returns (address) {
        return lidoAdapterStorage()._weth;
    }

    function weth() internal view returns (address) {
        return lidoAdapterStorage()._weth;
    }

    function lido() internal view returns (address) {
        return lidoAdapterStorage()._lido;
    }

    function wstETH() internal view returns (address) {
        return lidoAdapterStorage()._wstETH;
    }

    function withdrawalQueue() internal view returns (address) {
        return lidoAdapterStorage()._withdrawalQueue;
    }

    function vault() internal view returns (address) {
        return lidoAdapterStorage()._vault;
    }

    function rewardRecipient() internal view returns (address) {
        return lidoAdapterStorage()._rewardRecipient;
    }

    function operator() internal view returns (address) {
        return lidoAdapterStorage()._operator;
    }

    /// @dev Reverts `ProtocolAdapterUnauthorized` unless the caller is the wired operator. Placed at
    ///      the very top of `deploy`/`withdraw`/`harvest` — BEFORE the reentrancy guard — so an
    ///      unauthorized call never leaves the guard latched. Zero operator ⇒ always reverts.
    /// @dev Returns the per-diamond {WETHUnwrapper}, CREATE2-deploying it on first use. The address
    ///      is derived from `address(this)` (the diamond, under delegatecall) + the fixed salt, so
    ///      every diamond lazily gets exactly one unwrapper and re-derivation is a pure computation.
    function _wethUnwrapper() private returns (address unwrapper_) {
        bytes memory code = type(WETHUnwrapper).creationCode;
        unwrapper_ = address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), _WETH_UNWRAPPER_SALT, keccak256(code))))
            )
        );
        if (unwrapper_.code.length == 0) {
            bytes32 salt = _WETH_UNWRAPPER_SALT;
            address deployed_;
            assembly ("memory-safe") {
                deployed_ := create2(0, add(code, 0x20), mload(code), salt)
            }
            if (deployed_ != unwrapper_) revert ILidoAdapter.LidoAdapterUnwrapperDeployFailed();
        }
    }

    function _checkOperator() private view {
        if (msg.sender != lidoAdapterStorage()._operator) {
            revert IProtocolAdapter.ProtocolAdapterUnauthorized(msg.sender);
        }
    }

    function bufferBalance() internal view returns (uint256) {
        return AdapterBaseLib.balanceOfSelf(lidoAdapterStorage()._weth);
    }

    function stakedWstETH() internal view returns (uint256) {
        return AdapterBaseLib.balanceOfSelf(lidoAdapterStorage()._wstETH);
    }

    function pendingWithdrawalAssets() internal view returns (uint256) {
        return lidoAdapterStorage()._pendingAssets;
    }

    function pendingRequestCount() internal view returns (uint256) {
        return lidoAdapterStorage()._pendingRequests.length();
    }

    function pendingRequestAt(uint256 index) internal view returns (uint256) {
        return lidoAdapterStorage()._pendingRequests.at(index);
    }

    function minHealthFactor() internal pure returns (uint256) {
        return type(uint256).max; // staking-only, no debt
    }

    function healthFactor() internal pure returns (uint256) {
        return type(uint256).max; // no debt
    }

    function isPaused() internal view returns (bool) {
        return PausableLib.paused() || EmergencyStopLib.isStopped();
    }

    /// @notice NAV in WETH/ETH units = idle WETH buffer + wstETH valued in stETH + pending in-queue stETH.
    /// @dev stETH is valued 1:1 with ETH/WETH using Lido's PROTOCOL-REDEMPTION rate (`getStETHByWstETH`),
    ///      a monotone, protocol-controlled exchange rate — NOT a secondary-market price. The pending term
    ///      keeps funds-in-flight through the async withdrawal queue from disappearing from accounting
    ///      between `requestWithdrawal` and `claimWithdrawal`.
    ///
    ///      KNOWN LIMITATION — stETH/ETH de-peg (not corrected here; this NAV is intentionally
    ///      market-price-blind). During a stress event stETH can trade at a discount to ETH while this
    ///      function still values the staked + queued legs at par. Consequence: a holder who redeems
    ///      against the synchronous WETH buffer is paid at the (inflated) par NAV, while the staked leg
    ///      must exit slowly through the Lido queue at the eventual realized (discounted) value — the
    ///      difference is socialized onto the remaining shareholders. This is a valuation-vs-realizable
    ///      mismatch, not an on-chain-manipulable bug (the redemption rate is monotone and not attacker-
    ///      controlled). MITIGATION until corrected: bound exposure by capping this strategy's vault
    ///      allocation target and the WETH buffer so the par-priced synchronous-exit surface stays small.
    ///      FUTURE FIX: apply a haircut to `stakedValue + _pendingAssets` from a Chainlink stETH/ETH feed
    ///      (via the existing `ChainlinkAdapter`) whenever stETH is below peg.
    function totalAssetsManaged() internal view returns (uint256) {
        LidoAdapterStorage storage $ = lidoAdapterStorage();
        uint256 buffer = AdapterBaseLib.balanceOfSelf($._weth);
        uint256 stakedValue;
        uint256 wst = AdapterBaseLib.balanceOfSelf($._wstETH);
        if (wst > 0) stakedValue = IWstETH($._wstETH).getStETHByWstETH(wst);
        return buffer + stakedValue + $._pendingAssets;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CONFIG
    //////////////////////////////////////////////////////////////////////////*//

    function setRewardRecipient(address recipient) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (recipient == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        lidoAdapterStorage()._rewardRecipient = recipient;
        emit IProtocolAdapter.RewardRecipientSet(recipient);
    }

    /// @notice Sets the authorized operator for `deploy`/`withdraw`/`harvest` (admin-only). Rejects
    ///         `address(0)` so the trio cannot be opened to an unauthenticated default.
    function setOperator(address operator_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (operator_ == address(0)) revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        lidoAdapterStorage()._operator = operator_;
        emit IProtocolAdapter.OperatorSet(operator_);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               STAKING LEG
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sweeps the idle WETH buffer into Lido: WETH → ETH → stETH (`submit`) → wstETH (`wrap`).
    /// @dev Reverts paused/stopped and on a zero idle balance. Reentrancy-gated. Canonical WETH9 pays
    ///      `withdraw` via `msg.sender.transfer` (2,300-gas stipend) — too little for the diamond's
    ///      zero-selector routing to the {Receive} facet — so the unwrap goes through a per-diamond
    ///      CREATE2 {WETHUnwrapper}, which absorbs the stipend send and returns the ETH with full gas
    ///      (the {Receive} facet accepts it; no guarded state runs, so it is safe inside the
    ///      `nonReentrant` window).
    function deploy() internal returns (uint256 deployed) {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        if (isPaused()) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterPaused();
        }
        LidoAdapterStorage storage $ = lidoAdapterStorage();
        address weth_ = $._weth;
        uint256 idle = AdapterBaseLib.balanceOfSelf(weth_);
        if (idle == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterNothingToDeploy();
        }

        // WETH -> native ETH, relayed through the stipend-safe unwrapper (see @dev above).
        address unwrapper_ = _wethUnwrapper();
        if (!IWETH9(weth_).transfer(unwrapper_, idle)) revert ILidoAdapter.LidoAdapterWethTransferFailed();
        WETHUnwrapper(payable(unwrapper_)).unwrap(IWETH9(weth_));
        // ETH -> stETH (1:1 at submit). Measure the real stETH minted (rebasing-safe).
        address lido_ = $._lido;
        uint256 stBefore = AdapterBaseLib.balanceOfSelf(lido_);
        ILido(lido_).submit{value: idle}(address(0));
        uint256 stReceived = AdapterBaseLib.balanceOfSelf(lido_) - stBefore;
        if (stReceived == 0) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert ILidoAdapter.LidoAdapterNothingStaked();
        }

        // stETH -> wstETH (held). Approve stETH to the wstETH wrapper, then wrap.
        address wst_ = $._wstETH;
        AdapterBaseLib.forceApprove(lido_, wst_, stReceived);
        IWstETH(wst_).wrap(stReceived);

        deployed = idle;
        emit IProtocolAdapter.Deployed(weth_, idle);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Synchronous `IStrategy.withdraw` — served **only** from the idle WETH buffer.
    /// @dev **Shortfall-honest by design.** `actual = min(amount, bufferBalance)`; when the buffer is
    ///      short it transfers what it has and reports that — the staked leg must be liberated
    ///      out-of-band via `requestWithdrawal`/`claimWithdrawal`, and the StrategyManager's
    ///      shortfall check turns the under-delivery into a recorded shortfall upstream. The staked
    ///      wstETH position is intentionally never touched here.
    function withdraw(uint256 amount, address to) internal returns (uint256 withdrawn) {
        _checkOperator();
        ReentrancyGuardLib.nonReentrantBefore();
        LidoAdapterStorage storage $ = lidoAdapterStorage();
        // Recipient pin: a recall may ONLY land in the adapter's own vault. The legit caller (the
        // StrategyManager) already passes the vault; this makes redirecting the buffer impossible.
        if (to != $._vault) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterInvalidRecipient(to);
        }
        // transferHonest already caps at the adapter's WETH balance (== the buffer) and reports the
        // real amount sent, so a buffer shortfall returns less without reverting.
        withdrawn = AdapterBaseLib.transferHonest($._weth, to, amount);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            ASYNC QUEUE LEG
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Unwraps `wstAmount` wstETH to stETH and enqueues it in the Lido withdrawal queue
    ///         (admin/keeper). Records the request id + stETH amount as pending so NAV is unchanged
    ///         by the move (staked value falls, pending rises by the same stETH amount).
    function requestWithdrawal(uint256 wstAmount) internal returns (uint256 requestId) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ReentrancyGuardLib.nonReentrantBefore();
        LidoAdapterStorage storage $ = lidoAdapterStorage();
        uint256 held = AdapterBaseLib.balanceOfSelf($._wstETH);
        if (wstAmount > held) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert ILidoAdapter.LidoAdapterInsufficientWstETH(wstAmount, held);
        }
        requestId = _enqueue($, wstAmount);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Claims a finalized withdrawal request (permissionless/keeper): pulls the owed ETH from
    ///         the queue (a full-gas payout that lands via the diamond's {Receive} facet), wraps it
    ///         1:1 into the WETH buffer, and clears
    ///         the request from pending.
    function claimWithdrawal(uint256 requestId) internal returns (uint256 ethReceived) {
        ReentrancyGuardLib.nonReentrantBefore();
        LidoAdapterStorage storage $ = lidoAdapterStorage();
        if (!$._pendingRequests.contains(requestId)) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert ILidoAdapter.LidoAdapterUnknownRequest(requestId);
        }

        // Measure ETH delta the claim pays in (the queue sends native ETH to this facet's receive()).
        uint256 ethBefore = address(this).balance;
        ILidoWithdrawalQueue($._withdrawalQueue).claimWithdrawal(requestId);
        ethReceived = address(this).balance - ethBefore;

        // Clear pending bookkeeping (decrement by the recorded stETH amount).
        uint256 recorded = $._requestAssets[requestId];
        $._pendingAssets -= recorded;
        $._pendingRequests.remove(requestId);
        delete $._requestAssets[requestId];

        // ETH -> WETH buffer.
        if (ethReceived > 0) IWETH9($._weth).deposit{value: ethReceived}();

        emit ILidoAdapter.WithdrawalClaimed(requestId, ethReceived);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              HARVEST / SWEEP
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice No-op: Lido yield accrues in the wstETH→stETH exchange rate (reflected in NAV), NOT a
    ///         claimable reward token, so there is nothing to claim or forward on the standard
    ///         `IProtocolAdapter.harvest()` path. Kept as a graceful no-op (for an authorized
    ///         operator) so a keeper sweep never reverts. Use `harvestToken` to forward a specific
    ///         stray (airdropped) token. Operator-gated for parity with the other adapters' trio.
    function harvest() internal view {
        _checkOperator();
    }

    /// @notice Forwards the adapter's entire balance of a stray `token` raw to the reward recipient
    ///         (admin/keeper). The three core tokens (WETH buffer, stETH hop, wstETH stake) are
    ///         rejected so a sweep can never drain the position or the buffer.
    function harvestToken(address token) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ReentrancyGuardLib.nonReentrantBefore();
        LidoAdapterStorage storage $ = lidoAdapterStorage();
        if (token == $._weth || token == $._lido || token == $._wstETH) {
            ReentrancyGuardLib.nonReentrantAfter();
            revert IProtocolAdapter.ProtocolAdapterZeroAddress();
        }
        uint256 forwarded = AdapterBaseLib.forwardRewardRaw(token, $._rewardRecipient);
        if (forwarded > 0) emit IProtocolAdapter.RewardsForwarded(token, $._rewardRecipient, forwarded);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            EMERGENCY WITHDRAW
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Emergency exit (admin, runs even when stopped): sends the entire WETH buffer to the
    ///         vault now AND enqueues the full wstETH stake in the Lido withdrawal queue.
    /// @dev **Async limitation:** the queue leg cannot complete synchronously — the staked ETH
    ///      returns only once the request finalizes and `claimWithdrawal` is run, after which a
    ///      final `withdraw` sweeps it to the vault. `recovered` is therefore only the buffer paid
    ///      out immediately; the enqueued stake remains in NAV as `pendingWithdrawalAssets`.
    function emergencyWithdraw() internal returns (uint256 recovered) {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ReentrancyGuardLib.nonReentrantBefore();
        LidoAdapterStorage storage $ = lidoAdapterStorage();

        // Enqueue the full wstETH stake (the slow leg completes later via claimWithdrawal).
        uint256 wst = AdapterBaseLib.balanceOfSelf($._wstETH);
        if (wst > 0) _enqueue($, wst);

        // Send the entire WETH buffer to the vault immediately.
        recovered = AdapterBaseLib.transferHonest($._weth, $._vault, AdapterBaseLib.balanceOfSelf($._weth));
        emit IProtocolAdapter.EmergencyWithdrawn($._weth, $._vault, recovered);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Unwraps `wstAmount` wstETH to stETH, approves the queue, requests a single-entry
    ///      withdrawal owned by this adapter, and records the request id + stETH amount as pending.
    ///      Caller is responsible for the reentrancy guard and any balance pre-checks.
    function _enqueue(LidoAdapterStorage storage $, uint256 wstAmount) private returns (uint256 requestId) {
        address lido_ = $._lido;
        address queue_ = $._withdrawalQueue;

        // wstETH -> stETH. Measure the real stETH out.
        uint256 stBefore = AdapterBaseLib.balanceOfSelf(lido_);
        IWstETH($._wstETH).unwrap(wstAmount);
        uint256 stAmount = AdapterBaseLib.balanceOfSelf(lido_) - stBefore;

        // Approve stETH to the queue and request a single withdrawal owned by this adapter.
        AdapterBaseLib.forceApprove(lido_, queue_, stAmount);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = stAmount;
        uint256[] memory ids = ILidoWithdrawalQueue(queue_).requestWithdrawals(amounts, address(this));
        requestId = ids[0];

        // Record as pending so NAV accounts for the in-flight stETH.
        $._pendingRequests.add(requestId);
        $._requestAssets[requestId] = stAmount;
        $._pendingAssets += stAmount;

        emit ILidoAdapter.WithdrawalRequested(requestId, stAmount);
    }
}
