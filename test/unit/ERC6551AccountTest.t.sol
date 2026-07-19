// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {ERC6551Account} from "@lattice/accounts/ERC6551Account.sol";
import {ERC6551AccountLib} from "@lattice/accounts/libraries/ERC6551AccountLib.sol";
import {ITokenBound} from "@lattice/interfaces/accounts/ITokenBound.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

contract MockTBA is ERC6551Account {
    function initialize(uint256 chainId, address tokenContract, uint256 tokenId) external {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        ERC6551AccountLib.__ERC6551Account_init(chainId, tokenContract, tokenId);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

contract MockNFT {
    mapping(uint256 tokenId => address) public ownerOf;

    function setOwner(uint256 tokenId, address o) external {
        ownerOf[tokenId] = o;
    }
}

contract Target {
    uint256 public value;
    uint256 public received;

    function setValue(uint256 v) external payable {
        value = v;
        received += msg.value;
    }

    function boom() external pure {
        revert("boom");
    }
}

contract ERC6551AccountTest is Test {
    MockTBA acct;
    MockNFT nft;
    Target target;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    uint256 tokenId = 7;

    bytes4 constant MAGIC = 0x523e3260;

    function setUp() public {
        nft = new MockNFT();
        nft.setOwner(tokenId, alice);
        acct = new MockTBA();
        acct.initialize(block.chainid, address(nft), tokenId);
        target = new Target();
    }

    function test_Token() public view {
        (uint256 c, address tc, uint256 id) = acct.token();
        assertEq(c, block.chainid, "chainId");
        assertEq(tc, address(nft), "tokenContract");
        assertEq(id, tokenId, "tokenId");
    }

    function test_SupportsInterface() public view {
        assertTrue(acct.supportsInterface(0x6faff5f1), "IERC6551Account");
        assertTrue(acct.supportsInterface(0x51945447), "IERC6551Executable");
    }

    function test_IsValidSigner() public view {
        assertEq(acct.isValidSigner(alice, ""), MAGIC, "owner not a valid signer");
        assertEq(acct.isValidSigner(bob, ""), bytes4(0), "non-owner accepted");
    }

    function test_State_Initial() public view {
        assertEq(acct.state(), 0, "initial state");
    }

    function test_Execute() public {
        vm.prank(alice);
        acct.execute(address(target), 0, abi.encodeCall(Target.setValue, (42)), 0);
        assertEq(target.value(), 42, "call not executed");
        assertEq(acct.state(), 1, "state not bumped");
    }

    function test_Execute_RevertNotOwner() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ITokenBound.InvalidSigner.selector, bob));
        acct.execute(address(target), 0, abi.encodeCall(Target.setValue, (1)), 0);
    }

    function test_Execute_RevertUnsupportedOp() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ITokenBound.UnsupportedOperation.selector, uint8(1)));
        acct.execute(address(target), 0, abi.encodeCall(Target.setValue, (1)), 1);
    }

    function test_Execute_ForwardsValue() public {
        vm.deal(address(acct), 1 ether);
        vm.prank(alice);
        acct.execute(address(target), 0.5 ether, abi.encodeCall(Target.setValue, (3)), 0);
        assertEq(target.value(), 3, "value call not executed");
        assertEq(target.received(), 0.5 ether, "ETH not forwarded");
    }

    function test_Execute_BubblesRevert() public {
        vm.prank(alice);
        vm.expectRevert(bytes("boom"));
        acct.execute(address(target), 0, abi.encodeCall(Target.boom, ()), 0);
    }

    /// @dev Control follows the NFT: transferring the token moves the valid signer.
    function test_OwnerFollowsNFT() public {
        nft.setOwner(tokenId, bob);
        assertEq(acct.isValidSigner(bob, ""), MAGIC, "new owner not valid");
        assertEq(acct.isValidSigner(alice, ""), bytes4(0), "old owner still valid");
        vm.prank(bob);
        acct.execute(address(target), 0, abi.encodeCall(Target.setValue, (9)), 0);
        assertEq(target.value(), 9, "new owner could not execute");
    }

    function test_CrossChainOwnerUnresolved() public {
        MockTBA foreign = new MockTBA();
        foreign.initialize(block.chainid + 1, address(nft), tokenId); // token lives on another chain
        assertEq(foreign.isValidSigner(alice, ""), bytes4(0), "cross-chain owner should be unresolved");
    }
}
