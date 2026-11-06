# 0021. ERC-3643 uses a closed immutable token composition

- **Status:** Accepted
- **Date:** 2026-11-06, for [#172](https://github.com/dadadave80/lattice/issues/172)

## Context

ERC-3643 must enforce eligibility, freezes and compliance on every supported movement. A facet that
calls `ERC20Lib` directly would bypass a permissioned `transfer` replacement. [0009](0009-token-extension-hook-model.md)
already makes such compositions incompatible. Merely documenting that rule is insufficient for this token.

## Options considered

1. **A specific closed immutable composition.** Check the actual plain Lattice host runtime, every
   approved facet runtime and the exact required selector routes during canonical initialization.
2. **A shared ERC-20 movement policy boundary.** Cover arbitrary direct movers, but add reads and an
   external policy call across every shared movement path, including unrelated ERC-20 tokens. The
   isolated paired probe measured +2,196 gas on ordinary transfers without an active policy and
   +1,328 bytes in the base ERC20 facet. It also exposed callback timing relative to vote checkpoints.
3. **General upgrade admission or arbitrary approved hash lists.** Require a broader authority and
   upgrade framework without a demonstrated need for this first profile.

## Decision

Use option 1, retaining 0009. There is no global movement hook, policy field in ERC20Storage,
caller-supplied hash list, generic scheduler or upgrade framework.

`DeployERC3643` installs the token, AgentRole, all five standard registry/compliance components,
Ownable, ERC-165 and the diamond loupe. ERC-7674 temporary approval is the sole optional facet.
There is no cut, account execution, delegatecall, vote, vault, permit or alternate accounting route.
The canonical initializer checks actual code hashes and complete route sets before external component
binding and again after initialization; selector self-reporting is not admission. It accepts only the
plain Lattice host, excluding account hosts with native fallback or execution capabilities.

Generated fingerprints are imported only by initialization code. The native build helper records
the host, every facet, selectors and canonical compiler settings in its input hash, rejects link
references and immutables, and rejects a facet dependency on profile/initializer code. Source or
metadata changes require review and regeneration. No deployed token can adopt regenerated values.

This guarantee assumes the canonical initializer and atomic recipe. The general LatticeFactory can
execute arbitrary initializers that write arbitrary diamond storage. A malicious alternative can
skip admission or change storage after a check; this profile does not certify those deployments.

The suite starts paused. Owner-controlled AgentRole uses existing AccessControl role bookkeeping
without routing or registering IAccessControl, seeding DEFAULT_ADMIN_ROLE, or exposing grantRole.
Owner transfer changes administration immediately; existing agents remain until explicitly removed.

Ordinary movement checks pause, both full freezes, free balance, recipient identity and canTransfer.
Agent mint and forced transfer require recipient identity but bypass ordinary pause/freeze and
canTransfer checks. Agent burn needs no identity and thaws only a frozen-balance deficit. Every
movement invokes its applicable lifecycle callback once, atomically. Batch operations use the scalar
rules. A suite-specific transient lock covers movement, recovery and registry/compliance mutation.

Recovery verifies the lost identity and the target's management key, permits zero balance and an
existing target with the same identity, sums partial freezes and ORs full freezes. A new target copies
the lost country; an existing target keeps its country. The old wallet is unregistered and fully
frozen. Persistent and temporary allowances are not enumerated or revoked. `version()` reports the
source-owned Lattice version.

Co-located authorized writes call internal helpers under the existing lock. External identity storage
must bind the real registry, including its predicted address before deployment. External recovery
requires actual token agent authority. Compliance must be pre-bound or genuinely authorize token
binding; a prior binding must clear atomically or out of band before replacement.

## Consequences

- Ordinary ERC-20 deployments pay no new movement cost. This profile intentionally rules out alternate
  token movers and account/upgrade compositions, including ERC1363, flash mint, wrappers and vault shares.
- Fresh MIT logic and fresh ABI declarations follow the CC0 standard. No GPL T-REX or ONCHAINID
  implementation or regulatory rule pack is included. External identity, claim issuer and compliance
  endpoints remain explicit trust and availability dependencies.
- Six new persistent namespaces and a separate transient execution lock leave existing layouts intact.
- The token reuses the mandatory registry's read-only STATICCALL route instead of duplicating the
  complete verifier. Under solc 0.8.36 / Foundry 1.9.0 / Cancun, this reduced runtime from 25,964 to
  22,404 bytes in the measured build. No deployment-size exception is introduced.
- Immutable tokens require a new reviewed deployment to change code. Migration and regulatory
  suitability are separate decisions; there is no automatic migration or regulatory certification.

## Confirmation

`ERC3643ProfileTest` tests actual factory admission, altered/missing/split routes, optional-facet
agreement, 17 real incompatible facets and native/account hosts. Token, recovery, registry, callback,
temporary-allowance and fuzz regressions pin the operation matrix. The storage guard, interface-route
and selector parity suites, deployment-size gates and `make erc3643-profile-check` enforce the build
boundary. The helper's mutation fixtures include code, route, compiler, link, immutable and dependency
drift. These local checks are not an independent security audit.

## References

- [ERC-3643](https://eips.ethereum.org/EIPS/eip-3643), CC0 standard and ABI assets
- [Permissioned token guide](../guides/erc3643.md)
- [#172](https://github.com/dadadave80/lattice/issues/172), comparison and implementation review
- [DeployERC3643](../../script/base/tokens/DeployERC3643.s.sol), [profile helper](../../script/erc3643-profile.sh)
