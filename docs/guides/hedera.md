# Lattice on Hedera

Mount Hedera's system contracts as Diamond facets: hold and issue HTS tokens, verify ED25519 account
signatures, read the network exchange rate, draw a native random seed, and schedule your own future calls.
The contracts are unaudited. [Verification status](#verification-status) records dated live probes and
read-only checks, limited to their observed source and toolchain. Behaviours marked **assumed**, including
probe6's native callback/sender, still need on-chain confirmation. A shared Foundry 1.9.0 booking
succeeded on 2026-11-06; its later scheduled call failed native payer authorization before observed EVM
entry. Offline generation-safety tests, unsigned plans and dry runs are separate evidence.

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
FOUNDRY_PROFILE=hedera forge build --skip test script
```

Use the shared pinned Foundry 1.9.0 binary with the default fork backend. Deploy with the canonical recipe:

```sh
FOUNDRY_PROFILE=hedera forge script script/base/tokens/DeployHTSAdapter.s.sol \
    --sig "run(address)" <ADMIN> \
    --rpc-url hedera-testnet --account <keystore> --broadcast --slow --legacy \
    --verify --verifier sourcify
```

Earlier versions of that command without `--broadcast` simulated cleanly against hedera-testnet on
2026-09-12 and 2026-10-08. The dated shared-pin checks below record their exact source and endpoint.
Sourcify verification remains unconfirmed — probe 8 in the table below.

Keep `[profile.hedera]` on the canonical Cancun target. A future target change needs a coordinated
release-build decision and updated reproducibility checks, rather than a chain-local compiler override.

`hedera` (295) and `hedera-testnet` (296) are already named RPC aliases in `foundry.toml`; set
`HEDERA_RPC_URL` / `HEDERA_TESTNET_RPC_URL` in `.env`.

### Shared pin and historical relay compatibility

The shared Foundry pin is **1.9.0** for Hedera as well as other chains. Use
`FOUNDRY_PROFILE=hedera` explicitly and keep the default fork backend. The successful shared-pin
booking below completes the broadcast condition that had kept a separate Hedera toolchain in use;
that exception is retired. It does not establish native scheduled-payer authorization or the callback sender.

The following records explain the earlier exception. In the 2026-09/10 measurements, Foundry 1.7.1
could reach Hedera's relay while the measured 1.8 defaults could not. The versions asked for account
state differently (hashio; 1.8.1 measured 2026-09-12, 1.7.1 re-traced 2026-10-08):

```
forge 1.7.1 -> eth_getTransactionCount(addr, "0x279521e")                     exit 0
forge 1.8.1 -> eth_getTransactionCount(addr, {"blockHash": "0x671a…", ...})    -32602
               Invalid parameter 1: The value passed is not valid: [object Object].
```

In those measurements, 1.7.1 used a block number (and `"latest"` for the sender's first nonce).
1.8's fork backend sent `{"blockHash": …, "requireCanonical": false}`. The then-deployed relay
validated the block parameter as a string on `eth_getTransactionCount`, `eth_getBalance`,
`eth_getCode` and `eth_getStorageAt`, rejecting EIP-1898 objects with `-32602`; `eth_getCode` also
rejected a bare hash with `-39012`. `eth_call` accepted `{blockHash}` and `{blockNumber}` but rejected
`requireCanonical`. Both EIP-1898 and the older number form are standard Ethereum JSON-RPC.
Measured 2026-09-12 with a script that deployed nothing, none of the tested 1.8.1 options avoided the
failure: `--legacy`, `--slow`, `--skip-simulation` with and without `--broadcast`, `--fork-block-number`,
`--no-storage-caching`, `--offline`, `--sender-nonce`, `--unlocked`, `--sender` and `--estimate`.
QuickNode returned the same error and relay Request-ID format. The official
[relay issue #5826](https://github.com/hiero-ledger/hiero-json-rpc-relay/issues/5826) and
[implementation #5845](https://github.com/hiero-ledger/hiero-json-rpc-relay/pull/5845) track EIP-1898 support.

Re-measured 2026-10-08 against `https://testnet.hashio.io/api` (`relay/0.79.0`), with the
`DeployHTSAdapter` simulation (no broadcast or key) and the opt-in `HTSAdapterFork` suite. The
[2026-10-08 transcript](https://github.com/dadadave80/lattice/issues/227#issuecomment-6058119157)
retains every request and relay Request-ID:

| Foundry | `DeployHTSAdapter` simulation | `HTSAdapterFork` forking test |
| --- | --- | --- |
| 1.7.1 (`4072e48`) | passes | passes |
| 1.8.1 (`982849d`) | `-32602 … [object Object]` | not re-run (failed 2026-09-12) |
| 1.8.3 (`cae51ad`) | `-32602 … [object Object]` | not run |
| 1.8.5 (`51a52c5`), default | `-32602 … [object Object]` | fails with the same database error |
| 1.8.5 with `--fork-state-by-number` | passes, no block-hash params sent | passes |

That historical number-based option, also exposed as `FOUNDRY_FORK_STATE_BY_NUMBER=true`, reached
Forge scripts, tests and cheatcode forks in 1.8.5 through
[Foundry #17352](https://github.com/foundry-rs/foundry/pull/17352); it was an Anvil-only option in 1.8.3/1.8.4.
The 2026-10-08 simulation also accepted the environment form; the `fork_state_by_number` config key
was not exercised. Number-based reads cannot guarantee a consistent snapshot across a reorganization,
skip the disk state cache, and do not replace hash reads for transaction replay. No broadcast with that
option was measured. It is not needed by the current shared-pin workflow.

A read-only recheck on 2026-11-06 reported `relay/0.80.3` at hashio: all 30 requests succeeded
(five state/call methods, each with `latest`, number, bare hash, `{blockHash}`,
`{blockHash, requireCanonical: false}` and `{blockNumber}`). Foundry 1.9.0 (`6056c58`) passed
`DeployHTSAdapter` simulation and both `HTSAdapterFork` tests at source checkpoint
`fa606adca0129bedd8dabd54e1392a815234888b`. Those checks did not broadcast a transaction.

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

At source checkpoint `e45696b996fa91d4ba02778c9943f285ed9e9aaf`, targeted 1.7.1/1.9.0 builds again
matched for `HTSAdapter`, `ERC20`, `Lattice`, `HSSAdapter`, `HederaProbeFacet` and `ProbeHedera`,
including their 86-artifact dependency graph, metadata, links and immutable locations. All 90 input
files matched that checkpoint. The shared-pin `HTSAdapterFork` tests passed (2 tests). A separate
`DeployHTSAdapter` simulation failed with a Hashio HTTP 500 / JSON-RPC `-32020` upstream
“socket hang up”; it was not retried. That failure was not an EIP-1898 rejection, and no transaction
was signed or broadcast.

In the historical comparisons, commands that did not open a fork backend also worked on both compared
versions: `forge create`, `cast send` / `call` / `mktx`, and `vm.rpc` inside a test. Both legacy and EIP-1559
signing were exercised. The approved booking below used `--legacy`; that option does not fix relay block
parameter compatibility. `--slow` helps against rate limits.

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
  the mirror node simulates it. In the September/October measurements, the fork reached hashio on 1.7.1
  while the then-shared defaults were rejected for EIP-1898 params. The dated 1.9.0 read-only results above
  update that observation; the successful shared-pin booking below is separate native evidence. The
  suite uses the shared binary. With a configured `HEDERA_TESTNET_RPC_URL` and a live
  `HEDERA_TEST_TOKEN`, both tests run; without the token, both skip.

## Verification status

The table preserves dated historical live executions and read-only checks; these do not verify the
remaining assumptions or the current release. The shared-pin booking is confirmed below; probe6's
native callback/sender remains unverified. Offline generation-safety tests do not establish it.
`script/config/hedera/ProbeHedera.s.sol` exists to settle the native assumptions and is deliberately not
broadcast by CI.

| # | Behaviour | Status |
| --- | --- | --- |
| 1 | `associateToken` from a facet, then an inbound transfer | still assumed — the probe's association target was its own treasury token, so it could only ever return 194 |
| 2 | `createFungibleToken` with `delegatableContractId` keys, then `mintToken` from a facet | **confirmed live, 2026-09-12** — token `0.0.10506856` created by a facet with the diamond as treasury and delegatable admin+supply keys; `HTSAdapter.mintToken` minted 500. Excess-`msg.value` refund still unmeasured |
| 3 | The same create with a `contractId` key → 326 | **REFUTED live, 2026-09-12** — minted successfully instead (token `0.0.10506858`, supply 1000 → 1777). The control was degenerate: the key was byte-identical to the diamond's own account key and got elided before verification. See "The delegatable-key rule" |
| 4 | HTS getters and both HAS auth functions staying `view` (`staticcall`-safe) | partly confirmed — `isToken` answers `(22, true)` through the relay's `eth_call` (2026-09-12); whether a diamond's own `view` facet function may `staticcall` it *inside a transaction* is still assumed |
| 5 | `redirectForAccount(address(this), …)` giving a diamond unlimited auto-associations | partially measured — the frame succeeded and returned 32 bytes decoding to `15`, so `0x16a` does expose the entrypoint; whether the association limit actually changed is unverified, and `redirectForAccount` stays out of the vendored interface until it is |
| 6 | `scheduleSelfCall` firing with `msg.sender == address(this)` | unverified — the 2026-09-12 attempt reverted `HSSInvalidExpiry`; the 2026-11-06 raw sender probe booked successfully but its scheduled call failed `INVALID_PAYER_SIGNATURE` before observed EVM entry. No native sender measured |
| 7 | ED25519 verification through `isAuthorizedRaw` from the ERC-1271 path | assumed |
| 8 | Sourcify verification reproducing under `FOUNDRY_PROFILE=hedera` | assumed |
| — | System-contract code shape, **both** networks: `eth_getCode(0x167)` is `0xfe`; `0x168`, `0x169`, `0x16a` and `0x16b` are all empty. (The research brief said `0x16b` also answers `0xfe` — it does not.) | **confirmed live, 2026-09-12** |
| — | CreateX `0xba5Ed099…ba5Ed` has no code on Hedera mainnet or testnet | **confirmed live, 2026-09-12** |
| — | The Arachnid proxy `0x4e59b448…956C` has code on Hedera mainnet **and** testnet, byte-identical to `test/helpers/ArachnidProxy.RUNTIME` | **confirmed live, 2026-09-12** |
| — | `forge script` on Foundry 1.8.1 cannot reach Hedera's relay (its fork backend's EIP-1898 block-hash params are rejected, by hashio and QuickNode alike); Foundry 1.7.1 can, and the probe run was made with it. This is historical; relay EIP-1898 support and the shared-pin booking are recorded above and below | **confirmed live, 2026-09-12** |
| — | The relay (`relay/0.79.0` on hashio) rejected EIP-1898 objects on `eth_getTransactionCount`, `eth_getBalance`, `eth_getCode` and `eth_getStorageAt` with `-32602` (`eth_call` accepts them but rejects the `requireCanonical` key Foundry adds), and Foundry 1.8.3 and 1.8.5 still send them by default. Foundry 1.8.5's `--fork-state-by-number` reaches it in a `forge script` simulation and the forking `HTSAdapterFork` test; no broadcast with that option was measured | **confirmed live, 2026-10-08** |
| — | Hashio reported `relay/0.80.3`; all 30 state/call request forms above succeeded. The shared Foundry 1.9.0 pin passed `DeployHTSAdapter` simulation and both `HTSAdapterFork` tests; 1.7.1/1.9.0 build parity holds at `fa606adc`. These were read-only checks; the later successful shared-pin broadcast is separate evidence below | **read-only checks, 2026-11-06** |

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
The native payer-authorization/sender path is still **unverified**: probe6 uses raw `scheduleCall`
to its ungated callback, so the envelope's extra self-call cannot manufacture the measured sender.
Read `HSSCallScheduled` in that transaction's receipt for its schedule address; `scheduleOf` describes
tracked jobs, not this raw probe. The existing
[upstream payer-signature report](https://github.com/hiero-ledger/hiero-consensus-node/issues/27263)
records two testnet schedules created on 2026-09-12 that failed `INVALID_PAYER_SIGNATURE` before entering
the EVM. The 2026-11-06 retest below failed at the same native stage. Neither result measures a callback
sender, and an authorization repair has not been validated. Issue
[#226](https://github.com/dadadave80/lattice/issues/226) still needs a separately authorized successful
native callback with its sender, schedule ID, date and measured consensus-node version. Offline mock
coverage and local generation safety do not satisfy that live acceptance.

### Native retest on 2026-11-06

The first approved [1M booking](https://testnet.mirrornode.hedera.com/api/v1/contracts/results/0xf2d4a225865d90573d64a0a7557baa77b8742b32dbab182e8d7fca20b8d13cf9)
failed. Its [native action trace](https://testnet.mirrornode.hedera.com/api/v1/contracts/results/0xf2d4a225865d90573d64a0a7557baa77b8742b32dbab182e8d7fca20b8d13cf9/actions?limit=100)
shows HSS received and consumed 935,804 gas, then failed with `INSUFFICIENT_GAS`. The expiry was still 165 seconds
in the future. `HSSCallFailed(...,21)` reflects the adapter's failed-frame fallback, not a native UNKNOWN
response or an expiry diagnosis. No schedule or callback was evidenced by that failed transaction.

A separately approved booking from source
[`4a7913dfcf10425ec2598723811e5496492f7ac3`](https://github.com/dadadave80/lattice/commit/4a7913dfcf10425ec2598723811e5496492f7ac3)
used the shared Foundry 1.9.0 binary, `FOUNDRY_PROFILE=hedera`, the default fork backend and a Thirdweb endpoint.
Its [2M transaction](https://testnet.mirrornode.hedera.com/api/v1/contracts/results/0x7c14969725b69671d533d7a238bfab1c79dd00d4feba6dbacd296af68dd35ab2)
succeeded at 1793991731.096673104, using 1,446,999 gas. Its
[native action trace](https://testnet.mirrornode.hedera.com/api/v1/contracts/results/0x7c14969725b69671d533d7a238bfab1c79dd00d4feba6dbacd296af68dd35ab2/actions?limit=100)
shows HSS received 1,904,788 gas, used 1,409,649 and returned 22 with schedule address
`0x0000000000000000000000000000000000ad194c`. The transaction input and scheduled body specify
zero value; the diamond event matches expiry 1793992027, callback 200,000 gas and zero indexed job ID.
This confirms the shared-pin
broadcast/booking path that #227 required, independently of the scheduled execution result.

[Schedule 0.0.11344204](https://testnet.mirrornode.hedera.com/api/v1/schedules/0.0.11344204) names payer
`0.0.10506850`, creator `0.0.10499114` and `wait_for_expiry=true`. Its own
[scheduled CONTRACTCALL](https://testnet.mirrornode.hedera.com/api/v1/transactions?timestamp=1793992027.007135136&limit=100)
at 1793992027.007135136 failed `INVALID_PAYER_SIGNATURE`, with no charge. The complete
[exact-timestamp contract-result list](https://testnet.mirrornode.hedera.com/api/v1/contracts/results?timestamp=1793992027.007135136&limit=100)
is empty. Its `executed_timestamp` therefore records a failed execution attempt, not a successful
callback. No native EVM sender or callback log was observed; keep the strict-self guard.

Current public account data identifies the payer key as plain `ContractID(self)`, while the schedule's
admin key is `DelegatableContractID(self)`. These are distinct native authorities, separate from
Lattice's scheduler role. Zero recorded Mirror signatures do not establish that no implicit native
contract authorization existed; current account data does not reconstruct execution-time key history.
The published [release/0.79 candidate verifier](https://github.com/hiero-ledger/hiero-consensus-node/blob/aa6af6975a737dbd9b7f9605586695cc91709c4d/hedera-node/hedera-schedule-service-impl/src/main/java/com/hedera/node/app/service/schedule/impl/handlers/AbstractScheduleHandler.java#L295)
and its [explicit tests](https://github.com/hiero-ledger/hiero-consensus-node/blob/aa6af6975a737dbd9b7f9605586695cc91709c4d/hedera-node/hedera-schedule-service-impl/src/test/java/com/hedera/node/app/service/schedule/impl/handlers/AbstractScheduleHandlerTest.java#L76)
do not let delegated authorization satisfy a plain ContractID payer key. That is a credible explanation
of this deployment's failure, not an attestation of the deployed node revision or a proven repair.
Adding `authorizeSchedule` through the same delegated path is not established as a fix. Native payer or
key changes require a separately reviewed authority/deployment design; no callback authentication is relaxed.

The operator's [testnet upgrade status](https://status.hedera.com/incidents/6qrr40p9mtcb) reported
v0.79.0 complete before this booking. No paid/native
`NetworkGetVersionInfo` result was obtained, and the exact deployed source commit remains unknown.
Relay `web3_clientVersion`, a mirror block's `hapi_version` and published candidate source are separate
facts; none substitutes for that native software-version measurement.

The two attempts' actual fees are distinct from their gas allowances:

| Attempt | Total charged HBAR | `hbar1` account 0.0.10499114 debit HBAR | Relay debit HBAR |
| --- | --- | --- | --- |
| Failed 1M booking | 1.20455715 | 1.20310008 | 0.00145707 |
| Successful 2M booking | 1.79427876 | 1.79427876 | 0 |
| Both approvals | 2.99883591 | 2.99737884 | 0.00145707 |

The scheduled failed call reports fee 0 and no transfers; its 200k allowance is not an additional measured
charge. Both one-operation approvals are consumed. No retry, authorization, cancellation, funding,
payer/key change or paid query follows from these results. The successful call targeted the existing
historical diamond/facets; it does not attest their source identity. Recompiling this script can rotate
metadata for its co-located throwaway probe facet without changing that live target's bytecode.

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
older fork timestamp. The callback has a 200,000 gas allowance and transfers zero value. The booking call
explicitly requests 2,000,000 gas; verify the recorded transaction limit, including intrinsic gas, in the
dry-run JSON. The 2026-11-06 booking at a 1,000,000 transaction limit forwarded 935,804 gas to native HSS
and failed there with `INSUFFICIENT_GAS`. The separately approved 2M retest booked successfully, as recorded
above; the successful budget is not a measured minimum or proof of callback execution. Both one-operation
approvals are consumed; any further submission requires fresh approval.

Prepare without a key, keystore or broadcast:

```sh
FOUNDRY_PROFILE=hedera forge script script/config/hedera/ProbeHedera.s.sol:ProbeHedera \
    --sig 'planProbe6(address,address,address,address,bytes32)' \
    <diamond> <scheduler> <hss-facet> <callback-facet> <unique-correlation-id> \
    --rpc-url hedera-testnet
```

Use the shared pinned 1.9.0 binary. A `probe6(address,address,address,bytes32)`
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
If scheduling or firing fails, preserve the native status and leave #226 open. The successful shared-pin
booking above validates that broadcast path for #227; it does not complete #226 or authorize another call.
