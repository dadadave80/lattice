# 0026. Recipes share checked cut plans and export descriptive composition data

- **Status:** Accepted
- **Date:** 2026-11-06; comparison for [#201](https://github.com/dadadave80/lattice/issues/201) and [#202](https://github.com/dadadave80/lattice/issues/202)

## Context

Canonical recipe builders encoded selector ownership, initializer order, input units and authorities in
imperative Solidity. A separate consumer catalog could drift from the builders, particularly at mixed
Add/Replace cuts, nested MultiInit wrappers and constructor-bound account topologies.

## Options considered

1. **Share pure cut declarations, retain typed initialization, export descriptive data.** Chosen: one cut
   plan feeds both checked materialization and recipeSpec; abi.encodeCall retains compiler checking.
2. **Build a generic runtime planner and initializer interpreter.** Adds a language, execution surface and
   authority assumptions beyond the required data export; no demonstrated need justifies that scope.
3. **Maintain an independent JSON/YAML catalog or infer composition from imports.** Duplicates source
   facts or confuses implementation dependencies with actual installed facets and initialized modules.
4. **Collect every script in one native EVM execution.** Measured script construction exceeds the default
   aggregate gas limit at TWAPOracle (1,073,634,307 gas used). Bounded per-record collection preserves
   default limits and native semantics; the initial cold 103-record run used at most 31,244,961 gas per
   invocation. These are local script execution measurements, not on-chain deployment gas.

## Decision

Every canonical recipe exposes the documented RecipeSpec DTO. Pure ordered facet plans drive both
buildCuts and the spec. Exclusions, partial export omissions and replacements require active named seams;
ordered Add/Replace validation mirrors diamond ownership, and assembled proxies are checked against
both declared owners and an independent fixed selector-owner oracle.

Known ERC1363 combinations with ERC20Pausable, ERC20Votes or GovernedVault fail before any shared
implementation resolution. This is a checked-script boundary; arbitrary diamondCut remains governed by
its on-chain authority and can bypass script policy. ADR0009's mutually exclusive movement model remains.

Initializer encoding stays typed in each builder. The data preserves complete ordered nested MultiInit
calls, external parameter names/types, units, examples, source-enforced rules, caller obligations and
constructor bindings. Binding strings describe source expressions and are never interpreted. Bundle
internal phases, including qualified policy-only initialization, remain compiler composition metadata.
Account owner/salt/default EntryPoint inputs are deployment contexts, separate from buildCuts(address).
Canonical EntryPoint instances are recorded from AccountReleaseInventory; custom EntryPoints remain
explicit caller choices. Chain-specific demos and abstract helpers have explicit catalog dispositions.

`make recipes` builds the pinned canonical profile, collects one recipe per native Forge invocation, checks
native ABI-byte serialization roundtrips, validates compiler ABI coverage and publishes out/recipes.json
atomically. It uses existing Bash, jq and Forge; it requires no RPC, broadcast, new runtime or relaxed
shared gas/code-size/filesystem configuration. The native codec emits small integers as JSON numbers
and larger integers, including the root-parent
uint256 sentinel, as decimal strings. Consumers must preserve that representation or use a lossless
JSON parser with arbitrary-precision integers; JavaScript number conversion is not generally safe.

## Consequences

The DTO is script data, not a deployed interface or a guarantee that external providers, EntryPoints,
assets, keys or circuits are trustworthy. Typed recipe tests cover each canonical variant and inherited
context. ABI checks reject missing or dangling records; they do not execute descriptive binding strings.
Early validation and script-data code add local build/deployment-script work. They do not change module
runtime logic, storage or interfaces. A native export needs multiple bounded local invocations and records
its source commit and dirty-tree state; consumers should pin a reviewed clean-source catalog.

## Confirmation

The five typed recipe suites compare actual cuts, initializer targets/selectors/tree and proxy kinds with
their specs. Separate real-proxy oracle tests cover contested ownership and missing/wrong-route controls.
Composition sentinel tests distinguish early rejection from rollback after attempted resolution. Native
catalog fixtures check metadata/ABI completeness; exporter fixtures exercise failure cleanup and atomic
publication. The actual cold catalog run must pass at default limits.

## References

- [Recipe DTO](../../script/lib/RecipeSpec.sol), [checked plans](../../script/lib/RecipePlanLib.sol)
- [Export command and format](../../script/README.md#recipe-data-and-checked-composition)
- [Movement policy](0009-token-extension-hook-model.md)
- [Account topology](0025-account-factory-release-identity.md)
