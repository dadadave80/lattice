# 0031. Initializer batches reject zero entries and retain indexed failures

- **Status:** Accepted; diamond-lib v0.4.0 adoption
- **Date:** 2026-11-06; dependency follow-up for [#192](https://github.com/dadadave80/lattice/issues/192)

## Context

[ADR0024](0024-upgrade-initializer-batches.md) established one replay-protected upgrade window,
while preserving the dependency's zero-address terminator and direct revert bubbling. A zero entry
can therefore return successfully after earlier writes and skip later steps. Bare inner errors also
omit the failed step's position in a nested batch.

[diamond-lib#35](https://github.com/dadadave80/diamond-lib/issues/35) and its
[implementation](https://github.com/dadadave80/diamond-lib/pull/37), released in
[v0.4.0](https://github.com/dadadave80/diamond-lib/releases/tag/v0.4.0), reject zero entries and retain
indexed diagnostics. Lattice has its own `ReinitMultiInit` loop, so a dependency update alone cannot
align that helper.

## Decision

Use the same input and failure policy for `MultiInit` and `ReinitMultiInit`. Arrays have matching,
exact lengths. A zero target reverts `MultiInit__ZeroInit(index)`; missing bytecode reverts
`NoBytecodeAtAddress(index, initAddress)`. Every failed delegatecall reverts
`MultiInit__StepFailed(index, init, reason)`, retaining its original reason bytes, including empty
bytes. Indexes are zero-based and nested batches retain each enclosing diagnostic.

Keep a small ordered delegatecall loop in `ReinitMultiInit`, using the dependency's canonical error
declarations. Preserve its sole `reinitMulti(uint64,address[],bytes[])` entrypoint, existing
`reinitializer(version)` modifier, strictly increasing version rule, empty-batch version advance,
storage slot and authority supplied by the diamond's authorized cut. A failure still rolls back
earlier steps, the cut and the version. No facet selector, role, namespace or storage field is added.

This replaces only ADR0024's zero-target and step-error policy. Its window, version read, storage
and authority decisions remain accepted. DiamondLib's separate address-only missing-code error
is unchanged.

## Alternatives and consequences

Updating only the dependency leaves the independent wrapper inconsistent. Inheriting `MultiInit`
would expose an additional public unwrapped method. Delegating to another deployed executor adds
an address/code dependency; introducing a shared abstraction expands the upstream change. A short
local loop avoids those costs while keeping the error ABI identical to the dependency.

Callers must remove zero sentinels and decode the new outer errors instead of expecting a bare
inner revert. Diagnostics identify execution position; they do not authenticate initializer code
or constrain its authority over diamond storage. Existing upgrade authorization and source review
remain necessary. Direct calls execute caller-selected code in the shared helper's own account
context, including storage, assets and external calls; the reinitializer is not authorization.
Shared helpers must not be given custody, token approvals or external roles. Both initializer bytecodes change and require normal release identity checks.
No gas optimization is claimed.

Adopt retained diamond-lib v0.4.0 at commit
`580d6921717830b52e63d1f512dc9439acf4562a` in the gitlink and dependency lock. Its `src/` tree
matches the reviewed indexed-error implementation. This dependency adoption is separate from a
Lattice release, canonical deployment or public source-verification submission.

## Confirmation

`ReinitMultiInitTest` checks ordered failure paths, exact custom/string/panic/empty reasons,
zero-position fuzzing, empty success, version/authority controls and cut/state/version rollback with
same-version retry. `GovernedVaultUpgradeTest` checks the indexed late bootstrap failure through
actual governance execution. Initializer inventory and composition metadata gates enforce the
matching entrypoint and parameter descriptions.

## References

- [ADR0024](0024-upgrade-initializer-batches.md)
- [diamond-lib#35](https://github.com/dadadave80/diamond-lib/issues/35)
- [diamond-lib#37](https://github.com/dadadave80/diamond-lib/pull/37)
- [Lattice dependency tracker#192](https://github.com/dadadave80/lattice/issues/192)
