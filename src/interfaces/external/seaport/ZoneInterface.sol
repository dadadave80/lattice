// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Schema, ZoneParameters} from "@lattice/interfaces/external/seaport/SeaportStructs.sol";

/// @title ZoneInterface (Seaport 1.6) — vendored subset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of Seaport 1.6's `ZoneInterface` (https://github.com/ProjectOpenSea/seaport). Upstream is MIT.
/// @notice The three Seaport 1.6 zone hooks a restricted-order zone must implement. A zone returns its own
///         function selector as the magic value to authorize/validate; any other value (or a revert) makes
///         Seaport reject the order with `InvalidRestrictedOrder`.
/// @dev Verified verbatim against `ProjectOpenSea/seaport-types` @ `b724932` (tag v1.6.3):
///      `src/interfaces/ZoneInterface.sol`. The upstream interface also `is IERC165` and re-declares
///      `supportsInterface` — intentionally OMITTED here so a Diamond facet implementing this does NOT claim
///      the `0x01ffc9a7` selector (owned by the Diamond's shared ERC-165 facet). `type(ZoneInterface).interfaceId`
///      for these three hooks is `0x3822a094` (= authorizeOrder ^ validateOrder ^ getSeaportMetadata).
///      `authorizeOrder` is the PRE-fulfillment hook (new in 1.6); `validateOrder` is POST-fulfillment. Both
///      are non-view and run with `msg.sender == Seaport`.
/// @custom:lattice-source Seaport
interface ZoneInterface {
    /// @notice Called before any transfers. Return `authorizeOrder.selector` (`0x01e4d72a`) to authorize.
    function authorizeOrder(ZoneParameters calldata zoneParameters) external returns (bytes4 authorizedOrderMagicValue);

    /// @notice Called after all transfers. Return `validateOrder.selector` (`0x17b1f942`) to validate.
    function validateOrder(ZoneParameters calldata zoneParameters) external returns (bytes4 validOrderMagicValue);

    /// @notice SIP introspection: the zone's name + supported schemas.
    function getSeaportMetadata() external view returns (string memory name, Schema[] memory schemas);
}
