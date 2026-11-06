# 0027. Governor validates the declared governed-cut executor topology

- **Status:** Accepted
- **Date:** 2026-11-06; implementation decision for [#208](https://github.com/dadadave80/lattice/issues/208)

## Context

GovernedDiamondCut grants its self-administered executor role to the diamond. A direct Governor or
co-located timelock reaches the cut from that address. An external timelock reaches it as the
timelock and cannot execute proposed cuts under the default role policy. Other Governor and cut
compositions legitimately use external timelocks.

## Options considered

1. **Declare policy during guarded initialization and bind it to the actual cut owner.** Chosen:
   checks configuration without introducing runtime classification or a general routing framework.
2. **Grant the external timelock a cut role automatically.** Rejected: silently changes authority
   and creates executor-rotation responsibilities unrelated to validation.
3. **Infer policy from ERC165, role state or runtime fingerprints.** Rejected: cut interface IDs
   collide, roles may outlive routes, and build-specific runtime classification adds history and
   regeneration complexity. Rejecting all external timelocks would break independent compositions.

## Decision

- Append a declared cut owner and explicit external-topology exemption to Governor storage, keeping
  its existing namespace, field prefix, selector set and interface ID.
- Canonical governed-cut initialization requires a nonzero installed `diamondCut` owner, declares
  that route's policy and checks the configured timelock. Governor initialization and its existing
  governance-only `updateTimelock` perform the same validation. Both module initialization orders
  are checked. Zero and self timelocks remain supported.
- This is a trusted initializer declaration, with the same composition trust boundary as role
  setup. It does not certify arbitrary runtime bytecode or mismatched initializer/cut pairs.
- Ignore a stale declaration once another facet owns the cut selector. A governed-cut upgrade to
  a new address must re-register the declaration in its authorized initialization batch.
- Permit a distinctly named, explicitly acknowledged initializer opt-out. It changes validation
  only and never grants an executor role. Its external authority design needs separate validation.
- Legacy unmarked deployments require an explicit policy-only backfill through an authorized
  reinitializer. That step preserves configuration, roles and emergency state. Upgrading Governor
  alone does not retroactively identify an old cut deployment or repair existing governance liveness.

## Consequences

Configuration paths gain bounded storage/route checks and one appended policy word; proposal
execution authority and role administration stay unchanged. The guard does not protect a caller
that deliberately omits trusted initialization, uses an arbitrary migration, selects the explicit
exemption or later installs an unreviewed cut policy without re-registering it. There is no new
runtime dependency or public Governor selector.

Under the shared Cancun/solc 0.8.36 optimizer profile, Governor runtime grows from 17,082 to
17,519 bytes (+437). The existing atomic governed-vault deployment fixture grows from 6,864,747
to 6,887,915 gas (+23,168), including initialization and calldata effects. The recorded steady-state
governance gas snapshots remain unchanged. Alternative implementations were not benchmarked.

## Confirmation

Real LatticeFactory compositions execute proposed cuts under both supported topologies and both
initialization orders. Regressions cover incompatible initialization/setters, explicit opt-out
without role grants, stale route replacement, re-registration, initialization guards and legacy
backfill/rollback. Existing standalone external-timelock tests remain applicable.

## References

- [GovernorInit](../../src/governance/GovernorInit.sol),
  [GovernorLib](../../src/governance/libraries/GovernorLib.sol),
  [GovernedDiamondCutLib](../../src/governance/libraries/GovernedDiamondCutLib.sol)
- [Topology tests](../../test/integration/GovernorTimelockTopologyTest.t.sol)
- [Composition guide](../guides/compose-your-own-diamond.md#governor-and-governed-cut-executors)
