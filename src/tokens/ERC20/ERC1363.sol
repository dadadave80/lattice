// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1363} from "@lattice/interfaces/tokens/IERC1363.sol";
import {ERC1363Lib} from "@lattice/tokens/ERC20/libraries/ERC1363Lib.sol";

/// @title ERC1363
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC1363.sol)
/// @notice Stateless Diamond facet adding ERC-1363 `transferAndCall`, `transferFromAndCall` and `approveAndCall` to
///         ERC-20. Pure delegator to {ERC1363Lib}.
/// @dev Additive: cut it next to the base {ERC20} facet. It replaces no selector and shares none.
///      Mutually exclusive with the ERC-20 movement overrides (decision D25 on #234): ERC20Pausable, ERC20Votes and
///      GovernedVault `Replace` `transfer`/`transferFrom`, and the `*AndCall` paths move tokens through {ERC20Lib}
///      without them, so a pause would not stop them and votes would not follow them. No selector clash catches
///      this at cut time; `CompositionHazardsTest` pins it. {ERC1363Lib} lists every difference from OpenZeppelin.
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC1363 is IERC1363 {
    /// @inheritdoc IERC1363
    function transferAndCall(address to, uint256 value) public virtual returns (bool) {
        return ERC1363Lib.transferAndCall(to, value, "");
    }

    /// @inheritdoc IERC1363
    function transferAndCall(address to, uint256 value, bytes memory data) public virtual returns (bool) {
        return ERC1363Lib.transferAndCall(to, value, data);
    }

    /// @inheritdoc IERC1363
    function transferFromAndCall(address from, address to, uint256 value) public virtual returns (bool) {
        return ERC1363Lib.transferFromAndCall(from, to, value, "");
    }

    /// @inheritdoc IERC1363
    function transferFromAndCall(address from, address to, uint256 value, bytes memory data)
        public
        virtual
        returns (bool)
    {
        return ERC1363Lib.transferFromAndCall(from, to, value, data);
    }

    /// @inheritdoc IERC1363
    function approveAndCall(address spender, uint256 value) public virtual returns (bool) {
        return ERC1363Lib.approveAndCall(spender, value, "");
    }

    /// @inheritdoc IERC1363
    function approveAndCall(address spender, uint256 value, bytes memory data) public virtual returns (bool) {
        return ERC1363Lib.approveAndCall(spender, value, data);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC1363 methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `approveAndCall(address,uint256)` 0x3177029f
    ///      `approveAndCall(address,uint256,bytes)` 0xcae9ca51
    ///      `transferAndCall(address,uint256)` 0x1296ee62
    ///      `transferAndCall(address,uint256,bytes)` 0x4000aea0
    ///      `transferFromAndCall(address,address,uint256)` 0xd8fbe994
    ///      `transferFromAndCall(address,address,uint256,bytes)` 0xc1d34b89
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"3177029fcae9ca511296ee624000aea0d8fbe994c1d34b89";
    }
}
