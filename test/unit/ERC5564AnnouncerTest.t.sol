// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC5564Announcer} from "@lattice/interfaces/privacy/IERC5564Announcer.sol";
import {ERC5564Announcer} from "@lattice/privacy/ERC5564Announcer.sol";
import {ERC5564AnnouncerLib} from "@lattice/privacy/libraries/ERC5564AnnouncerLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockERC5564AnnouncerContract
/// @notice Wrapper that inherits the ERC5564Announcer facet and exposes init + ERC-165 discovery.
contract MockERC5564AnnouncerContract is ERC5564Announcer {
    function initialize() external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC5564AnnouncerLib.__ERC5564Announcer_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC5564AnnouncerTest
/// @notice Unit tests for the ERC-5564 stealth-address announcer facet.
contract ERC5564AnnouncerTest is Test {
    MockERC5564AnnouncerContract announcer;

    address sender = address(0xA1);
    address stealth = address(0x5778);

    event Announcement(
        uint256 indexed schemeId,
        address indexed stealthAddress,
        address indexed caller,
        bytes ephemeralPubKey,
        bytes metadata
    );

    function setUp() public {
        announcer = new MockERC5564AnnouncerContract();
        announcer.initialize();
    }

    function test_AnnounceEmitsWithCallerForcedToMsgSender() public {
        uint256 schemeId = 1;
        bytes memory eph = hex"0288c2b1a4f6090807060504030201aabbccddeeff00112233445566778899aabb";
        bytes memory meta = hex"2a"; // view tag byte

        vm.expectEmit(true, true, true, true, address(announcer));
        emit Announcement(schemeId, stealth, sender, eph, meta);

        vm.prank(sender);
        announcer.announce(schemeId, stealth, eph, meta);
    }

    function test_AnnounceIsPermissionless() public {
        // Any address may announce; this must not revert regardless of caller.
        vm.prank(address(0xBEEF));
        announcer.announce(1, stealth, hex"0102", hex"03");
    }

    function test_AnnounceAllowsEmptyBytes() public {
        vm.prank(sender);
        announcer.announce(0, stealth, "", "");
    }

    function test_SupportsIERC5564Announcer() public view {
        assertTrue(announcer.supportsInterface(type(IERC5564Announcer).interfaceId));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IERC5564Announcer).interfaceId, bytes4(0x4d1f9583), "IERC5564Announcer interfaceId moved");
    }
}
