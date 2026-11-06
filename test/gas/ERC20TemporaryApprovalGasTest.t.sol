// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TemporaryApprovalActor as Actor} from "@lattice-test/helpers/TemporaryApprovalActor.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20TemporaryApprovalLib} from "@lattice/tokens/ERC20/libraries/ERC20TemporaryApprovalLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @title GasTemporaryToken
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Identical runtime/ABI for base and registered-interface measurements, avoiding dispatcher confounding.
contract GasTemporaryToken is ERC20, Initializable {
    function initialize(bool registerTemporaryInterface, address owner) external initializer {
        ERC20Lib.__ERC20_init("Gas", "GAS");
        if (registerTemporaryInterface) ERC20TemporaryApprovalLib.__ERC20TemporaryApproval_init();
        ERC20Lib._mint(owner, 1000);
    }

    function temporaryApprove(address spender, uint256 value) external returns (bool) {
        return ERC20TemporaryApprovalLib.temporaryApprove(spender, value);
    }
}

/// @title GasTemporarySpender
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Snapshot a token call nested in the same transaction as a temporary grant.
contract GasTemporarySpender is Test {
    function spend(GasTemporaryToken token, address owner, string calldata label) external {
        vm.startSnapshotGas("ERC20TemporaryApproval", label);
        token.transferFrom(owner, address(0xB0B), 10);
        vm.stopSnapshotGas();
    }
}

/// @notice Cold persistent cases differ only in ERC-165 registration. They use identical runtime allowance code.
///         Temporary cases follow a same-tx grant, warming the token address; their snapshots exclude the
///         grant and batch/actor dispatch costs. No persistent activation flag exists.
/// forge-config: default.isolate = true
contract ERC20TemporaryApprovalGasTest is Test {
    GasTemporaryToken registered;
    GasTemporaryToken baseOnly;
    Actor owner;
    GasTemporarySpender spender;

    function setUp() public {
        owner = new Actor();
        spender = new GasTemporarySpender();
        registered = new GasTemporaryToken();
        registered.initialize(true, address(owner));
        baseOnly = new GasTemporaryToken();
        baseOnly.initialize(false, address(owner));
    }

    function _approve(GasTemporaryToken token, uint256 amount) internal {
        Actor.Action[] memory actions = new Actor.Action[](1);
        actions[0] = Actor.Action(address(token), abi.encodeCall(ERC20.approve, (address(spender), amount)), false);
        owner.run(actions);
    }

    function test_Gas_BasePersistent() public {
        _approve(baseOnly, 20);
        spender.spend(baseOnly, address(owner), "basePersistentCold");
    }

    function test_Gas_RegisteredPersistent() public {
        _approve(registered, 20);
        spender.spend(registered, address(owner), "registeredPersistentCold");
    }

    function test_Gas_TemporaryCovered() public {
        _temporarySpend(20, 0, "temporaryCoveredWarm");
    }

    function test_Gas_TemporaryMixed() public {
        _temporarySpend(7, 20, "temporaryMixedWarm");
    }

    function _temporarySpend(uint256 temporary, uint256 persistent, string memory label) internal {
        if (persistent != 0) _approve(registered, persistent);
        Actor.Action[] memory actions = new Actor.Action[](2);
        actions[0] = Actor.Action(
            address(registered),
            abi.encodeCall(GasTemporaryToken.temporaryApprove, (address(spender), temporary)),
            false
        );
        actions[1] = Actor.Action(
            address(spender), abi.encodeCall(GasTemporarySpender.spend, (registered, address(owner), label)), false
        );
        owner.run(actions);
    }

    function test_Gas_TemporaryApprove() public {
        vm.startSnapshotGas("ERC20TemporaryApproval", "temporaryApproveCold");
        registered.temporaryApprove(address(spender), 20);
        vm.stopSnapshotGas();
    }
}
