// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IPyth} from "@lattice/interfaces/external/pyth/IPyth.sol";
import {IPythAdapter} from "@lattice/interfaces/oracles/IPythAdapter.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.PythAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant PYTH_ADAPTER_STORAGE_SLOT = 0x4f06923ad9b02e8a3ff8edafe956de2290e9ad8f87494c6f70ad4259b24ff100;

/// @dev 0x3839468c is `type(IPythAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x3839468c), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IPYTHADAPTER_SLOT = 0x8285166a3f9489792233ccce4dfcee0aa88473267c0fab1b647d041fceb112c6;

/// @notice Packed data for a single registered Pyth feed.
/// @dev APPEND-ONLY. A registered feed has `maxStaleness != 0` (the not-registered sentinel).
struct PythFeed {
    /// @notice The Pyth price-feed id.
    bytes32 priceId;
    /// @notice Maximum age in seconds before a price is considered stale.
    uint48 maxStaleness;
    /// @notice Maximum confidence ratio in basis points (`conf/price`); 0 disables the check.
    uint64 maxConfBps;
}

/// @notice ERC-7201 namespaced storage for PythAdapter.
/// @dev APPEND-ONLY: new fields may only be added at the end.
/// @custom:storage-location erc7201:lattice.storage.PythAdapter
struct PythAdapterStorage {
    /// @dev feed key => feed config.
    mapping(bytes32 key => PythFeed) _feeds;
    /// @dev the Pyth contract.
    address _pyth;
}

/// @title PythAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Pyth Network (https://github.com/pyth-network/pyth-crosschain)
/// @notice Library wrapping the pull-based Pyth oracle with per-feed staleness + confidence
///         configuration and WAD normalization, exposing the shared {IPriceOracleReader} read surface.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {PythAdapter} facet forwards to it. Reads use Pyth's `getPriceUnsafe` and validate staleness,
///      future timestamp, sign, and confidence on-chain.
library PythAdapterLib {
    function pythAdapterStorage() internal pure returns (PythAdapterStorage storage $) {
        assembly {
            $.slot := PYTH_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes PythAdapter with the Pyth contract and registers the ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __PythAdapter_init(address pyth_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (pyth_ == address(0)) revert IPythAdapter.PythContractIsZero();
        pythAdapterStorage()._pyth = pyth_;
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IPythAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IPYTHADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function pyth() internal view returns (address) {
        return pythAdapterStorage()._pyth;
    }

    function getFeed(bytes32 key) internal view returns (bytes32 priceId, uint48 maxStaleness, uint64 maxConfBps) {
        PythFeed storage f = pythAdapterStorage()._feeds[key];
        return (f.priceId, f.maxStaleness, f.maxConfBps);
    }

    function getUpdateFee(bytes[] calldata updateData) internal view returns (uint256) {
        return IPyth(_requirePyth()).getUpdateFee(updateData);
    }

    /// @notice Returns the validated raw Pyth price for `key`.
    /// @dev Validates: registration, sign (`price > 0`), future-timestamp, staleness, and confidence.
    function latestAnswerRaw(bytes32 key)
        internal
        view
        returns (int64 price, int32 expo, uint64 conf, uint256 publishTime)
    {
        PythFeed storage f = pythAdapterStorage()._feeds[key];
        if (f.maxStaleness == 0) revert IPythAdapter.PythFeedNotRegistered(key);

        IPyth.Price memory p = IPyth(_requirePyth()).getPriceUnsafe(f.priceId);
        price = p.price;
        expo = p.expo;
        conf = p.conf;
        publishTime = p.publishTime;

        if (price <= 0) revert IPythAdapter.PythInvalidAnswer(key, price);
        // Future-timestamp guard (avoids an underflow panic and rejects impossible data).
        if (publishTime > block.timestamp) revert IPythAdapter.PythFuturePrice(key, publishTime);
        if (block.timestamp - publishTime > f.maxStaleness) {
            revert IPythAdapter.PythStaleData(key, publishTime, f.maxStaleness);
        }
        // Confidence: reject if conf/price exceeds maxConfBps (0 disables). price > 0 here.
        if (f.maxConfBps != 0 && uint256(conf) * 10_000 > uint256(uint64(price)) * f.maxConfBps) {
            revert IPythAdapter.PythConfidenceTooWide(key, conf, price, f.maxConfBps);
        }
    }

    /// @notice Returns the latest price normalized to 18 decimals (WAD): `price * 10^(18 + expo)`.
    function latestAnswer(bytes32 key) internal view returns (int256 answerWad) {
        (int64 price, int32 expo,,) = latestAnswerRaw(key);

        int256 e = int256(18) + int256(expo);
        if (e >= 0) {
            if (e > 36) revert IPythAdapter.PythExpoOutOfRange(expo);
            answerWad = int256(price) * int256(10 ** uint256(e));
        } else {
            if (e < -36) revert IPythAdapter.PythExpoOutOfRange(expo);
            // ponytail: integer division truncates toward zero; unreachable for real feeds (expo ~ -8).
            answerWad = int256(price) / int256(10 ** uint256(-e));
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  UPDATES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Refreshes Pyth prices from `updateData`; caller-funded with excess refunded.
    /// @dev Permissionless. Effects are external (in the Pyth contract); the refund is the final step.
    function updatePriceFeeds(bytes[] calldata updateData) internal {
        address p = _requirePyth();
        uint256 fee = IPyth(p).getUpdateFee(updateData);
        if (msg.value < fee) revert IPythAdapter.PythInsufficientFee(msg.value, fee);

        IPyth(p).updatePriceFeeds{value: fee}(updateData);

        uint256 refund = msg.value - fee;
        if (refund != 0) {
            (bool ok,) = msg.sender.call{value: refund}("");
            if (!ok) revert IPythAdapter.PythRefundFailed();
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function setPyth(address pyth_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (pyth_ == address(0)) revert IPythAdapter.PythContractIsZero();
        pythAdapterStorage()._pyth = pyth_;
        emit IPythAdapter.PythContractSet(pyth_);
    }

    function registerFeed(bytes32 key, bytes32 priceId, uint48 maxStaleness, uint64 maxConfBps) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (priceId == bytes32(0) || maxStaleness == 0) revert IPythAdapter.PythInvalidConfig();
        pythAdapterStorage()._feeds[key] =
            PythFeed({priceId: priceId, maxStaleness: maxStaleness, maxConfBps: maxConfBps});
        emit IPythAdapter.FeedRegistered(key, priceId, maxStaleness, maxConfBps);
    }

    function unregisterFeed(bytes32 key) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        delete pythAdapterStorage()._feeds[key];
        emit IPythAdapter.FeedUnregistered(key);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    function _requirePyth() private view returns (address p) {
        p = pythAdapterStorage()._pyth;
        if (p == address(0)) revert IPythAdapter.PythContractNotSet();
    }
}
