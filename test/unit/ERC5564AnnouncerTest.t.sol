// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC5564AnnouncerTestBase} from "@lattice-test/base/ERC5564AnnouncerTestBase.sol";
import {IERC5564Announcer} from "@lattice/interfaces/privacy/IERC5564Announcer.sol";
import {ERC5564Announcer} from "@lattice/privacy/ERC5564Announcer.sol";

/// @title ERC5564AnnouncerTest
/// @notice Exercises the ERC-5564 stealth-address announcer through a REAL {Diamond} assembled by the
///         ready-to-deploy {DeployERC5564Announcer} script (see {ERC5564AnnouncerTestBase}) — every `announce`
///         routes through the diamond's `delegatecall` dispatch, not a flattened inheritance mock.
///         `supportsInterface` is answered by the cut-in `ERC165Facet`. The announcer is permissionless.
contract ERC5564AnnouncerTest is ERC5564AnnouncerTestBase {
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
        diamond = _deployERC5564Announcer();
        announcer = ERC5564Announcer(diamond);
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
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC5564Announcer).interfaceId));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IERC5564Announcer).interfaceId, bytes4(0x4d1f9583), "IERC5564Announcer interfaceId moved");
    }
}
