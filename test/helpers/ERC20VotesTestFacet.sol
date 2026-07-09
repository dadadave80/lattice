// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @title ERC20VotesTestFacet
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test-only facet exposing the entrypoints the {ERC20Votes} facet test needs that no production facet
///         surfaces: the checkpoint-tracking, uint208-cap-enforcing {ERC20VotesLib._mint}/{ERC20VotesLib._burn}
///         (production minting is app-specific / access-gated) plus the `nonces`/`DOMAIN_SEPARATOR` reads used to
///         build a `delegateBySig` digest. Cut ON TOP of the production {DeployERC20Votes} recipe so a facet test
///         can seed voting balances and sign delegations while still exercising the REAL diamond dispatch — never
///         shipped, never part of a `run()` deploy. `mint`/`burn` revert exactly as {ERC20VotesLib} does.
contract ERC20VotesTestFacet {
    /// @notice Mint with vote-checkpoint tracking (reverts `ERC20ExceededSafeSupply` past the uint208 cap).
    function mint(address to, uint256 value) external {
        ERC20VotesLib._mint(to, value);
    }

    /// @notice Burn with vote-checkpoint tracking.
    function burn(address from, uint256 value) external {
        ERC20VotesLib._burn(from, value);
    }

    /// @notice Exposes the ERC-2612-style nonce counter (used to build a `delegateBySig` digest).
    function nonces(address account) external view returns (uint256) {
        return NoncesLib.nonces(account);
    }

    /// @notice Exposes the EIP-712 domain separator (used to build a `delegateBySig` digest).
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return EIP712Lib.domainSeparatorV4();
    }
}
