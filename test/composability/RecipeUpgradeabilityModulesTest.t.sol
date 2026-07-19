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
import {RecipeGuards} from "@lattice-test/composability/RecipeGuards.sol";
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
contract RecipeUpgradeabilityModulesTest is RecipeGuards {
    TestnetAsset internal asset;

    function setUp() public {
        asset = new TestnetAsset("Guard Asset", "GA");
    }

    function test_Upgradeable_AccessControl() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAccessControl().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_AccessControlEnumerable() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAccessControlEnumerable().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_AccessControlTimed() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAccessControlTimed().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_AccessManaged() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAccessManaged().buildCuts(address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_AccessManaged() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployAccessManaged().buildCuts(address(this), ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        assertEq(AccessManaged(d).authority(), address(this), "module init: authority");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_AccessManager() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAccessManager().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    /// @notice The MODULE admin (AccessManager ADMIN_ROLE) and the UPGRADE admin (DEFAULT_ADMIN_ROLE) are
    ///         DISTINCT authorities in distinct role systems — a param swap inside the overload dies here.
    function test_Upgradeable_AccessManager() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployAccessManager().buildCuts(ADMIN, UPGRADE_ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        (bool isMember,) = AccessManager(d).hasRole(0, ADMIN);
        assertTrue(isMember, "module init: manager ADMIN_ROLE");
        (bool upgraderIsManagerAdmin,) = AccessManager(d).hasRole(0, UPGRADE_ADMIN);
        assertFalse(upgraderIsManagerAdmin, "upgrade admin must NOT hold the manager role");
        _assertAdminCanCut(d, UPGRADE_ADMIN);
    }

    function test_Upgradeable_ConstantProduct() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployConstantProduct().buildCuts(ADMIN, address(this), address(0xA55E7));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_AggregatorExecAdapter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployAggregatorExecAdapter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_StrategyManager() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployStrategyManager().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_VaultCore() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployVaultCore().buildCuts(address(asset), "Vault", "VLT", ADMIN, 0);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 8);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ENSResolver() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployENSResolver().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ENSReverseClaimer() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployENSReverseClaimer().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ENSSubnameIssuer() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployENSSubnameIssuer().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_SafeHarborAdopter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeploySafeHarborAdopter().buildCuts(ADMIN, address(this), address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_CommitReveal() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployCommitReveal().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_CommitReveal() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployCommitReveal().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        assertTrue(ERC165Facet(d).supportsInterface(type(ICommitReveal).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC5564Announcer() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC5564Announcer().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC5564Announcer() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC5564Announcer().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        assertTrue(ERC165Facet(d).supportsInterface(type(IERC5564Announcer).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_ERC6538Registry() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC6538Registry().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_ERC6538Registry() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployERC6538Registry().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 7);
        assertTrue(ERC165Facet(d).supportsInterface(type(IERC6538Registry).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_Groth16Verifier() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGroth16Verifier().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_Groth16Verifier() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployGroth16Verifier().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        assertTrue(ERC165Facet(d).supportsInterface(type(IGroth16Verifier).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_PlonkVerifier() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployPlonkVerifier().buildCuts();
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 4);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_PlonkVerifier() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployPlonkVerifier().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        assertTrue(ERC165Facet(d).supportsInterface(type(IPlonkVerifier).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Immutable_PrivateVoting() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployPrivateVoting().buildCuts(address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 5);
        _assertImmutableByDesign(d);
    }

    function test_Upgradeable_PrivateVoting() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployPrivateVoting().buildCuts(address(this), ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 7);
        assertTrue(ERC165Facet(d).supportsInterface(type(IPrivateVoting).interfaceId), "module init flag");
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_Semaphore() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeploySemaphore().buildCuts(ADMIN, address(this));
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_ShieldedPool() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployShieldedPool().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_CircuitBreaker() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployCircuitBreaker().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_EmergencyStop() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployEmergencyStop().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_InvariantChecker() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployInvariantChecker().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_Pausable() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployPausable().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_RateLimiter() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployRateLimiter().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }

    function test_Upgradeable_Multicall() public {
        (FacetCut[] memory cuts, address init, bytes memory cd) = new DeployMulticall().buildCuts(ADMIN);
        address d = _assemble(cuts, init, cd);
        _assertIntrospectable(d, 6);
        _assertAdminCanCut(d, ADMIN);
    }
}
