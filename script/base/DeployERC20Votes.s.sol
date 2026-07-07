// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployERC20} from "@lattice-script/base/DeployERC20.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20/ERC20Votes.sol";
import {ERC20VotesInit} from "@lattice/tokens/ERC20/ERC20VotesInit.sol";

/// @title DeployERC20Votes
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a governance ERC-20 (ERC-5805 votes) token diamond: the base {DeployERC20}
///         recipe (ERC165 + ERC20 + {ERC20Init}), the {ERC20Votes} facet, and the {AccessControl} facet whose
///         DEFAULT_ADMIN_ROLE gates a consumer's minting authority. {ERC20Votes} is a MIXED cut — its
///         checkpoint-updating `transfer`/`transferFrom` REPLACE the base ERC-20 variants (so vote weight moves
///         with balances), while the ERC-5805 delegation + ERC-6372 clock surface (`delegate`/`delegateBySig`/
///         `getVotes`/`delegates`/`getPastVotes`/`getPastTotalSupply`/`clock`/`CLOCK_MODE`/`numCheckpoints`/
///         `checkpoints`) is ADDED. {ERC20VotesInit} seeds the EIP-712 domain, nonce, checkpoint, and role state.
///         Both inits run in one initializing window via {BaseDeploy._assembleMulti}.
contract DeployERC20Votes is BaseDeploy {
    /// @notice Builds the votes ERC-20 diamond cuts + initializers (no broadcast, no proxy deploy).
    /// @param name_ Token name (also the EIP-712 domain name). @param symbol_ Token symbol.
    /// @param admin The address granted DEFAULT_ADMIN_ROLE.
    /// @return cuts The facet cuts (ERC165 + ERC20 + ERC20Votes[Replace transfer/transferFrom + Add votes surface]
    ///         + AccessControl).
    /// @return inits The initializers, run in order ({ERC20Init} then {ERC20VotesInit}).
    /// @return initCalldatas The calldata matching each initializer.
    function buildCuts(string memory name_, string memory symbol_, address admin)
        public
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
    {
        (FacetCut[] memory baseCuts, address baseInit, bytes memory baseCalldata) =
            new DeployERC20().buildCuts(name_, symbol_);

        address votesFacet = address(new ERC20Votes());

        // `transfer`/`transferFrom` already exist on the base ERC-20 facet — replace them with the
        // checkpoint-updating variants so voting power tracks balance movement.
        bytes4[] memory replaceSelectors = new bytes4[](2);
        replaceSelectors[0] = ERC20Votes.transfer.selector;
        replaceSelectors[1] = ERC20Votes.transferFrom.selector;

        // The ERC-5805 delegation + ERC-6372 clock surface (IVotes) plus the OZ ERC20Votes checkpoint
        // accessors are new — add them. IVotes selectors reference the interface because `getVotes` &c. are
        // inherited into ERC20Votes (a `ContractName.fn.selector` resolves only own-declared members).
        bytes4[] memory addSelectors = new bytes4[](10);
        addSelectors[0] = IVotes.delegate.selector;
        addSelectors[1] = IVotes.delegateBySig.selector;
        addSelectors[2] = IVotes.getVotes.selector;
        addSelectors[3] = IVotes.getPastVotes.selector;
        addSelectors[4] = IVotes.getPastTotalSupply.selector;
        addSelectors[5] = IVotes.delegates.selector;
        addSelectors[6] = IVotes.clock.selector;
        addSelectors[7] = IVotes.CLOCK_MODE.selector;
        addSelectors[8] = ERC20Votes.numCheckpoints.selector;
        addSelectors[9] = ERC20Votes.checkpoints.selector;

        cuts = new FacetCut[](baseCuts.length + 3);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        cuts[baseCuts.length] =
            FacetCut({facetAddress: votesFacet, action: FacetCutAction.Add, functionSelectors: addSelectors});
        cuts[baseCuts.length + 1] =
            FacetCut({facetAddress: votesFacet, action: FacetCutAction.Replace, functionSelectors: replaceSelectors});
        cuts[baseCuts.length + 2] = _cut(address(new AccessControl()), "AccessControl");

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
