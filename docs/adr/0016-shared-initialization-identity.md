# 0016. Shared bootstrap identity and routed interface claims

- **Status:** Accepted
- **Date:** 2026-11-06

## Context

Several module initializers can run inside one diamond's initialization window. EIP-712 domain
initialization previously overwrote an earlier module's name/version, and repeated AccessControl
initialization could grant another bootstrap admin. Internal signing helpers also advertised their
optional public views even when no facet routed those selectors. The resulting ERC-165 claims were
false; the delayed Safe cut recipe likewise advertised the immediate `diamondCut` interface.

## Options considered

1. Let the last initializer win, leaving composition tools to warn about conflicts.
2. Require each signing recipe to install extra view facets, or maintain separate view-only init
   artifacts and init-chain entries.
3. Refuse conflicting shared bootstrap identity and advertise optional views only when routed.

For legacy AccessControl state, treating an empty new marker as fresh could silently grant another
admin. Refusing every first install after initialization version 1 would also block adding the module
to a diamond that never used it. Guessing from current role members cannot recover the original admin:
the role map is not enumerable, and legitimate role grants/revocations change its contents.

## Decision

Use option 3. EIP-712 initialization compares the existing name/version hashes. A conflicting domain
reverts; an identical domain preserves its stored strings and separator cache. AccessControl appends
its original bootstrap admin and an initialized marker. A conflicting admin reverts; an identical
admin is a no-op, including after its role has been revoked. Role administration still uses the
ordinary grant/revoke operations.

A registered AccessControl instance with no new bootstrap marker is treated as legacy and refuses
bootstrap initialization. Read the existing precomputed registration slot; do not infer an admin from
role contents. An unregistered module can still be installed for the first time in a later
reinitializer. This assumes historical module initialization followed the supported registration
convention. Custom legacy code that seeded roles without registering AccessControl needs a reviewed
migration; this check cannot identify arbitrary custom storage history.

EIP712 and Nonces advertise their view interfaces only when the corresponding selector is in the
diamond's facet map, clearing stale claims when a view is absent. Lattice installs cuts before invoking module initializers. An inheritance-based
consumer that exposes these views can register them explicitly. The delayed Safe cut initializer
registers loupe discovery and its own delayed-cut interface, without claiming immediate `diamondCut`.

## Consequences

- Existing namespaces, selectors and interface IDs remain unchanged. AccessControl's record is an
  append-only storage extension and requires a minor release.
- Upgrading a legacy AccessControl facet does not itself change any roles. A custom upgrade initializer
  must avoid replaying bootstrap or deliberately migrate its historical bootstrap record after review.
- Domain identity cannot be changed by composing another module initializer. An intentional domain
  migration requires its own reviewed upgrade logic rather than an accidental overwrite.
- Recipes need no extra view facets or initializer artifacts. Shared view registration follows the
  actual router, while their internal hashing/nonce operations remain usable without public views.
- The recipe guard derives interface IDs from compiler-declared selectors and checks every claimed
  ID. Inherited declarations are excluded from an ERC-165 ID; separately claimed parent IDs are checked
  separately. Canonical ERC-721/ERC-1155 core and metadata IDs are checked independently because
  Lattice's interface files bundle those declarations.

## Confirmation

- `InitializationCompositionTest` uses real Lattice diamonds and production module initializers to
  cover shared domains, conflicting admins, revoked admins, legacy registration and first install at
  version 2, including transaction rollback.
- Every existing production recipe's `RecipeGuards` introspection check verifies advertised interfaces
  against routed selectors. Harness self-tests prove a false view claim fails.
- The storage checker verifies the appended AccessControl fields against the trusted base.

## References

- [#205: conflicting shared initialization](https://github.com/dadadave80/lattice/issues/205)
- [#206: truthful recipe interface claims](https://github.com/dadadave80/lattice/issues/206)
- [0008: freeze once live](0008-freeze-once-live.md)
- [`AccessControlLib`](../../src/access/libraries/AccessControlLib.sol)
- [`EIP712Lib`](../../src/utils/libraries/EIP712Lib.sol)
