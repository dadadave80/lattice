// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
pragma abicoder v1;

import {V3SpokePoolInterface} from "@lattice/interfaces/external/across/V3SpokePoolInterface.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title MockSpokePool
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test fixture implementing the vendored {V3SpokePoolInterface}: records every `deposit` arg verbatim
///         plus the allowance it was granted; optionally pulls the input amount (as the real SpokePool does) so
///         the adapter's balance settles to 0 (no-token-stuck).
/// @dev Lives in its own file under `pragma abicoder v1`: the ABI-coder-v2 calldata decoder for a 12-parameter
///      external function is stack-too-deep under the repo's legacy (non-via-ir) codegen pipeline — which is
///      exactly why the adapter under test takes a single `DepositParams` struct instead. The v1 decoder (no
///      validation temporaries) fits. Nothing here needs v2 features (no structs/nested dynamic types cross
///      the mock's ABI).
contract MockSpokePool is V3SpokePoolInterface {
    bytes32 public lastDepositor;
    bytes32 public lastRecipient;
    bytes32 public lastInputToken;
    bytes32 public lastOutputToken;
    uint256 public lastInputAmount;
    uint256 public lastOutputAmount;
    uint256 public lastDestinationChainId;
    bytes32 public lastExclusiveRelayer;
    uint32 public lastQuoteTimestamp;
    uint32 public lastFillDeadline;
    uint32 public lastExclusivityParameter;
    bytes public lastMessage;
    uint256 public allowanceSeen;
    uint256 public calls;
    bool public pullFunds = true;

    function setPullFunds(bool p) external {
        pullFunds = p;
    }

    function deposit(
        bytes32 depositor,
        bytes32 recipient,
        bytes32 inputToken,
        bytes32 outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        bytes32 exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityParameter,
        bytes memory message
    ) external payable {
        address token = address(uint160(uint256(inputToken)));
        allowanceSeen = IERC20(token).allowance(msg.sender, address(this));
        lastDepositor = depositor;
        lastRecipient = recipient;
        lastInputToken = inputToken;
        lastOutputToken = outputToken;
        lastInputAmount = inputAmount;
        lastOutputAmount = outputAmount;
        lastDestinationChainId = destinationChainId;
        lastExclusiveRelayer = exclusiveRelayer;
        lastQuoteTimestamp = quoteTimestamp;
        lastFillDeadline = fillDeadline;
        lastExclusivityParameter = exclusivityParameter;
        lastMessage = message;
        ++calls;
        if (pullFunds) IERC20(token).transferFrom(msg.sender, address(this), inputAmount);
    }
}
