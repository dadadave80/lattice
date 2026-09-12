// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployHTSAdapter} from "@lattice-script/base/tokens/DeployHTSAdapter.s.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {HASSignatureVerifier} from "@lattice/accounts/hedera/HASSignatureVerifier.sol";
import {HAS_SYSTEM_CONTRACT} from "@lattice/accounts/hedera/HASSignatureVerifierLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IHASSignatureVerifier} from "@lattice/interfaces/accounts/IHASSignatureVerifier.sol";
import {HederaResponseCodes} from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import {IHederaTokenService} from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
import {IHSSAdapter} from "@lattice/interfaces/oracles/IHSSAdapter.sol";
import {IHederaExchangeRateAdapter} from "@lattice/interfaces/oracles/IHederaExchangeRateAdapter.sol";
import {IHTSAdapter} from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import {HSSAdapter} from "@lattice/oracles/hedera/HSSAdapter.sol";
import {HSS_SCHEDULER_ROLE} from "@lattice/oracles/hedera/HSSAdapterLib.sol";
import {HederaExchangeRateAdapter} from "@lattice/oracles/hedera/HederaExchangeRateAdapter.sol";
import {
    HTS_DEFAULT_AUTO_RENEW_PERIOD,
    HTS_KEY_ADMIN,
    HTS_KEY_SUPPLY,
    HTS_MANAGER_ROLE,
    HTS_SYSTEM_CONTRACT
} from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import {console2} from "forge-std/console2.sol";

/// @title HederaProbeFacet
/// @notice The throwaway facet the day-0 probe cuts alongside the released Hedera modules — it holds ONLY the
///         three things {HTSAdapter} / {HSSAdapter} deliberately cannot express, so every other probe still
///         exercises production code.
///         1. {probeContractIdKeySupply} creates a token whose SUPPLY key is a plain `contractId` key and then
///            mints against it with a RAW call that returns the response code instead of reverting — the
///            negative control for the `delegatableContractId` rule ({HTSAdapterLib} always sets the
///            delegatable form, and its `mintToken` maps the failure to `HTSKeyNotActive`, hiding the code).
///         2. {probeRedirectForAccount} issues an explicitly UNVERIFIED raw call to the Hedera Account Service
///            `redirectForAccount(address,bytes)` entrypoint. That function is NOT part of the vendored
///            {IHederaAccountService} subset and must not be added to it until this probe says it exists.
///         3. {probeCallback} is the Schedule Service callback target: it EMITS `msg.sender` and
///            `block.timestamp` rather than storing them, so the probe needs no ERC-7201 namespace of its own.
/// @dev Cut into the probe diamond through {BaseDeploy-_cut}, which sources selectors from the ERC-8153
///      {exportSelectors} export below — the same path every released facet uses.
///      {probeCallback} is deliberately UNGATED: `HSSAdapterLib.checkScheduledSelfCall` asserts
///      `msg.sender == address(this)`, and asserting the answer would hide it. The probe reports the sender
///      the network actually presents.
contract HederaProbeFacet {
    /// @notice `setUnlimitedAutomaticAssociations(bool)` (HIP-904) — the inner selector wrapped by the
    ///         `redirectForAccount` experiment. The wrapper's existence is what probe 5 settles.
    bytes4 internal constant HAS_SET_UNLIMITED_AUTOMATIC_ASSOCIATIONS = 0xf5677e99;

    /// @notice A `contractId`-supply-key create + raw mint: `createCode`, the token, and the mint response code.
    event HederaProbeContractIdKey(int64 createCode, address indexed token, int64 mintCode);

    /// @notice The raw `redirectForAccount` frame outcome and its verbatim return data.
    event HederaProbeRedirect(bool frameSucceeded, bytes returnData);

    /// @notice The scheduled callback fired: who the network presented as the caller, and when.
    event HederaProbeCallback(address indexed sender, uint256 timestamp, bytes32 indexed jobId);

    /// @notice Creates a fungible token with an ADMIN key in the `delegatableContractId` form and a SUPPLY key
    ///         in the plain `contractId` form, then mints `mintAmount` against it with a raw HTS call.
    /// @dev Isolating the key form to the SUPPLY key is the point: the admin key stays usable, so a mint
    ///      failure can only be the supply key. A facet call reaches HTS inside a `delegatecall` frame, which
    ///      activates `delegatableContractId` keys only — the expected `mintCode` is therefore
    ///      `INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE` (326), the code {IHTSAdapter-HTSKeyNotActive}
    ///      describes. Forwards `msg.value` as the creation fee and never reverts on a response code.
    /// @param name The token name.
    /// @param symbol The token symbol.
    /// @param mintAmount The amount minted to the treasury after creation.
    /// @return createCode The `createFungibleToken` response code (`SUCCESS == 22`, `UNKNOWN == 21` for a
    ///         halted frame).
    /// @return token The created token, or `address(0)` when creation failed.
    /// @return mintCode The `mintToken` response code, or `UNKNOWN` when creation failed / the frame halted.
    function probeContractIdKeySupply(string calldata name, string calldata symbol, int64 mintAmount)
        external
        payable
        virtual
        returns (int64 createCode, address token, int64 mintCode)
    {
        AccessControlLib.checkRole(HTS_MANAGER_ROLE);

        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](2);
        keys[0].keyType = HTS_KEY_ADMIN;
        keys[0].key.delegatableContractId = address(this);
        keys[1].keyType = HTS_KEY_SUPPLY;
        keys[1].key.contractId = address(this);

        IHederaTokenService.HederaToken memory t;
        t.name = name;
        t.symbol = symbol;
        t.memo = "lattice hedera probe 3: contractId supply key";
        t.treasury = address(this);
        t.tokenKeys = keys;
        t.expiry.autoRenewAccount = address(this);
        t.expiry.autoRenewPeriod = HTS_DEFAULT_AUTO_RENEW_PERIOD;

        createCode = HederaResponseCodes.UNKNOWN;
        mintCode = HederaResponseCodes.UNKNOWN;

        (bool ok, bytes memory ret) = HTS_SYSTEM_CONTRACT.call{value: msg.value}(
            abi.encodeCall(IHederaTokenService.createFungibleToken, (t, int64(0), int32(0)))
        );
        if (ok && ret.length >= 64) (createCode, token) = abi.decode(ret, (int64, address));

        if (createCode == HederaResponseCodes.SUCCESS) {
            (ok, ret) = HTS_SYSTEM_CONTRACT.call(
                abi.encodeCall(IHederaTokenService.mintToken, (token, mintAmount, new bytes[](0)))
            );
            if (ok && ret.length >= 128) (mintCode,,) = abi.decode(ret, (int64, int64, int64[]));
        }
        emit HederaProbeContractIdKey(createCode, token, mintCode);
    }

    /// @notice Calls `redirectForAccount(address,bytes)` on the Hedera Account Service system contract with
    ///         this diamond as the account and `setUnlimitedAutomaticAssociations(true)` as the inner call.
    /// @dev EXPLICITLY UNVERIFIED. `redirectForAccount` is absent from the vendored {IHederaAccountService}
    ///      subset on purpose — nothing in Lattice may depend on it until a real testnet run proves the
    ///      entrypoint exists AND that a diamond's `delegatecall` frame satisfies it. Encoded with
    ///      `abi.encodeWithSignature` rather than a typed call for exactly that reason. Never reverts: the
    ///      frame outcome and verbatim return data are returned and emitted.
    /// @return frameSucceeded True when the raw frame did not halt (says nothing about the response code).
    /// @return returnData The verbatim return data — empty for an address with no code, a response code
    ///         (or an ABI-encoded revert) once the entrypoint really exists.
    function probeRedirectForAccount() external virtual returns (bool frameSucceeded, bytes memory returnData) {
        AccessControlLib.checkRole(HTS_MANAGER_ROLE);
        (frameSucceeded, returnData) = HAS_SYSTEM_CONTRACT.call(
            abi.encodeWithSignature(
                "redirectForAccount(address,bytes)",
                address(this),
                abi.encodeWithSelector(HAS_SET_UNLIMITED_AUTOMATIC_ASSOCIATIONS, true)
            )
        );
        emit HederaProbeRedirect(frameSucceeded, returnData);
    }

    /// @notice The Schedule Service callback target — emits the caller the network presents and the consensus
    ///         timestamp of the execution.
    /// @dev Ungated by design (see the contract header): the whole question is whether a network-fired
    ///      schedule arrives with `msg.sender == address(this)`, which is what
    ///      `HSSAdapterLib.checkScheduledSelfCall` assumes. Emitting keeps the probe storage-free.
    /// @param jobId The {IHSSAdapter-scheduleSelfCall} job id the schedule was created under.
    function probeCallback(bytes32 jobId) external virtual {
        emit HederaProbeCallback(msg.sender, block.timestamp, jobId);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect HederaProbeFacet methodIdentifiers` (alphabetical by signature). Chunks:
    ///      `probeCallback(bytes32)` 0xe81f180c
    ///      `probeContractIdKeySupply(string,string,int64)` 0x697deb22
    ///      `probeRedirectForAccount()` 0x7153e40d
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"e81f180c697deb227153e40d";
    }
}

/// @title ProbeHedera
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The DAY-0 Hedera testnet probe: deploys ONE throwaway diamond carrying every Hedera module
///         ({HTSAdapter} + {HSSAdapter} + {HederaExchangeRateAdapter} + {HASSignatureVerifier} + the local
///         {HederaProbeFacet}) and drives the eight questions Hedera's semantics leave open and NO offline
///         test can answer. Each result is printed with its raw value and what that value settles.
/// @dev UNVERIFIED UNTIL SOMEONE RUNS IT. Nothing below has been executed against a live network: the
///      offline suite covers the modules, not Hedera's behaviour, and this script is the instrument that
///      converts the open questions into evidence. Treat every "expected" in the log lines as a hypothesis.
///
///      WHY THREE ENTRYPOINTS. `forge script` runs the script body in revm against a fork BEFORE it
///      broadcasts anything, and a Hedera fork cannot execute a system contract at all: the relay reports
///      `0xfe` as the code of 0x167 and nothing for 0x168 / 0x169 / 0x16a / 0x16b, so every HTS / HSS frame
///      halts locally and every 0x168 / 0x16a frame returns empty. Two consequences shape this script:
///      - every probe call is a LOW-LEVEL call whose failure is logged, never propagated. Run with
///        `--skip-simulation`. THE LOAD-BEARING ASSUMPTION: Foundry queues a broadcast transaction when the
///        frame is ENTERED, not when it succeeds, so a probe that halts in revm is still sent. That is
///        assumed, not verified. FAILURE SIGNATURE: `run()` broadcasts only the deploy / grant / fund
///        transactions and none of the probes — then this is what broke, and each probe has to be replayed
///        with `cast send` from the calldata the log prints. `--skip-simulation` also moves gas to the
///        relay's `eth_estimateGas`, equally unverified: a probe rejected for gas is the other symptom;
///      - a value a probe produces on-chain (a token address, a schedule address) is invisible to the local
///        frame, so anything that CONSUMES such a value runs in a later command and reads it back through
///        `vm.rpc("eth_call", ...)`, which hands the call to the relay where the mirror node executes it.
///
///      RELAY REQUIREMENT — the endpoint MUST implement EIP-1898. Foundry fetches account state with an
///      object block parameter (`{"blockNumber": "0x.."}`); the public hashio relay rejects it
///      (`-32602 Invalid parameter 1 ... [object Object]`, confirmed 2026-09-12), so every `forge script`
///      run below fails against hashio BEFORE it broadcasts — `--skip-simulation` does not avoid it and
///      neither does pinning a fork block. Point `HEDERA_TESTNET_RPC_URL` at a provider relay that supports
///      it. `cast` and `vm.rpc` send plain string block params and are unaffected.
///
///      RUNBOOK — Hedera testnet (chain 296), a funded key, and `FOUNDRY_PROFILE=hedera` throughout
///      (Hedera runs Cancun; the profile also keeps Sourcify verification reproducible).
///      `S=script/config/hedera/ProbeHedera.s.sol:ProbeHedera`
///       1. deploy + the self-contained probes (2-create, 3, 5, 6):
///          FOUNDRY_PROFILE=hedera forge script $S --sig "run()" --rpc-url hedera-testnet \
///            --account <name> --sender <addr> --broadcast --slow --skip-simulation
///       2. the probes that need the created token (1, 2-mint), read back live first:
///          FOUNDRY_PROFILE=hedera forge script $S --sig "follow(address)" <diamond> --rpc-url hedera-testnet \
///            --account <name> --sender <addr> --broadcast --slow --skip-simulation
///       3. the read-only report (probes 1-state, 2-balance, 4, 6-schedule, 7) — broadcast-free, re-runnable:
///          FOUNDRY_PROFILE=hedera forge script $S --sig "report(address)" <diamond> --rpc-url hedera-testnet
///      Step 3 after step 1 shows the pre-association state; after step 2 the post state. Poll the schedule
///      address from step 1 on the mirror node (`/api/v1/schedules/<id>`) about a minute after it is created,
///      then read the `HederaProbeCallback` log on HashScan.
///
///      ENV (all optional, all read through `vm.envOr`, so the script compiles and dry-runs with none set):
///      - `HEDERA_TESTNET_PK`   broadcast key; unset falls back to `--account` / `--sender`.
///      - `HEDERA_TEST_ACCOUNT` probe 7 subject account (an EVM alias or a long-zero Hedera address).
///      - `HEDERA_TEST_HASH`    probe 7 message hash.
///      - `HEDERA_TEST_SIG`     probe 7 signature (65 bytes ECDSA, 64 bytes ED25519).
///      Probe 7 logs a SKIPPED line unless all three fixtures are present.
contract ProbeHedera is DeployHTSAdapter {
    /// @notice The `[rpc_endpoints]` alias every `vm.rpc` read in this script targets. `vm.rpc` is what makes a
    ///         system-contract read really execute: the relay hands it to the mirror node instead of revm.
    string internal constant HEDERA_TESTNET_ALIAS = "hedera-testnet";

    /// @notice Hedera testnet chain id — the `--chain` argument of the probe-8 verification commands.
    uint256 internal constant HEDERA_TESTNET_CHAIN_ID = 296;

    /// @notice HBAR forwarded as `msg.value` on each `create*Token` call. Hedera prices creation in USD
    ///         (~$1) and REFUNDS the excess to the calling contract — whether that refund lands on the
    ///         DIAMOND is exactly what probe 2 measures. Hedera's EVM boundary is 18-decimal weibar, so
    ///         `20 ether == 20 HBAR`.
    uint256 internal constant CREATE_FEE = 20 ether;

    /// @notice HBAR sent to the diamond before the probes: it is the treasury AND the auto-renew account of
    ///         every token it creates, and the payer of every schedule it books.
    uint256 internal constant FUND_AMOUNT = 30 ether;

    /// @notice Probe 6 schedules its callback this many seconds out — far enough past consensus time to be
    ///         accepted, near enough to poll inside one sitting.
    uint256 internal constant SCHEDULE_DELAY = 60;

    /// @notice Gas the network reserves for the scheduled callback (an event emit through diamond dispatch).
    uint256 internal constant SCHEDULE_GAS_LIMIT = 200_000;

    /// @notice The {IHSSAdapter-scheduleSelfCall} job id probe 6 books, and the key `scheduleOf` reads back.
    bytes32 internal constant PROBE_JOB_ID = keccak256("lattice.probe.hedera.selfCall");

    /// @notice Probe 2 / probe 3 token parameters, and the amount each probe mints to the treasury.
    int32 internal constant PROBE_DECIMALS = 8;
    int64 internal constant PROBE_INITIAL_SUPPLY = 0;
    int64 internal constant PROBE_MAX_SUPPLY = 0;
    int64 internal constant PROBE_MINT_AMOUNT = 1000;

    /// @notice One US cent in tinycents — the probe-4 input to `tinycentsToTinybars`.
    uint256 internal constant ONE_CENT_IN_TINYCENTS = 1e8;

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECIPE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The probe recipe: {DeployHTSAdapter-buildCuts} plus {HSSAdapter}, {HederaExchangeRateAdapter},
    ///         {HASSignatureVerifier} and the local {HederaProbeFacet}.
    /// @dev Initialized by {HTSAdapterInit} ALONE. {HSSAdapterInit} seeds AccessControl as well
    ///      (`AccessControlLib.__AccessControl_init(admin)`), so running both would re-run the access-control
    ///      module initializer inside the same window. Verified against
    ///      `src/access/libraries/AccessControlLib.sol`: `__AccessControl_init` only calls
    ///      `InitializableLib.checkInitializing` (satisfied throughout the window), then `_grantRole`, which
    ///      no-ops when the role is already held, and `registerInterface`, which re-writes the same ERC-165
    ///      slot — so the second run would NOT revert, it would merely repeat work already done and make the
    ///      recipe lie about which initializer owns access control. `HSS_SCHEDULER_ROLE` is therefore granted
    ///      afterwards through the cut-in `AccessControl` facet, which is the honest one-owner arrangement.
    ///      {HederaPrngAdapter} is out of scope: its 0x169 read is settled by the same `vm.rpc` path probe 4
    ///      exercises and needs no diamond of its own.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`, `HTS_MANAGER_ROLE` and `HTS_OPERATOR_ROLE`.
    /// @return cuts The ten facet cuts.
    /// @return init The {HTSAdapterInit}-plus-introspection {MultiInit}.
    /// @return initCalldata The matching `multiInit` calldata.
    /// @return names The `<file>:<Contract>` artifact id of each cut, index-aligned with `cuts` (probe 8).
    function buildProbeCuts(address admin)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata, string[] memory names)
    {
        FacetCut[] memory base;
        (base, init, initCalldata) = buildCuts(admin);

        cuts = new FacetCut[](base.length + 4);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        cuts[base.length] = _cut(address(new HSSAdapter()));
        cuts[base.length + 1] = _cut(address(new HederaExchangeRateAdapter()));
        cuts[base.length + 2] = _cut(address(new HASSignatureVerifier()));
        cuts[base.length + 3] = _cut(address(new HederaProbeFacet()));

        names = new string[](cuts.length);
        names[0] = "lib/diamond-lib/src/facets/ERC165Facet.sol:ERC165Facet";
        names[1] = "src/access/AccessControl.sol:AccessControl";
        names[2] = "src/tokens/hedera/HTSAdapter.sol:HTSAdapter";
        names[3] = "lib/diamond-lib/src/facets/DiamondLoupeFacet.sol:DiamondLoupeFacet";
        names[4] = "src/governance/AccessControlDiamondCut.sol:AccessControlDiamondCut";
        names[5] = "src/Receive.sol:Receive";
        names[6] = "src/oracles/hedera/HSSAdapter.sol:HSSAdapter";
        names[7] = "src/oracles/hedera/HederaExchangeRateAdapter.sol:HederaExchangeRateAdapter";
        names[8] = "src/accounts/hedera/HASSignatureVerifier.sol:HASSignatureVerifier";
        names[9] = "script/config/hedera/ProbeHedera.s.sol:HederaProbeFacet";
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        STEP 1 - DEPLOY + PROBES 2,3,5,6
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deploys the throwaway probe diamond, funds it, grants `HSS_SCHEDULER_ROLE`, and broadcasts the
    ///         probes that need no on-chain value from an earlier one: probe 2's create, probe 3, probe 5 and
    ///         probe 6. Prints the diamond address, every probe's raw local outcome, and the probe-8
    ///         verification commands.
    /// @return diamond The probe diamond — the argument of `follow(address)` and `report(address)`.
    function run() external returns (address diamond) {
        address admin = _beginBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata, string[] memory names) = buildProbeCuts(admin);
        diamond = _assemble(cuts, init, initCalldata);

        console2.log("");
        console2.log("=== LATTICE HEDERA DAY-0 PROBE ===============================================");
        _line("diamond ", vm.toString(diamond), "the throwaway probe diamond; pass it to follow()/report()");
        _line("admin   ", vm.toString(admin), "DEFAULT_ADMIN + HTS_MANAGER + HTS_OPERATOR (HTSAdapterInit)");
        _line("chain   ", vm.toString(block.chainid), "expected 296 (hedera-testnet); 295 would be mainnet");

        IAccessControl(diamond).grantRole(HSS_SCHEDULER_ROLE, admin);
        _line(
            "role    ",
            "HSS_SCHEDULER_ROLE -> admin",
            "granted through the AccessControl facet, NOT HSSAdapterInit (one initializer owns access control)"
        );

        (bool funded,) = diamond.call{value: FUND_AMOUNT}("");
        _line(
            "funding ",
            string.concat(vm.toString(FUND_AMOUNT), " weibar, local frame ok=", vm.toString(funded)),
            "the Receive facet must accept a bare HBAR send; the diamond pays auto-renew and schedule fees"
        );

        // --- PROBE 2: delegatableContractId create; the mint follows in `follow(address)` ---------------
        console2.log("");
        console2.log("--- PROBE 2: createFungibleToken with delegatableContractId keys ---------------");
        _line("balance-before", vm.toString(diamond.balance), "local (revm) view; report() reads the live one");
        _probe(
            diamond,
            CREATE_FEE,
            abi.encodeCall(
                IHTSAdapter.createFungibleToken,
                (
                    "Lattice Probe Token",
                    "LPT",
                    "lattice hedera probe 2",
                    PROBE_DECIMALS,
                    PROBE_INITIAL_SUPPLY,
                    PROBE_MAX_SUPPLY
                )
            ),
            "SUCCESS means a facet frame may create a token the diamond treasuries and keys"
        );
        _line("balance-after ", vm.toString(diamond.balance), "local (revm) view; report() reads the live one");
        _line(
            "settles ",
            "excess-msg.value refund",
            "compare report()'s live balance against the 30 HBAR funded: a balance above it means HTS refunded"
            " the unspent creation fee TO THE DIAMOND (the calling contract), not to the broadcaster"
        );
        _line("settles ", "mint", "probe 2's mintToken needs this token's address; it runs in follow(address)");

        // --- PROBE 3: the same create with a contractId supply key, then mint ---------------------------
        console2.log("");
        console2.log("--- PROBE 3: contractId (NOT delegatableContractId) supply key, then mint ------");
        _probe(
            diamond,
            CREATE_FEE,
            abi.encodeCall(
                HederaProbeFacet.probeContractIdKeySupply, ("Lattice Probe Dead Key", "LPDK", PROBE_MINT_AMOUNT)
            ),
            "read HederaProbeContractIdKey(createCode, token, mintCode) from the receipt: createCode 22 with"
            " mintCode 326 (INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE) confirms a contractId key held by a"
            " diamond is DEAD - the exact failure IHTSAdapter.HTSKeyNotActive names - and that HTSAdapterLib is"
            " right to set delegatableContractId always; mintCode 22 would refute it"
        );

        // --- PROBE 5: the redirectForAccount experiment -------------------------------------------------
        console2.log("");
        console2.log("--- PROBE 5: HAS redirectForAccount(address,bytes) -----------------------------");
        _probe(
            diamond,
            0,
            abi.encodeCall(HederaProbeFacet.probeRedirectForAccount, ()),
            "read HederaProbeRedirect(frameSucceeded, returnData): non-empty returnData means 0x16a really"
            " exposes redirectForAccount and a diamond's delegatecall frame reaches it - only THEN may"
            " redirectForAccount be added to the vendored IHederaAccountService subset"
        );

        // --- PROBE 6: scheduleSelfCall at the probe callback --------------------------------------------
        console2.log("");
        console2.log("--- PROBE 6: scheduleSelfCall ~60s out at the probe callback -------------------");
        uint256 expiry = block.timestamp + SCHEDULE_DELAY;
        _probe(
            diamond,
            0,
            abi.encodeCall(
                IHSSAdapter.scheduleSelfCall,
                (
                    PROBE_JOB_ID,
                    expiry,
                    SCHEDULE_GAS_LIMIT,
                    abi.encodeCall(HederaProbeFacet.probeCallback, (PROBE_JOB_ID))
                )
            ),
            "report() reads scheduleOf(jobId) - poll that address on the mirror node"
            " (/api/v1/schedules/<id>) ~60s out, then read HederaProbeCallback on HashScan: sender == the"
            " diamond confirms HSSAdapterLib.checkScheduledSelfCall's msg.sender assumption"
        );
        _line("job-id  ", vm.toString(PROBE_JOB_ID), "the scheduleOf key report(address) reads back");
        _line(
            "expiry  ", vm.toString(expiry), "fork-clock seconds; the relay rejects an expiry at/below consensus time"
        );

        vm.stopBroadcast();

        _printVerifyCommands(diamond, cuts, names);
        console2.log("");
        console2.log(
            string.concat(
                "NEXT: --sig \"follow(address)\" ",
                vm.toString(diamond),
                "   then   --sig \"report(address)\" ",
                vm.toString(diamond)
            )
        );
        console2.log("=============================================================================");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          STEP 2 - PROBES 1 AND 2 (MINT)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The probes that consume probe 2's token: probe 1 (`associateToken` from a facet) and probe 2's
    ///         `mintToken`. The token address exists only on-chain, so it is read back through
    ///         `vm.rpc("eth_call", createdTokens())` before either call is broadcast.
    /// @param diamond The probe diamond `run()` printed.
    function follow(address diamond) external {
        console2.log("");
        console2.log("=== LATTICE HEDERA DAY-0 PROBE - FOLLOW ======================================");
        address[] memory tokens = _readCreatedTokens(diamond);
        if (tokens.length == 0) {
            _line(
                "ABORT   ",
                "createdTokens() is empty",
                "probe 2's create never landed - check the run() receipts before re-running follow()"
            );
            return;
        }
        address token = tokens[0];
        _line("token   ", vm.toString(token), "probe 2's token, read live from the diamond's createdTokens()");

        address admin = _beginBroadcast();
        _line("admin   ", vm.toString(admin), "the broadcaster; holds HTS_MANAGER_ROLE and HTS_OPERATOR_ROLE");

        // --- PROBE 1: associateToken from a facet ------------------------------------------------------
        console2.log("");
        console2.log("--- PROBE 1: associateToken from a facet ---------------------------------------");
        _probe(
            diamond,
            0,
            abi.encodeCall(IHTSAdapter.associateToken, (token)),
            "the diamond is this token's TREASURY, so the outcome separates three worlds: a revert carrying"
            " HTSTokenAlreadyAssociated (HTS code 194) proves creation auto-associated the treasury AND that"
            " HTS keys the call on the DIAMOND (msg.sender inside the facet's delegatecall frame); a clean"
            " SUCCESS means creation does NOT auto-associate; anything else means the frame is not seen as the"
            " diamond at all. report() then prints isAssociated(token), the association state itself"
        );

        // --- PROBE 2 (continued): mintToken from a facet ------------------------------------------------
        console2.log("");
        console2.log("--- PROBE 2 (cont.): mintToken from a facet ------------------------------------");
        _probe(
            diamond,
            0,
            abi.encodeCall(IHTSAdapter.mintToken, (token, PROBE_MINT_AMOUNT, new bytes[](0))),
            "a successful mint proves the delegatableContractId SUPPLY key HTSAdapterLib sets is ACTIVE for a"
            " facet call - the positive control probe 3 is the negative of"
        );

        vm.stopBroadcast();
        console2.log("");
        console2.log(
            string.concat("NEXT: --sig \"report(address)\" ", vm.toString(diamond), "  (broadcast-free, re-runnable)")
        );
        console2.log("=============================================================================");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        STEP 3 - THE READ-ONLY REPORT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reads every probe result back OFF-REVM and prints it: the live HBAR balance (probe 2's refund),
    ///         the association state (probe 1), the view-classified getters and 0x168 conversions (probe 4),
    ///         the schedule address (probe 6) and `isAuthorizedRaw` (probe 7). Broadcast-free and re-runnable.
    /// @dev Every read goes through `vm.rpc(HEDERA_TESTNET_ALIAS, "eth_call", ...)`. A forked `staticcall`
    ///      would be meaningless: the relay reports no code at 0x168 / 0x16a, so revm would return empty data
    ///      and the facets would surface that as a revert or a `false`. `vm.rpc` hands the call to the relay,
    ///      where the mirror node executes it for real.
    /// @param diamond The probe diamond `run()` printed.
    function report(address diamond) external {
        console2.log("");
        console2.log("=== LATTICE HEDERA DAY-0 PROBE - REPORT ======================================");
        _line("diamond ", vm.toString(diamond), "read through vm.rpc eth_call on the hedera-testnet alias");

        // --- PROBE 2: the live balance (excess-msg.value refund) ---------------------------------------
        console2.log("");
        console2.log("--- PROBE 2: the diamond's live HBAR balance ----------------------------------");
        bytes memory raw = _rpc("eth_getBalance", string.concat("[\"", vm.toString(diamond), "\",\"latest\"]"));
        _line(
            "balance ",
            string.concat(vm.toString(_toUint(raw)), " weibar (raw ", vm.toString(raw), ")"),
            "above the 30 HBAR funded => HTS refunded the unspent creation fee to the DIAMOND (probe 2 AND"
            " probe 3 each forward 20 HBAR, so both refunds land here: ~68 HBAR is the both-refunded"
            " expectation); at or below 30 => the refund went elsewhere and a create must be funded exactly"
        );

        address[] memory tokens = _readCreatedTokens(diamond);
        if (tokens.length == 0) {
            _line("ABORT   ", "createdTokens() is empty", "probe 2's create never landed; nothing else to read");
            return;
        }
        address token = tokens[0];
        _line("token   ", vm.toString(token), "probe 2's token");

        // --- PROBE 1: the association state -------------------------------------------------------------
        console2.log("");
        console2.log("--- PROBE 1: the association state ---------------------------------------------");
        raw = _call(diamond, abi.encodeCall(IHTSAdapter.isAssociated, (token)));
        _line(
            "isAssociated",
            _boolOrEmpty(raw),
            "true => the diamond IS associated (as treasury, or by follow()'s associateToken); this is the"
            " HIP-719 facade on the token address answering for the diamond's own account"
        );

        // --- PROBE 4: the view-classified getters and the 0x168 conversions -----------------------------
        console2.log("");
        console2.log("--- PROBE 4: view-classified getters from a view path -------------------------");
        raw = _call(diamond, abi.encodeCall(IHTSAdapter.isHTSToken, (token)));
        _line(
            "isToken ",
            _boolOrEmpty(raw),
            "true => HTS's isToken is genuinely callable through a facet STATICCALL, so HTSAdapter's view"
            " classification holds; empty data => it is not a view and the getters must become non-view"
        );
        raw = _call(diamond, abi.encodeCall(IHTSAdapter.htsTokenType, (token)));
        _line(
            "tokenType",
            raw.length == 0 ? "<empty>" : vm.toString(int256(abi.decode(raw, (int32)))),
            "0 => FUNGIBLE_COMMON (expected for probe 2's token), 1 => NON_FUNGIBLE_UNIQUE"
        );
        raw = _call(diamond, abi.encodeCall(IHederaExchangeRateAdapter.tinycentsToTinybars, (ONE_CENT_IN_TINYCENTS)));
        _line(
            "1 US cent",
            raw.length == 0 ? "<empty>" : string.concat(vm.toString(abi.decode(raw, (uint256))), " tinybars"),
            "a non-zero answer => the 0x168 conversions really are view-callable from a facet staticcall;"
            " empty => HederaExchangeRateAdapterLib's `view` classification is wrong"
        );
        raw = _call(diamond, abi.encodeCall(IHederaExchangeRateAdapter.hbarUsdWad, ()));
        _line(
            "HBAR/USD",
            raw.length == 0 ? "<empty>" : string.concat(vm.toString(abi.decode(raw, (uint256))), " wad"),
            "sanity check the derived price against the published HBAR rate; a wild value means the tinycent"
            " scaling in hbarUsdWad is wrong"
        );

        // --- PROBE 6: the schedule address --------------------------------------------------------------
        console2.log("");
        console2.log("--- PROBE 6: the scheduled self-call -------------------------------------------");
        raw = _call(diamond, abi.encodeCall(IHSSAdapter.scheduleOf, (PROBE_JOB_ID)));
        _line(
            "schedule",
            raw.length == 0 ? "<empty>" : vm.toString(abi.decode(raw, (address))),
            "poll /api/v1/schedules/<id> on the testnet mirror node: `executed_timestamp` set => the network"
            " fired it; then read HederaProbeCallback on HashScan for the sender it presented"
        );

        // --- PROBE 7: isAuthorizedRaw through HASSignatureVerifier ---------------------------------------
        console2.log("");
        console2.log("--- PROBE 7: isAuthorizedRaw through HASSignatureVerifier ----------------------");
        address account = vm.envOr("HEDERA_TEST_ACCOUNT", address(0));
        bytes32 messageHash = vm.envOr("HEDERA_TEST_HASH", bytes32(0));
        bytes memory signature = vm.envOr("HEDERA_TEST_SIG", bytes(""));
        if (account == address(0) || messageHash == bytes32(0) || signature.length == 0) {
            _line(
                "SKIPPED ",
                "HEDERA_TEST_ACCOUNT / HEDERA_TEST_HASH / HEDERA_TEST_SIG unset",
                "set all three (65-byte ECDSA or 64-byte ED25519 signature) and re-run report() to settle it"
            );
        } else {
            raw = _call(
                diamond, abi.encodeCall(IHASSignatureVerifier.isAuthorizedRaw, (account, messageHash, signature))
            );
            _line(
                "authorized",
                _boolOrEmpty(raw),
                "HAS isAuthorizedRaw returns a BARE bool - a pure signature check, not the RESPONSE_CODE64_BOOL"
                " flow - so true here means HASSignatureVerifierLib decodes the right shape and an ED25519-keyed"
                " Hedera account can sign for a Lattice smart account"
            );
        }

        console2.log("=============================================================================");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 INTERNALS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Starts the broadcast as `HEDERA_TESTNET_PK` when it is set, else as `--account` / `--sender`.
    /// @return broadcaster The address every probe transaction is sent from, and the diamond's admin.
    function _beginBroadcast() private returns (address broadcaster) {
        uint256 pk = vm.envOr("HEDERA_TESTNET_PK", uint256(0));
        if (pk == 0) {
            broadcaster = msg.sender;
            vm.startBroadcast();
        } else {
            broadcaster = vm.addr(pk);
            vm.startBroadcast(pk);
        }
    }

    /// @dev Broadcasts one probe call and logs it. The call is LOW-LEVEL and its failure is never propagated:
    ///      in the local frame every Hedera system contract is dead (0x167 answers `0xfe`, 0x168 / 0x169 / 0x16a /
    ///      0x169 / 0x16a have no code), so `ok == false` here is the EXPECTED local result and says nothing
    ///      about the broadcast transaction — ASSUMING Foundry queued it at frame entry (see this contract's
    ///      header). Read the receipt, the emitted events, and `report(address)`.
    /// @param target The probe diamond.
    /// @param value HBAR forwarded as `msg.value`.
    /// @param data The encoded probe call.
    /// @param settles What the on-chain outcome of this probe decides.
    function _probe(address target, uint256 value, bytes memory data, string memory settles) private {
        _line("selector", vm.toString(bytes4(data)), "the broadcast call; full calldata below");
        _line("calldata", vm.toString(data), "replayable with `cast send` against the same diamond");
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        _line(
            "local   ",
            string.concat("ok=", vm.toString(ok), " return=", vm.toString(ret)),
            "revm cannot execute a Hedera system contract, so ok=false is expected and carries NO verdict"
        );
        _line("settles ", "see below", settles);
    }

    /// @dev The diamond's `createdTokens()` read live through the relay (empty when the create never landed).
    function _readCreatedTokens(address diamond) private returns (address[] memory tokens) {
        bytes memory raw = _call(diamond, abi.encodeCall(IHTSAdapter.createdTokens, ()));
        if (raw.length == 0) return new address[](0);
        tokens = abi.decode(raw, (address[]));
    }

    /// @dev One `eth_call` against `to`, executed by the relay rather than revm.
    /// @return raw The call's verbatim return data (empty when the relay returned `0x`, i.e. it reverted).
    function _call(address to, bytes memory data) private returns (bytes memory raw) {
        raw = _rpc(
            "eth_call",
            string.concat("[{\"to\":\"", vm.toString(to), "\",\"data\":\"", vm.toString(data), "\"},\"latest\"]")
        );
    }

    /// @dev A JSON-RPC round trip against the `hedera-testnet` alias, normalised to the result's payload.
    ///      `vm.rpc` ABI-encodes the JSON result, and the encoding depends on the value's SHAPE: a result
    ///      exactly one word wide is assumed to arrive as that word, anything longer as a dynamic `bytes`
    ///      (offset - length - payload). That is assumed, not verified — so the dynamic branch is taken ONLY
    ///      when word 0 really is the 0x20 offset, and any other shape is handed back verbatim. Every caller
    ///      length-checks what it gets, so a wrong shape degrades to a raw / `<empty>` log line instead of
    ///      reverting the whole report.
    function _rpc(string memory method, string memory params) private returns (bytes memory payload) {
        bytes memory encoded = vm.rpc(HEDERA_TESTNET_ALIAS, method, params);
        if (encoded.length < 64) return encoded;
        bytes32 head;
        assembly ("memory-safe") {
            head := mload(add(encoded, 0x20))
        }
        if (head != bytes32(uint256(0x20))) return encoded;
        payload = abi.decode(encoded, (bytes));
    }

    /// @dev Big-endian value of up to 32 bytes, right-aligned — for a JSON-RPC quantity (`eth_getBalance`
    ///      answers `0x1bc…`, not a padded word) as well as for a single ABI word.
    function _toUint(bytes memory b) private pure returns (uint256 value) {
        uint256 len = b.length > 32 ? 32 : b.length;
        for (uint256 i; i < len; ++i) {
            value = (value << 8) | uint8(b[i]);
        }
    }

    /// @dev `"true"` / `"false"` for a decodable bool return, `"<empty>"` when the relay returned nothing.
    function _boolOrEmpty(bytes memory raw) private pure returns (string memory) {
        if (raw.length == 0) return "<empty> (the relay reverted this call)";
        return abi.decode(raw, (bool)) ? "true" : "false";
    }

    /// @dev PROBE 8: the exact Sourcify verification commands for the diamond and every facet it was cut with.
    ///      Hedera-bound builds MUST use `FOUNDRY_PROFILE=hedera` (Cancun) or the bytecode will not match.
    ///      The one-shot initializers are omitted deliberately: they are delegatecalled once and are not part
    ///      of the diamond's runtime surface.
    function _printVerifyCommands(address diamond, FacetCut[] memory cuts, string[] memory names) private pure {
        console2.log("");
        console2.log("--- PROBE 8: verification commands (run under FOUNDRY_PROFILE=hedera) ----------");
        console2.log(_verifyCommand(diamond, "src/Lattice.sol:Lattice"));
        for (uint256 i; i < cuts.length; ++i) {
            console2.log(_verifyCommand(cuts[i].facetAddress, names[i]));
        }
    }

    /// @dev One `forge verify-contract` line for `target` compiled from artifact id `name`.
    function _verifyCommand(address target, string memory name) private pure returns (string memory) {
        return string.concat(
            "FOUNDRY_PROFILE=hedera forge verify-contract ",
            vm.toString(target),
            " ",
            name,
            " --chain ",
            vm.toString(HEDERA_TESTNET_CHAIN_ID),
            " --verifier sourcify"
        );
    }

    /// @dev One result line: a label, the raw value, and what that value implies.
    function _line(string memory label, string memory value, string memory implies) private pure {
        console2.log(string.concat(label, "  ", value));
        console2.log(string.concat("          => ", implies));
    }
}
