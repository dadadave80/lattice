// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HTSAdapterTestBase} from "@lattice-test/base/HTSAdapterTestBase.sol";
import {HederaResponseCodes} from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import {IHederaTokenService} from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
import {IHTSAdapter} from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import {HTSAdapter} from "@lattice/tokens/hedera/HTSAdapter.sol";
import {HTS_SYSTEM_CONTRACT} from "@lattice/tokens/hedera/HTSAdapterLib.sol";

/// @title HTSAdapterFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice hedera-testnet coverage for the production {DeployHTSAdapter} diamond, assembled on a fork through
///         the same recipe `run --broadcast` and the offline suite use ({HTSAdapterTestBase}). The two tests
///         sit on opposite sides of one boundary: a Foundry fork replays RPC-fetched state in revm and the
///         Hedera Token Service system contract has no bytecode to replay, so nothing it is asked to execute
///         locally can work — while an `eth_call` handed back to the relay is simulated by the mirror node and
///         answers normally.
///
/// Enabling fork tests:
///   export HEDERA_TESTNET_RPC_URL=<hedera-testnet-json-rpc-relay>
///   export HEDERA_TEST_TOKEN=<live-hedera-testnet-HTS-token>
///   FOUNDRY_PROFILE=hedera forge test --match-path "test/fork/HTSAdapterFork.t.sol"
///
/// Without HEDERA_TEST_TOKEN set, all tests in this contract are skipped.
///
/// {test_Fork_AssociateTokenCannotExecuteHTSOnAFork} needs one thing more than the others — a relay Foundry
/// can actually fork from — and is skipped unless you opt in:
///   export HEDERA_TEST_FORK=true
///
/// @dev Only {test_Fork_AssociateTokenCannotExecuteHTSOnAFork} forks, and it opens the fork in its own body
///      rather than in `setUp`, because forking hedera-testnet at all needs a relay that accepts EIP-1898
///      block-parameter objects: Foundry fetches every account with one, and the public hashio relay rejects
///      it (`Invalid parameter 1: The value passed is not valid: [object Object]`) whether or not the fork is
///      pinned to a block. That is why it carries its OWN `HEDERA_TEST_FORK` opt-in: on the endpoint
///      `.env.example` documents, forking aborts the test with a database error that no `try`/`catch` can
///      turn into a skip, so leaving it ungated would hand anyone who merely sets HEDERA_TEST_TOKEN a red
///      suite for an endpoint limitation. {test_Fork_RelayEthCallSeesALiveHTSToken} is unaffected — `vm.rpc`
///      addresses the endpoint by its `rpc_endpoints` alias and never opens a fork — so it still runs
///      against hashio, and it is the test that actually exercises the live network.
contract HTSAdapterFork is HTSAdapterTestBase {
    /// @dev The `rpc_endpoints` alias (chain 296), shared by the fork and the relay `eth_call`.
    string constant HEDERA_TESTNET = "hedera-testnet";

    address admin = makeAddr("admin");
    address token; // HEDERA_TEST_TOKEN — an existing hedera-testnet HTS token

    function setUp() public {
        token = vm.envOr("HEDERA_TEST_TOKEN", address(0));
        if (token == address(0)) vm.skip(true);
    }

    /// @notice Documents a FOUNDRY limitation, not a Lattice defect: a fork cannot execute a Hedera system
    ///         contract. `vm.createSelectFork` only pulls account state over RPC and replays it in revm, and
    ///         HTS has no bytecode to pull — the relay answers `eth_getCode(0x167)` with `0xfe`, so the plain
    ///         `call` in {HTSAdapterLib._callForCode} runs INVALID and halts. A halted frame is mapped to
    ///         {HederaResponseCodes.UNKNOWN} (21) exactly as hiero-contracts' helper does, and 21 is not one of
    ///         the codes {HTSAdapterLib._check} translates, so it surfaces as the catch-all
    ///         {IHTSAdapter.HTSCallFailed} carrying the HTS selector. Pinning the precise error draws the
    ///         boundary twice over: an association only ever succeeds against the real network, and the adapter
    ///         never mistakes an unexecutable system contract for success. That `0xfe` is also what keeps this
    ///         a typed revert — were the relay to report NO code, the `call` would succeed with empty
    ///         returndata and `abi.decode` would bubble a dataless revert instead.
    function test_Fork_AssociateTokenCannotExecuteHTSOnAFork() public {
        if (!vm.envOr("HEDERA_TEST_FORK", false)) vm.skip(true);
        vm.createSelectFork(HEDERA_TESTNET);
        diamond = _deployHTSAdapter(admin);
        htsAdapter = HTSAdapter(diamond);

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHTSAdapter.HTSCallFailed.selector,
                IHederaTokenService.associateToken.selector,
                HederaResponseCodes.UNKNOWN
            )
        );
        htsAdapter.associateToken(token);
    }

    /// @notice The other side of the boundary: handing the very same system contract an `eth_call` over
    ///         `vm.rpc` leaves execution with the relay, which has the mirror node simulate it. `isToken` is a
    ///         `RESPONSE_CODE64_BOOL` getter, so a live token answers (SUCCESS, true) — proving both that
    ///         HEDERA_TEST_TOKEN is a real HTS token and that the calldata {HTSAdapterLib.isHTSToken} builds is
    ///         accepted by the network unchanged.
    function test_Fork_RelayEthCallSeesALiveHTSToken() public {
        bytes memory ret = _ethCall(HTS_SYSTEM_CONTRACT, abi.encodeCall(IHederaTokenService.isToken, (token)));
        (int64 code, bool isToken) = abi.decode(ret, (int64, bool));

        assertEq(code, HederaResponseCodes.SUCCESS, "isToken response code");
        assertTrue(isToken, "HEDERA_TEST_TOKEN is not a live HTS token");
    }

    /// @dev `eth_call` sent straight to the hedera-testnet relay. `vm.rpc` returns the raw result bytes — the
    ///      cheatcode decodes the JSON hex string itself — so the caller `abi.decode`s them directly.
    function _ethCall(address to, bytes memory data) internal returns (bytes memory ret) {
        string memory params =
            string.concat('[{"to":"', vm.toString(to), '","data":"', vm.toString(data), '"},"latest"]');
        ret = vm.rpc(HEDERA_TESTNET, "eth_call", params);
    }
}
