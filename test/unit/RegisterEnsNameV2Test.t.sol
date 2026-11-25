// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IETHRegistryRecords, RegisterEnsName} from "@lattice-script/config/RegisterEnsName.s.sol";
import {IETHRegistrar} from "@lattice/interfaces/external/ens/IETHRegistrar.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {Test} from "forge-std/Test.sol";

contract RegisterEnsNameV2Test is Test {
    address constant REGISTRAR = 0xf633e7FC17e2bbE0D0965D18ec1821dcB754a3d3;
    address constant REGISTRY = 0xD4eBcbBdF463C9c45784603Db0dDD499BC44A8B4;
    bytes32 constant SECRET = bytes32(uint256(42));
    RegisterEnsName script;
    RegisterEnsName.Registration r;
    address payer = address(this);
    address token = makeAddr("token");
    bytes32 h;

    function setUp() public {
        vm.chainId(11155111);
        vm.warp(100_000);
        script = new RegisterEnsName();
        address resolver = makeAddr("resolver");
        vm.etch(resolver, hex"00");
        r = RegisterEnsName.Registration("demo", payer, address(0), resolver, 365 days, bytes32(0));
        h = keccak256(abi.encode(r.label, r.owner, SECRET, r.subregistry, r.resolver, r.duration, r.referrer));
        vm.setEnv("ENS_REGISTRATION_SECRET", vm.toString(SECRET));
        _reply(REGISTRAR, abi.encodeCall(IETHRegistrar.ETH_REGISTRY, ()), abi.encode(REGISTRY));
        _reply(REGISTRAR, abi.encodeCall(IETHRegistrar.MIN_COMMITMENT_AGE, ()), abi.encode(uint64(60)));
        _reply(REGISTRAR, abi.encodeCall(IETHRegistrar.MAX_COMMITMENT_AGE, ()), abi.encode(uint64(86400)));
        _reply(REGISTRAR, abi.encodeCall(IETHRegistrar.MIN_REGISTER_DURATION, ()), abi.encode(uint64(28 days)));
        _reply(REGISTRAR, abi.encodeCall(IETHRegistrar.isAvailable, (r.label)), abi.encode(true));
        _reply(
            REGISTRAR, abi.encodeCall(IETHRegistrar.getRegisterPrice, (r.label, r.duration, token)), abi.encode(7, 2)
        );
        _reply(REGISTRY, abi.encodeCall(IETHRegistryRecords.findOwner, (r.label)), abi.encode(address(0)));
        _reply(token, abi.encodeCall(IERC20.decimals, ()), abi.encode(uint8(6)));
        _reply(token, abi.encodeCall(IERC20.balanceOf, (payer)), abi.encode(100));
        _allowance(0);
        _age(60);
    }

    function _reply(address target, bytes memory data, bytes memory result) internal {
        vm.mockCall(target, data, result);
    }

    function _age(uint64 age) internal {
        _reply(REGISTRAR, abi.encodeCall(IETHRegistrar.commitmentAt, (h)), abi.encode(uint64(block.timestamp) - age));
    }

    function _allowance(uint256 amount) internal {
        _reply(token, abi.encodeCall(IERC20.allowance, (payer, REGISTRAR)), abi.encode(amount));
    }

    function _reveal(uint256 cap) internal {
        script.reveal(r, token, cap);
    }

    function test_WrongChain() public {
        vm.chainId(1);
        vm.expectRevert("Sepolia only");
        script.commit(h);
    }

    function test_CommitBroadcastsOnlyHashAndSkipsLiveCommitment() public {
        _reply(REGISTRAR, abi.encodeCall(IETHRegistrar.commitmentAt, (h)), abi.encode(0));
        bytes memory data = abi.encodeCall(IETHRegistrar.commit, (h));
        _reply(REGISTRAR, data, "");
        vm.expectCall(REGISTRAR, data, 1);
        script.commit(h);
        _age(17);
        script.commit(h);
    }

    function test_RevealTooEarly() public {
        _age(59);
        vm.expectRevert("Commitment too young");
        _reveal(9);
    }

    function test_RevealAtMaximumAge() public {
        _age(86400);
        vm.expectRevert("Commitment expired; use a fresh secret");
        _reveal(9);
    }

    function test_MissingCommitmentAfterAlteredTuple() public {
        r.referrer = bytes32(uint256(1));
        vm.mockCall(REGISTRAR, abi.encodePacked(IETHRegistrar.commitmentAt.selector), abi.encode(0));
        vm.expectRevert("Commitment missing");
        _reveal(9);
    }

    function test_QuoteExceedsBudget() public {
        vm.expectRevert("Quote exceeds spending cap");
        _reveal(8);
    }

    function test_UnsupportedToken() public {
        vm.mockCallRevert(
            REGISTRAR, abi.encodeCall(IETHRegistrar.getRegisterPrice, (r.label, r.duration, token)), "unsupported"
        );
        vm.expectRevert(bytes("unsupported"));
        _reveal(9);
    }

    function test_PayerBalanceTooLow() public {
        _reply(token, abi.encodeCall(IERC20.balanceOf, (payer)), abi.encode(8));
        vm.expectRevert("Insufficient payment token balance");
        _reveal(9);
    }

    function test_ApprovalFromDifferentQuoteRequiresOperator() public {
        _allowance(10);
        vm.expectRevert("Clear existing allowance or use a dedicated payer");
        _reveal(10);
    }

    function test_RetryAfterMinedApprovalUsesExistingExactAmount() public {
        _allowance(9);
        bytes memory data = abi.encodeCall(
            IETHRegistrar.register, (r.label, r.owner, SECRET, r.subregistry, r.resolver, r.duration, token, r.referrer)
        );
        vm.expectCall(token, abi.encodeCall(IERC20.approve, (REGISTRAR, 9)), 0);
        vm.mockCallRevert(REGISTRAR, data, "price changed");
        vm.expectRevert(bytes("price changed"));
        _reveal(9);
    }

    function test_MismatchedOwnerOnRetry() public {
        _reply(REGISTRY, abi.encodeCall(IETHRegistryRecords.findOwner, (r.label)), abi.encode(token));
        vm.expectRevert("Registered owner differs");
        _reveal(9);
    }

    function test_CompletedRetryChecksRegistryAndSkipsApproval() public {
        _reply(REGISTRY, abi.encodeCall(IETHRegistryRecords.findOwner, (r.label)), abi.encode(payer));
        _reply(REGISTRY, abi.encodeCall(IETHRegistryRecords.getSubregistry, (r.label)), abi.encode(r.subregistry));
        _reply(REGISTRY, abi.encodeCall(IETHRegistryRecords.getResolver, (r.label)), abi.encode(r.resolver));
        _reply(REGISTRY, abi.encodeCall(IETHRegistryRecords.findTokenId, (r.label)), abi.encode(53));
        vm.expectCall(token, abi.encodeCall(IERC20.approve, (REGISTRAR, 9)), 0);
        assertEq(script.reveal(r, token, 9), 53);
    }
}
