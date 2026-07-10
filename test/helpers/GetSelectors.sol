// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

/// @title GetSelectors
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from diamond-lib v0.1.4 (https://github.com/dadadave80/diamond-lib)
/// @notice Helper contract for extracting function selectors from facet contracts via `forge inspect` FFI.
/// @dev Vendored VERBATIM from diamond-lib v0.1.4 `test/helpers/GetSelectors.sol`, which v0.2.0 removed in
///      favor of on-chain ERC-8153 `exportSelectors()` reads (`test/helpers/Selectors.sol`). Lattice still
///      needs the FFI path for TEST-ONLY facets that deliberately carry no `exportSelectors()` (production
///      facets self-report and are cut via {BaseDeploy}'s address-based helpers). New tests should prefer
///      ERC-8153 self-reports; reach for this only when inspecting a non-8153 fixture.
abstract contract GetSelectors is Test {
    /// @notice Extracts function selectors from a given facet using `forge inspect` via FFI.
    /// @dev Uses FFI to call `forge inspect <facet> methodIdentifiers` which returns only
    ///      the small methodIdentifiers JSON, avoiding the full artifact dump in traces.
    /// @param _facet The name of the facet contract to inspect.
    /// @return selectors_ An array of function selectors extracted from the facet.
    function _getSelectors(string memory _facet) internal returns (bytes4[] memory selectors_) {
        string[] memory cmd = new string[](5);
        cmd[0] = "forge";
        cmd[1] = "inspect";
        cmd[2] = _facet;
        cmd[3] = "methodIdentifiers";
        cmd[4] = "--json";

        string memory json = string(vm.ffi(cmd));
        string[] memory signatures = vm.parseJsonKeys(json, "");
        uint256 len = signatures.length;
        selectors_ = new bytes4[](len);

        for (uint256 i; i < len; ++i) {
            selectors_[i] = bytes4(keccak256(bytes(signatures[i])));
        }
    }
}
