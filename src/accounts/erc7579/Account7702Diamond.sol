// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccountDiamond} from "@lattice/accounts/erc7579/AccountDiamond.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";

/// @title Account7702Diamond
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Optional hardened EIP-7702 delegate (#58 item 7). The bare {Diamond}'s ungated `initialize` is safe
///         only when onboarding is ATOMIC — the 7702 authorization bundled into the same transaction as the
///         first UserOp, which is the standard 4337+7702 flow. An EOA that instead applies the delegation in a
///         separate, earlier transaction and leaves itself uninitialized is exposed to a front-runner who can
///         initialize it with a hostile blueprint. Delegating to THIS contract closes that window: the
///         unauthenticated `initialize` is disabled, and onboarding requires the delegating EOA's signature
///         over the exact `(cuts, init, calldata)`, bound to this account and chain.
/// @dev A front-runner cannot forge the EOA's signature, so cannot substitute a hostile blueprint; replaying
///      the EOA's own signed onboarding only reproduces the intended state (`init7702` sets owner = the EOA).
///      The residual is at most a failed first UserOp + retry, never account hijacking.
contract Account7702Diamond is AccountDiamond {
    /// @notice The provided onboarding signature did not recover to this account (the delegating EOA).
    error UnauthorizedOnboarding();

    /// @dev Domain tag separating the onboarding digest from any other message the EOA might sign.
    bytes32 private constant _ONBOARD_TAG = keccak256("Lattice.EIP7702.Onboard.v1");

    /// @notice Disabled on this delegate — use {initializeAuthorized} so onboarding is bound to the EOA's key.
    function initialize(FacetCut[] calldata, address, bytes calldata) public payable virtual override {
        revert UnauthorizedOnboarding();
    }

    /// @notice Initializes the delegated EOA's storage, gated by the EOA's signature over the onboarding.
    /// @param _facetCuts The facet cuts to apply.
    /// @param _init The initializer delegatecalled by `diamondCut` (e.g. `AccountInit`).
    /// @param _calldata The initializer calldata (e.g. `AccountInit.init7702()`).
    /// @param _signature The delegating EOA's ECDSA signature over {onboardingDigest} of the above.
    function initializeAuthorized(
        FacetCut[] calldata _facetCuts,
        address _init,
        bytes calldata _calldata,
        bytes calldata _signature
    ) external payable virtual {
        bytes32 digest = onboardingDigest(_facetCuts, _init, _calldata);
        (address signer, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, _signature);
        if (err != ECDSA.RecoverError.NoError || signer != address(this)) revert UnauthorizedOnboarding();

        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        DiamondLib.diamondCut(_facetCuts, _init, _calldata);
        InitializableLib.postInitializer(s);
    }

    /// @notice The digest the delegating EOA signs to authorize an onboarding. Bound to this account
    ///         (`address(this)`) and chain, so a signature cannot be replayed onto another account or chain.
    function onboardingDigest(FacetCut[] calldata _facetCuts, address _init, bytes calldata _calldata)
        public
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                _ONBOARD_TAG,
                address(this),
                block.chainid,
                keccak256(abi.encode(_facetCuts)),
                _init,
                keccak256(_calldata)
            )
        );
    }
}
