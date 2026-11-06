// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20TemporaryApproval} from "@lattice/interfaces/tokens/IERC20TemporaryApproval.sol";
import {ERC20TemporaryApprovalLib} from "@lattice/tokens/ERC20/libraries/ERC20TemporaryApprovalLib.sol";

/// @title ERC20TemporaryApproval
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/token/ERC20/extensions/draft-ERC20TemporaryApproval.sol)
/// @notice Additive ERC-7674 facet; registers discovery alongside the shared ERC20 allowance implementation.
/// @dev All allowance spenders must use the matching ERC20Lib version, including any custom facets.
///      No movement selector is replaced; ADR0009's movement-family exclusions still apply.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC20TemporaryApproval is IERC20TemporaryApproval {
    /// @inheritdoc IERC20TemporaryApproval
    function temporaryApprove(address spender, uint256 value) external returns (bool) {
        return ERC20TemporaryApprovalLib.temporaryApprove(spender, value);
    }

    /// @notice ERC-8153 packed selector export, excluding exportSelectors itself.
    function exportSelectors() external pure returns (bytes memory selectors) {
        selectors = hex"42232a4c";
    }
}
