// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {
    ERC7579ModuleConfigLib,
    FALLBACK_CALLTYPE_DELEGATECALL
} from "@lattice/accounts/erc7579/libraries/ERC7579ModuleConfigLib.sol";
import {IModuleConfig} from "@lattice/interfaces/accounts/IModuleConfig.sol";

/// @title AccountDiamond
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-7579 reference implementation (https://github.com/erc7579/erc7579-implementation)
/// @notice An EIP-2535 Diamond whose fallback adds ERC-7579 FALLBACK (type 3) handler dispatch LAYERED UNDER the
///         facet map (#58 follow-on): a selector the diamond owns is dispatched to its facet exactly as before,
///         and only an otherwise-unhandled selector falls through to an installed fallback handler. `diamondCut`
///         thus remains the sole selector authority; 7579 fallbacks extend the account's reach without shadowing
///         facets (install reverts {FallbackShadowsFacet} for an owned selector). A selector neither a facet nor
///         a handler claims reverts {NoFallbackHandler} (vs. the base Diamond's silent empty return).
/// @dev Forwards to the handler via CALL — with the original caller appended ERC-2771-style — or DELEGATECALL,
///      per the handler's registered call type. This is the proxy the `AccountFactory` deploys and that
///      `Account7702Diamond` extends, so factory- and 7702-onboarded accounts both get fallback support.
contract AccountDiamond is Lattice {
    fallback() external payable virtual override {
        // Non-reverting overload: returns address(0) on a miss so we can fall through to the registry (the
        // single-arg `selectorToFacet` reverts {FunctionDoesNotExist}, which is the base Diamond's fallback path).
        address facet = DiamondLib.selectorToFacet(DiamondLib.diamondStorage(), msg.sig);
        if (facet != address(0)) {
            // Facet wins (diamondCut authority): the standard diamond delegatecall.
            assembly {
                calldatacopy(0, 0, calldatasize())
                let ok := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
                returndatacopy(0, 0, returndatasize())
                switch ok
                case 0 { revert(0, returndatasize()) }
                default { return(0, returndatasize()) }
            }
        }

        // Selector miss → ERC-7579 fallback registry.
        (address handler, bytes1 callType) = ERC7579ModuleConfigLib.fallbackHandlerFor(msg.sig);
        if (handler == address(0)) revert IModuleConfig.NoFallbackHandler(msg.sig);

        if (callType == FALLBACK_CALLTYPE_DELEGATECALL) {
            assembly {
                calldatacopy(0, 0, calldatasize())
                let ok := delegatecall(gas(), handler, 0, calldatasize(), 0, 0)
                returndatacopy(0, 0, returndatasize())
                switch ok
                case 0 { revert(0, returndatasize()) }
                default { return(0, returndatasize()) }
            }
        }

        // CALL: forward with the original caller appended (ERC-2771), so the handler can recover `msg.sender`.
        // `callvalue()` (only the ETH sent WITH this call, never the account's standing balance) is forwarded to
        // the handler — deliberate, unlike the ERC-7579 reference's hardcoded value 0; do not "fix" it to 0.
        assembly {
            calldatacopy(0, 0, calldatasize())
            mstore(calldatasize(), shl(96, caller()))
            let ok := call(gas(), handler, callvalue(), 0, add(calldatasize(), 20), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch ok
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
