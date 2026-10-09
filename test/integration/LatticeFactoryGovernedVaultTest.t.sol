// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {CannotAddFunctionToDiamondThatAlreadyExists, Facet, FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedVault} from "@lattice/defi/GovernedVault.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {EMERGENCY_GUARDIAN_ROLE} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal mintable ERC-20 used as the vault's underlying asset.
contract CompositionAsset {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }
}

/// @title LatticeFactoryGovernedVaultTest
/// @notice #176: the production {DeployGovernedVault} recipe assembled through the REGISTRY path. The 8 facets
///         the recipe cuts whole become registry entries; the 6 facets it cuts with `_cutExcept` stay custom
///         cuts, because a {RecipeEntry} cannot exclude selectors. The registry-built vault must route every
///         selector exactly like the custom-only reference vault, wire its self-governance, leave the factory
///         without any role, and keep state isolated between instances.
contract LatticeFactoryGovernedVaultTest is Test {
    DeployGovernedVault internal recipe;
    LatticeRegistry internal registry;
    LatticeFactory internal factory;
    CompositionAsset internal asset;

    uint64 internal constant V1 = 1 << 48;

    /// @dev Indexes into {DeployGovernedVault}'s 14 base cuts that the recipe cuts WHOLE (`_cut`).
    uint256[8] internal WHOLE = [uint256(0), 1, 2, 9, 10, 11, 12, 13];
    /// @dev Indexes the recipe cuts PARTIALLY (`_cutExcept`): ERC20, ERC4626, VaultCore, Votes, ERC20Votes, Governor.
    uint256[6] internal PARTIAL = [uint256(3), 4, 5, 6, 7, 8];

    function setUp() public {
        recipe = new DeployGovernedVault();
        registry = new LatticeRegistry(address(this));
        factory = new LatticeFactory(registry, address(0), address(0));
        asset = new CompositionAsset();
    }

    function _params(string memory name) internal view returns (GovernedVaultParams memory p) {
        p.asset = address(asset);
        p.name = name;
        p.symbol = "gV";
        p.minDelay = 100;
        p.votingDelay = 1;
        p.votingPeriod = 50;
        p.quorumNumerator = 4;
    }

    /// @dev Registers the recipe's whole-cut facets and returns the mixed recipe for `p`.
    function _mixedRecipe(GovernedVaultParams memory p)
        internal
        returns (RecipeEntry[] memory entries, FacetCut[] memory customCuts, address init, bytes memory data)
    {
        FacetCut[] memory cuts;
        (cuts, init, data) = recipe.buildCuts(p);
        entries = new RecipeEntry[](WHOLE.length);
        for (uint256 i; i < WHOLE.length; ++i) {
            address facet = cuts[WHOLE[i]].facetAddress;
            bytes32 name = keccak256(abi.encode("lattice.vault-part", WHOLE[i]));
            if (registry.resolve(facet.codehash) == address(0)) registry.register(name, V1, facet);
            entries[i] = RecipeEntry({nameHash: name, version: V1});
        }
        customCuts = new FacetCut[](PARTIAL.length);
        for (uint256 i; i < PARTIAL.length; ++i) {
            customCuts[i] = cuts[PARTIAL[i]];
        }
    }

    function _deployMixed(string memory name, bytes32 salt) internal returns (address vault) {
        (RecipeEntry[] memory entries, FacetCut[] memory customCuts, address init, bytes memory data) =
            _mixedRecipe(_params(name));
        vault = factory.deploy(entries, customCuts, init, data, salt);
    }

    /// @notice The registry-built vault routes every selector to the same facet as the custom-only reference.
    function test_RegistryVaultRoutesLikeTheCustomOnlyReference() public {
        address refVault = recipe.deployAtomic(_params("Ref"), factory, keccak256("reference"));
        address vault = _deployMixed("Mixed", keccak256("mixed"));
        assertEq(vault, factory.predict(address(this), keccak256("mixed")), "deploy == predict");

        Facet[] memory refFacets = IDiamondLoupe(refVault).facets();
        assertEq(IDiamondLoupe(vault).facetAddresses().length, refFacets.length, "same facet count (14)");
        assertEq(refFacets.length, 14, "14 facets");
        for (uint256 i; i < refFacets.length; ++i) {
            bytes4[] memory selectors = refFacets[i].functionSelectors;
            for (uint256 j; j < selectors.length; ++j) {
                assertEq(
                    IDiamondLoupe(vault).facetAddress(selectors[j]), refFacets[i].facetAddress, "routed differently"
                );
            }
        }
        assertEq(IDiamondLoupe(vault).facetAddress(IERC8153.exportSelectors.selector), address(0), "no 8153 route");
    }

    /// @notice Self-governance wiring holds and the factory ends up holding no role the recipe defines.
    function test_RegistryVaultIsSelfGovernedAndFactoryHoldsNoRole() public {
        address vault = _deployMixed("Mixed", keccak256("mixed"));
        assertEq(Governor(payable(vault)).token(), vault, "votes come from the vault");
        assertEq(Governor(payable(vault)).timelock(), vault, "queues through the vault");

        bytes32[6] memory roles = [
            DEFAULT_ADMIN_ROLE,
            keccak256("PROPOSER_ROLE"),
            keccak256("EXECUTOR_ROLE"),
            keccak256("CANCELLER_ROLE"),
            UPGRADE_EXECUTOR_ROLE,
            EMERGENCY_GUARDIAN_ROLE
        ];
        for (uint256 i; i < roles.length; ++i) {
            assertFalse(AccessControl(vault).hasRole(roles[i], address(factory)), "factory holds a role");
            assertFalse(AccessControl(vault).hasRole(roles[i], address(this)), "deployer holds a role");
        }
        assertTrue(AccessControl(vault).hasRole(DEFAULT_ADMIN_ROLE, vault), "the vault administers itself");
    }

    /// @notice Two registry-built vaults share every facet but no state.
    function test_RegistryVaultsShareFacetsButNotState() public {
        address a = _deployMixed("Vault A", keccak256("a"));
        address b = _deployMixed("Vault B", keccak256("b"));
        assertEq(
            keccak256(abi.encode(IDiamondLoupe(a).facetAddresses())),
            keccak256(abi.encode(IDiamondLoupe(b).facetAddresses())),
            "same facet set"
        );

        address alice = makeAddr("alice");
        asset.mint(alice, 100 ether);
        vm.startPrank(alice);
        asset.approve(a, 100 ether);
        GovernedVault(a).deposit(100 ether, alice);
        vm.stopPrank();

        assertEq(IERC20(a).balanceOf(alice), 100 ether, "shares in A");
        assertEq(IERC20(b).balanceOf(alice), 0, "no shares in B");
        assertEq(IERC20(b).totalSupply(), 0, "B untouched");
        assertEq(IERC20(a).name(), "Vault A", "A metadata");
        assertEq(IERC20(b).name(), "Vault B", "B metadata");
    }

    /// @notice Why six facets stay custom cuts: the same facets as WHOLE registry entries collide with
    ///         {GovernedVault}'s reconciled selectors. A registry recipe for this vault needs selector exclusion
    ///         on {RecipeEntry} (the #176 `exclude` proposal).
    function test_PartialFacetsCannotBeRegistryEntriesToday() public {
        (FacetCut[] memory cuts,,) = recipe.buildCuts(_params("X"));
        registry.register(keccak256("lattice.ERC20"), V1, cuts[3].facetAddress);
        registry.register(keccak256("lattice.GovernedVault"), V1, cuts[9].facetAddress);
        registry.register(keccak256("lattice.DiamondLoupeFacet"), V1, cuts[10].facetAddress);

        RecipeEntry[] memory entries = new RecipeEntry[](3);
        entries[0] = RecipeEntry({nameHash: keccak256("lattice.DiamondLoupeFacet"), version: V1});
        entries[1] = RecipeEntry({nameHash: keccak256("lattice.ERC20"), version: V1});
        entries[2] = RecipeEntry({nameHash: keccak256("lattice.GovernedVault"), version: V1});

        vm.expectRevert(
            abi.encodeWithSelector(CannotAddFunctionToDiamondThatAlreadyExists.selector, bytes4(keccak256("name()")))
        );
        factory.deploy(entries, new FacetCut[](0), address(0), "", keccak256("collide"));
    }
}
