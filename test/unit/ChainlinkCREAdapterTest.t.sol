// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ChainlinkCREAdapterTestBase} from "@lattice-test/base/ChainlinkCREAdapterTestBase.sol";
import {IReceiver} from "@lattice/interfaces/external/chainlink/IReceiver.sol";
import {IChainlinkCREAdapter} from "@lattice/interfaces/oracles/IChainlinkCREAdapter.sol";
import {ChainlinkCREAdapter} from "@lattice/oracles/ChainlinkCREAdapter.sol";

/// @title ChainlinkCREAdapterTest
/// @notice Exercises the ChainlinkCREAdapter facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployChainlinkCREAdapter} script (see {ChainlinkCREAdapterTestBase}) — every call below routes
///         through the diamond's `delegatecall` dispatch, not a flattened inheritance mock. Admin gating is
///         enforced by the cut-in `AccessControl` facet; `supportsInterface` (canonical IReceiver id) by the
///         cut-in `ERC165Facet`.
contract ChainlinkCREAdapterTest is ChainlinkCREAdapterTestBase {
    address admin = address(0x1);
    address user = address(0x2);
    address forwarder = address(0xF0);

    bytes32 constant WORKFLOW_ID = keccak256("WORKFLOW");
    bytes10 constant WORKFLOW_NAME = bytes10("myflow");
    address constant WORKFLOW_OWNER = address(0xABCD);
    bytes2 constant REPORT_ID = 0x0001;

    bytes report = abi.encode(uint256(42), uint256(1700000000));

    function setUp() public {
        diamond = _deployChainlinkCREAdapter(admin);
        cre = ChainlinkCREAdapter(diamond);
    }

    /// @dev Builds 64-byte KeystoneForwarder metadata: workflowId ++ name ++ owner ++ reportId.
    function _metadata(bytes32 workflowId, address owner) internal pure returns (bytes memory) {
        return abi.encodePacked(workflowId, WORKFLOW_NAME, owner, REPORT_ID);
    }

    function _configure() internal {
        vm.startPrank(admin);
        cre.setForwarder(forwarder);
        cre.setWorkflow(WORKFLOW_ID, true);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetForwarderByAdmin() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit IChainlinkCREAdapter.CREForwarderSet(forwarder);
        cre.setForwarder(forwarder);
        assertEq(cre.getForwarder(), forwarder);
    }

    function test_SetForwarderRevertsForNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        cre.setForwarder(forwarder);
    }

    function test_SetForwarderRevertsOnZero() public {
        vm.prank(admin);
        vm.expectRevert(IChainlinkCREAdapter.CREInvalidForwarder.selector);
        cre.setForwarder(address(0));
    }

    function test_SetWorkflowByAdmin() public {
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit IChainlinkCREAdapter.CREWorkflowSet(WORKFLOW_ID, true);
        cre.setWorkflow(WORKFLOW_ID, true);
        assertTrue(cre.isWorkflowAllowed(WORKFLOW_ID));
    }

    function test_SetWorkflowRevertsForNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        cre.setWorkflow(WORKFLOW_ID, true);
    }

    function test_SetWorkflowRevertsOnZeroId() public {
        vm.prank(admin);
        vm.expectRevert(IChainlinkCREAdapter.CREInvalidWorkflowId.selector);
        cre.setWorkflow(bytes32(0), true);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 ON REPORT
    //////////////////////////////////////////////////////////////////////////*//

    function test_OnReportStoresAndEmits() public {
        _configure();

        vm.expectEmit(true, true, false, true);
        emit IChainlinkCREAdapter.ReportReceived(WORKFLOW_ID, WORKFLOW_OWNER, REPORT_ID);
        vm.prank(forwarder);
        cre.onReport(_metadata(WORKFLOW_ID, WORKFLOW_OWNER), report);

        (bytes memory storedReport, uint256 ts) = cre.getLatestReport(WORKFLOW_ID);
        assertEq(storedReport, report, "report payload mismatch");
        assertEq(ts, block.timestamp, "timestamp mismatch");
    }

    function test_OnReportRevertsWhenNotConfigured() public {
        vm.prank(forwarder);
        vm.expectRevert(IChainlinkCREAdapter.CRENotConfigured.selector);
        cre.onReport(_metadata(WORKFLOW_ID, WORKFLOW_OWNER), report);
    }

    function test_OnReportRevertsFromNonForwarder() public {
        _configure();
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkCREAdapter.CREOnlyForwarder.selector, user));
        cre.onReport(_metadata(WORKFLOW_ID, WORKFLOW_OWNER), report);
    }

    function test_OnReportRevertsOnShortMetadata() public {
        _configure();
        bytes memory shortMeta = abi.encodePacked(WORKFLOW_ID, WORKFLOW_NAME); // 42 bytes < 64
        vm.prank(forwarder);
        vm.expectRevert(IChainlinkCREAdapter.CREInvalidMetadata.selector);
        cre.onReport(shortMeta, report);
    }

    function test_OnReportRevertsForDisallowedWorkflow() public {
        _configure();
        bytes32 other = keccak256("OTHER");
        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkCREAdapter.CREWorkflowNotAllowed.selector, other));
        cre.onReport(_metadata(other, WORKFLOW_OWNER), report);
    }

    function test_DisallowingWorkflowBlocksReports() public {
        _configure();
        // First report succeeds.
        vm.prank(forwarder);
        cre.onReport(_metadata(WORKFLOW_ID, WORKFLOW_OWNER), report);

        // Admin revokes the workflow.
        vm.prank(admin);
        cre.setWorkflow(WORKFLOW_ID, false);

        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkCREAdapter.CREWorkflowNotAllowed.selector, WORKFLOW_ID));
        cre.onReport(_metadata(WORKFLOW_ID, WORKFLOW_OWNER), report);
    }

    function test_OnReportDecodesOwnerFromMetadata() public {
        _configure();
        address owner = address(0xDeadBEeFDeADbEEF00000000000000000000beEf);

        vm.expectEmit(true, true, false, true);
        emit IChainlinkCREAdapter.ReportReceived(WORKFLOW_ID, owner, REPORT_ID);
        vm.prank(forwarder);
        cre.onReport(_metadata(WORKFLOW_ID, owner), report);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsCanonicalIReceiverInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IReceiver).interfaceId));
    }
}
