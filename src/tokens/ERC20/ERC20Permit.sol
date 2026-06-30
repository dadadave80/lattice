// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Permit} from "@lattice/interfaces/tokens/IERC20Permit.sol";
import {ERC20PermitLib} from "@lattice/tokens/ERC20/libraries/ERC20PermitLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @title ERC20Permit
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol)
/// @notice Stateless Diamond facet adding ERC-2612 permit-based approvals to ERC-20.
/// @dev Owns ONLY the ERC-2612 surface (`permit`/`nonces`/`DOMAIN_SEPARATOR`), implemented over {EIP712Lib} and
///      {NoncesLib}. It does NOT inherit the {EIP712} / {Nonces} facets — doing so would re-export
///      `eip712Domain()` / `nonces()` and collide with those standalone facets (and any other EIP-712 extension)
///      in a Diamond. A token that also wants ERC-5267 `eip712Domain()` discovery cuts the standalone {EIP712}
///      facet as a COMPONENT via the blueprint (see `TokenBlueprintHelper._permitTokenBlueprint`); the EIP-712 and
///      nonce storage are seeded once in the token's initializer (`EIP712Lib.__EIP712_init`/`NoncesLib.__Nonces_init`).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract ERC20Permit is IERC20Permit {
    /// @inheritdoc IERC20Permit
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
    {
        ERC20PermitLib.permit(owner, spender, value, deadline, v, r, s);
    }

    /// @inheritdoc IERC20Permit
    function nonces(address owner) public view virtual returns (uint256) {
        return NoncesLib.nonces(owner);
    }

    /// @inheritdoc IERC20Permit
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return EIP712Lib.domainSeparatorV4();
    }
}
