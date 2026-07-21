// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployVaultCore} from "@lattice-script/base/defi/DeployVaultCore.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {IMintableToken} from "@lattice-test/helpers/IMintableToken.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";

/// @title VaultCoreTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for VaultCore facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. VaultCore extends ERC-4626 (whose shares ARE an ERC-20 token): `setUp` assembles the
///         production {DeployVaultCore} recipe (ERC165 + AccessControl + VaultCore, the last exposing every
///         ERC-20 share selector, the ERC-4626 vault selectors, and the strategy-hook selectors via
///         inheritance) over an underlying-asset ERC-20 diamond assembled from {DeployERC20} + a
///         {TokenTestFacet}. Every call routes through the diamond's `delegatecall` dispatch.
/// @dev `admin` is granted `DEFAULT_ADMIN_ROLE` at init, so it — not `msg.sender` of the deploy — governs the
///      strategy manager.
abstract contract VaultCoreTestBase is GetSelectors {
    DeployERC20 internal assetDeployer;
    DeployVaultCore internal vaultDeployer;

    address internal underlyingAddr; // the underlying-asset ERC-20 diamond
    IMintableToken internal underlying; // typed handle on the underlying (mint/approve/transfer/balanceOf)
    address internal vaultAddr; // the assembled VaultCore diamond
    IVaultCore internal vault; // typed handle on the vault (ERC-20 + ERC-4626 + strategy calls dispatch through it)

    address internal admin = address(0xAD);

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

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        token_ = address(d);
    }

    /// @notice Assembles the production VaultCore diamond over `asset_` with `admin_` as the vault admin.
    /// @return vault_ The deployed VaultCore diamond.
    function _deployVault(address asset_, string memory name_, string memory symbol_, address admin_)
        internal
        returns (address vault_)
    {
        vaultDeployer = new DeployVaultCore();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            vaultDeployer.buildCuts(asset_, name_, symbol_, admin_, 0);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        vault_ = address(d);
    }

    function setUp() public virtual {
        underlyingAddr = _deployMintableERC20("Mock Token", "MTK");
        underlying = IMintableToken(underlyingAddr);

        vaultAddr = _deployVault(underlyingAddr, "Vault Share", "vSHARE", admin);
        vault = IVaultCore(vaultAddr);
    }
}
