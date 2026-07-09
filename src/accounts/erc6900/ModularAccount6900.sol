// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {ERC6900ExecutorLib} from "@lattice/accounts/erc6900/libraries/ERC6900ExecutorLib.sol";

/// @title ModularAccount6900
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-6900 reference implementation (https://github.com/erc6900/reference-implementation)
/// @notice An EIP-2535 Diamond whose fallback adds ERC-6900 execution-module dispatch LAYERED UNDER the facet
///         map (#74): a selector the diamond owns is delegatecalled to its facet exactly as before; an otherwise
///         unhandled selector is dispatched to the installed ERC-6900 execution MODULE that owns it — via CALL
///         (the module runs in its OWN storage context, not the account's), wrapped by the account's runtime
///         authorization and pre/post execution hooks. A selector neither a facet nor an installed execution
///         function owns reverts {IERC6900Executor.UnrecognizedFunction}.
/// @dev The two dispatch regimes are disjoint by design: facet selectors → DELEGATECALL (shared Diamond storage,
///      `diamondCut` authority); ERC-6900 execution-module selectors → external CALL to the module (separate
///      storage). This is the 6900 analogue of `AccountDiamond` and the proxy a 6900-flavored account blueprint
///      deploys.
contract ModularAccount6900 is Diamond {
    fallback() external payable virtual override {
        // Facet wins (diamondCut authority): the standard diamond delegatecall. Non-reverting overload — the
        // single-arg `selectorToFacet` reverts {FunctionDoesNotExist} on a miss.
        address facet = DiamondLib.selectorToFacet(DiamondLib.diamondStorage(), msg.sig);
        if (facet != address(0)) {
            assembly {
                calldatacopy(0, 0, calldatasize())
                let ok := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
                returndatacopy(0, 0, returndatasize())
                switch ok
                case 0 { revert(0, returndatasize()) }
                default { return(0, returndatasize()) }
            }
        }

        // Selector miss → ERC-6900 execution-module dispatch (CALL + runtime auth + exec hooks; reverts
        // {UnrecognizedFunction} if no module owns the selector).
        bytes memory ret = ERC6900ExecutorLib.dispatch();
        assembly {
            return(add(ret, 32), mload(ret))
        }
    }
}
