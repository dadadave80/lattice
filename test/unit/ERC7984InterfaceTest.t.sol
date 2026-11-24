// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC7984, IERC7984Disclosure, IERC7984Receiver} from "@lattice/interfaces/tokens/IERC7984.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Pins the ERC-7984 interface id, event topics and error and helper selectors.
contract ERC7984InterfaceTest is Test {
    function test_InterfaceId_Is0x4958f2a4() public pure {
        assertEq(type(IERC7984).interfaceId, bytes4(0x4958f2a4));
    }

    function test_Events_MatchErcTopics() public pure {
        assertEq(
            IERC7984.ConfidentialTransfer.selector, 0x67500e8d0ed826d2194f514dd0d8124f35648ab6e3fb5e6ed867134cffe661e9
        );
        assertEq(IERC7984.AmountDisclosed.selector, 0x83bbbc07896439e5d950a6cead04cbc676180af7a61cecf43f5296475057f571);
        assertEq(IERC7984.OperatorSet.selector, 0x921a218a75d18e8ec5704851e6b234a85725b21a2521ce889622c35dedc1fa12);
        assertEq(
            IERC7984Disclosure.AmountDiscloseRequested.selector,
            0x189c3bfae2e5ce7726b29d57bb6ed0f1a7ebcd153a863ff5ecb6cd998064c98c
        );
    }

    function test_DisclosureAndReceiverSelectors() public pure {
        assertEq(IERC7984Disclosure.requestDiscloseEncryptedAmount.selector, bytes4(0xd8061806));
        assertEq(IERC7984Disclosure.discloseEncryptedAmount.selector, bytes4(0xb1af281e));
        assertEq(IERC7984Receiver.onConfidentialTransferReceived.selector, bytes4(0x46083bfd));
    }

    function test_ErrorSelectors() public pure {
        assertEq(IERC7984.ERC7984InvalidReceiver.selector, bytes4(0x8d518801));
        assertEq(IERC7984.ERC7984InvalidSender.selector, bytes4(0xee457ebf));
        assertEq(IERC7984.ERC7984UnauthorizedSpender.selector, bytes4(0x79f2cb38));
        assertEq(IERC7984.ERC7984UnauthorizedUseOfEncryptedAmount.selector, bytes4(0x67cfe805));
        assertEq(IERC7984.ERC7984UnauthorizedCaller.selector, bytes4(0x782c6ffd));
        assertEq(IERC7984.ERC7984UtilsUnauthorizedUseOfEncryptedAmount.selector, bytes4(0x4ae3cfa9));
        assertEq(IERC7984.ERC7984DiamondCallerInstalled.selector, bytes4(0x9752f36d));
        assertEq(IERC7984.ERC7984DelegatedHost.selector, bytes4(0xe5f852be));
        assertEq(IERC7984.ERC7984NotInitialized.selector, bytes4(0x67f40659));
    }
}
