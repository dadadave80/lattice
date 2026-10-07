// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IReceiverV2} from "@lattice/interfaces/external/circle/IReceiverV2.sol";

/// @notice The mint hook of a test USDC (every in-repo test MockUSDC exposes `mint(address,uint256)`).
interface IMintableUSDC {
    function mint(address to, uint256 amount) external;
}

/// @title MockCCTPMessageTransmitter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Circle CCTP v2 (https://github.com/circlefin/evm-cctp-contracts)
/// @notice Test fixture modelling the parts of `MessageTransmitterV2.receiveMessage` the CCTP adapter's safety
///         rests on, without verifying attestations: it enforces the header `destinationCaller` (byte 108; zero
///         = anyone), consumes the header `nonce` (byte 12) exactly once, and mints the NET amount (`amount` at
///         byte 216 minus `feeExecuted` at byte 312) to `mintRecipient` (byte 184). Like Circle's, a failed check
///         reverts.
contract MockCCTPMessageTransmitter is IReceiverV2 {
    address public immutable usdc;

    mapping(bytes32 nonce => bool used) public usedNonces;
    uint256 public calls;

    constructor(address usdc_) {
        usdc = usdc_;
    }

    function receiveMessage(bytes calldata message, bytes calldata) external returns (bool) {
        bytes32 destinationCaller = bytes32(message[108:140]);
        require(
            destinationCaller == bytes32(0) || destinationCaller == bytes32(uint256(uint160(msg.sender))),
            "Invalid caller for message"
        );
        bytes32 nonce = bytes32(message[12:44]);
        require(!usedNonces[nonce], "Nonce already used");
        usedNonces[nonce] = true;
        ++calls;

        address mintRecipient = address(uint160(uint256(bytes32(message[184:216]))));
        uint256 net = uint256(bytes32(message[216:248])) - uint256(bytes32(message[312:344]));
        IMintableUSDC(usdc).mint(mintRecipient, net);
        return true;
    }

    function localDomain() external pure returns (uint32) {
        return 6;
    }
}
