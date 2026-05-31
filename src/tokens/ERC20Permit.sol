// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Permit} from "@lattice/interfaces/IERC20Permit.sol";
import {ERC20} from "@lattice/tokens/ERC20.sol";
import {ERC20PermitLib} from "@lattice/tokens/libraries/ERC20PermitLib.sol";
import {EIP712} from "@lattice/utils/EIP712.sol";
import {Nonces} from "@lattice/utils/Nonces.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @title ERC20Permit
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol)
/// @notice Stateless Diamond facet adding ERC-2612 permit-based approvals to ERC-20.
/// @dev Inherits ERC20, EIP712, and Nonces. Delegates permit logic to ERC20PermitLib.
///      EIP712 and Nonces modules must be initialized separately in the initializer.
contract ERC20Permit is ERC20, EIP712, Nonces, IERC20Permit {
    /// @inheritdoc IERC20Permit
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        ERC20PermitLib.permit(owner, spender, value, deadline, v, r, s);
    }

    /// @inheritdoc IERC20Permit
    function nonces(address owner) public view virtual override(Nonces, IERC20Permit) returns (uint256) {
        return NoncesLib.nonces(owner);
    }

    /// @inheritdoc IERC20Permit
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return EIP712Lib.domainSeparatorV4();
    }
}
