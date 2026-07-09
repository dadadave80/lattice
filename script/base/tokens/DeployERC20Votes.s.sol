// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {Votes} from "@lattice/governance/Votes.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20/ERC20Votes.sol";
import {ERC20VotesInit} from "@lattice/tokens/ERC20/ERC20VotesInit.sol";

/// @title DeployERC20Votes
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a governance ERC-20 (ERC-5805 votes) token diamond: the base {DeployERC20}
///         recipe (ERC165 + ERC20 + {ERC20Init}), the {Votes} facet (ERC-5805 delegation + ERC-6372 clock), the
///         {ERC20Votes} facet, and the {AccessControl} facet whose DEFAULT_ADMIN_ROLE gates a consumer's minting
///         authority. Each facet owns ONLY its own selectors (the composability principle): the {Votes} facet
///         ADDs `getVotes`/`getPastVotes`/`getPastTotalSupply`/`delegates`/`delegate`/`delegateBySig`/`clock`/
///         `CLOCK_MODE`; {ERC20Votes} is a MIXED cut — its checkpoint-updating `transfer`/`transferFrom` REPLACE
///         the base ERC-20 variants and its balance-aware `delegate`/`delegateBySig` REPLACE the base {Votes}
///         variants (so vote weight moves with balances), while `numCheckpoints`/`checkpoints` are ADDED.
///         {ERC20VotesInit} seeds the EIP-712 domain, nonce, checkpoint, and role state. Both inits run in one
///         initializing window via {BaseDeploy._assembleMulti}.
contract DeployERC20Votes is BaseDeploy {
    /// @notice Builds the votes ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name (also the EIP-712 domain name). @param symbol_ Token symbol.
    /// @param admin The address granted DEFAULT_ADMIN_ROLE.
    /// @return cuts The facet cuts (ERC165 + ERC20 + Votes + ERC20Votes[Add checkpoints, Replace transfer/
    ///         transferFrom/delegate/delegateBySig] + AccessControl).
    /// @return inits The initializers, run in order ({ERC20Init} then {ERC20VotesInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC20().buildCuts(name_, symbol_);

        address votesFacet = address(new ERC20Votes());

        // `transfer`/`transferFrom` (base ERC-20) and `delegate`/`delegateBySig` (base {Votes}) already exist —
        // replace them with the checkpoint/balance-aware variants so voting power tracks balance movement.
        bytes4[] memory replaceSelectors = new bytes4[](4);
        replaceSelectors[0] = ERC20Votes.transfer.selector;
        replaceSelectors[1] = ERC20Votes.transferFrom.selector;
        replaceSelectors[2] = ERC20Votes.delegate.selector;
        replaceSelectors[3] = ERC20Votes.delegateBySig.selector;

        // The OZ ERC20Votes checkpoint accessors are new — add them.
        bytes4[] memory addSelectors = new bytes4[](2);
        addSelectors[0] = ERC20Votes.numCheckpoints.selector;
        addSelectors[1] = ERC20Votes.checkpoints.selector;

        cuts = new FacetCut[](baseCuts.length + 4);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        // The ERC-5805 delegation + ERC-6372 clock surface comes from the standalone {Votes} facet.
        cuts[baseCuts.length] = _cut(address(new Votes()));
        cuts[baseCuts.length + 1] =
            FacetCut({facetAddress: votesFacet, action: FacetCutAction.Add, functionSelectors: addSelectors});
        cuts[baseCuts.length + 2] =
            FacetCut({facetAddress: votesFacet, action: FacetCutAction.Replace, functionSelectors: replaceSelectors});
        cuts[baseCuts.length + 3] = _cut(address(new AccessControl()));

        inits = new address[](2);
        inits[0] = baseInit;
        inits[1] = address(new ERC20VotesInit());

        initCalldatas = new bytes[](2);
        initCalldatas[0] = baseCalldata;
        initCalldatas[1] = abi.encodeCall(ERC20VotesInit.init, (name_, admin));
    }

    /// @notice Deploys a votes ERC-20 token diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(string memory name_, string memory symbol_, address admin) external returns (address token) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            buildCuts(name_, symbol_, admin);
        token = _assembleMulti(cuts, inits, initCalldatas);
        vm.stopBroadcast();
    }
}
