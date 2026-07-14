// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IETHRegistrarController} from "@lattice/interfaces/external/IETHRegistrarController.sol";
import {Script, console} from "forge-std/Script.sol";

/// @title RegisterEnsName
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Registers a fresh `.eth` second-level name on SEPOLIA through the LIVE ENS
///         `ETHRegistrarController` in ONE transaction. The live controller generation (Namechain-era
///         "premigration") has NO commit/reveal and NO `rentPrice` view: it prices internally from
///         `msg.value` and refunds the excess, so this script sends a conservative fixed value. The
///         registration carries NO resolver/data (this generation is not trusted by the deployed
///         `PublicResolver`, so in-registration record writes revert — the proven live pattern registers
///         bare and wires records afterwards, which suits the vault flow anyway: the forward record should
///         point at the DIAMOND, deployed later) and NO reverse record (`reverseRecord = 0`: the controller
///         would name the BROADCASTING EOA, while the vault diamond claims its own reverse record at init
///         through {GovernedVaultENSInit}).
/// @dev RUNBOOK — registering `myvault.eth` for `$OWNER` (the label is the SECOND-LEVEL label only,
///      "myvault" not "myvault.eth", ≥3 characters; runs for 1 year, upstream minimum 28 days):
///
///        1. forge script script/config/RegisterEnsName.s.sol --rpc-url sepolia --account <name> --broadcast \
///             --sig "register(string,address)" "myvault" $OWNER
///        2. Deploy the vault diamond (DeployGovernedVaultENS) with ensName "myvault.eth".
///        3. Wire the FORWARD record (name -> diamond) as the owner — two calls:
///             cast send 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e \
///               "setResolver(bytes32,address)" $(cast namehash myvault.eth) \
///               0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5 --rpc-url sepolia --account <name>
///             cast send 0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5 \
///               "setAddr(bytes32,address)" $(cast namehash myvault.eth) <diamond> \
///               --rpc-url sepolia --account <name>
///           (or both via https://sepolia.app.ens.domains). The diamond's reverse record is already claimed
///           at init, so once the forward record lands the name is the vault's PRIMARY name.
///
///      Step 1 sends 0.01 ETH; the controller consumes the actual rent (~0.003 ETH/year for a 5+ char name
///      at the current Sepolia oracle price) and refunds the rest in the same transaction. NOTE: without
///      commit/reveal this flow is front-runnable — acceptable on a testnet; re-check the live controller
///      generation before reusing on mainnet.
contract RegisterEnsName is Script {
    //*//////////////////////////////////////////////////////////////////////////
    //                       VERIFIED SEPOLIA ADDRESSES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ENS .eth registrar controller — the LIVE controller authorized on the Sepolia BaseRegistrar
    ///         (`controllers(0xdf60...) == true`, verified on-chain; e.g. successful `register` tx
    ///         0x2dcd461f2e001670319d9ccf50814d724d166736fab2b50d671efd6dae8cc0be, block 11229975). NOTE the
    ///         ens-contracts `deployments/sepolia/ETHRegistrarController.json` artifact
    ///         (0xfb3cE5D01e0f33f41DbB39035dB9745962F1f968) carries the SAME ABI but is NOT authorized on the
    ///         BaseRegistrar — registering through it reverts.
    address internal constant SEPOLIA_ETH_REGISTRAR_CONTROLLER = 0xdf60C561Ca35AD3C89D24BbA854654b1c3477078;

    /// @notice ENS public resolver (ensdomains/ens-contracts deployments/sepolia/PublicResolver.json).
    address internal constant SEPOLIA_PUBLIC_RESOLVER = 0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5;

    /// @dev `namehash("eth")` = `keccak256(abi.encodePacked(bytes32(0), keccak256("eth")))` (upstream `ETH_NODE`).
    bytes32 internal constant ETH_NODE = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;

    /// @notice Registration duration: 1 year (upstream minimum is 28 days).
    uint256 internal constant REGISTRATION_DURATION = 365 days;

    /// @notice Value sent with the registration; the controller consumes the internally-priced rent and
    ///         refunds the excess in the same transaction (~0.003 ETH/year for a 5+ char name today).
    uint256 internal constant REGISTRATION_VALUE = 0.01 ether;

    //*//////////////////////////////////////////////////////////////////////////
    //                                 REGISTER
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers `label`.eth to `owner` for 1 year in one transaction; excess value is refunded.
    ///         Records are wired AFTERWARDS by the owner (see the contract runbook) — the forward record
    ///         should point at the vault diamond, which is deployed after the name exists.
    /// @param label The second-level label ("myvault" for myvault.eth).
    /// @param owner The registrant (the name's ENS-registry owner).
    function register(string calldata label, address owner) external {
        IETHRegistrarController controller = IETHRegistrarController(SEPOLIA_ETH_REGISTRAR_CONTROLLER);

        vm.startBroadcast();
        controller.register{value: REGISTRATION_VALUE}(_registration(label, owner));
        vm.stopBroadcast();

        console.log("Registered %s.eth to %s for 1 year", label, owner);
        console.log("  sent (excess refunded by the controller):", REGISTRATION_VALUE);
        console.log("NEXT: deploy the vault (DeployGovernedVaultENS) with ensName '%s.eth', then as the owner", label);
        console.log("wire the forward record at the diamond (see the runbook in this file):");
        console.log("  1. registry.setResolver(namehash, PublicResolver 0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5)");
        console.log("  2. resolver.setAddr(namehash, <diamond>)");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Builds the `Registration` matching the proven live pattern: NO resolver and NO data (the live
    ///      controller generation is not trusted by the deployed `PublicResolver`, so in-registration record
    ///      writes revert — records are wired by the owner afterwards), NO reverse record (it would name the
    ///      broadcasting EOA, not the vault), zero legacy secret (no commit/reveal in this generation), no
    ///      referrer.
    function _registration(string calldata label, address owner)
        internal
        pure
        returns (IETHRegistrarController.Registration memory registration)
    {
        registration = IETHRegistrarController.Registration({
            label: label,
            owner: owner,
            duration: REGISTRATION_DURATION,
            secret: bytes32(0),
            resolver: address(0),
            data: new bytes[](0),
            reverseRecord: 0,
            referrer: bytes32(0)
        });
    }
}
