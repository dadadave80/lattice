// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {GovernedVaultENSInit, GovernedVaultENSParams} from "@lattice/defi/GovernedVaultENSInit.sol";
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {console} from "forge-std/Script.sol";

/// @title TestnetAsset
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice TESTNET-ONLY open-faucet ERC-20 — anyone may `mint` themselves balance. Deployed by
///         {DeployGovernedVaultENS.run} as the vault's underlying when no real asset is supplied, so the
///         Sepolia dogfooding loop (mint → approve → deposit → vote) needs no external token. NEVER deploy
///         this to a mainnet: the open faucet makes every balance worthless by construction.
contract TestnetAsset is IERC20 {
    string private _name;
    string private _symbol;

    /// @inheritdoc IERC20
    mapping(address account => uint256 balance) public balanceOf;
    /// @inheritdoc IERC20
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;
    /// @inheritdoc IERC20
    uint256 public totalSupply;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /// @inheritdoc IERC20
    function name() external view returns (string memory) {
        return _name;
    }

    /// @inheritdoc IERC20
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /// @inheritdoc IERC20
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @notice Open faucet: mints `amount` to `to`, no gate whatsoever (TESTNET-ONLY by design).
    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    /// @inheritdoc IERC20
    function approve(address spender, uint256 value) external returns (bool success) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        success = true;
    }

    /// @inheritdoc IERC20
    function transfer(address to, uint256 value) external returns (bool success) {
        uint256 balance = balanceOf[msg.sender];
        if (balance < value) revert ERC20InsufficientBalance(msg.sender, balance, value);
        balanceOf[msg.sender] = balance - value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        success = true;
    }

    /// @inheritdoc IERC20
    function transferFrom(address from, address to, uint256 value) external returns (bool success) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < value) revert ERC20InsufficientAllowance(msg.sender, allowed, value);
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - value;
        uint256 balance = balanceOf[from];
        if (balance < value) revert ERC20InsufficientBalance(from, balance, value);
        balanceOf[from] = balance - value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        success = true;
    }
}

/// @title DeployGovernedVaultENS
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for the ENS-NAMED self-governed ERC-4626 vault: the {DeployGovernedVault}
///         13-cut diamond plus the {ENSReverseClaimer} facet, initialized in ONE shot by
///         {GovernedVaultENSInit} — the vault claims its primary ENS name at init (the registrar sees the
///         diamond as `msg.sender`), and every future rename passes through share-holder governance
///         (`ENS_MANAGER_ROLE` is held by the diamond only).
/// @dev SANE SEPOLIA TESTNET DEFAULTS for `GovernedVaultParams` (the {VotesLib} clock is
///      `mode=timestamp`, so `votingDelay`/`votingPeriod` are SECONDS, not blocks):
///      - `asset`             `address(0)` → {run} deploys a fresh {TestnetAsset} faucet as the underlying
///      - `decimalsOffset`    0
///      - `minDelay`          300  (5-minute timelock)
///      - `votingDelay`       60   (1 minute before voting opens)
///      - `votingPeriod`      600  (10-minute voting window)
///      - `proposalThreshold` 0    (any share-holder may propose)
///      - `quorumNumerator`   4    (4% of supply)
///      `reverseRegistrar` on Sepolia is the ENS `ReverseRegistrar`
///      `0xA0a1AbcDAe1a2a4A2EF8e9113Ff0e02DD81DC0C6` (ensdomains/ens-contracts deployments/sepolia).
contract DeployGovernedVaultENS is DeployGovernedVault {
    /// @notice Builds the 14 cuts + combined initializer for the ENS-named self-governed vault (no broadcast,
    ///         no proxy deploy): the inherited 13 base cuts plus the {ENSReverseClaimer} facet, initialized by
    ///         the combined {GovernedVaultENSInit} (which replays the base init sequence exactly).
    function buildCutsWithENS(GovernedVaultENSParams memory p)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        FacetCut[] memory baseCuts = _buildBaseCuts();
        cuts = new FacetCut[](baseCuts.length + 1);
        for (uint256 i; i < baseCuts.length; ++i) {
            cuts[i] = baseCuts[i];
        }
        cuts[baseCuts.length] = _cut(address(new ENSReverseClaimer()));

        init = address(new GovernedVaultENSInit());
        initCalldata = abi.encodeCall(GovernedVaultENSInit.init, (p));
    }

    /// @notice Deploys the ENS-named self-governed vault diamond (broadcasting entrypoint for
    ///         `forge script ... --broadcast`). A zero `p.vault.asset` deploys a fresh {TestnetAsset} faucet
    ///         as the underlying (Sepolia dogfooding).
    function run(GovernedVaultENSParams memory p) external returns (address vault) {
        vm.startBroadcast();
        if (p.vault.asset == address(0)) {
            p.vault.asset = address(new TestnetAsset("Lattice Testnet Asset", "tLAT"));
            console.log("TestnetAsset (open faucet) deployed as underlying:", p.vault.asset);
        }
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCutsWithENS(p);
        vault = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();

        console.log("GovernedVaultENS diamond:", vault);
        console.log("  underlying asset:      ", p.vault.asset);
        console.log("  reverse registrar:     ", p.reverseRegistrar);
        console.log("  init (one-shot):       ", init);
        console.log("  claimed ENS name:      ", p.ensName);
        for (uint256 i; i < cuts.length; ++i) {
            console.log("  facet cut:", i, cuts[i].facetAddress);
        }
        console.log("NEXT STEPS:");
        console.log(" 1. The vault's REVERSE record (vault -> name) is already claimed. For the name to show as");
        console.log("    the vault's primary name, point the FORWARD record (name -> vault) at the diamond:");
        console.log("    set the name's addr record to the diamond via https://sepolia.app.ens.domains, or:");
        console.log("    cast send <PublicResolver> 'setAddr(bytes32,address)' <namehash(name)> <diamond>");
        console.log("    (Sepolia PublicResolver: 0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5)");
        console.log(" 2. Dogfood: mint TestnetAsset, approve the vault, deposit, delegate, propose.");
        console.log(" 3. Rename later via governance: propose setEnsName(newName) targeting the diamond.");
    }
}
