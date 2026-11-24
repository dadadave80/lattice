// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC7984ForkBase, IVersioned} from "@lattice-test/fork/ERC7984SepoliaFork.t.sol";

contract ERC7984MainnetFork is ERC7984ForkBase {
    function setUp() public {
        _selectFork("MAINNET_RPC_URL", "mainnet", 26468149);
    }

    function test_Fork_HostVersionsMatchHarness() public view {
        assertEq(IVersioned(cfg.acl).getVersion(), "ACL v0.4.0");
        assertEq(IVersioned(cfg.executor).getVersion(), "FHEVMExecutor v0.5.0");
    }
}
