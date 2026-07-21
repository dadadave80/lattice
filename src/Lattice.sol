// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {DiamondLib, FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";

/*
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⣦⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⣿⣿⣿⣿⣦⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⢹⣿⣿⡏⠻⣿⣿⣦⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁⠀⢸⣿⣿⡇⠀⠈⠻⣿⣿⣦⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁⠀⠀⠀⢸⣿⣿⡇⠀⠀⠀⠈⠻⣿⣿⣦⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁⠀⠀⠀⠀⠀⣸⣿⣿⣇⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁⠀⠀⠀⠀⠀⣠⣾⣿⡿⢿⣿⣷⣄⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀
⠀⠀⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁⠀⠀⠀⠀⠀⣠⣾⣿⡿⠋⠀⠀⠙⢿⣿⣷⣄⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀
⠀⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁⠀⠀⠀⠀⠀⣠⣾⣿⡿⠋⠀⠀⠀⠀⠀⠀⠙⢿⣿⣷⣄⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀
⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁⠀⠀⠀⠀⠀⣠⣾⣿⡿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢿⣿⣷⣄⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀
⠀⠀⢀⣴⣿⣿⣟⣁⣀⣀⣀⣀⣀⣠⣾⣿⡿⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢿⣿⣷⣄⣀⣀⣀⣀⣀⣈⣻⣿⣿⣦⡀
⠀⠰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣏⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣹⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠆
⠀⠀⠈⠻⣿⣿⣯⡉⠉⠉⠉⠉⠉⠙⢿⣿⣷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⣿⡿⠋⠉⠉⠉⠉⠉⢉⣽⣿⣿⠟⠁
⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀⠀⠀⠀⠀⠀⠙⢿⣿⣷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣠⣾⣿⡿⠋⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁
⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀⠀⠀⠀⠀⠀⠙⢿⣿⣷⣄⠀⠀⠀⠀⠀⠀⣠⣾⣿⡿⠋⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀⠀⠀⠀⠀⠀⠙⢿⣿⣷⣄⠀⠀⣠⣾⣿⡿⠋⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀⠀⠀⠀⠀⠀⠙⢿⣿⣷⣾⣿⡿⠋⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀⠀⠀⠀⠀⠀⢹⣿⣿⡏⠀⠀⠀⠀⠀⢀⣴⣿⣿⠟⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀⠀⠀⠀⢸⣿⣿⡇⠀⠀⠀⢀⣴⣿⣿⠟⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⡀⠀⢸⣿⣿⡇⠀⢀⣴⣿⣿⠟⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣦⣸⣿⣿⣇⣴⣿⣿⠟⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⠻⣿⣿⣿⣿⣿⣿⠟⠁
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠙⢿⣿⡿⠋
⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉
*/

/// @title Lattice
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from diamond-lib (https://github.com/dadadave80/diamond-lib)
/// @notice Lattice's concrete diamond: the initializer-guarded preset over diamond-lib's abstract
///         fallback-only {Diamond} base (upstream v0.3.0 made the base abstract and dropped
///         `initialize`/`receive`; this contract restores the guarded `initialize`, Lattice-owned).
///         Bare-ETH acceptance is deliberately NOT restored here — cut the {Receive} facet under the
///         zero selector instead (every Lattice recipe does); a diamond without it rejects plain sends.
///         Deployed bare (directly or via {LatticeFactory} CREATE2), then cut ONCE through {initialize};
///         all later upgrades go through whichever cut facet the initial cut installed.
/// @dev `initialize` is guarded by the `initializer` modifier from the {Initializable} mixin over the
///      vendored {InitializableLib} — a nested initializer invoked inside a constructor finalizes exactly
///      once. Kept `virtual` — account presets override it (e.g. {Account7702Diamond} disables it in favor
///      of signature-gated onboarding).
contract Lattice is Diamond, Initializable {
    /// @notice Apply the initial facet cut and run the init delegatecall — callable ONCE.
    /// @param _facetCuts The initial facet cuts to install.
    /// @param _init The initializer contract delegatecalled after the cut (or address(0)).
    /// @param _calldata The delegatecall payload for `_init`.
    function initialize(FacetCut[] calldata _facetCuts, address _init, bytes calldata _calldata)
        public
        payable
        virtual
        initializer
    {
        DiamondLib.diamondCut(_facetCuts, _init, _calldata);
    }
}
