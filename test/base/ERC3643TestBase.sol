// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC3643} from "@lattice-script/base/tokens/DeployERC3643.s.sol";
import {ERC3643TokenIdentityMock, ERC3643TokenPolicyMock} from "@lattice-test/helpers/ERC3643TokenMocks.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {IAgentRole} from "@lattice/interfaces/tokens/erc3643/IAgentRole.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ERC3643Params} from "@lattice/tokens/ERC3643/ERC3643Params.sol";
import {Test} from "forge-std/Test.sol";

/// @title ERC3643TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Tests use the production cuts, canonical admission initializer and actual atomic LatticeFactory.
abstract contract ERC3643TestBase is Test {
    LatticeFactory internal factory;
    DeployERC3643 internal recipe;
    address internal diamond;
    IERC3643 internal token;
    IIdentityRegistry internal registry;
    ERC3643TokenIdentityMock internal aliceIdentity;
    ERC3643TokenIdentityMock internal bobIdentity;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);
    address internal spender = address(0x5EED);
    uint256 internal nonce;

    function _config(bool temporary) internal view returns (ERC3643Params memory config) {
        config.owner = address(this);
        config.agents = new address[](1);
        config.agents[0] = address(this);
        config.name = "Permissioned";
        config.symbol = "PERM";
        config.decimals = 6;
        config.temporaryApproval = temporary;
    }

    function _deploy(ERC3643Params memory config) internal returns (address result) {
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(config);
        result = factory.deploy(new RecipeEntry[](0), cuts, init, data, bytes32(++nonce));
    }

    function deployConfig(ERC3643Params memory config) external returns (address) {
        return _deploy(config);
    }

    function _register(address wallet, ERC3643TokenIdentityMock identity, uint16 country) internal {
        registry.registerIdentity(wallet, IERC3643Identity(address(identity)), country);
    }

    function _externalPolicy() internal returns (ERC3643TokenPolicyMock policy) {
        policy = new ERC3643TokenPolicyMock(address(this));
        policy.bindToken(diamond);
        token.setCompliance(address(policy));
    }

    function setUp() public virtual {
        factory = new LatticeFactory(new LatticeRegistry(address(this)), address(0), address(0));
        recipe = new DeployERC3643();
        diamond = _deploy(_config(false));
        token = IERC3643(diamond);
        registry = IIdentityRegistry(diamond);
        aliceIdentity = new ERC3643TokenIdentityMock();
        aliceIdentity.setManagement(alice, true);
        bobIdentity = new ERC3643TokenIdentityMock();
        bobIdentity.setManagement(bob, true);
        _register(alice, aliceIdentity, 11);
        _register(bob, bobIdentity, 22);
        token.mint(alice, 1000);
        token.mint(bob, 100);
        token.unpause();
    }
}
