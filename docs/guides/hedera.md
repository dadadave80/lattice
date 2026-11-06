# Lattice on Hedera

Mount Hedera's system contracts as Diamond facets: hold and issue HTS tokens, verify ED25519 account
signatures, read the network exchange rate, draw a native random seed, and schedule your own future calls.
The contracts are unaudited. **No transaction here has been sent to a live Hedera network** — every
behaviour below that needs a signed transaction is still an assumption read from consensus-node source.
Read-only `eth_call`s against the public testnet relay HAVE been run; what they settled is marked confirmed
in [Verification status](#verification-status).

## The five modules

| Facet | Area | System contract | What it gives a diamond |
| --- | --- | --- | --- |
| `HTSAdapter` | `src/tokens/hedera/` | HTS `0x167` | The diamond as an HTS account: associate/dissociate itself, create fungible and non-fungible tokens it treasuries, mint, burn, transfer its own balance, and spend an allowance granted to it. |
| `HASSignatureVerifier` | `src/accounts/hedera/` | HAS `0x16a` | HIP-632 `isAuthorizedRaw` / `isAuthorized` as never-reverting views, and the `SignerType.HederaAccount` branch that lets a **Hedera ED25519 account own a Lattice smart account**. |
| `HederaExchangeRateAdapter` | `src/oracles/hedera/` | Exchange Rate `0x168` | Tinycent/tinybar conversion and a USD-cents helper for pricing HTS fees. The network's *fee* rate, refreshed roughly hourly — never a liquidation price feed. |
| `HederaPrngAdapter` | `src/oracles/hedera/` | PRNG `0x169` | A synchronous 32-byte seed with no request/callback round trip. The ordering node sees the seed first — do not use it where that matters. |
| `HSSAdapter` | `src/oracles/hedera/` | HSS `0x16b` | HIP-1215 scheduled contract calls and HIP-755 schedule authorization; the diamond pays for and admins what it schedules. |

None of the system contracts has bytecode. Every Lattice library reaches them with `call` or `staticcall`
and never `delegatecall` — a direct delegatecall from user code has been blocked since consensus node
v0.34.5 and halts the frame with `PRECOMPILE_ERROR`, burning the frame's gas.

HTS, HAS and HSS return `int64` **response codes** instead of reverting (`SUCCESS == 22`). Each library maps
the codes its module can produce to typed errors and everything else to a catch-all carrying the selector and
the raw code, so an integrator can always recover the network's own answer. A failed frame is treated as
`UNKNOWN` (21).

## The delegatable-key rule

This is the one Hedera fact that changes how you configure a token, and it exists **because** Lattice is a
diamond. It is also more subtle than it first appears — we measured it on testnet and the naive statement
of it is wrong.

A facet call is a `delegatecall` frame. When that frame calls HTS, the node passes
`hasParentDelegateCall = true`, which becomes `onlyDelegatableContractKeysActive`, and
`ActiveContractVerificationStrategy.decideForPrimitive` then returns `INVALID` for a plain `contractId`
key. So **wherever a `contractId` key is actually verified, it fails.** `HTSAdapterLib` therefore sets
`key.delegatableContractId = address(this)` on every key it creates, and that is the right call.

What is **not** true is the tempting shorter version — "a `contractId` key held by a diamond is dead and
fails with 326". On testnet (consensus node 0.76.3, 2026-09-12) a token whose supply key was
`contractId(<diamond>)` minted **successfully** from a facet, twice, including through the production
`HTSAdapter.mintToken` path (token `0.0.10506858`, supply 1000 → 1777).

The reason is **payer-key elision**, not activation. A relay-deployed contract's own account key is
`contractId(self)`. The dispatched child `TokenMint`'s synthetic payer is the diamond, so its payer key is
`contractId(<diamond>)` — byte-identical to that supply key — and `PreHandleContextImpl.requireKey` drops a
required key equal to the payer key. The supply key was never verified at all. A `delegatableContractId`
key is a different protobuf oneof (field 8 vs field 1), so it is *not* equal to the payer key: it really is
required, really is verified, and really does pass.

Keep using `delegatableContractId`, because it is the form that is verified-and-passes rather than merely
skipped, and because the elision does not cover:

- a diamond whose account key is not `contractId(self)` (e.g. created by a HAPI `ContractCreate` with an
  explicit ED25519 admin key) — there a `contractId` key is verified, and dies;
- a `contractId` nested inside a `KeyList` or `ThresholdKey` — not `.equals()` the payer key, so required;
- any key naming a contract other than the caller.

Those three are read from consensus-node source and are **not** measured — treat them as inference.

If you hand a diamond a token created elsewhere, update its keys to the delegatable form
(`updateTokenKeys`) rather than relying on the elision. Operations needing only the diamond's own account
authority — moving its own balance, associating itself — work regardless, because the diamond is the child
transaction's payer.

## Associate before you receive

A contract created by a top-level `EthereumTransaction` — which is everything `forge script` broadcasts — gets
`maxAutomaticTokenAssociations = 0`. A diamond created through `LatticeFactory` inherits the factory's 0.
So a diamond has **no** auto-association slots and must associate explicitly, from a facet, before it can
receive a token:

```solidity
IHTSAdapter(diamond).associateToken(token);   // HTS_MANAGER_ROLE
```

Dissociation fails with `TRANSACTION_REQUIRES_ZERO_TOKEN_BALANCES` (195, surfaced as `HTSNonZeroBalance`)
while any balance remains, and with `ACCOUNT_IS_TREASURY` (196, surfaced as `HTSAccountIsTreasury`) for a token
the diamond treasuries — the treasury seat is refused first, however empty the balance is.

Two consequences worth planning for: a diamond that is a token treasury or holds HTS tokens cannot be torn
down, and a diamond that is a token's auto-renew account takes on that token's renewal charges — so it must
hold HBAR. That is why `Receive` is in the `DeployHTSAdapter` recipe.

## Build with the Hedera profile

Lattice explicitly pins Cancun for its default, CI and Hedera profiles; it does not inherit Solidity
0.8.36's newer default target. The node and EVM versions in the dated probe results below describe those
measurements. A network protocol upgrade does not independently change the release compiler target.

Earlier releases compiled the default profile for Osaka. Switching to Cancun changes compiler metadata
and deterministic addresses, even where executable code is identical. Reproduce a historical deployment
from its release tag and settings. Build and deploy everything Hedera-bound under the dedicated profile:

```sh
script/config/hedera/forge-hedera.sh build --skip test script
```

Deploy with the canonical recipe, through the same wrapper (the relay note below explains the pin):

```sh
script/config/hedera/forge-hedera.sh script script/base/tokens/DeployHTSAdapter.s.sol \
    --sig "run(address)" <ADMIN> \
    --rpc-url hedera-testnet --account <keystore> --broadcast --slow --legacy \
    --verify --verifier sourcify
```

That command without `--broadcast` simulates cleanly against hedera-testnet (checked 2026-09-12 and 2026-10-08).
Sourcify verification under the pin is still unconfirmed — probe 8 in the table below.

Keep `[profile.hedera]` on the canonical Cancun target. A future target change needs a coordinated
release-build decision and updated reproducibility checks, rather than a chain-local compiler override.

`hedera` (295) and `hedera-testnet` (296) are already named RPC aliases in `foundry.toml`; set
`HEDERA_RPC_URL` / `HEDERA_TESTNET_RPC_URL` in `.env`.

**Run Hedera `forge script` work on Foundry 1.7.1.** By default, Foundry 1.8 cannot reach Hedera's JSON-RPC
relay from `forge script` or a forking test; 1.7.1 can. The two versions ask the relay for account state
differently (against hashio; 1.8.1 measured 2026-09-12, 1.7.1 re-traced 2026-10-08):

```
forge 1.7.1 -> eth_getTransactionCount(addr, "0x279521e")                     exit 0
forge 1.8.1 -> eth_getTransactionCount(addr, {"blockHash": "0x671a…", ...})    -32602
               Invalid parameter 1: The value passed is not valid: [object Object].
```

In the 2026-09/10 measurements, 1.7.1 asked for state at a block number (and the sender's first nonce at
`"latest"`). 1.8's fork backend sent an EIP-1898 block-hash object, `{"blockHash": …, "requireCanonical": false}`.
On `eth_getTransactionCount`, `eth_getBalance`, `eth_getCode` and `eth_getStorageAt`, the then-deployed Hedera
relay (`hiero-json-rpc-relay`) validated the block parameter as a string (a number, a tag or a bare hash), so
it rejected every EIP-1898 object with `-32602`, and `eth_getCode` also rejected a bare hash (`-39012`).
`eth_call` accepted `{"blockHash": …}` and `{"blockNumber": …}` but rejected the `requireCanonical` key, so all
five methods rejected the exact object 1.8 sent. EIP-1898 is standard
Ethereum JSON-RPC, and so is the older form. Measured 2026-09-12 with a script that deploys nothing: on 1.8.1 no
flag avoids it (`--legacy`, `--slow`, `--skip-simulation` with and without `--broadcast`, `--fork-block-number`,
`--no-storage-caching`, `--offline`, `--sender-nonce`, `--unlocked`, `--sender`, `--estimate`), and changing relay
does not help — a QuickNode Hedera-testnet endpoint returns the byte-identical error with the same relay Request-ID
format.

Re-measured 2026-10-08 against `https://testnet.hashio.io/api` (`relay/0.79.0`), with the `DeployHTSAdapter`
simulation above (no `--broadcast`, no key) and `HTSAdapterFork` with `HEDERA_TEST_FORK=true`:

| Foundry | `DeployHTSAdapter` simulation | `HTSAdapterFork` forking test |
| --- | --- | --- |
| 1.7.1 (`4072e48`) | passes | passes |
| 1.8.1 (`982849d`) | `-32602 … [object Object]` | not re-run (failed 2026-09-12) |
| 1.8.3 (`cae51ad`) | `-32602 … [object Object]` | not run |
| 1.8.5 (`51a52c5`), default | `-32602 … [object Object]` | fails with the same database error |
| 1.8.5 with `--fork-state-by-number` | passes, no block-hash params sent | passes |

`--fork-state-by-number` (also `FOUNDRY_FORK_STATE_BY_NUMBER=true`, which behaved the same in the simulation;
config key `fork_state_by_number`, not exercised) reaches `forge script` and `forge test` in 1.8.5
([foundry-rs/foundry#17352](https://github.com/foundry-rs/foundry/pull/17352)); in 1.8.3 and 1.8.4 it is an
`anvil` flag only. Its help text warns that number-based reads cannot guarantee a consistent snapshot if the chain
reorganizes and skip the disk state cache, and that transaction replay still needs hash-addressed state. No
broadcast has been made with it yet, so the wrapper stays the supported route until #227 verifies one and retires
the exception.

The repo's shared pin for CI, builds and tests is v1.9.0. The documented Hedera exception remains until
#227 verifies a broadcast on the shared pin. The historical table above concerns the listed 1.8 releases.
A read-only recheck on 2026-11-06 against the same endpoint reported `relay/0.80.3`: all 30 requests
(five state/call methods, each with `latest`, number, bare hash, `{blockHash}`,
`{blockHash, requireCanonical: false}` and `{blockNumber}`) succeeded. Foundry 1.9.0 (`6056c58`) passed
`DeployHTSAdapter` simulation and both `HTSAdapterFork` tests on source checkpoint
`fa606adca0129bedd8dabd54e1392a815234888b`. These checks did not broadcast a transaction.
Hedera work goes through a wrapper that runs the installed 1.7.1 binary directly under
`FOUNDRY_PROFILE=hedera`, without touching your active `forge`:

```sh
foundryup --install v1.7.1    # once; then `foundryup --use <your usual version>` if foundryup switched to it
script/config/hedera/forge-hedera.sh <forge args…>
```

Historical parity check: under `[profile.hedera]`, Foundry 1.7.1 (`4072e48`) and 1.8.5
(`51a52c5`) resolve the same compiler settings and both build with solc `0.8.36+commit.8a079791`. Re-checked
2026-10-08: `HTSAdapter`, `ERC20` and `Lattice` have identical creation and runtime bytecode, with the CBOR
metadata tail stripped and with it included. The same holds for every other `src/` and `lib/` artifact. The only
differences are the metadata of three `test/` helpers, which Forge's test-linking preprocessor touches. So an
Arachnid address or a Sourcify metadata hash computed under one version holds for a deploy made under the
other. The same check passed for 1.7.1 against 1.8.1 on 2026-09-12.
Rechecked on 2026-11-06 at the same `fa606adc` source checkpoint: 1.7.1 and 1.9.0 with solc 0.8.36,
Cancun and `[profile.hedera]` produced identical creation/runtime bytecode (metadata included), library
link references and immutable patch positions for all 647 source/library contract and interface
artifacts; 407 had nonempty creation/runtime code. This is build parity for that checkpoint, not a
shared-pin broadcast verification or a promise that later source edits preserve deterministic addresses.

Anything that never opens a fork backend works on **both** versions — `forge create`, `cast send` / `call` /
`mktx`, and `vm.rpc` inside a test. `--legacy` is worth passing as Hedera's native transaction form, but it is
not what fixes this: `cast mktx` signs cleanly in both legacy and EIP-1559 form. `--slow` helps against rate
limits.

## Deterministic deployment: Arachnid, not CreateX

CreateX (`0xba5Ed099…ba5Ed`) is **not** deployed on Hedera. The Arachnid deterministic-deployment proxy
`0x4e59b44847b379578588920cA78FbF26c0B4956C` **is** (mainnet `0.0.6264020`, testnet `0.0.4283707`).
`ArachnidDeployer` is the canonical release path on every chain, and `BaseDeploy._facet` reuses or
deploys facets through that proxy even where CreateX is also present.

Release addresses use plain EIP-1014 with the proxy as deployer and the unguarded salt. The same build,
salt and constructor arguments therefore give the same addresses on Hedera and other chains. Older
CreateX-first development deployments remain historical instances; reproduce them from their original
source and configuration. See [the release reference](../../REGISTRY_DEPLOYMENTS.md).

`LatticeFactory.deploy` uses a native `new Lattice{salt}()`, which is standard EIP-1014 (HIP-329) and works
unmodified. Hedera's EIP-6780 semantics never delete a pre-existing contract, so the metamorphic-redeploy
concern does not arise.

## What does not work on Hedera

- **`Account7702Diamond`.** EIP-7702 is HIP-1340, approved and implemented, but
  `contracts.codeDelegations.enabled = false` even on the v0.77 branch. Gate its recipe on chain id.
- **`SignerType.HederaAccount` on a non-Hedera chain.** `setHederaAccountSigner` refuses outright where HAS
  does not answer, and that refusal is load-bearing rather than defensive: a Lattice account is its own
  `DEFAULT_ADMIN_ROLE` holder, so the signer you install is the one every later admin call must satisfy —
  `setOwner`, the only route back to ECDSA, included. Arming a Hedera signer with no live HAS would make
  every signature `false` with no authority left able to undo it, stranding the account and its `diamondCut`
  upgrade path permanently. The check probes the system contract for a real answer rather than allowlisting
  chain ids, so it stays correct on previewnet, a Solo local network, and any future Hedera chain id.
- **P256 / WebAuthn signers.** Hedera has no secp256r1 precompile (EIP-7951 is an Osaka feature) and `0x100`
  there is a system account, so `SignerType.P256` and `SignerType.WebAuthn` return `false` unless the Solady
  fallback verifier contract is deployed on the chain. Use `SignerType.HederaAccount` instead — it is strictly
  better on Hedera, because HAS follows key rotation.
- **Safe v1.4.1.** Only v1.3.0 is on Hedera mainnet, and Hedera is absent from the `safe-deployments`
  registry, so `SafeDiamondCut` / `GovernedSafeDiamondCut` recipes must point at v1.3.0.
- **HIP-1028 token metadata keys** (Deferred) and **HIP-1195 hooks** (approved, disabled by default).
- **Fork tests that execute a system contract.** A Foundry fork fetches state over RPC and executes locally in
  revm; the relay reports `0xfe` as the code of `0x167` and nothing at all for `0x168`/`0x169`/`0x16a`/`0x16b`, so no
  HTS/HAS/HSS call executes on a plain fork — reads included. `test/fork/HTSAdapterFork.t.sol` asserts that
  local shape and uses `vm.rpc("eth_call", …)` to hand anything that must really execute to the relay, where
  the mirror node simulates it. The one test that forks reaches hashio on the pinned Foundry 1.7.1, but not
  on the shared pin's defaults, whose EIP-1898 block-hash params the relay rejects. So it sits behind its own
  `HEDERA_TEST_FORK=true` opt-in and runs through `script/config/hedera/forge-hedera.sh`. Setting
  `HEDERA_TEST_TOKEN` alone gives you the relay-backed test plus a skip, never a spurious failure.

## Verification status

Nothing below has been executed on a live Hedera network. The semantics marked **assumed** are read from
consensus-node source and HIP text but are not yet confirmed on-chain; `script/config/hedera/ProbeHedera.s.sol`
exists to settle them, and is deliberately not broadcast by CI.

| # | Behaviour | Status |
| --- | --- | --- |
| 1 | `associateToken` from a facet, then an inbound transfer | still assumed — the probe's association target was its own treasury token, so it could only ever return 194 |
| 2 | `createFungibleToken` with `delegatableContractId` keys, then `mintToken` from a facet | **confirmed live, 2026-09-12** — token `0.0.10506856` created by a facet with the diamond as treasury and delegatable admin+supply keys; `HTSAdapter.mintToken` minted 500. Excess-`msg.value` refund still unmeasured |
| 3 | The same create with a `contractId` key → 326 | **REFUTED live, 2026-09-12** — minted successfully instead (token `0.0.10506858`, supply 1000 → 1777). The control was degenerate: the key was byte-identical to the diamond's own account key and got elided before verification. See "The delegatable-key rule" |
| 4 | HTS getters and both HAS auth functions staying `view` (`staticcall`-safe) | partly confirmed — `isToken` answers `(22, true)` through the relay's `eth_call` (2026-09-12); whether a diamond's own `view` facet function may `staticcall` it *inside a transaction* is still assumed |
| 5 | `redirectForAccount(address(this), …)` giving a diamond unlimited auto-associations | partially measured — the frame succeeded and returned 32 bytes decoding to `15`, so `0x16a` does expose the entrypoint; whether the association limit actually changed is unverified, and `redirectForAccount` stays out of the vendored interface until it is |
| 6 | `scheduleSelfCall` firing with `msg.sender == address(this)` | still assumed — the attempt reverted `HSSInvalidExpiry`: the probe computed the expiry from the fork clock, 125 s behind consensus time |
| 7 | ED25519 verification through `isAuthorizedRaw` from the ERC-1271 path | assumed |
| 8 | Sourcify verification reproducing under `FOUNDRY_PROFILE=hedera` | assumed |
| — | System-contract code shape, **both** networks: `eth_getCode(0x167)` is `0xfe`; `0x168`, `0x169`, `0x16a` and `0x16b` are all empty. (The research brief said `0x16b` also answers `0xfe` — it does not.) | **confirmed live, 2026-09-12** |
| — | CreateX `0xba5Ed099…ba5Ed` has no code on Hedera mainnet or testnet | **confirmed live, 2026-09-12** |
| — | The Arachnid proxy `0x4e59b448…956C` has code on Hedera mainnet **and** testnet, byte-identical to `test/helpers/ArachnidProxy.RUNTIME` | **confirmed live, 2026-09-12** |
| — | `forge script` on Foundry 1.8.1 cannot reach Hedera's relay (its fork backend's EIP-1898 block-hash params are rejected, by hashio and QuickNode alike); Foundry 1.7.1 can, and the probe run was made with it. Whether Foundry or the relay should change is open | **confirmed live, 2026-09-12** |
| — | The relay (`relay/0.79.0` on hashio) rejected EIP-1898 objects on `eth_getTransactionCount`, `eth_getBalance`, `eth_getCode` and `eth_getStorageAt` with `-32602` (`eth_call` accepts them but rejects the `requireCanonical` key Foundry adds), and Foundry 1.8.3 and 1.8.5 still send them by default. Foundry 1.8.5's `--fork-state-by-number` reaches it in a `forge script` simulation and the forking `HTSAdapterFork` test; a broadcast under it is unverified (#227) | **confirmed live, 2026-10-08** |
| — | Hashio reported `relay/0.80.3`; all 30 state/call request forms above succeeded. The shared Foundry 1.9.0 pin passed `DeployHTSAdapter` simulation and both `HTSAdapterFork` tests; 1.7.1/1.9.0 build parity holds at `fa606adc`. The shared-pin broadcast needed to retire the wrapper is still unverified (#227) | **read-only checks, 2026-11-06** |

To run the probes you need a funded testnet account: set `HEDERA_TESTNET_RPC_URL` and `HEDERA_TESTNET_PK`
in `.env` and fund the derived address from the Hedera portal faucet. Record each outcome in the relevant
module's natspec as `@dev Verified on testnet <date>, consensus node vX.Y` — the node version matters, because
v0.77 changes gas accounting.

## Out of scope for now

Exchange-rate and PRNG recipes and tests (Phase 2), plus native HSS callback verification (probe6);
custom fees, KYC/freeze/pause/wipe,
HIP-904 airdrops, `hedera-forking` facade tests and a Solo local-node CI job (Phase 3). The exchange-rate and PRNG skeletons compile and are inventoried; HSS now has a recipe and offline
recovery tests, with native sender verification still outstanding.

## Recovering scheduled self-call jobs

The HSS recipe (`DeployHSSAdapter`) now pairs the frozen seven-selector `HSSAdapter` interface
(`0xd07095cf`) with `HSSAdapterRecovery` (`0x4d10dd54`). The latter wraps new `scheduleSelfCall` bookings
in a job-and-generation envelope. The original callback still calls `completeSelfCall(jobId)` before
rescheduling, and the diamond needs `HSS_SCHEDULER_ROLE` itself if it schedules its next occurrence.
Budget `gasLimit` for the envelope's context writes and self-call as well as the callback.

A scheduler-role holder can call `cancelSelfCall(jobId)` after deletion, an unfired expiry, a failed
callback, or missing HBAR. Local state and its generation are invalidated before a best-effort native
`deleteSchedule` call. Its return/event flag reports native deletion success; the native attempt is
capped at 100,000 gas, copies only one return word, and may be skipped when the call needs to reserve
event/return gas. An unsuccessful native deletion cannot retain the local reservation. A stale wrapped
callback is rejected before business logic executes.

Upgrade both facets together and run `HSSAdapterRecoveryInit` inside the upgrade's initialization
window to register the additional interface. Storage is append-only. Existing unwrapped jobs have no
generation context: cancel and reschedule them. Their raw payload can still execute if native deletion
fails, although `completeSelfCall` cannot clear a replacement. Review those legacy payloads before
reusing the same business operation; local recovery cannot retroactively wrap or veto them.

Self-call authority remains a trust boundary. Do not install unrestricted public self-call executors.
The network-fired payer/sender assumption is still **unverified**: probe6 now uses raw `scheduleCall`
to its ungated callback, so the envelope's extra self-call cannot manufacture the measured sender.
Read `HSSCallScheduled` in that transaction's receipt for its schedule address; `scheduleOf` describes
tracked jobs, not this raw probe. The existing
[upstream payer-signature report](https://github.com/hiero-ledger/hiero-consensus-node/issues/27263)
records two testnet schedules created on 2026-09-12 that failed `INVALID_PAYER_SIGNATURE` before entering
the EVM. It does not establish the behavior of the current node or the callback sender. Issue
[#226](https://github.com/dadadave80/lattice/issues/226) still needs a separately authorized successful
native callback with its sender, schedule ID, date and measured consensus-node version. Offline mock
coverage and local generation safety do not satisfy that live acceptance.

### Minimal native sender probe

`ProbeHedera.planProbe6` prepares a single raw `scheduleCall` against an **existing** probe diamond.
`probe6` queues that call using the CLI sender. Neither entrypoint deploys a diamond, funds it, creates
tokens, reads `HEDERA_TESTNET_PK`, or books a tracked recovery job. Keep the callback ungated: a recovery
envelope would insert a self-call and conceal the native sender being measured.

Inputs are the existing diamond, its approved `scheduleCall` and `probeCallback` facet addresses, the
public scheduler address, and a unique nonzero correlation ID for this attempt. Record the target and
facet code fingerprints before approving the action. The preflight checks chain 296, nonempty live code,
both exact routes and the scheduler's `HSS_SCHEDULER_ROLE` through relay reads. Route addresses are trust
inputs; these checks do not verify historical facet source or prove possession of the scheduler's key.
The expiry is calculated **after** preflight, from wall-clock time plus 600 seconds, rather than from the
older fork timestamp. The callback has a 200,000 gas allowance and transfers zero value. The booking call explicitly requests
1,000,000 gas; verify the recorded transaction limit, including intrinsic gas, in the dry-run JSON.

Prepare without a key, keystore or broadcast:

```sh
FOUNDRY_PROFILE=hedera forge script script/config/hedera/ProbeHedera.s.sol:ProbeHedera \
    --sig 'planProbe6(address,address,address,address,bytes32)' \
    <diamond> <scheduler> <hss-facet> <callback-facet> <unique-correlation-id> \
    --rpc-url hedera-testnet
```

Use the pinned 1.9.0 binary explicitly when validating #227. A `probe6(address,address,address,bytes32)`
dry run, with `--sender <scheduler> --skip-simulation --legacy` and **without** `--broadcast` or
`--account`, records the one planned call. Its local result cannot establish native success: revm does
not implement HSS. Inspect the dry-run transaction array, target, zero value, gas and exact nested input.
A later authorized invocation recalculates its expiry; do not submit an old absolute deadline.

Broadcasting requires explicit authorization, a controlled scheduler's keystore, fresh fee limits and
sufficient balances for the scheduler's booking transaction and the diamond's automatic callback. Use
`--with-gas-price` for the legacy transaction price; Forge's `--gas-price` configures the local EVM and
`--gas-limit` configures its block limit. Do not use either as a claimed transaction fee cap. No automatic
funding, retry, cancellation, `authorizeSchedule`, payer substitution or verification is part of this probe.

Preserve the approved plan and booking transaction/receipt. Require a successful booking with the exact
target/value/input and `HSSCallScheduled` emitted by the diamond: its target, expiry and gas must match,
and its indexed job ID is zero. That event gives the schedule address; `scheduleOf(correlationId)` does
not. Read the schedule entity from the mirror node and retain its payer and execution timestamp.
An `executed_timestamp` alone is insufficient: historical schedules failed before EVM entry. Require
the scheduled transaction's own successful result and its `HederaProbeCallback` log, matching the
diamond emitter and exact correlation ID. An arbitrary direct call can emit the same ungated event,
so a search for the event alone is not evidence of a network-fired callback.

Record the actual callback sender, event timestamp, schedule ID, date and **consensus-node software
version**. Keep the relay's `web3_clientVersion` and a mirror block's `hapi_version` as separate facts;
neither is a measurement of `hederaServicesVersion`. Compare the event sender with both the EVM alias
and canonical Hedera address, while retaining Solidity's exact `msg.sender == address(this)` question.
If scheduling or firing fails, preserve the native status and leave #226 open. A successful shared-pin
booking validates that broadcast path for #227; retirement of the wrapper and its exception requires
the completed result and a separate reviewed cleanup.
