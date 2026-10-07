// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HAS_SYSTEM_CONTRACT} from "@lattice/accounts/hedera/HASSignatureVerifierLib.sol";
import {IHederaAccountService} from "@lattice/interfaces/external/hedera/IHederaAccountService.sol";
import {Test} from "forge-std/Test.sol";

/// @title HASSignatureVerifierFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice hedera-testnet coverage for the Hedera Account Service path behind {HASSignatureVerifierLib}. The
///         key check is asserted over `vm.rpc` rather than through the facet, because it is the only way it
///         can really run: a Foundry fork replays RPC-fetched state in revm, and HAS has no bytecode to fetch
///         — the relay answers `eth_getCode(0x16a)` with nothing at all — so a locally executed `staticcall`
///         would hit an empty account and the facet would (correctly) report `false`. Handing the relay an
///         `eth_call` instead has the mirror node simulate it against the account's real key.
///         The fixtures must be a matching triple for ONE hedera-testnet account: HEDERA_TEST_SIG is that
///         account's key signing HEDERA_TEST_HASH (65 bytes ECDSA-secp256k1, or 64 bytes ED25519).
///
/// Enabling fork tests:
///   export HEDERA_TESTNET_RPC_URL=<hedera-testnet-json-rpc-relay>
///   export HEDERA_TEST_ACCOUNT=<hedera-testnet-account-evm-address>
///   export HEDERA_TEST_HASH=<32-byte-message-hash>
///   export HEDERA_TEST_SIG=<that-account-s-signature-over-the-hash>
///   forge test --match-path "test/fork/HASSignatureVerifierFork.t.sol"
///
/// Without HEDERA_TEST_ACCOUNT and HEDERA_TEST_SIG set, all tests in this contract are skipped.
///
/// @dev No `vm.createSelectFork` here: nothing in this suite executes locally, and forking hedera-testnet
///      needs the Hedera-pinned Foundry 1.7.1 (`script/config/hedera/forge-hedera.sh`), because Foundry
///      1.8.1's fork backend sends EIP-1898 block-hash params that Hedera's relay rejects. `vm.rpc`
///      addresses the endpoint by its `rpc_endpoints` alias instead.
contract HASSignatureVerifierFork is Test {
    /// @dev The `rpc_endpoints` alias (chain 296) the `eth_call` is sent to.
    string constant HEDERA_TESTNET = "hedera-testnet";

    address account; // HEDERA_TEST_ACCOUNT — the account whose key signed the fixture
    bytes32 messageHash; // HEDERA_TEST_HASH — the 32-byte message hash that was signed
    bytes signature; // HEDERA_TEST_SIG — the raw ECDSA (65b) or ED25519 (64b) signature

    function setUp() public {
        account = vm.envOr("HEDERA_TEST_ACCOUNT", address(0));
        messageHash = vm.envOr("HEDERA_TEST_HASH", bytes32(0));
        signature = vm.envOr("HEDERA_TEST_SIG", bytes(""));
        if (account == address(0) || signature.length == 0) vm.skip(true);
    }

    /// @notice `isAuthorizedRaw` is the one HAS entry point that does NOT follow the `RESPONSE_CODE64_BOOL`
    ///         convention: it is a pure signature check over a simple key and returns a BARE bool, reverting
    ///         (rather than returning a code) on malformed input or a key list. The relay answer is therefore
    ///         decoded as a single `bool` — the same shape {HASSignatureVerifierLib.isAuthorizedRaw} decodes
    ///         after its `staticcall`, over byte-identical calldata.
    function test_Fork_RelayEthCallAuthorizesTheFixtureSignature() public {
        bytes memory ret = _ethCall(
            HAS_SYSTEM_CONTRACT,
            abi.encodeCall(IHederaAccountService.isAuthorizedRaw, (account, abi.encodePacked(messageHash), signature))
        );

        assertTrue(abi.decode(ret, (bool)), "HAS did not authorize the fixture signature");
    }

    /// @dev `eth_call` sent straight to the hedera-testnet relay. `vm.rpc` returns the raw result bytes — the
    ///      cheatcode decodes the JSON hex string itself — so the caller `abi.decode`s them directly.
    function _ethCall(address to, bytes memory data) internal returns (bytes memory ret) {
        string memory params =
            string.concat('[{"to":"', vm.toString(to), '","data":"', vm.toString(data), '"},"latest"]');
        ret = vm.rpc(HEDERA_TESTNET, "eth_call", params);
    }
}
