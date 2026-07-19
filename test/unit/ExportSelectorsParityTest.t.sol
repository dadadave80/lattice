// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {Test} from "forge-std/Test.sol";

/// @title ExportSelectorsParityTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice THE ERC-8153 parity gate: every Lattice facet's runtime {IERC8153-exportSelectors} must exactly equal
///         the selector set `forge inspect` derives from its compiled ABI (minus `exportSelectors()` itself). This
///         is what lets {BaseDeploy} build `FacetCut`s from a facet's self-report instead of FFI: if the two ever
///         diverge (a selector added to the ABI but not the export, or vice-versa) a diamond would be cut with the
///         wrong function set. For each facet: deploy it, read `exportSelectors()`, decode the tightly packed
///         bytes, and assert SET equality (order-insensitive) with `forge inspect`, no duplicates, no
///         `exportSelectors()` (0x0ef22643) in the export, and a non-empty result — every failure names the facet.
/// @dev The `test_AllFacetsExportSelectorsParity` gate FAILS until every facet implements ERC-8153 (facets are
///      migrated in parallel). The `test_Harness_*` cases prove the harness itself is correct TODAY against local
///      mock fixtures: a compliant facet passes every check; a facet that (wrongly) exports 0x0ef22643, one with a
///      duplicate selector, and one with a malformed (non-4-multiple) length are each caught.
contract ExportSelectorsParityTest is Test {
    /// @dev `IERC8153.exportSelectors()` — must never appear inside any facet's own export.
    bytes4 private constant SEL_EXPORT = 0x0ef22643;

    //*//////////////////////////////////////////////////////////////////////////
    //                          THE PARITY GATE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Every inventory facet's `exportSelectors()` equals its `forge inspect` method set.
    function test_AllFacetsExportSelectorsParity() public {
        (string[] memory names, string[] memory paths) = _inventory();
        for (uint256 i; i < names.length; ++i) {
            _assertFacetParity(names[i], paths[i]);
        }
    }

    /// @notice Every deployable inventory facet's runtime code is under the EIP-170 24,576-byte limit, so it can
    ///         actually be deployed and cut. `forge build --sizes` cannot gate this (it exits non-zero on
    ///         test-only mocks), so this is the CI guard: the ERC-8153 export additions shrank the tightest
    ///         facet's headroom, and this fails LOUDLY on the next facet that tips over instead of only
    ///         surfacing as an opaque facet-creation revert somewhere in the suite.
    function test_AllFacetsUnderEip170Limit() public {
        (string[] memory names, string[] memory paths) = _inventory();
        for (uint256 i; i < names.length; ++i) {
            uint256 size = deployCode(paths[i]).code.length;
            assertLe(
                size, 24_576, string.concat(names[i], ": runtime code exceeds EIP-170 (", vm.toString(size), " B)")
            );
        }
    }

    /// @dev Deploys `path` (`"<file>:<Name>"`), reads + decodes its export, and asserts full parity. Each failure
    ///      message begins with `name`. Uses guarded early-returns so one broken facet still names itself cleanly
    ///      instead of aborting the whole sweep with a raw revert.
    function _assertFacetParity(string memory name, string memory path) internal {
        address facet = deployCode(path);

        (bool ok, bytes memory ret) = facet.staticcall(abi.encodeWithSelector(SEL_EXPORT));
        assertTrue(ok, string.concat(name, ": exportSelectors() reverted (ERC-8153 not implemented yet?)"));
        if (!ok) return;
        assertGe(ret.length, 64, string.concat(name, ": exportSelectors() did not return a bytes blob"));
        if (ret.length < 64) return;

        bytes memory packed = abi.decode(ret, (bytes));
        assertTrue(packed.length != 0, string.concat(name, ": exportSelectors() returned no selectors"));
        assertTrue(packed.length % 4 == 0, string.concat(name, ": exportSelectors() length not a multiple of 4"));
        if (packed.length == 0 || packed.length % 4 != 0) return;

        bytes4[] memory got = _decodePacked(packed);
        assertFalse(_hasDuplicate(got), string.concat(name, ": export contains a duplicate selector"));
        assertFalse(
            _containsSel(got, SEL_EXPORT),
            string.concat(name, ": export must not include exportSelectors() (0x0ef22643)")
        );

        // Inspect by NAME, not path: inventory names are unique artifacts (pinned by the release
        // consistency test), and the diamond-lib core entries use bare-basename identifiers that
        // `forge inspect` cannot resolve as source paths.
        bytes4[] memory expected = _stripSelf(_ffiMethodSelectors(name));
        assertTrue(_setEq(got, expected), string.concat(name, ": exportSelectors() != forge inspect method set"));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        HARNESS SELF-TESTS (mocks)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A compliant facet passes every parity check (decode, non-empty, %4, no dup, no self, set equality).
    function test_Harness_AcceptsCompliantFacet() public {
        address mock = address(new ParityCompliantMock());
        bytes4[] memory got = _decodeChecked(mock);

        assertEq(got.length, 3, "compliant mock: expected 3 selectors");
        assertFalse(_hasDuplicate(got), "compliant mock: unexpected duplicate");
        assertFalse(_containsSel(got, SEL_EXPORT), "compliant mock: unexpectedly exports itself");

        bytes4[] memory expected = new bytes4[](3);
        expected[0] = bytes4(keccak256("alpha()"));
        expected[1] = bytes4(keccak256("beta(uint256)"));
        expected[2] = bytes4(keccak256("gamma(address,bytes32)"));
        assertTrue(_setEq(got, expected), "compliant mock: export set != ABI set");
    }

    /// @notice The self-selector guard fires when a facet (wrongly) includes 0x0ef22643 in its export.
    function test_Harness_RejectsSelfSelector() public {
        address mock = address(new ParityIncludesSelfMock());
        bytes4[] memory got = _decodeChecked(mock);
        // The gate asserts `assertFalse(_containsSel(got, SEL_EXPORT))`; here that condition is true => it fails.
        assertTrue(_containsSel(got, SEL_EXPORT), "self-selector mock: guard failed to detect 0x0ef22643");
    }

    /// @notice The duplicate guard fires when a facet exports the same selector twice.
    function test_Harness_RejectsDuplicates() public {
        address mock = address(new ParityDuplicateMock());
        bytes4[] memory got = _decodeChecked(mock);
        // The gate asserts `assertFalse(_hasDuplicate(got))`; here that condition is true => it fails.
        assertTrue(_hasDuplicate(got), "duplicate mock: guard failed to detect duplicate selector");
    }

    /// @notice The length guard reverts when a facet's export is not a whole number of 4-byte selectors.
    function test_Harness_RejectsMalformedLength() public {
        address mock = address(new ParityMalformedLengthMock());
        vm.expectRevert(bytes("parity: exportSelectors() length not a multiple of 4"));
        this.decodeCheckedExternal(mock);
    }

    /// @notice The empty guard reverts when a facet exports nothing.
    function test_Harness_RejectsEmpty() public {
        address mock = address(new ParityEmptyMock());
        vm.expectRevert(bytes("parity: exportSelectors() returned no selectors"));
        this.decodeCheckedExternal(mock);
    }

    /// @dev External wrapper so `vm.expectRevert` can catch reverts thrown by the validating decoder.
    function decodeCheckedExternal(address facet) external view returns (bytes4[] memory) {
        return _decodeChecked(facet);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        DECODE / VALIDATION HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Staticcalls, validates (success, non-empty, %4), and decodes a facet's packed `exportSelectors()`.
    ///      Mirrors {BaseDeploy-_exportedSelectors}: the deploy path and this gate share one decode contract.
    function _decodeChecked(address facet) internal view returns (bytes4[] memory) {
        (bool ok, bytes memory ret) = facet.staticcall(abi.encodeWithSelector(SEL_EXPORT));
        require(ok, "parity: exportSelectors() staticcall reverted");
        bytes memory packed = abi.decode(ret, (bytes));
        require(packed.length != 0, "parity: exportSelectors() returned no selectors");
        require(packed.length % 4 == 0, "parity: exportSelectors() length not a multiple of 4");
        return _decodePacked(packed);
    }

    /// @dev Splits tightly packed 4-byte selector bytes into a `bytes4[]` (assumes `packed.length % 4 == 0`).
    function _decodePacked(bytes memory packed) private pure returns (bytes4[] memory selectors) {
        uint256 count = packed.length / 4;
        selectors = new bytes4[](count);
        for (uint256 i; i < count; ++i) {
            bytes4 sel;
            assembly ("memory-safe") {
                sel := mload(add(add(packed, 0x20), mul(i, 4)))
            }
            selectors[i] = sel;
        }
    }

    /// @dev FFI `forge inspect <what> methodIdentifiers --json` -> the selector set of every ABI method.
    function _ffiMethodSelectors(string memory what) private returns (bytes4[] memory selectors) {
        string[] memory cmd = new string[](5);
        cmd[0] = "forge";
        cmd[1] = "inspect";
        cmd[2] = what;
        cmd[3] = "methodIdentifiers";
        cmd[4] = "--json";
        string memory json = string(vm.ffi(cmd));
        string[] memory sigs = vm.parseJsonKeys(json, "");
        selectors = new bytes4[](sigs.length);
        for (uint256 i; i < sigs.length; ++i) {
            selectors[i] = bytes4(keccak256(bytes(sigs[i])));
        }
    }

    /// @dev `sels` without `exportSelectors()` (0x0ef22643) — `forge inspect` lists it once a facet is ERC-8153.
    function _stripSelf(bytes4[] memory sels) private pure returns (bytes4[] memory kept) {
        kept = new bytes4[](sels.length);
        uint256 n;
        for (uint256 i; i < sels.length; ++i) {
            if (sels[i] != SEL_EXPORT) kept[n++] = sels[i];
        }
        assembly ("memory-safe") {
            mstore(kept, n)
        }
    }

    function _containsSel(bytes4[] memory set, bytes4 sel) private pure returns (bool) {
        for (uint256 i; i < set.length; ++i) {
            if (set[i] == sel) return true;
        }
        return false;
    }

    function _hasDuplicate(bytes4[] memory set) private pure returns (bool) {
        for (uint256 i; i < set.length; ++i) {
            for (uint256 j = i + 1; j < set.length; ++j) {
                if (set[i] == set[j]) return true;
            }
        }
        return false;
    }

    /// @dev Order-insensitive equality of two duplicate-free selector sets.
    function _setEq(bytes4[] memory a, bytes4[] memory b) private pure returns (bool) {
        if (a.length != b.length) return false;
        for (uint256 i; i < a.length; ++i) {
            if (!_containsSel(b, a[i])) return false;
        }
        for (uint256 i; i < b.length; ++i) {
            if (!_containsSel(a, b[i])) return false;
        }
        return true;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INVENTORY
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev The 99 release facets (95 Lattice + 4 diamond-lib core) under ERC-8153 parity, as (contract name, `"<file>:<Name>"` deploy path)
    ///      pairs — sourced from the SHARED {FacetInventory}, the same list {DeployRelease} releases from.
    function _inventory() private pure returns (string[] memory names, string[] memory paths) {
        (names, paths) = FacetInventory.inventory();
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                          LOCAL MOCK FIXTURES
//////////////////////////////////////////////////////////////////////////*//

/// @dev A correctly-implemented ERC-8153 facet: exports EXACTLY its own three ABI selectors, no duplicates, and
///      never `exportSelectors()` itself. The export is derived from the same signature strings as the functions,
///      so the runtime report and the compiled ABI agree by construction.
contract ParityCompliantMock is IERC8153 {
    function alpha() external pure {}
    function beta(uint256) external pure {}
    function gamma(address, bytes32) external pure {}

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(
            bytes4(keccak256("alpha()")),
            bytes4(keccak256("beta(uint256)")),
            bytes4(keccak256("gamma(address,bytes32)"))
        );
    }
}

/// @dev A non-compliant facet that wrongly lists `exportSelectors()` (0x0ef22643) in its own export.
contract ParityIncludesSelfMock is IERC8153 {
    function alpha() external pure {}

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(bytes4(keccak256("alpha()")), bytes4(0x0ef22643));
    }
}

/// @dev A non-compliant facet that exports the same selector twice.
contract ParityDuplicateMock is IERC8153 {
    function alpha() external pure {}
    function beta(uint256) external pure {}

    function exportSelectors() external pure returns (bytes memory) {
        bytes4 s = bytes4(keccak256("alpha()"));
        return abi.encodePacked(s, bytes4(keccak256("beta(uint256)")), s);
    }
}

/// @dev A non-compliant facet whose export is not a whole number of 4-byte selectors.
contract ParityMalformedLengthMock is IERC8153 {
    function exportSelectors() external pure returns (bytes memory) {
        return hex"0ef226"; // 3 bytes
    }
}

/// @dev A non-compliant facet that exports nothing.
contract ParityEmptyMock is IERC8153 {
    function exportSelectors() external pure returns (bytes memory) {
        return "";
    }
}
