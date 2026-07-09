// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";

/// @title ComposabilityInvariant
/// @notice Guards the EIP-2535 composability of the ERC-20 facet family: a diamond maps each selector to one
///         facet, so an extension may only expose its OWN selectors plus an allow-listed set it `Replace`s on the
///         base. If an extension is ever changed to `is ERC20` (or otherwise re-exports a base selector), its
///         `forge inspect` method set balloons and this test fails naming the facet — long before anyone tries to
///         cut two of them together. Fast static check; the real-diamond proof lives in {ERC20DiamondComposition}.
/// @dev SCOPE: this checks re-export of ERC-20 BASE selectors only. Utility / cross-family collisions (a facet
///      re-exporting `eip712Domain()`/`nonces()`/`hasRole()`) are out of scope here — that is the follow-up A2
///      pairwise-disjointness guard. A completeness assertion forces every ERC-20 facet file to be registered
///      below, so a NEW facet written `is ERC20` that nobody lists here fails the build rather than slipping past.
contract ComposabilityInvariant is GetSelectors {
    function test_Erc20ExtensionsNeverReExportBaseSelectors() public {
        bytes4[] memory base = _strip8153(_getSelectors("ERC20"));
        assertGt(base.length, 0, "base ERC20 selectors empty -> forge inspect name mismatch");

        uint256 checked;
        // Purely additive extensions: zero overlap with the base.
        checked += _noReExport("ERC20Burnable", base, _none());
        checked += _noReExport("ERC20Capped", base, _none());
        checked += _noReExport("ERC20FlashMint", base, _none());
        checked += _noReExport("ERC20Permit", base, _none());
        checked += _noReExport("ERC20Crosschain", base, _none());
        // Override extensions: may own ONLY the base selectors they Replace.
        checked += _noReExport("ERC20Wrapper", base, _sels("decimals()"));
        checked += _noReExport(
            "ERC20Pausable", base, _sels("transfer(address,uint256)", "transferFrom(address,address,uint256)")
        );
        checked += _noReExport(
            "ERC20Votes", base, _sels("transfer(address,uint256)", "transferFrom(address,address,uint256)")
        );

        // Completeness: every ERC-20 extension facet file (src/tokens/ERC20/*.sol minus the ERC20.sol base and the
        // *Init.sol deploy initializers) must be checked above, so adding a facet without a `_noReExport` line fails
        // the build instead of going unguarded.
        assertEq(
            checked, _erc20ExtensionFacetCount(), "an ERC-20 facet is unregistered here -> add its _noReExport line"
        );
    }

    /// @dev Returns 1 (one facet inspected). Any base selector the facet exposes that is not an allow-listed
    ///      `Replace` fails the test. Also validates the allow-list is live (no dead/typo entries).
    function _noReExport(string memory facet, bytes4[] memory base, bytes4[] memory allowed)
        internal
        returns (uint256)
    {
        bytes4[] memory s = _strip8153(_getSelectors(facet));
        assertGt(s.length, 0, string.concat(facet, " inspected to zero selectors -> forge inspect name mismatch"));
        for (uint256 i; i < allowed.length; ++i) {
            assertTrue(_has(base, allowed[i]), string.concat(facet, ": allow-list entry is not a base selector"));
            assertTrue(
                _has(s, allowed[i]), string.concat(facet, ": allow-list selector not exposed (stale Replace entry)")
            );
        }
        for (uint256 i; i < s.length; ++i) {
            if (_has(base, s[i]) && !_has(allowed, s[i])) {
                assertTrue(
                    false, string.concat(facet, " re-exports a base ERC20 selector -> breaks diamond composability")
                );
            }
        }
        return 1;
    }

    /// @dev FFI-lists the ERC-20 EXTENSION facet files on disk — every `src/tokens/ERC20/*.sol` except the
    ///      `ERC20.sol` base and the `*Init.sol` deploy initializers (not facets) — and counts them. Uses a newline
    ///      list (not `wc -l`) so the result is never a bare 2-digit decimal that `vm.ffi` would hex-decode into a
    ///      control byte (e.g. "14" -> 0x14), which would otherwise break the count as the facet family grows.
    function _erc20ExtensionFacetCount() internal returns (uint256 count) {
        string[] memory cmd = new string[](3);
        cmd[0] = "sh";
        cmd[1] = "-c";
        cmd[2] = "ls src/tokens/ERC20/*.sol | grep -v '/ERC20.sol$' | grep -v 'Init.sol$'";
        string[] memory lines = vm.split(string(vm.ffi(cmd)), "\n");
        for (uint256 i; i < lines.length; ++i) {
            if (bytes(lines[i]).length > 0) ++count;
        }
    }

    function _has(bytes4[] memory arr, bytes4 x) private pure returns (bool) {
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] == x) return true;
        }
        return false;
    }

    /// @dev Drops the ERC-8153 `exportSelectors()` selector (0x0ef22643). EVERY facet exports it, so once the
    ///      ERC-20 base and its extensions implement ERC-8153 it appears in each `forge inspect` set and would
    ///      false-positive as a "re-exported base selector". It is allow-listed here (never cut onto a diamond),
    ///      so both the base set and each extension set are filtered before the re-export comparison.
    function _strip8153(bytes4[] memory arr) private pure returns (bytes4[] memory kept) {
        kept = new bytes4[](arr.length);
        uint256 n;
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i] != bytes4(0x0ef22643)) kept[n++] = arr[i];
        }
        assembly ("memory-safe") {
            mstore(kept, n)
        }
    }

    function _sig(string memory s) private pure returns (bytes4) {
        return bytes4(keccak256(bytes(s)));
    }

    function _none() private pure returns (bytes4[] memory a) {
        a = new bytes4[](0);
    }

    function _sels(string memory a) private pure returns (bytes4[] memory r) {
        r = new bytes4[](1);
        r[0] = _sig(a);
    }

    function _sels(string memory a, string memory b) private pure returns (bytes4[] memory r) {
        r = new bytes4[](2);
        r[0] = _sig(a);
        r[1] = _sig(b);
    }
}
