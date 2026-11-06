// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {DeployGovernedVaultENS, TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {DeployVaultCore} from "@lattice-script/base/defi/DeployVaultCore.s.sol";
import {DeployERC1155Pausable} from "@lattice-script/base/tokens/DeployERC1155Pausable.s.sol";
import {DeployERC1155URIStorage} from "@lattice-script/base/tokens/DeployERC1155URIStorage.s.sol";
import {DeployERC20Pausable} from "@lattice-script/base/tokens/DeployERC20Pausable.s.sol";
import {DeployERC20Votes} from "@lattice-script/base/tokens/DeployERC20Votes.s.sol";
import {DeployERC20Wrapper} from "@lattice-script/base/tokens/DeployERC20Wrapper.s.sol";
import {DeployERC4626} from "@lattice-script/base/tokens/DeployERC4626.s.sol";
import {DeployERC721Enumerable} from "@lattice-script/base/tokens/DeployERC721Enumerable.s.sol";
import {DeployERC721Pausable} from "@lattice-script/base/tokens/DeployERC721Pausable.s.sol";
import {DeployERC721URIStorage} from "@lattice-script/base/tokens/DeployERC721URIStorage.s.sol";
import {DeployERC721Votes} from "@lattice-script/base/tokens/DeployERC721Votes.s.sol";
import {ArachnidDeployer} from "@lattice-script/lib/ArachnidDeployer.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {ExpectedRecipeRoute, RecipeSeamExpectations} from "@lattice-test/composability/RecipeSeamExpectations.sol";
import {ReleasedRecipeGuards} from "@lattice-test/composability/ReleasedRecipeGuards.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {GovernedVaultENSParams} from "@lattice/defi/GovernedVaultENSInit.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {IAccessControlDiamondCut} from "@lattice/interfaces/governance/IAccessControlDiamondCut.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @title CanonicalRecipeSeamOracle
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Checks actual proxy routes against fixed source-reviewed owners, independent of recipe declarations.
/// @dev Has no Test or recipe-spec inheritance, so canonical context suites can reuse this oracle directly.
abstract contract CanonicalRecipeSeamOracle {
    error UnknownCanonicalSeamOwner(string owner);
    error CanonicalSeamOwnerCodeMissing(string owner, address expected);
    error MissingCanonicalSeam(string recipe, bytes4 selector, string owner, address expected);
    error WrongCanonicalSeam(string recipe, bytes4 selector, string owner, address expected, address actual);

    VmSafe private constant SEAM_VM = VmSafe(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev The caller supplies a fixed fixture literal, never a name discovered from the plan or proxy.
    function _assertCanonicalSeams(address diamond, string memory fixedRecipeName) internal view {
        ExpectedRecipeRoute[] memory routes = RecipeSeamExpectations.forRecipe(fixedRecipeName);
        for (uint256 i; i < routes.length; ++i) {
            ExpectedRecipeRoute memory route = routes[i];
            address expected = _predictedSeamOwner(route.owner);
            if (expected.code.length == 0) revert CanonicalSeamOwnerCodeMissing(route.owner, expected);
            address actual = IDiamondLoupe(diamond).facetAddress(route.selector);
            if (actual == address(0)) {
                revert MissingCanonicalSeam(fixedRecipeName, route.selector, route.owner, expected);
            }
            if (actual != expected) {
                revert WrongCanonicalSeam(fixedRecipeName, route.selector, route.owner, expected, actual);
            }
        }
    }

    /// @dev Inventory supplies creation artifacts, not observed addresses or a recipe's permitted owners.
    function _predictedSeamOwner(string memory owner) internal view returns (address) {
        (string[] memory names, string[] memory artifacts) = FacetInventory.inventory();
        bytes32 key = keccak256(bytes(owner));
        for (uint256 i; i < names.length; ++i) {
            if (keccak256(bytes(names[i])) == key) {
                return ArachnidDeployer.predict(
                    keccak256(abi.encodePacked("lattice.", owner, ".", LatticeVersion.VERSION)),
                    keccak256(SEAM_VM.getCode(artifacts[i]))
                );
            }
        }
        revert UnknownCanonicalSeamOwner(owner);
    }
}

/// @title RecipeSeamOracleTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Covers all 12 seam builders and both ENS entrypoints on initialized factory-deployed proxies.
/// @dev Raw admin cuts deliberately corrupt an otherwise canonical recipe to prove the oracle rejects drift.
contract RecipeSeamOracleTest is ReleasedRecipeGuards, CanonicalRecipeSeamOracle {
    TestnetAsset private _asset;

    function setUp() public {
        _asset = new TestnetAsset("Seam Asset", "SA");
    }

    function test_Canonical_ERC4626() public {
        (FacetCut[] memory cuts, address init, bytes memory data) =
            new DeployERC4626().buildCuts(address(_asset), "Seam Vault", "SV", 0);
        _assertFixture(_assemble(cuts, init, data), "DeployERC4626", 1);
    }

    function test_Canonical_VaultCore() public {
        (FacetCut[] memory cuts, address init, bytes memory data) =
            new DeployVaultCore().buildCuts(address(_asset), "Seam Vault", "SV", ADMIN, 0);
        _assertFixture(_assemble(cuts, init, data), "DeployVaultCore", 8);
    }

    function test_Canonical_ERC20Wrapper() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC20Wrapper().buildCuts("Seam Token", "ST", address(_asset));
        _assertFixture(_assembleMulti(cuts, inits, data), "DeployERC20Wrapper", 1);
    }

    function test_Canonical_ERC20Pausable() public {
        _assertFixture(_pausableProxy(), "DeployERC20Pausable", 2);
    }

    function test_Canonical_ERC20Votes() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC20Votes().buildCuts("Seam Token", "ST", ADMIN);
        _assertFixture(_assembleMulti(cuts, inits, data), "DeployERC20Votes", 4);
    }

    function test_Canonical_ERC721Pausable() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC721Pausable().buildCuts("Seam NFT", "SN", ADMIN);
        _assertFixture(_assembleMulti(cuts, inits, data), "DeployERC721Pausable", 3);
    }

    function test_Canonical_ERC721Votes() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC721Votes().buildCuts("Seam NFT", "SN");
        _assertFixture(_assembleMulti(cuts, inits, data), "DeployERC721Votes", 5);
    }

    function test_Canonical_ERC721Enumerable() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC721Enumerable().buildCuts("Seam NFT", "SN");
        _assertFixture(_assembleMulti(cuts, inits, data), "DeployERC721Enumerable", 3);
    }

    function test_Canonical_ERC721URIStorage() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC721URIStorage().buildCuts("Seam NFT", "SN", ADMIN);
        _assertFixture(_assembleMulti(cuts, inits, data), "DeployERC721URIStorage", 1);
    }

    function test_Canonical_ERC1155URIStorage() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC1155URIStorage().buildCuts("seam://", ADMIN);
        _assertFixture(_assembleMulti(cuts, inits, data), "DeployERC1155URIStorage", 1);
    }

    function test_Canonical_ERC1155Pausable() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC1155Pausable().buildCuts("seam://", ADMIN);
        _assertFixture(_assembleMulti(cuts, inits, data), "DeployERC1155Pausable", 2);
    }

    function test_Canonical_GovernedVault() public {
        vm.warp(1_000_000);
        (FacetCut[] memory cuts, address init, bytes memory data) = new DeployGovernedVault().buildCuts(_vaultParams());
        _assertFixture(_assemble(cuts, init, data), "DeployGovernedVault", 16);
    }

    function test_Canonical_GovernedVaultENSInheritedBase() public {
        vm.warp(1_000_000);
        (FacetCut[] memory cuts, address init, bytes memory data) =
            new DeployGovernedVaultENS().buildCuts(_vaultParams());
        _assertFixture(_assemble(cuts, init, data), "DeployGovernedVaultENS", 16);
    }

    function test_Canonical_GovernedVaultENS() public {
        vm.warp(1_000_000);
        GovernedVaultENSParams memory p;
        p.vault = _vaultParams();
        // This routing fixture skips the optional inline ENS claim; ENS behavior has its own tests.
        p.reverseRegistrar = address(0xE115);
        (FacetCut[] memory cuts, address init, bytes memory data) = new DeployGovernedVaultENS().buildCutsWithENS(p);
        _assertFixture(_assemble(cuts, init, data), "DeployGovernedVaultENS", 16);
    }

    function test_OracleRejectsWrongOwnerAfterAuthorizedRawCut() public {
        address diamond = _pausableProxy();
        _assertFixture(diamond, "DeployERC20Pausable", 2);
        address expected = _predictedSeamOwner("ERC20Pausable");
        address wrong = _predictedSeamOwner("ERC20");
        assertEq(IDiamondLoupe(diamond).facetAddress(IERC20.balanceOf.selector), wrong, "plain ERC20 is installed");
        assertTrue(wrong != expected, "distinct released implementations");

        _rawAdminCut(diamond, FacetCutAction.Replace, wrong, IERC20.transfer.selector);
        assertEq(IDiamondLoupe(diamond).facetAddress(IERC20.transfer.selector), wrong, "raw cut changed owner");
        assertEq(IDiamondLoupe(diamond).facetAddress(IERC20.transferFrom.selector), expected, "other seam is intact");

        vm.expectRevert(
            abi.encodeWithSelector(
                WrongCanonicalSeam.selector,
                "DeployERC20Pausable",
                IERC20.transfer.selector,
                "ERC20Pausable",
                expected,
                wrong
            )
        );
        this.assertCanonicalSeams(diamond, "DeployERC20Pausable");
    }

    function test_OracleRejectsMissingRouteAfterAuthorizedRawCut() public {
        address diamond = _pausableProxy();
        _assertFixture(diamond, "DeployERC20Pausable", 2);
        address expected = _predictedSeamOwner("ERC20Pausable");

        _rawAdminCut(diamond, FacetCutAction.Remove, address(0), IERC20.transfer.selector);
        assertEq(IDiamondLoupe(diamond).facetAddress(IERC20.transfer.selector), address(0), "raw cut removed route");
        assertEq(IDiamondLoupe(diamond).facetAddress(IERC20.transferFrom.selector), expected, "other seam is intact");

        vm.expectRevert(
            abi.encodeWithSelector(
                MissingCanonicalSeam.selector,
                "DeployERC20Pausable",
                IERC20.transfer.selector,
                "ERC20Pausable",
                expected
            )
        );
        this.assertCanonicalSeams(diamond, "DeployERC20Pausable");
    }

    /// @dev External boundary lets negative tests require the exact oracle error after a successful raw cut.
    function assertCanonicalSeams(address diamond, string memory fixedRecipeName) external view {
        _assertCanonicalSeams(diamond, fixedRecipeName);
    }

    function _assertFixture(address diamond, string memory recipe, uint256 count) private view {
        assertEq(RecipeSeamExpectations.forRecipe(recipe).length, count, "fixed seam count");
        _assertCanonicalSeams(diamond, recipe);
    }

    function _pausableProxy() private returns (address) {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC20Pausable().buildCuts("Seam Token", "ST", ADMIN);
        return _assembleMulti(cuts, inits, data);
    }

    function _rawAdminCut(address diamond, FacetCutAction action, address facet, bytes4 selector) private {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: facet, action: action, functionSelectors: selectors});
        vm.prank(ADMIN);
        IAccessControlDiamondCut(diamond).diamondCut(cuts, address(0), "");
    }

    function _vaultParams() private view returns (GovernedVaultParams memory p) {
        p.asset = address(_asset);
        p.name = "Seam Vault";
        p.symbol = "SV";
        p.minDelay = 300;
        p.votingDelay = 60;
        p.votingPeriod = 600;
        p.quorumNumerator = 4;
    }
}
