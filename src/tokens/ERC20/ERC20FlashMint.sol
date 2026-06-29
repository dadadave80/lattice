// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC3156FlashBorrower} from "@lattice/interfaces/external/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@lattice/interfaces/external/IERC3156FlashLender.sol";
import {IERC20FlashMint} from "@lattice/interfaces/tokens/IERC20FlashMint.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20FlashMintLib} from "@lattice/tokens/ERC20/libraries/ERC20FlashMintLib.sol";

/// @title ERC20FlashMint
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20FlashMint.sol)
/// @notice Stateless Diamond facet — ERC-3156 flash loans at the token level (the token mints itself as the loan).
/// @dev Pure delegator to {ERC20FlashMintLib}. Default fee is 0 (burned). A supply cap ({ERC20Capped}) is not
///      reflected by `maxFlashLoan` — pair with a cap-aware flash-mint library if that composition is needed.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC20FlashMint is ERC20, IERC20FlashMint {
    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token) public view virtual returns (uint256) {
        return ERC20FlashMintLib.maxFlashLoan(token);
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address token, uint256 value) public view virtual returns (uint256) {
        return ERC20FlashMintLib.flashFee(token, value);
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 value, bytes calldata data)
        public
        virtual
        returns (bool)
    {
        return ERC20FlashMintLib.flashLoan(receiver, token, value, data);
    }
}
