// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/DeployERC20.s.sol";
import {DeployERC4626} from "@lattice-script/base/DeployERC4626.s.sol";
import {IMintableToken} from "@lattice-test/helpers/IMintableToken.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";

/// @title ERC4626TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-4626 vault facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. The vault's shares ARE an ERC-20 token: `setUp` assembles the production
///         {DeployERC4626} recipe (ERC165 + ERC4626, the latter exposing every ERC-20 share selector via
///         inheritance) over an underlying-asset ERC-20 diamond assembled from {DeployERC20} + a
///         {TokenTestFacet} (for seeding depositor balances). Every standard call in a subclass test routes
///         through the diamond's `delegatecall` dispatch, catching selector/storage/init bugs a mock hides.
/// @dev `_deployVault` is reusable so tests can spin up extra vaults (e.g. a non-zero decimals offset, or a
///      weird underlying token) against the same production recipe.
abstract contract ERC4626TestBase is GetSelectors {
    DeployERC20 internal assetDeployer;
    DeployERC4626 internal vaultDeployer;

    address internal underlyingAddr; // the underlying-asset ERC-20 diamond
    IMintableToken internal underlying; // typed handle on the underlying (mint/approve/transfer/balanceOf)
    address internal vaultAddr; // the assembled ERC-4626 vault diamond
    ERC4626 internal vault; // typed handle on the vault (ERC-20 share calls + vault calls dispatch through it)

    /// @notice Assembles a base ERC-20 diamond + the {TokenTestFacet} so it can be freely minted as a vault asset.
    /// @return token_ The deployed mintable ERC-20 diamond.
    function _deployMintableERC20(string memory name_, string memory symbol_) internal returns (address token_) {
        assetDeployer = new DeployERC20();
        (FacetCut[] memory prod, address init, bytes memory initCalldata) = assetDeployer.buildCuts(name_, symbol_);

        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new TokenTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("TokenTestFacet")
        });

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        token_ = address(d);
    }

    /// @notice Assembles the production ERC-4626 vault diamond over `asset_`.
    /// @return vault_ The deployed vault diamond.
    function _deployVault(address asset_, string memory name_, string memory symbol_, uint8 decimalsOffset_)
        internal
        returns (address vault_)
    {
        vaultDeployer = new DeployERC4626();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            vaultDeployer.buildCuts(asset_, name_, symbol_, decimalsOffset_);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        vault_ = address(d);
    }

    function setUp() public virtual {
        underlyingAddr = _deployMintableERC20("Vault Token", "VTK");
        underlying = IMintableToken(underlyingAddr);

        vaultAddr = _deployVault(underlyingAddr, "Vault Token", "vVTK", 0);
        vault = ERC4626(vaultAddr);
    }
}
