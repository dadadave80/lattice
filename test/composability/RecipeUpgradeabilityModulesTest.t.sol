// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// AUTO-STRUCTURED guard suite — one test per deploy recipe (see RecipeGuards).
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccessControl} from "@lattice-script/base/access/DeployAccessControl.s.sol";
import {DeployAccessControlEnumerable} from "@lattice-script/base/access/DeployAccessControlEnumerable.s.sol";
import {DeployAccessControlTimed} from "@lattice-script/base/access/DeployAccessControlTimed.s.sol";
import {DeployAccessManaged} from "@lattice-script/base/access/DeployAccessManaged.s.sol";
import {DeployAccessManager} from "@lattice-script/base/access/DeployAccessManager.s.sol";
import {DeployConstantProduct} from "@lattice-script/base/amm/DeployConstantProduct.s.sol";
import {DeployAggregatorExecAdapter} from "@lattice-script/base/defi/DeployAggregatorExecAdapter.s.sol";
import {TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {DeployStrategyManager} from "@lattice-script/base/defi/DeployStrategyManager.s.sol";
import {DeployVaultCore} from "@lattice-script/base/defi/DeployVaultCore.s.sol";
import {DeployENSResolver} from "@lattice-script/base/ens/DeployENSResolver.s.sol";
import {DeployENSReverseClaimer} from "@lattice-script/base/ens/DeployENSReverseClaimer.s.sol";
import {DeployENSSubnameIssuer} from "@lattice-script/base/ens/DeployENSSubnameIssuer.s.sol";
import {DeploySafeHarborAdopter} from "@lattice-script/base/governance/DeploySafeHarborAdopter.s.sol";
import {DeployCommitReveal} from "@lattice-script/base/privacy/DeployCommitReveal.s.sol";
import {DeployERC5564Announcer} from "@lattice-script/base/privacy/DeployERC5564Announcer.s.sol";
import {DeployERC6538Registry} from "@lattice-script/base/privacy/DeployERC6538Registry.s.sol";
import {DeployGroth16Verifier} from "@lattice-script/base/privacy/DeployGroth16Verifier.s.sol";
import {DeployPlonkVerifier} from "@lattice-script/base/privacy/DeployPlonkVerifier.s.sol";
import {DeployPrivateVoting} from "@lattice-script/base/privacy/DeployPrivateVoting.s.sol";
import {DeploySemaphore} from "@lattice-script/base/privacy/DeploySemaphore.s.sol";
import {DeployShieldedPool} from "@lattice-script/base/privacy/DeployShieldedPool.s.sol";
import {DeployCircuitBreaker} from "@lattice-script/base/security/DeployCircuitBreaker.s.sol";
import {DeployEmergencyStop} from "@lattice-script/base/security/DeployEmergencyStop.s.sol";
import {DeployInvariantChecker} from "@lattice-script/base/security/DeployInvariantChecker.s.sol";
import {DeployPausable} from "@lattice-script/base/security/DeployPausable.s.sol";
import {DeployRateLimiter} from "@lattice-script/base/security/DeployRateLimiter.s.sol";
import {DeployMulticall} from "@lattice-script/base/utils/DeployMulticall.s.sol";
import {RecipeConsistencyGuards} from "@lattice-test/composability/RecipeConsistencyGuards.sol";
import {AccessManaged} from "@lattice/access/AccessManaged.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {ICommitReveal} from "@lattice/interfaces/privacy/ICommitReveal.sol";
import {IERC5564Announcer} from "@lattice/interfaces/privacy/IERC5564Announcer.sol";
import {IERC6538Registry} from "@lattice/interfaces/privacy/IERC6538Registry.sol";
import {IGroth16Verifier} from "@lattice/interfaces/privacy/IGroth16Verifier.sol";
import {IPlonkVerifier} from "@lattice/interfaces/privacy/IPlonkVerifier.sol";
import {IPrivateVoting} from "@lattice/interfaces/privacy/IPrivateVoting.sol";

/// @title RecipeUpgradeabilityModulesTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Modules-family recipe guards: every diamond these recipes assemble must be introspectable and
///         either admin-upgradeable or immutable BY DESIGN (never silently frozen).
contract RecipeUpgradeabilityModulesTest is RecipeConsistencyGuards {
    TestnetAsset internal asset;

    function setUp() public {
        asset = new TestnetAsset("Guard Asset", "GA");
    }

    function test_Upgradeable_AccessControl() public {
        _expectRecipe(new DeployAccessControl().recipeSpec(), 0, "DeployAccessControl");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAccessControl().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_AccessControlEnumerable() public {
        _expectRecipe(new DeployAccessControlEnumerable().recipeSpec(), 0, "DeployAccessControlEnumerable");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAccessControlEnumerable().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_AccessControlTimed() public {
        _expectRecipe(new DeployAccessControlTimed().recipeSpec(), 0, "DeployAccessControlTimed");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAccessControlTimed().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_AccessManaged() public {
        _expectRecipe(new DeployAccessManaged().recipeSpec(), 0, "DeployAccessManaged");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAccessManaged().buildCuts(address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_AccessManaged() public {
        _expectRecipe(new DeployAccessManaged().recipeSpec(), 1, "DeployAccessManaged");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployAccessManaged().buildCuts(address(this), ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertEq(AccessManaged(d).authority(), address(this), "module init: authority");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_AccessManager() public {
        _expectRecipe(new DeployAccessManager().recipeSpec(), 0, "DeployAccessManager");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAccessManager().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    /// @notice The MODULE admin (AccessManager ADMIN_ROLE) and the UPGRADE admin (DEFAULT_ADMIN_ROLE) are
    ///         DISTINCT authorities in distinct role systems — a param swap inside the overload dies here.
    function test_Upgradeable_AccessManager() public {
        _expectRecipe(new DeployAccessManager().recipeSpec(), 1, "DeployAccessManager");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployAccessManager().buildCuts(ADMIN, UPGRADE_ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        (bool isMember,) = AccessManager(d).hasRole(0, ADMIN);
        assertTrue(isMember, "module init: manager ADMIN_ROLE");
        (bool upgraderIsManagerAdmin,) = AccessManager(d).hasRole(0, UPGRADE_ADMIN);
        assertFalse(upgraderIsManagerAdmin, "upgrade admin must NOT hold the manager role");
        _assertAdminCanCut(d, UPGRADE_ADMIN);
    }

    function test_Upgradeable_ConstantProduct() public {
        _expectRecipe(new DeployConstantProduct().recipeSpec(), 0, "DeployConstantProduct");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployConstantProduct().buildCuts(ADMIN, address(this), address(0xA55E7));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_AggregatorExecAdapter() public {
        _expectRecipe(new DeployAggregatorExecAdapter().recipeSpec(), 0, "DeployAggregatorExecAdapter");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAggregatorExecAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, true);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_StrategyManager() public {
        _expectRecipe(new DeployStrategyManager().recipeSpec(), 0, "DeployStrategyManager");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployStrategyManager().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_VaultCore() public {
        _expectRecipe(new DeployVaultCore().recipeSpec(), 0, "DeployVaultCore");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployVaultCore().buildCuts(address(asset), "Vault", "VLT", ADMIN, 0);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 7);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ENSResolver() public {
        _expectRecipe(new DeployENSResolver().recipeSpec(), 0, "DeployENSResolver");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployENSResolver().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ENSReverseClaimer() public {
        _expectRecipe(new DeployENSReverseClaimer().recipeSpec(), 0, "DeployENSReverseClaimer");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployENSReverseClaimer().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ENSSubnameIssuer() public {
        _expectRecipe(new DeployENSSubnameIssuer().recipeSpec(), 0, "DeployENSSubnameIssuer");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployENSSubnameIssuer().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_SafeHarborAdopter() public {
        _expectRecipe(new DeploySafeHarborAdopter().recipeSpec(), 0, "DeploySafeHarborAdopter");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeploySafeHarborAdopter().buildCuts(ADMIN, address(this), address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_CommitReveal() public {
        _expectRecipe(new DeployCommitReveal().recipeSpec(), 0, "DeployCommitReveal");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployCommitReveal().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_CommitReveal() public {
        _expectRecipe(new DeployCommitReveal().recipeSpec(), 1, "DeployCommitReveal");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployCommitReveal().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertTrue(ERC165Facet(d).supportsInterface(type(ICommitReveal).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC5564Announcer() public {
        _expectRecipe(new DeployERC5564Announcer().recipeSpec(), 0, "DeployERC5564Announcer");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC5564Announcer().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC5564Announcer() public {
        _expectRecipe(new DeployERC5564Announcer().recipeSpec(), 1, "DeployERC5564Announcer");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC5564Announcer().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertTrue(ERC165Facet(d).supportsInterface(type(IERC5564Announcer).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC6538Registry() public {
        _expectRecipe(new DeployERC6538Registry().recipeSpec(), 0, "DeployERC6538Registry");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC6538Registry().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC6538Registry() public {
        _expectRecipe(new DeployERC6538Registry().recipeSpec(), 1, "DeployERC6538Registry");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC6538Registry().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertTrue(ERC165Facet(d).supportsInterface(type(IERC6538Registry).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_Groth16Verifier() public {
        _expectRecipe(new DeployGroth16Verifier().recipeSpec(), 0, "DeployGroth16Verifier");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGroth16Verifier().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_Groth16Verifier() public {
        _expectRecipe(new DeployGroth16Verifier().recipeSpec(), 1, "DeployGroth16Verifier");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGroth16Verifier().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertTrue(ERC165Facet(d).supportsInterface(type(IGroth16Verifier).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_PlonkVerifier() public {
        _expectRecipe(new DeployPlonkVerifier().recipeSpec(), 0, "DeployPlonkVerifier");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployPlonkVerifier().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 3);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_PlonkVerifier() public {
        _expectRecipe(new DeployPlonkVerifier().recipeSpec(), 1, "DeployPlonkVerifier");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployPlonkVerifier().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        assertTrue(ERC165Facet(d).supportsInterface(type(IPlonkVerifier).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_PrivateVoting() public {
        _expectRecipe(new DeployPrivateVoting().recipeSpec(), 0, "DeployPrivateVoting");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployPrivateVoting().buildCuts(address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertBareEth(d, false);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_PrivateVoting() public {
        _expectRecipe(new DeployPrivateVoting().recipeSpec(), 1, "DeployPrivateVoting");
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployPrivateVoting().buildCuts(address(this), ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertBareEth(d, false);
        assertTrue(ERC165Facet(d).supportsInterface(type(IPrivateVoting).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_Semaphore() public {
        _expectRecipe(new DeploySemaphore().recipeSpec(), 0, "DeploySemaphore");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeploySemaphore().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ShieldedPool() public {
        _expectRecipe(new DeployShieldedPool().recipeSpec(), 0, "DeployShieldedPool");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployShieldedPool().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_CircuitBreaker() public {
        _expectRecipe(new DeployCircuitBreaker().recipeSpec(), 0, "DeployCircuitBreaker");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployCircuitBreaker().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_EmergencyStop() public {
        _expectRecipe(new DeployEmergencyStop().recipeSpec(), 0, "DeployEmergencyStop");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployEmergencyStop().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_InvariantChecker() public {
        _expectRecipe(new DeployInvariantChecker().recipeSpec(), 0, "DeployInvariantChecker");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployInvariantChecker().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_Pausable() public {
        _expectRecipe(new DeployPausable().recipeSpec(), 0, "DeployPausable");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployPausable().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_RateLimiter() public {
        _expectRecipe(new DeployRateLimiter().recipeSpec(), 0, "DeployRateLimiter");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployRateLimiter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_Multicall() public {
        _expectRecipe(new DeployMulticall().recipeSpec(), 0, "DeployMulticall");
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployMulticall().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertBareEth(d, false);
        _assertAdminCanCut(d, ADMIN);
    }
}
