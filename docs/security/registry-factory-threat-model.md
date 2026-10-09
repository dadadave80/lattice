# LatticeRegistry and LatticeFactory: threat model and test map

This document maps every external entry point of `LatticeRegistry` and `LatticeFactory`, the trust
boundaries between their callers, the invariants the two contracts are meant to keep, and the tests that
check each one. It also lists what the tests found and what they do not cover.

It describes the source at `dev` 8e95a08. The work behind it (issue #176) added tests only. Neither
contract changed, because any byte change moves their canonical addresses (their deployment salts carry no
version). Passing these tests is not an audit and does not make either contract production ready.

## Components and trust boundaries

| Actor | Can do | Trusted for |
| --- | --- | --- |
| Registry owner (the curator) | `register`, `setLatest`, `transferOwnership` | Which facets enter Tier B, and where each `latest` pointer points |
| Pending owner | `acceptOwnership` | Nothing until it accepts |
| Anyone | `attest`, every view, `factory.deploy`, `factory.predict` | Nothing |
| A facet's `exportSelectors()` | Runs under the registry's `staticcall` at `register` and on every live read | Nothing: the registry pins `codehash` and `keccak256(blob)` at registration |
| The factory's registry | Answers `latest` and `getCut` during `deploy` | Everything it returns. The factory does not re-validate registry cuts |
| A deployer (`msg.sender` of `deploy`) | Picks the salt, the recipe, the init and the init calldata | Its own diamond only. The salt is bound to the sender |
| The init contract | Runs by `delegatecall` inside `Lattice.initialize`, with `msg.sender` equal to the factory | Its own diamond only |

The two contracts are standalone, plain and non-upgradeable. The factory holds no state and its registry
address is fixed at construction. The registry's only privileged role is the curator of Tier B. Tier A
(`attest`/`resolve`) and all reads are permissionless.

## Entry points

### LatticeRegistry (`src/LatticeRegistry.sol`)

| Entry point | Line | Caller | External calls | Writes |
| --- | --- | --- | --- | --- |
| `constructor(initialOwner)` | 66 | deployer | none | `owner` |
| `attest(deployed)` | 77 | anyone | `EXTCODEHASH` | `_resolver[codehash]` if unset |
| `resolve(codehash)` | 82 | anyone | none | none |
| `register(bytes32 \| string, version, facet)` | 91, 130 | owner | `EXTCODEHASH`, `staticcall exportSelectors()` | `_records`, `_resolver` if unset |
| `setLatest(bytes32 \| string, version)` | 96, 135 | owner | none | `_latestVersion` |
| `get`, `latest` (both overloads) | 101-108, 140-147 | anyone | none | none |
| `getSelectors`, `getCut` (both overloads) | 111-118, 150-157 | anyone, and the factory | `EXTCODEHASH`, `staticcall exportSelectors()` | none |
| `nameHash(name)` | 160 | anyone | none | none |
| `transferOwnership(newOwner)` | 169 | owner | none | `pendingOwner` |
| `acceptOwnership()` | 175 | pending owner | none | `owner`, `pendingOwner` |

### LatticeFactory (`src/LatticeFactory.sol`)

| Entry point | Line | Caller | External calls | Writes |
| --- | --- | --- | --- | --- |
| `constructor(registry, reverseRegistrar, reverseRecordOwner)` | 44 | deployer | `IReverseRegistrar.claim` when ENS is configured | immutables |
| `deploy(entries, customCuts, init, initCalldata, salt)` | 59 | anyone | `registry.latest` (version 0), `registry.getCut`, CREATE2 of `Lattice`, `Lattice.initialize`, which delegatecalls `init` | a new diamond |
| `predict(deployer, salt)` | 116 | anyone | none | none |
| `registry()` | 32 | anyone | none | none |

`deploy` runs in this order: refuse an empty recipe, refuse `exportSelectors()` in any custom cut, return
early if `(msg.sender, salt)` is already deployed (line 84), resolve the entries through the registry, append
the custom cuts, check loupe coverage, CREATE2 the proxy, call `initialize`, and emit `DiamondDeployed`.

## Invariants and the tests that check them

The invariant set is the one proposed in #176 (R1-R7, F1-F6). Each invariant has a stateful suite and,
where useful, targeted unit and fuzz tests.

| Id | Property | Stateful | Unit and fuzz |
| --- | --- | --- | --- |
| R1 | A record never changes once written | `LatticeRegistryInvariant`, `LatticeRegistryCodeDriftInvariant` (`invariant_R1_RecordsAreImmutable`) | `LatticeRegistryFuzz.testFuzz_RecordIsImmutable`, `LatticeRegistryTest.test_I1_*` |
| R2 | A non-zero `resolve(h)` never changes and is the first attester; `register`'s auto-attest never overwrites it | `invariant_R2_ResolverIsFirstWriteWins` | `LatticeRegistryHostileExporterTest.test_RegisterAutoAttestNeverOverwritesResolver`, `LatticeRegistryTest.testFuzz_AttestFirstWriteWins` |
| R3 | A set `latest(n)` equals `get(n, latest(n).version)`; an unset one reverts | `invariant_R3_LatestPointsAtARecord` | `LatticeRegistryTest.test_SetLatest*` |
| R4 | `owner != 0`; ownership moves only through `acceptOwnership`, which clears `pendingOwner`; `transferOwnership(0)` cancels; strangers cannot write | `invariant_R4_Ownership` | `LatticeRegistryFuzz.testFuzz_OwnershipHandover`, `LatticeRegistryFuzz.test_Finding_CancelledHandoverIsAcceptableOnlyByAddressZero` |
| R5 | String and hash overloads return the same data or the same error | `invariant_R5_StringHashParity` | `LatticeRegistryFuzz.testFuzz_StringAndHashOverloadsAgree` |
| R6 | `getCut` returns the pinned selectors, or reverts `CodeDrift` when the code changed, else `SelectorDrift` | `invariant_R6_GetCutIsPinnedOrDrift` (flip-based drift in `LatticeRegistryInvariant`, `vm.etch` drift in `LatticeRegistryCodeDriftInvariant`) | `LatticeRegistryHostileExporterTest` live-read section |
| R7 | Version 0 never holds a record | `invariant_R7_VersionZeroNeverRegisters` | `LatticeRegistryFuzz.testFuzz_VersionZeroNeverRegisters` |
| F1 | deploy == predict == CREATE2 over `keccak256(type(Lattice).creationCode)`; a resolved entry keeps the version resolved at deploy time | `LatticeFactoryInvariant.invariant_F1_DeployEqualsPredict` | `LatticeFactoryFuzz.testFuzz_DeployEqualsPredictEqualsCreate2`, `LatticeFactoryHardeningTest.test_PredictMatchesCreate2OverLatticeCreationCode` |
| F2 | A reverted deploy leaves no code and stays retryable | `invariant_F2_FailedDeploysLeaveNoCode` | `LatticeFactoryFuzz.testFuzz_FailedInitRollsBackAndRetries`, `test_DriftMidRecipeRollsBackAndStaysRetryable` |
| F3 | The factory holds a role on a diamond exactly when the init granted `msg.sender` (finding F-6) | `invariant_F3_FactoryAuthority` | `test_Finding_InitGrantingMsgSenderGrantsTheFactory`, `test_ExplicitAdminInitLeavesFactoryWithoutRole`, `LatticeFactoryGovernedVaultTest.test_RegistryVaultIsSelfGovernedAndFactoryHoldsNoRole` |
| F4 | A repeat `(sender, salt)` returns the same address, emits nothing, and leaves the loupe unchanged | `invariant_F4_RepeatDeploysLeaveLoupeUnchanged` (plus asserts in the handler) | `LatticeFactoryFuzz.testFuzz_IdempotentReturnIgnoresAnyRecipe`, `test_Finding_OccupiedAddressIgnoresNewRecipeAndInit` |
| F5 | All four loupe selectors are routed | `invariant_F5_F6_LoupeRoutedExportNot` | `LatticeFactoryFuzz.testFuzz_LoupeCoverageNeedsAllFour`, `LatticeFactoryTest` loupe section |
| F6 | `exportSelectors()` (`0x0ef22643`) is never routed | `invariant_F5_F6_LoupeRoutedExportNot` | `LatticeFactoryFuzz.testFuzz_ExportSelectorInCustomCutAlwaysRefused` |

All three invariant suites run with `fail_on_revert = true`: the handlers predict each outcome from ghost
state and assert expected reverts with `vm.expectRevert`, so a handler that silently reverted would fail the
run. Under `FOUNDRY_PROFILE=ci` they run 64 runs at depth 128.

## Other properties and where they are tested

| Property | Tests |
| --- | --- |
| Registration accepts a return exactly when it decodes to a non-empty, 4-aligned, duplicate-free blob without `0x0ef22643`, and pins the hash of the decoded blob | `LatticeRegistryFuzz.testFuzz_BlobAcceptanceMatchesTheRule`, `testFuzz_RawReturnNeverRegistersAnythingButTheDecodedBlob`, `testFuzz_StructuredReturnNeverRegistersAnythingButTheDecodedBlob` |
| Hostile exporters: reverting, gas-burning, short, malformed offsets and lengths, truncated, non-canonical, trailing bytes, dirty padding, huge returns, duplicates and the self-selector at the end of long blobs, re-entry into the registry from inside the staticcall | `LatticeRegistryHostileExporterTest` |
| Mutable exports and code drift: transient selector drift, a live answer switched to a short or malformed return, emptied code, code swapped for code with the same export | `LatticeRegistryHostileExporterTest` live-read section |
| Tier A is a code-identity lookup: same-codehash instances in different states export different selectors, and `resolve` returns the first attester | `test_Finding_ResolveReturnsFirstAttesterWhileExportsDiffer` |
| Recipe kinds (pinned, latest, custom, mixed) route every selector to the facet that supplied it | `LatticeFactoryFuzz.testFuzz_MixedRecipesRouteEverySelector`, `LatticeFactoryTest` |
| Selector collisions abort the deploy: registry/registry, the same entry twice, pinned plus latest of one name, a duplicate inside one custom cut, registry/custom | `LatticeFactoryHardeningTest` collision section, `LatticeFactoryTest.test_DeployRevertsOnSelectorCollisionWithRegistryCut` |
| Cut order: custom cuts run after registry cuts, so a custom `Replace` or `Remove` can change a registry selector (never a loupe selector) | `test_CustomRemoveDropsRegistrySelector`, `LatticeFactoryTest.test_CustomReplaceCutRePointsRegistrySelector` |
| Caller and salt isolation, including a competing caller reusing a victim's salt | `LatticeFactoryFuzz.testFuzz_CallerSaltIsolation`, `test_CompetingCallerCannotOccupyAnotherCallersAddress` |
| ETH sent to a predicted address does not block deployment | `test_PrefundedPredictedAddressDeploysAndKeepsBalance` |
| Malicious init callbacks: re-entering `initialize` (refused, deploy rolls back), re-entering `factory.deploy` (the child's salt is bound to the new diamond), a custom-error revert (bubbles byte for byte) | `LatticeFactoryHardeningTest` authority and callbacks section |
| A selector the proxy itself defines (`initialize`) can be cut but is never reachable through the diamond | `test_ProxyShadowedSelectorIsCutButUnreachable` |
| A real module (the self-governed vault) through the registry path: same routing as the custom-only recipe, self-governance wired, no role for the factory or the deployer, no shared state between two vaults | `LatticeFactoryGovernedVaultTest` |
| Gas and size baselines | `LatticeCoreGasTest` (gated, `snapshots/LatticeCoreGasTest.json`), `LatticeCoreDesignBenchTest` (logged, not gated) |

## Findings

No finding lets a third party take over or alter someone else's diamond, or change a curated record. Most
are error-reporting gaps, resource bounds, or semantics that the joint `deployStrict` PR should settle.
Each one is pinned by a passing test named `test_Finding_*`, so a fix shows up as a deliberate test change.

| Id | Finding | Severity | Test | Suggested change (joint PR) |
| --- | --- | --- | --- | --- |
| R-1 | A return of 64 bytes or more that `abi.decode` rejects (offset or length past the end, truncated data) makes `register` revert with EMPTY data, and a huge declared length reverts with `Panic(0x41)`, not `LatticeRegistry__NotERC8153` as `ILatticeRegistry` documents. On the live path the same input makes `getCut` revert with empty data, while `_liveSelectors`' NatSpec says Panic. Both fail closed. | Low (wrong error, no state impact) | `test_Finding_RegisterBareRevertOn*`, `test_Finding_RegisterPanicsOnHugeDeclaredLength`, `test_Finding_LiveMalformedReturnIsBareRevert`, the two raw-return fuzz tests | Validate the offset and length words before decoding, or decode in assembly, and revert `NotERC8153` / `SelectorDrift`; fix the NatSpec either way |
| R-2 | The exporter `staticcall` forwards all available gas and copies the whole return. A curated exporter that returns a valid encoding plus about 1 MB makes every `getCut` (and every factory deploy that resolves it) cost more than 3M gas; a looping or statically-reverting exporter burns 63/64 of the caller's gas | Low (only curated or would-be-curated facets; the owner pays at `register`, consumers pay on reads) | `test_Finding_ReturnBombRegistersAndTaxesEveryRead`, `test_LoopingExporterBurnsForwardedGasThenRevertsNotERC8153`, `test_ReentrantAttestInsideStaticcallDependsOnRegistryState` | Cap the forwarded gas and the copied return size; or store the blob at registration so live reads never call the facet (see the design comparison) |
| R-3 | Tier A is a code-identity lookup. Two instances with one codehash can export different selectors (an exporter that reads its own storage), and `resolve` returns the first attester. The `ILatticeRegistry` Tier A NatSpec claims any same-codehash address is equivalent, which holds only under `delegatecall` | Informational (trust-model documentation) | `test_Finding_ResolveReturnsFirstAttesterWhileExportsDiffer`, `test_RegisterAutoAttestNeverOverwritesResolver` | State the supported-facet assumptions in the NatSpec (no reads of the facet's own storage outside `delegatecall`, a `pure` exporter, no proxy facets, `resolve` is not a selector source) |
| R-4 | `transferOwnership(0)` cancels by storing `pendingOwner = 0`, and `acceptOwnership` does not reject a zero pending owner, so a call from address 0 would set `owner = 0`. No transaction is sent from address 0, so this is reachable only under a cheatcode | Informational | `LatticeRegistryFuzz.test_Finding_CancelledHandoverIsAcceptableOnlyByAddressZero` | `if (pendingOwner == address(0)) revert` in `acceptOwnership`, so R4 holds by construction |
| F-1 | The factory constructor rejects only a zero registry, not a codeless one. Such a factory deploys custom-only recipes, and every recipe entry reverts with empty data | Low (permanent misconfiguration of an immutable contract) | `test_Finding_ConstructorAcceptsCodelessRegistry` | Also revert when `registry.code.length == 0` |
| F-2 | `init == address(0)` with non-empty init calldata succeeds and drops the calldata (DiamondLib returns early) | Low (a recipe that forgot its init deploys uninitialized, without an error) | `test_Finding_ZeroInitSilentlyDropsCalldata` | Revert on a zero init with non-empty calldata |
| F-3 | A repeat `deploy` for an occupied `(sender, salt)` returns the existing diamond and ignores the new entries, custom cuts, init and calldata, with no event | By design today; the reason for `deployStrict` | `test_Finding_OccupiedAddressIgnoresNewRecipeAndInit`, `testFuzz_IdempotentReturnIgnoresAnyRecipe`, invariant F4 | `deployStrict` reverts `LatticeFactory__AlreadyDeployed(diamond)` |
| F-4 | Users behind one shared forwarder (Multicall3, a relayer) reach the factory with the same `msg.sender` and share one salt namespace: the second user silently receives the first user's diamond and admin (#176 residual (b)) | Medium for integrations that route deploys through a shared forwarder; none for today's scripts, which call the factory directly | `test_Finding_SharedForwarderCallersShareOneNamespace` | `deployStrict` turns the silent return into a revert; document that deploys must come from the deploying account |
| F-5 | A `version == 0` entry resolves `latest` when the transaction executes. A curator move between signing and inclusion changes the cut, and `DiamondDeployed(diamond, deployer, salt)` cannot tell which version was cut (#176 residual (a)) | Low (curator-trusted; the registry NatSpec already tells security-critical consumers to pin) | `test_Finding_LatestMovedBeforeInclusionIsInvisibleInTheEvent` | Recipe hash in the event (D27); optionally refuse version 0 in `deployStrict`; repeat the pinning advice on `RecipeEntry` |
| F-6 | `Lattice.initialize` is called by the factory, so an init that grants `msg.sender` grants the factory, which has no call surface to use the role. The deployer holds nothing and the role is stranded | Low (footgun for consumer inits; no shipped init does this) | `test_Finding_InitGrantingMsgSenderGrantsTheFactory`, invariant F3 | Document it on `deploy` and in the guide; inits take an explicit admin |
| F-7 | An init that self-destructs the diamond is accepted, and `deploy` returns the address and emits `DiamondDeployed`. Because the diamond was created in the same transaction, EIP-6780 deletes it when the transaction ends, so the same `(sender, salt)` can deploy again with another recipe and emit a second `DiamondDeployed` for the same address | Low (only the deployer's own address; breaks "one `DiamondDeployed` per address" for indexers) | `test_Finding_SelfDestructingInitStillEmitsDiamondDeployed` (both halves: the first deploy's event, then a second deploy for the same `(sender, salt)` with another recipe that emits a second `DiamondDeployed` for the same address) | No in-transaction check can catch it (the deletion happens after `deploy` returns). Record it as a known property: indexers treat the latest `DiamondDeployed` for an address as authoritative |

### Reproducing F-7

The EIP-6780 deletion happens at the end of the transaction that created the diamond. Forge runs each
top-level call of a test as its own transaction (`isolate`, on by default in Foundry 1.8.5), so the next
`deploy` from the test sees the emptied address, creates the diamond again and emits a second
`DiamondDeployed`; `test_Finding_SelfDestructingInitStillEmitsDiamondDeployed` asserts that second event and
the second recipe's routing. The test contract's own `code.length` read of the address is not a reliable
witness of the deletion, so the test does not rely on it.

The same sequence was also run against `anvil --hardfork osaka` (Foundry 1.8.5) on 2026-10-09, as
corroboration on a node:

1. `forge create` `LatticeRegistry`, `LatticeFactory` (registry, no ENS), `DiamondLoupeFacet` and
   `test/helpers/LatticeCoreMocks.sol:CoreSelfDestructInit`.
2. `cast send <factory> "deploy((bytes32,uint64)[],(address,uint8,bytes4[])[],address,bytes,bytes32)" "[]"
   "[(<loupe>,0,[0x7a0ed627,0xadfca15e,0x52ef6b2c,0xcdffacc6])]" <init> 0xe1c7392a <salt>`: status 1,
   `DiamondDeployed` emitted, and `cast code <predicted>` returns `0x` afterwards.
3. The same call with `init = address(0)` and empty calldata: status 1, a second `DiamondDeployed` for the
   same address, and the address now has code.

## What is not covered

- **Deployment on real networks.** These tests run on Forge's EVM. Chain-specific behaviour (Hedera's
  relay, L2 system calls, chains without EIP-6780) is untested here; `LatticeFactoryENSFork` covers the ENS
  constructor path on a fork.
- **The 13 facets without ERC-8153 exports** (#176 research comment). They cannot be registered and stay
  custom cuts. Exporting them changes facet sources, which this work did not do.
- **Partial-facet registry recipes.** Six of the governed vault's 14 facets cannot be registry entries,
  because `RecipeEntry` cannot exclude selectors (`test_PartialFacetsCannotBeRegistryEntriesToday`).
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
`LatticeCoreDesignBenchTest` logs the prototype measurements the design comparison uses
(`forge test --match-contract LatticeCoreDesignBenchTest -vv`). Its selector-representation comparison runs
the real registry and two prototype registries (selectors stored as a code blob, or as a `bytes4[]`) behind
the same `getSelectors(bytes32,uint64)` call, from cold state, so every design pays the record lookup, the
codehash pin and the `bytes4[]` return and decode.
