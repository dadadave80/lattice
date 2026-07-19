// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20/ERC20Votes.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                               MOCK ASSET TOKEN
//////////////////////////////////////////////////////////////////////////*//

/// @notice Simple mintable ERC20Votes used as the vault's underlying asset.
contract InvAsset is ERC20, ERC20Votes {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(ERC20, ERC20Votes) returns (bytes memory) {}

    function transfer(address to, uint256 value) public override(ERC20, ERC20Votes) returns (bool) {
        return ERC20Votes.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20, ERC20Votes) returns (bool) {
        return ERC20Votes.transferFrom(from, to, value);
    }

    function initialize(address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init("Inv Asset", "IASSET");
        EIP712Lib.__EIP712_init("Inv Asset", "1");
        NoncesLib.__Nonces_init();
        VotesLib.__Votes_init();
        ERC20VotesLib.__ERC20Votes_init();
        AccessControlLib.__AccessControl_init(admin);
        InitializableLib.postInitializer(s);
    }

    function mint(address to, uint256 amount) external {
        ERC20VotesLib._mint(to, amount);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                MOCK VAULT
//////////////////////////////////////////////////////////////////////////*//

/// @notice ERC4626 vault for invariant testing. Flattens the composable {ERC20} share facet and the {ERC4626}
///         vault facet into one mock; `decimals` is disambiguated to the ERC-4626 share-offset variant.
contract InvVault is ERC20, ERC4626 {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(ERC20, ERC4626) returns (bytes memory) {}

    function initialize(address asset_) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init("Inv Vault", "IVAULT");
        ERC4626Lib.__ERC4626_init(asset_, 0);
        AccessControlLib.__AccessControl_init(msg.sender);
        InitializableLib.postInitializer(s);
    }

    /// @dev Resolves the `decimals()` clash between the flattened {ERC20} and {ERC4626} facets.
    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Handler that exercises deposit, mint, withdraw, redeem, and donate.
contract ERC4626RoundTripHandler is Test {
    InvAsset public asset;
    InvVault public vault;

    address[3] public actors;
    uint256 constant MAX_AMOUNT = 1_000e18;
    uint256 constant INITIAL_MINT = 100_000e18;

    constructor(InvAsset asset_, InvVault vault_) {
        asset = asset_;
        vault = vault_;

        actors[0] = address(0xB1);
        actors[1] = address(0xB2);
        actors[2] = address(0xB3);

        // Pre-mint and pre-approve for each actor.
        for (uint256 i; i < actors.length; ++i) {
            asset.mint(actors[i], INITIAL_MINT);
            vm.prank(actors[i]);
            asset.approve(address(vault), type(uint256).max);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function deposit(uint256 actorSeed, uint256 assets) external {
        address actor = _actor(actorSeed);
        uint256 bal = asset.balanceOf(actor);
        if (bal == 0) return;
        assets = bound(assets, 1, bal);
        vm.prank(actor);
        vault.deposit(assets, actor);
    }

    function mint(uint256 actorSeed, uint256 shares) external {
        address actor = _actor(actorSeed);
        uint256 bal = asset.balanceOf(actor);
        if (bal == 0) return;
        uint256 maxShares = vault.previewDeposit(bal);
        if (maxShares == 0) return;
        shares = bound(shares, 1, maxShares);
        vm.prank(actor);
        vault.mint(shares, actor);
    }

    function withdraw(uint256 actorSeed, uint256 assets) external {
        address actor = _actor(actorSeed);
        uint256 maxWithdraw = vault.maxWithdraw(actor);
        if (maxWithdraw == 0) return;
        assets = bound(assets, 1, maxWithdraw);
        vm.prank(actor);
        vault.withdraw(assets, actor, actor);
    }

    function redeem(uint256 actorSeed, uint256 shares) external {
        address actor = _actor(actorSeed);
        uint256 maxRedeem = vault.maxRedeem(actor);
        if (maxRedeem == 0) return;
        shares = bound(shares, 1, maxRedeem);
        vm.prank(actor);
        vault.redeem(shares, actor, actor);
    }

    /// @notice Donate assets directly to the vault (simulates yield).
    function donate(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        uint256 bal = asset.balanceOf(actor);
        if (bal == 0) return;
        amount = bound(amount, 1, bal / 10 + 1); // donate at most 10% of balance
        vm.prank(actor);
        asset.transfer(address(vault), amount);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title ERC4626RoundTripInvariant
/// @notice Invariant: ERC-4626 round-trip conversions must not create value from nothing.
contract ERC4626RoundTripInvariant is Test {
    InvAsset internal asset;
    InvVault internal vault;
    ERC4626RoundTripHandler internal handler;

    address admin = address(0xAD);

    function setUp() public {
        asset = new InvAsset();
        asset.initialize(admin);

        vault = new InvVault();
        vault.initialize(address(asset));

        handler = new ERC4626RoundTripHandler(asset, vault);
        targetContract(address(handler));
    }

    /// @notice previewDeposit(previewMint(s)) >= s — you never get more shares minting than depositing.
    function invariant_RoundTripDepositMint() public view {
        if (vault.totalSupply() == 0) return; // skip empty vault (trivially true)
        uint256 s = 1e18;
        // previewMint(s) = assets needed to get s shares
        uint256 assets = vault.previewMint(s);
        if (assets == 0) return;
        // previewDeposit(assets) = shares you'd get for those assets
        uint256 sharesBack = vault.previewDeposit(assets);
        // Round-trip: sharesBack >= s (depositing the required assets gives AT LEAST s shares)
        assertGe(sharesBack, s, "round-trip: previewDeposit(previewMint(s)) < s");
    }

    /// @notice convertToShares(convertToAssets(s)) <= s — converting to assets and back never inflates shares.
    function invariant_ConvertRoundTripNoFreeShares() public view {
        if (vault.totalSupply() == 0) return;
        uint256 s = 1e18;
        uint256 assets = vault.convertToAssets(s);
        if (assets == 0) return;
        uint256 sharesBack = vault.convertToShares(assets);
        assertLe(sharesBack, s, "convertToShares(convertToAssets(s)) > s");
    }

    /// @notice totalAssets() must equal (or exceed, due to donations) the vault's asset balance.
    function invariant_TotalAssetsConsistent() public view {
        uint256 vaultBalance = asset.balanceOf(address(vault));
        assertEq(vault.totalAssets(), vaultBalance, "totalAssets != vault asset balance");
    }
}
