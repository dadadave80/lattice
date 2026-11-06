// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC3643TestBase} from "@lattice-test/base/ERC3643TestBase.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {IAgentRole} from "@lattice/interfaces/tokens/erc3643/IAgentRole.sol";
import {Vm} from "forge-std/Vm.sol";

contract ERC3643TokenEventsTest is ERC3643TestBase {
    function _wallet(address wallet) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(wallet)));
    }

    function test_AgentEventsUseTheStandardIndexedAgent() public {
        vm.recordLogs();
        IAgentRole(diamond).addAgent(carol);
        IAgentRole(diamond).removeAgent(carol);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Reused AccessControl bookkeeping also emits RoleGranted/RoleRevoked; standard events are final.
        uint256 found;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics[0] == keccak256("AgentAdded(address)")
                    || logs[i].topics[0] == keccak256("AgentRemoved(address)")
            ) {
                assertEq(logs[i].emitter, diamond);
                assertEq(logs[i].topics.length, 2);
                assertEq(logs[i].topics[1], _wallet(carol));
                assertEq(logs[i].data.length, 0);
                assertEq(
                    logs[i].topics[0],
                    found == 0 ? keccak256("AgentAdded(address)") : keccak256("AgentRemoved(address)")
                );
                ++found;
            }
        }
        assertEq(found, 2);
    }

    function test_TokenInformationUsesCC0DynamicIndexedFields() public {
        vm.recordLogs();
        token.setName("Revised");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, diamond);
        assertEq(logs[0].topics.length, 4);
        assertEq(logs[0].topics[0], keccak256("UpdatedTokenInformation(string,string,uint8,string,address)"));
        assertEq(logs[0].topics[1], keccak256("Revised"));
        assertEq(logs[0].topics[2], keccak256("PERM"));
        assertEq(logs[0].topics[3], bytes32(0));
        (uint8 decimals_, string memory version_) = abi.decode(logs[0].data, (uint8, string));
        assertEq(decimals_, 6);
        assertEq(version_, LatticeVersion.VERSION);
    }

    function test_PauseEventsHaveUnindexedOriginalAgent() public {
        vm.recordLogs();
        token.pause();
        token.unpause();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].topics.length, 1);
        assertEq(logs[0].topics[0], keccak256("Paused(address)"));
        assertEq(logs[1].topics[0], keccak256("Unpaused(address)"));
        assertEq(abi.decode(logs[0].data, (address)), address(this));
        assertEq(abi.decode(logs[1].data, (address)), address(this));
    }

    function test_FreezeEventsPreserveWalletAmountAndAgentIndexing() public {
        vm.recordLogs();
        token.freezePartialTokens(alice, 50);
        token.unfreezePartialTokens(alice, 10);
        token.setAddressFrozen(alice, true);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 3);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256("TokensFrozen(address,uint256)"));
        assertEq(logs[0].topics[1], _wallet(alice));
        assertEq(abi.decode(logs[0].data, (uint256)), 50);
        assertEq(logs[1].topics[0], keccak256("TokensUnfrozen(address,uint256)"));
        assertEq(abi.decode(logs[1].data, (uint256)), 10);
        assertEq(logs[2].topics.length, 4);
        assertEq(logs[2].topics[0], keccak256("AddressFrozen(address,bool,address)"));
        assertEq(logs[2].topics[1], _wallet(alice));
        assertEq(logs[2].topics[2], bytes32(uint256(1)));
        assertEq(logs[2].topics[3], _wallet(address(this)));
        assertEq(logs[2].data.length, 0);
    }

    function test_DependencyEventsUseIndexedAddresses() public {
        vm.recordLogs();
        token.setIdentityRegistry(diamond);
        token.setCompliance(diamond);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].topics.length, 2);
        assertEq(logs[0].topics[0], keccak256("IdentityRegistryAdded(address)"));
        assertEq(logs[0].topics[1], _wallet(diamond));
        assertEq(logs[1].topics.length, 2);
        assertEq(logs[1].topics[0], keccak256("ComplianceAdded(address)"));
        assertEq(logs[1].topics[1], _wallet(diamond));
    }

    function test_RecoveryEmitsAllThreeIndexedIdentityAddresses() public {
        aliceIdentity.setManagement(carol, true);
        vm.recordLogs();
        token.recoveryAddress(alice, carol, address(aliceIdentity));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory recovered = logs[logs.length - 1];
        assertEq(recovered.emitter, diamond);
        assertEq(recovered.topics.length, 4);
        assertEq(recovered.topics[0], keccak256("RecoverySuccess(address,address,address)"));
        assertEq(recovered.topics[1], _wallet(alice));
        assertEq(recovered.topics[2], _wallet(carol));
        assertEq(recovered.topics[3], _wallet(address(aliceIdentity)));
        assertEq(recovered.data.length, 0);
    }
}
