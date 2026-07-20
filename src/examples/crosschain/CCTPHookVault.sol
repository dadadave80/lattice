// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {ICCTPHookReceiver} from "@lattice/interfaces/crosschain/ICCTPHookReceiver.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title CCTPHookVault
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Example CCTP v2 hook receiver: an auto-credit USDC vault. When USDC is bridged to this vault with a
///         Lattice hook envelope, the source diamond's {CCTPHookExecutor} calls {onCCTPHook} AFTER the mint and
///         the vault books the freshly-minted `amount` to the beneficiary encoded in `payload` — a "programmable
///         USDC" primitive where ONE attested cross-chain message both MOVES funds and CREDITS an account. The
///         beneficiary later {withdraw}s their booked balance.
/// @dev SECURITY MODEL. Two invariants keep the vault solvent (booked credits are always backed 1:1 by USDC the
///      vault actually holds):
///      1. AUTHENTICITY — {onCCTPHook} accepts calls ONLY from `executor`, the per-diamond, role-less, fund-less
///         {CCTPHookExecutor} that fires solely on a real Iris-attested burn addressed to its diamond.
///      2. BACKING — it requires the attested `mintRecipient` to be THIS vault, so the `amount` credited is USDC
///         that was just minted here (the interface warns targets MUST NOT assume the mint went to them: an
///         attacker may set the hook `target` to this vault while minting the USDC elsewhere).
///      `amount` is the attested NET-MINTED value (burn amount minus attested feeExecuted), so a credit equals
///      USDC received. `payload` is attacker-controlled, but it selects only WHO is credited — never HOW MUCH
///      (that comes from the attested mint) — so a hostile payload can at worst mis-address a credit it also
///      funded. A revert here is swallowed by the executor (the mint stands, the CCTP nonce is consumed).
///      TESTNET SHOWCASE contract; not audited.
/// @custom:security-contact daveproxy80@gmail.com
contract CCTPHookVault is ICCTPHookReceiver {
    /// @notice The source diamond's {CCTPHookExecutor} — the ONLY authorized caller of {onCCTPHook}.
    address public immutable executor;

    /// @notice The USDC minted into this vault (e.g. Base Sepolia USDC in the showcase).
    address public immutable usdc;

    /// @notice USDC booked to each beneficiary, withdrawable by them.
    mapping(address beneficiary => uint256 amount) public creditOf;

    /// @notice Total USDC booked across all beneficiaries (== the USDC this vault holds against credits).
    uint256 public totalCredited;

    event Credited(address indexed beneficiary, uint256 amount, uint32 sourceDomain, bytes32 sender);
    event Withdrawn(address indexed beneficiary, uint256 amount);

    error CCTPHookVault__ZeroAddress();
    error CCTPHookVault__NotExecutor();
    error CCTPHookVault__NotMintRecipient();
    error CCTPHookVault__BadPayload();
    error CCTPHookVault__InsufficientCredit();

    /// @param executor_ The diamond's {CCTPHookExecutor} (read from `ICCTPBridgeAdapter.hookExecutor()`).
    /// @param usdc_ The destination-chain USDC that CCTP mints into this vault.
    constructor(address executor_, address usdc_) {
        if (executor_ == address(0) || usdc_ == address(0)) revert CCTPHookVault__ZeroAddress();
        executor = executor_;
        usdc = usdc_;
    }

    /// @inheritdoc ICCTPHookReceiver
    /// @dev Books `amount` (attested net-minted USDC) to the beneficiary in the first 20 bytes of `payload`.
    function onCCTPHook(
        uint32 sourceDomain,
        bytes32 sender,
        bytes32 mintRecipient,
        uint256 amount,
        bytes calldata payload
    ) external {
        if (msg.sender != executor) revert CCTPHookVault__NotExecutor();
        // BACKING invariant: the USDC must have been minted to THIS vault, or the credit would be unbacked.
        if (mintRecipient != bytes32(uint256(uint160(address(this))))) revert CCTPHookVault__NotMintRecipient();
        if (payload.length < 20) revert CCTPHookVault__BadPayload();

        address beneficiary = address(bytes20(payload[0:20]));
        creditOf[beneficiary] += amount;
        totalCredited += amount;
        emit Credited(beneficiary, amount, sourceDomain, sender);
    }

    /// @notice Withdraw `amount` of the caller's booked USDC to the caller (checks-effects-interactions).
    function withdraw(uint256 amount) external {
        uint256 credit = creditOf[msg.sender];
        if (amount > credit) revert CCTPHookVault__InsufficientCredit();
        unchecked {
            creditOf[msg.sender] = credit - amount; // amount <= credit
            totalCredited -= amount; // totalCredited >= credit >= amount
        }
        BridgeFungibleLib.safeTransfer(usdc, msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }
}
