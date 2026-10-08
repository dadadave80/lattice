// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {Votes} from "@lattice/governance/Votes.sol";
import {ERC721VotesInit} from "@lattice/tokens/ERC721/ERC721VotesInit.sol";
import {DiamondIntrospectionInit} from "@lattice/utils/DiamondIntrospectionInit.sol";

/// @title DeployERC721Votes
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for an ERC-721 token diamond with ERC-5805 voting power, one unit per token: the
///         base {DeployERC721} recipe (ERC165 + ERC721 + {ERC721Init}), the {Votes} facet (delegation views and the
///         ERC-6372 clock), and the {ERC721Votes} facet, which REPLACES the base `transferFrom`, both
///         `safeTransferFrom` overloads and the {Votes} facet's `delegate`/`delegateBySig` with unit-moving,
///         ERC-721-balance versions. {ERC721VotesInit} seeds the EIP-712 domain (version "1"), nonces and the
///         checkpoints (registering IVotes). All inits run in one initializing window via {BaseDeploy._assembleMulti}.
/// @dev DEFAULT overload: Immutable by design — no cut facet is cut (the inherited base recipe provides the
///      loupe); deploy a new diamond to change behavior. Use the ADMIN overload (`buildCuts(..., admin)` /
///      `run(..., admin)`) for an upgradeable deployment gated on `DEFAULT_ADMIN_ROLE`.
///      Mint and burn are app-specific: a minting facet calls {ERC721VotesLib._mint}/{_burn}, never {ERC721Lib}'s.
///      Do not add {ERC721Burnable}, {ERC721Wrapper}, {ERC721Pausable} or {ERC721Enumerable} to this diamond (see
///      {ERC721Votes}).
///      The `ERC721Votes` facet is the release facet from {BaseDeploy._facet}; the other cuts and the inits still
///      deploy fresh until every recipe moves to release contracts (#195).
contract DeployERC721Votes is BaseDeploy {
    /// @notice Builds the votes ERC-721 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name (also the EIP-712 domain name). @param symbol_ Token symbol.
    /// @return cuts The facet cuts (ERC165 + ERC721 + DiamondLoupeFacet + Votes + ERC721Votes [Replace]).
    /// @return inits The initializers, run in order ({DeployERC721}'s {MultiInit} chain, then {ERC721VotesInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC721().buildCuts(name_, symbol_);

        cuts = new FacetCut[](baseCuts.length + 2);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        // The ERC-5805 delegation + ERC-6372 clock surface comes from the standalone {Votes} facet.
        cuts[baseCuts.length] = _cut(address(new Votes()));
        // Every ERC721Votes selector already exists: the transfers on {ERC721}, the delegations on {Votes}.
        cuts[baseCuts.length + 1] = _replace(_facet("ERC721Votes"));

        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = address(new ERC721VotesInit());

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC721VotesInit.init, (name_));
    }

    /// @notice Deploys a votes ERC-721 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = buildCuts(name_, symbol_);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }

    /// @notice ADMIN OVERLOAD: the immutable default plus `AccessControl` + `AccessControlDiamondCut`, so
    ///         `admin` (granted `DEFAULT_ADMIN_ROLE`) can upgrade the diamond via `diamondCut`.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory defCuts, address[] memory defInits, bytes[] memory defCalldatas) = buildCuts(name_, symbol_);

        cuts = new FacetCut[](defCuts.length + 2);
        for (uint256 i; i < defCuts.length; ++i) {
            cuts[i] = defCuts[i];
        }
        cuts[defCuts.length] = _cut(address(new AccessControl()));
        cuts[defCuts.length + 1] = _cut(address(new AccessControlDiamondCut()));

        inits = new address[](defInits.length + 2);
        for (uint256 i; i < defInits.length; ++i) {
            inits[i] = defInits[i];
        }
        inits[defInits.length] = address(new AccessControlInit());
        inits[defInits.length + 1] = address(new DiamondIntrospectionInit());

        initCalldatas = new bytes[](defCalldatas.length + 2);
        for (uint256 i; i < defCalldatas.length; ++i) {
            initCalldatas[i] = defCalldatas[i];
        }
        initCalldatas[defCalldatas.length] = abi.encodeCall(AccessControlInit.init, (admin));
        // The base chain registered the loupe flag; the cut facet is live too — advertise both.
        initCalldatas[defCalldatas.length + 1] = abi.encodeCall(DiamondIntrospectionInit.initUpgradeable, ());
    }

    /// @notice ADMIN OVERLOAD: deploys the UPGRADEABLE variant — `admin` can `diamondCut`.
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
