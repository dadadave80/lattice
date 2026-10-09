# LatticeRegistry and LatticeFactory: threat model and test map

This document maps every external entry point of `LatticeRegistry` and `LatticeFactory`, the trust
boundaries between their callers, the invariants the two contracts are meant to keep, and the tests that
check each one. It also lists the findings of the #176 test work, what changed for each, and what the
tests do not cover.

It describes the source after the #176 hardening change (`deployStrict`, the recipe hash in
`DiamondDeployed`, `diamondInitCodeHash()`, the batch views, `RecipeEntry.exclude`, bounded exporter
reads). That change altered the bytecode of both contracts, so their canonical addresses moved: the
deployment salts carry no version, and every byte change moves them. Passing these tests is not an audit
and does not make either contract production ready.

## Components and trust boundaries

| Actor | Can do | Trusted for |
| --- | --- | --- |
| Registry owner (the curator) | `register`, `setLatest`, `transferOwnership` | Which facets enter Tier B, and where each `latest` pointer points |
| Pending owner | `acceptOwnership` | Nothing until it accepts |
| Anyone | `attest`, every view, `factory.deploy`, `factory.deployStrict`, `factory.predict` | Nothing |
| A facet's `exportSelectors()` | Runs under the registry's `staticcall` at `register` and on every live read, with at most 100,000 gas and 8,192 bytes of return data | Nothing: the registry pins `codehash` and `keccak256(blob)` at registration |
| The factory's registry | Answers `latest` and `getCut` during a deploy | Everything it returns. The factory does not re-validate registry cuts |
| A deployer (`msg.sender` of `deploy`/`deployStrict`) | Picks the salt, the recipe (including exclusions), the init and the init calldata | Its own diamond only. The salt is bound to the sender |
| The init contract | Runs by `delegatecall` inside `Lattice.initialize`, with `msg.sender` equal to the factory | Its own diamond only |

The two contracts are standalone, plain and non-upgradeable. The factory holds no state and its registry
address is fixed at construction (and must hold code). The registry's only privileged role is the curator
of Tier B. Tier A (`attest`/`resolve`) and all reads are permissionless.

Tier A is a code-identity index: `resolve(h)` returns the first address attested with runtime codehash
`h`. Two addresses with one codehash behave the same only when a diamond `delegatecall`s them and the facet
reads none of its own storage, exports through a `pure` `exportSelectors()`, and is not a proxy. Selectors
come from Tier B, never from `resolve`. `ILatticeRegistry`'s NatSpec states these assumptions (finding R-3).

## Entry points

### LatticeRegistry (`src/LatticeRegistry.sol`)

| Entry point | Line | Caller | External calls | Writes |
| --- | --- | --- | --- | --- |
| `constructor(initialOwner)` | 81 | deployer | none | `owner` |
| `attest(deployed)` | 92 | anyone | `EXTCODEHASH` | `_resolver[codehash]` if unset |
| `resolve(codehash)` | 97 | anyone | none | none |
| `register(bytes32 \| string, version, facet)` | 106, 164 | owner | `EXTCODEHASH`, bounded `staticcall exportSelectors()` | `_records`, `_resolver` if unset |
| `setLatest(bytes32 \| string, version)` | 111, 169 | owner | none | `_latestVersion` |
| `get`, `latest` (both overloads) | 116-121, 174-179 | anyone | none | none |
| `getMany(RecordKey[])`, `latestMany(bytes32[])` | 126, 136 | anyone | none | none |
| `getSelectors`, `getCut` (both overloads) | 145-150, 184-189 | anyone, and the factory | `EXTCODEHASH`, bounded `staticcall exportSelectors()` | none |
| `nameHash(name)` | 194 | anyone | none | none |
| `transferOwnership(newOwner)` | 203 | owner | none | `pendingOwner` |
| `acceptOwnership()` | 209 | pending owner (never when none is pending) | none | `owner`, `pendingOwner` |

Every `exportSelectors()` read goes through `_exportedBlob` (line 356): it forwards at most 100,000 gas,
refuses a return shorter than 64 or longer than 8,192 bytes without copying it, and decodes the ABI
`bytes` encoding by hand with exactly the acceptance rule of `abi.decode(ret, (bytes))`. Any failure yields
an empty blob, which `register` reports as `LatticeRegistry__NotERC8153` and a live read as
`LatticeRegistry__SelectorDrift`.

### LatticeFactory (`src/LatticeFactory.sol`)

| Entry point | Line | Caller | External calls | Writes |
| --- | --- | --- | --- | --- |
| `constructor(registry, reverseRegistrar, reverseRecordOwner)` | 45 | deployer | `IReverseRegistrar.claim` when ENS is configured | immutables |
| `deploy(entries, customCuts, init, initCalldata, salt)` | 60 | anyone | `registry.latest` (version 0), `registry.getCut`, CREATE2 of `Lattice`, `Lattice.initialize`, which delegatecalls `init` | a new diamond |
| `deployStrict(entries, customCuts, init, initCalldata, salt)` | 71 | anyone | as `deploy`, never `registry.latest` | a new diamond |
| `predict(deployer, salt)` | 82 | anyone | none | none |
| `registry()`, `diamondInitCodeHash()` | 32, 35 | anyone | none | none |

Both deploy entry points run `_deploy` in this order:

1. Validate the arguments: refuse an empty recipe, a zero init with non-empty calldata, and
   `exportSelectors()` in any custom cut. `deployStrict` also refuses any entry with version 0.
2. Compute the `(msg.sender, salt)` address. If it holds code, `deploy` returns it (the idempotent
   return) and `deployStrict` reverts `LatticeFactory__AlreadyDeployed(diamond)`.
3. Resolve each entry through the registry (`latest` first for version 0), drop its `exclude` selectors
   (each must be in the verified export, at most once), then append the custom cuts.
4. Check loupe coverage, hash the applied recipe (`keccak256(abi.encode(cuts, init, initCalldata))`),
   CREATE2 the proxy, call `initialize`, and emit
   `DiamondDeployed(diamond, deployer, recipeHash, salt, init)`.

## Invariants and the tests that check them

The invariant set is the one proposed in #176 (R1-R7, F1-F6). Each invariant has a stateful suite and,
where useful, targeted unit and fuzz tests.

| Id | Property | Stateful | Unit and fuzz |
| --- | --- | --- | --- |
| R1 | A record never changes once written | `LatticeRegistryInvariant`, `LatticeRegistryCodeDriftInvariant` (`invariant_R1_RecordsAreImmutable`) | `LatticeRegistryFuzz.testFuzz_RecordIsImmutable`, `LatticeRegistryTest.test_I1_*` |
| R2 | A non-zero `resolve(h)` never changes and is the first attester; `register`'s auto-attest never overwrites it | `invariant_R2_ResolverIsFirstWriteWins` | `LatticeRegistryHostileExporterTest.test_RegisterAutoAttestNeverOverwritesResolver`, `LatticeRegistryTest.testFuzz_AttestFirstWriteWins` |
| R3 | A set `latest(n)` equals `get(n, latest(n).version)`; an unset one reverts | `invariant_R3_LatestPointsAtARecord` | `LatticeRegistryTest.test_SetLatest*`, `test_LatestManyMatchesLatest`, `test_GetManyMatchesGetAndResolvesLatestForVersionZero` |
| R4 | `owner != 0`; ownership moves only through `acceptOwnership`, which clears `pendingOwner` and refuses when none is pending; `transferOwnership(0)` cancels; strangers cannot write | `invariant_R4_Ownership` | `LatticeRegistryFuzz.testFuzz_OwnershipHandover`, `LatticeRegistryFuzz.test_CancelledHandoverCannotBeAcceptedEvenByAddressZero` |
| R5 | String and hash overloads return the same data or the same error | `invariant_R5_StringHashParity` | `LatticeRegistryFuzz.testFuzz_StringAndHashOverloadsAgree` |
| R6 | `getCut` returns the pinned selectors, or reverts `CodeDrift` when the code changed, else `SelectorDrift` | `invariant_R6_GetCutIsPinnedOrDrift` (flip-based drift in `LatticeRegistryInvariant`, `vm.etch` drift in `LatticeRegistryCodeDriftInvariant`) | `LatticeRegistryHostileExporterTest` live-read section |
| R7 | Version 0 never holds a record | `invariant_R7_VersionZeroNeverRegisters` | `LatticeRegistryFuzz.testFuzz_VersionZeroNeverRegisters` |
| F1 | deploy == predict == CREATE2 over `diamondInitCodeHash()` (`keccak256(type(Lattice).creationCode)`); a resolved entry keeps the version resolved at deploy time | `LatticeFactoryInvariant.invariant_F1_DeployEqualsPredict` | `LatticeFactoryFuzz.testFuzz_DeployEqualsPredictEqualsCreate2`, `testFuzz_DeployStrictDeploysOnceThenReverts`, `LatticeFactoryHardeningTest.test_PredictMatchesCreate2OverLatticeCreationCode` |
| F2 | A reverted deploy leaves no code and stays retryable | `invariant_F2_FailedDeploysLeaveNoCode` | `LatticeFactoryFuzz.testFuzz_FailedInitRollsBackAndRetries`, `test_DriftMidRecipeRollsBackAndStaysRetryable` |
| F3 | The factory holds a role on a diamond exactly when the init granted `msg.sender` (finding F-6) | `invariant_F3_FactoryAuthority` | `test_InitGrantingMsgSenderGrantsTheFactory`, `test_ExplicitAdminInitLeavesFactoryWithoutRole`, `LatticeFactoryGovernedVaultTest.test_RegistryVaultIsSelfGovernedAndFactoryHoldsNoRole` |
| F4 | A repeat `deploy` for `(sender, salt)` returns the same address, emits nothing, and leaves the loupe unchanged; a repeat `deployStrict` reverts `AlreadyDeployed` | `invariant_F4_RepeatDeploysLeaveLoupeUnchanged` (plus asserts in the handler, which drives both entry points) | `LatticeFactoryFuzz.testFuzz_IdempotentReturnIgnoresAnyRecipe`, `testFuzz_DeployStrictDeploysOnceThenReverts`, `test_DeployOccupiedAddressIgnoresNewRecipeAndInit`, `test_DeployStrictRevertsOnOccupiedAddress` |
| F5 | All four loupe selectors are routed | `invariant_F5_F6_LoupeRoutedExportNot` | `LatticeFactoryFuzz.testFuzz_LoupeCoverageNeedsAllFour`, `test_ExcludeOfALoupeSelectorFailsLoupeCoverage`, `LatticeFactoryTest` loupe section |
| F6 | `exportSelectors()` (`0x0ef22643`) is never routed | `invariant_F5_F6_LoupeRoutedExportNot` | `LatticeFactoryFuzz.testFuzz_ExportSelectorInCustomCutAlwaysRefused` |

All three invariant suites run with `fail_on_revert = true`: the handlers predict each outcome from ghost
state and assert expected reverts with `vm.expectRevert`, so a handler that silently reverted would fail the
run. Under `FOUNDRY_PROFILE=ci` they run 64 runs at depth 128.

## Other properties and where they are tested

| Property | Tests |
| --- | --- |
| Registration accepts a return exactly when `abi.decode(ret, (bytes))` decodes it to a non-empty, 4-aligned, duplicate-free blob without `0x0ef22643`, pins the hash of the decoded blob, and reports every refusal as `NotERC8153` | `LatticeRegistryFuzz.testFuzz_BlobAcceptanceMatchesTheRule`, `testFuzz_RawReturnNeverRegistersAnythingButTheDecodedBlob`, `testFuzz_StructuredReturnNeverRegistersAnythingButTheDecodedBlob` |
| Hostile exporters: reverting, gas-burning (capped at 100,000 gas), short, malformed offsets and lengths, truncated, non-canonical, trailing bytes, dirty padding, returns over the 8,192-byte cap (refused without being copied), duplicates and the self-selector at the end of long blobs, re-entry into the registry from inside the staticcall | `LatticeRegistryHostileExporterTest` |
| Mutable exports and code drift: transient selector drift, a live answer switched to a short, malformed or oversized return, emptied code, code swapped for code with the same export | `LatticeRegistryHostileExporterTest` live-read section |
| Tier A is a code-identity lookup: same-codehash instances in different states export different selectors, and `resolve` returns the first attester | `test_ResolveReturnsFirstAttesterWhileExportsDiffer` |
| Batch views equal the single-record views, in order, and revert like them | `LatticeRegistryTest` batch-view section |
| Recipe kinds (pinned, latest, custom, mixed) route every selector to the facet that supplied it | `LatticeFactoryFuzz.testFuzz_MixedRecipesRouteEverySelector`, `LatticeFactoryTest` |
| `RecipeEntry.exclude` cuts exactly the rest of the export, in export order; an excluded selector the export lacks, or one excluded twice, aborts the deploy; it applies to `latest` entries; it resolves registry/registry collisions | `LatticeFactoryFuzz.testFuzz_ExcludeCutsExactlyTheComplement`, `LatticeFactoryHardeningTest` exclusion section |
| The recipe hash commits to the applied cuts (after exclusions), the init and the calldata | `test_RecipeHashCommitsToCutsInitAndCalldata`, `test_LatestMovedBeforeInclusionShowsInTheRecipeHash`, `LatticeFactoryTest.test_DeployEmitsDiamondDeployed`, `LatticeFactoryGovernedVaultTest.test_AllRegistryVaultRoutesLikeTheReferenceAndHashesTheProductionCuts` |
| Selector collisions abort the deploy: registry/registry, the same entry twice, pinned plus latest of one name, a duplicate inside one custom cut, registry/custom | `LatticeFactoryHardeningTest` collision section, `LatticeFactoryTest.test_DeployRevertsOnSelectorCollisionWithRegistryCut` |
| Cut order: custom cuts run after registry cuts, so a custom `Replace` or `Remove` can change a registry selector (never a loupe selector) | `test_CustomRemoveDropsRegistrySelector`, `LatticeFactoryTest.test_CustomReplaceCutRePointsRegistrySelector` |
| Caller and salt isolation, including a competing caller reusing a victim's salt | `LatticeFactoryFuzz.testFuzz_CallerSaltIsolation`, `test_CompetingCallerCannotOccupyAnotherCallersAddress` |
| ETH sent to a predicted address does not block deployment | `test_PrefundedPredictedAddressDeploysAndKeepsBalance` |
| Malicious init callbacks: re-entering `initialize` (refused, deploy rolls back), re-entering `factory.deploy` (the child's salt is bound to the new diamond), a custom-error revert (bubbles byte for byte) | `LatticeFactoryHardeningTest` authority and callbacks section |
| A selector the proxy itself defines (`initialize`) can be cut but is never reachable through the diamond | `test_ProxyShadowedSelectorIsCutButUnreachable` |
| A real module (the self-governed vault) through the registry path, both as 8 entries plus 6 custom cuts and as 14 entries (6 with `exclude`): same routing as the custom-only recipe, byte-identical applied cuts, self-governance wired, no role for the factory or the deployer, no shared state between two vaults | `LatticeFactoryGovernedVaultTest` |
| Gas and size baselines | `LatticeCoreGasTest` (gated, `snapshots/LatticeCoreGasTest.json`), `LatticeCoreDesignBenchTest` (logged, not gated) |

## Findings

No finding let a third party take over or alter someone else's diamond, or change a curated record. The
#176 hardening change fixed the findings it could fix without changing the address scheme, and documented
the rest in the NatSpec and here. Each finding's test now pins the fixed or documented behaviour.

| Id | Finding | Severity | Status | Test |
| --- | --- | --- | --- | --- |
| R-1 | A return of 64 bytes or more that `abi.decode` rejects made `register` revert with EMPTY data (or `Panic(0x41)` for a huge declared length) instead of `LatticeRegistry__NotERC8153`, and `getCut` revert with empty data instead of `SelectorDrift`. Both failed closed | Low (wrong error, no state impact) | **Fixed.** `_exportedBlob` decodes by hand with `abi.decode`'s acceptance rule; every refusal is `NotERC8153` at `register` and `SelectorDrift` on a live read | `test_RegisterRevertsNotERC8153On*`, `test_UnpaddedDataEndingAtTheReturnEndRegisters`, `test_LiveMalformedReturnIsSelectorDrift`, the two raw-return fuzz tests (`abi.decode` is their oracle) |
| R-2 | The exporter `staticcall` forwarded all available gas and copied the whole return. A curated exporter returning a valid encoding plus about 1 MB made every `getCut` (and every deploy resolving it) cost more than 3M gas; a looping exporter burned 63/64 of the caller's gas | Low | **Fixed.** At most 100,000 gas is forwarded (every release export runs in at most 2,233 gas) and at most 8,192 bytes are accepted (the largest release export is 224 bytes); a larger return is refused without being copied. The selector blob is still read live, not stored (see "Design decisions") | `test_LoopingExporterBurnsAtMostTheExportGasThenRevertsNotERC8153`, `test_ReturnBombIsRefusedAtRegistration`, `test_ReturnSizeCapBoundary`, `test_LiveOversizedReturnIsSelectorDrift` |
| R-3 | Tier A is a code-identity lookup; the `ILatticeRegistry` NatSpec claimed any same-codehash address is equivalent, which holds only under `delegatecall` for facets that meet the assumptions above | Informational | **Documented.** The Tier A NatSpec lists the four assumptions and says `resolve` is not a selector source | `test_ResolveReturnsFirstAttesterWhileExportsDiffer`, `test_RegisterAutoAttestNeverOverwritesResolver` |
| R-4 | `acceptOwnership` did not reject a zero pending owner, so a call from address 0 (cheatcode only) could complete a cancelled handover and set `owner = 0` | Informational | **Fixed.** `acceptOwnership` reverts `NotPendingOwner` when no handover is pending | `test_CancelledHandoverCannotBeAcceptedEvenByAddressZero`, `testFuzz_OwnershipHandover` |
| F-1 | The constructor rejected only a zero registry, not a codeless one, leaving a permanently misconfigured immutable factory | Low | **Fixed.** `LatticeFactory__InvalidRegistry(registry)` for any registry without code (`LatticeFactory__ZeroRegistry` is gone) | `test_ConstructorRejectsCodelessRegistry`, `LatticeFactoryTest.test_ConstructorRevertsOnZeroRegistry` |
| F-2 | `init == address(0)` with non-empty init calldata succeeded and dropped the calldata | Low | **Fixed.** `LatticeFactory__InitCalldataWithoutInit()` on both entry points, also on `deploy`'s idempotent path | `test_ZeroInitWithCalldataReverts` |
| F-3 | A repeat `deploy` for an occupied `(sender, salt)` returns the existing diamond and ignores the new recipe, with no event | By design for `deploy` | **Addressed by `deployStrict`,** which reverts `LatticeFactory__AlreadyDeployed(diamond)`; `deploy` keeps the idempotent return | `test_DeployOccupiedAddressIgnoresNewRecipeAndInit`, `test_DeployStrictRevertsOnOccupiedAddress`, `testFuzz_DeployStrictDeploysOnceThenReverts`, invariant F4 |
| F-4 | Users behind one shared forwarder (Multicall3, a relayer) reach the factory with the same `msg.sender` and share one salt namespace: through `deploy` the second user silently receives the first user's diamond and admin (#176 residual (b)) | Medium for integrations that route deploys through a shared forwarder; none for today's scripts, which call the factory directly | **Mitigated and documented.** Through `deployStrict` the second user's call reverts; `ILatticeFactory`'s NatSpec says to deploy from the deploying account or use `deployStrict`. Binding the salt to the end user would need a trusted-forwarder scheme (ERC-2771) the factory does not adopt | `test_SharedForwarderCallersShareOneNamespace` |
| F-5 | A `version == 0` entry resolves `latest` when the transaction executes; a curator move between signing and inclusion changed the cut, and `DiamondDeployed` could not tell which version was cut (#176 residual (a)) | Low (curator-trusted) | **Fixed.** `DiamondDeployed` carries the hash of the applied recipe, `deployStrict` refuses version 0 (`LatticeFactory__UnpinnedEntry`), and `RecipeEntry`'s NatSpec repeats the pinning advice. `deploy` still resolves `latest` at execution | `test_LatestMovedBeforeInclusionShowsInTheRecipeHash`, `testFuzz_DeployStrictRefusesLatestEntries` |
| F-6 | `Lattice.initialize` is called by the factory, so an init that grants `msg.sender` grants the factory, which cannot use the role; the deployer holds nothing | Low (footgun for consumer inits; no shipped init does this) | **Documented** on `deploy` (INIT AUTHORITY): inits take an explicit admin. Refusing such inits on-chain is not possible in general | `test_InitGrantingMsgSenderGrantsTheFactory`, invariant F3 |
| F-7 | An init that self-destructs the diamond is accepted; EIP-6780 deletes the diamond when the transaction ends, so the same `(sender, salt)` can deploy again and emit a second `DiamondDeployed` for the same address | Low (only the deployer's own address) | **Documented** on `DiamondDeployed`: indexers treat the latest event for an address as authoritative. No in-transaction check can see the deletion | `test_SelfDestructingInitCanEmitDiamondDeployedTwice` |

### Reproducing F-7

The EIP-6780 deletion happens at the end of the transaction that created the diamond. Forge runs each
top-level call of a test as its own transaction (`isolate`, on by default in Foundry 1.8.5), so the next
`deploy` from the test sees the emptied address, creates the diamond again and emits a second
`DiamondDeployed`; `test_SelfDestructingInitCanEmitDiamondDeployedTwice` asserts that second event and the
second recipe's routing. The test contract's own `code.length` read of the address is not a reliable
witness of the deletion, so the test does not rely on it.

The same sequence was run against `anvil --hardfork osaka` (Foundry 1.8.5) on 2026-10-09, before the
hardening change, as corroboration on a node. With the current ABI the `deploy` signature is
`deploy((bytes32,uint64,bytes4[])[],(address,uint8,bytes4[])[],address,bytes,bytes32)`:

1. `forge create` `LatticeRegistry`, `LatticeFactory` (registry, no ENS), `DiamondLoupeFacet` and
   `test/helpers/LatticeCoreMocks.sol:CoreSelfDestructInit`.
2. `cast send <factory> "deploy((bytes32,uint64,bytes4[])[],(address,uint8,bytes4[])[],address,bytes,bytes32)"
   "[]" "[(<loupe>,0,[0x7a0ed627,0xadfca15e,0x52ef6b2c,0xcdffacc6])]" <init> 0xe1c7392a <salt>`: status 1,
   `DiamondDeployed` emitted, and `cast code <predicted>` returns `0x` afterwards.
3. The same call with `init = address(0)` and empty calldata: status 1, a second `DiamondDeployed` for the
   same address, and the address now has code.

## Design decisions

- **Selector storage: capped live read, not a stored blob.** The design comparison recommended storing
  each selector blob at registration (SSTORE2) so reads never call the facet, and named capped live reads
  with correct errors as the minimum it accepts. This change ships that minimum, as the approved R-1/R-2
  scope asked: every exporter call gets at most 100,000 gas and 8,192 bytes of return, and every malformed
  return is `NotERC8153` at `register` and `SelectorDrift` on a read. Read gas is unchanged (the
  comparison measured the stored blob at about 1.7k more per read and 40k to 60k more per registration).
  The residual is the curator's to manage: a registered exporter whose answer depends on its own state, or
  on anything that can change, turns every read and every deploy that resolves it into `SelectorDrift`
  until a new version is registered. The caps bound what such an exporter costs a caller; nothing
  prevents the failure itself. Moving to a stored blob later changes `LatticeRegistry`'s bytecode and so
  moves both canonical addresses. **The maintainer confirmed the capped live read on 2026-10-09.**
- **`deploy` alongside `deployStrict`.** `deploy` keeps the idempotent return for scripts that pre-check
  the address (`BaseDeploy._assemble`); user interfaces should call `deployStrict`.

## What is not covered

- **Deployment on real networks.** These tests run on Forge's EVM. Chain-specific behaviour (Hedera's
  relay, L2 system calls, chains without EIP-6780, chains that reprice computation enough to matter for
  the 100,000-gas exporter budget) is untested here; `LatticeFactoryENSFork` covers the ENS constructor
  path on a fork.
- **Low-gas callers.** A `getCut` or `getSelectors` call left with too little gas to forward the full
  100,000 to the exporter can see the exporter run out of gas and then revert `SelectorDrift` instead of
  running out of gas itself. It still fails closed; retry with more gas.
- **The 13 facets without ERC-8153 exports** (#176 research comment). They cannot be registered and stay
  custom cuts.
- **Mutation testing** of the two contracts. The Gambit pilot (`make mutation`) targets three libraries; adding
  `LatticeRegistry` and `LatticeFactory` would measure how many mutants these suites kill.
- **Formal verification.** None.
- **Off-chain consumers** (Studio, indexers) and how they treat F-3, F-5 and F-7.

## Gas and size baselines

`snapshots/LatticeCoreGasTest.json` holds the gated baseline, produced under `FOUNDRY_PROFILE=ci`
(solc 0.8.36, optimizer 1,000,000 runs, `via_ir = false`, EVM osaka, Foundry 1.8.5). Forge runs each
top-level call from a test as its own transaction (`isolate`, on by default), so state-changing calls are
measured as whole transactions from cold state (21,000 intrinsic plus calldata plus execution) and view
calls as cold execution. Foundry's dynamic test linking turns a `new` written in a test file into an
unmetered cheatcode deployment, so the singleton deployments go through an explicit CREATE.

The hardening change moved the baseline as follows (before, after):

| Item | Before | After |
| --- | --- | --- |
| `LatticeRegistry` runtime / initcode (bytes) | 7,063 / 7,276 | 7,451 / 7,664 |
| `LatticeFactory` runtime / initcode (bytes) | 11,830 / 18,946 | 12,857 / 19,994 |
| `registry.getCut` with 4 / 16 / 64 selectors | 18,830 / 23,459 / 42,072 | 18,307 / 22,928 / 41,499 |
| `registry.register` with 4 / 64 / 256 selectors | 152,326 / 543,112 / 6,196,762 | 151,805 / 542,546 / 6,196,009 |
| `factory.deploy` loupe only: custom / pinned / latest | 1,603,720 / 1,614,780 / 1,621,374 | 1,606,053 / 1,617,349 / 1,623,948 |
| `factory.deploy` repeat (idempotent return) | 27,725 | 28,431 |
| `factory.deployStrict` loupe pinned | (new) | 1,617,826 |
| `factory.deploy` governed vault: custom / 8 entries + 6 custom / 14 entries with `exclude` | 6,857,926 / 6,880,606 / (new) | 6,877,906 / 6,902,499 / 7,078,231 |
| `registry.getMany` / `latestMany`, 3 records | (new) | 38,194 / 43,471 |

The bounded read is slightly cheaper than `abi.decode` (about 520 gas per read). Each fresh deploy pays the
recipe hash (about 2,300 gas for a loupe-only recipe, about 20,000 for the governed vault). The all-registry
vault costs 175,732 more than the 8 + 6 recipe: six more registry lookups plus the exclusion filter over 25
selectors. `LatticeCoreDesignBenchTest` logs the prototype measurements the design comparison uses
(`forge test --match-contract LatticeCoreDesignBenchTest -vv`).
