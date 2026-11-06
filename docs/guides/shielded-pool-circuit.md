# ShieldedPool withdraw-circuit requirements

This is a reference specification for a consumer and their circuit auditor, not an audited circuit
or a production verifier. Lattice ships no audited ShieldedPool withdrawal circuit. The circuit
under [test/fixtures/shielded](../../test/fixtures/shielded/withdraw.circom) is a test fixture only.

## Statement and public inputs

A withdrawal proves knowledge of a nullifier and secret whose commitment is a member of the pool
commitment tree at an accepted root. Its five public field elements, in order, are `root`,
`nullifierHash`, `recipient`, `relayer` and `fee`. This order matches
[IShieldedWithdrawVerifier](../../src/interfaces/privacy/IShieldedPool.sol) and
[ShieldedPoolLib.withdraw](../../src/privacy/libraries/ShieldedPoolLib.sol). The recipient and
relayer are the `uint160` encodings of the addresses, not hashes or strings. The fee is the integer
token amount in the token’s smallest unit.

The circuit must constrain `commitment = Poseidon(nullifier, secret)` with the two-input
`Poseidon(2)` circuit, using the same BN254 field, Poseidon parameters and input ordering as
[Lattice’s incremental Merkle-tree
implementation](../../src/privacy/libraries/IncrementalMerkleTreeLib.sol). It must constrain
`nullifierHash = Poseidon(nullifier)` with the one-input `Poseidon(1)` circuit. Neither a
caller-selected key nor a freely chosen nullifier hash is part of the statement.

## Membership and witness constraints

The witness consists of the nullifier, secret and complete authentication path. The circuit must
reconstruct the exact LeanIMT root, including leaf order, supported depth, index/path-bit ranges and
odd-node behavior. Every witness component that affects membership must be constrained; unused
padding and paths cannot provide an alternative route around membership.

Auditors must establish canonical field encodings and the absence of modular aliases, truncated
indices, unconstrained selectors and unsatisfied range assumptions. The supported maximum tree
size/depth must be explicit and must cover the consumer’s configured lifetime. The contract’s
root-history acceptance does not prove that the circuit computed that root correctly.

## Withdrawal binding

All five public inputs must remain cryptographically bound after the actual circuit compiler’s
optimizations and trusted setup. With one valid generated proof, independently changing root,
nullifierHash, recipient, relayer or fee must fail verification. A witness or public-input
declaration alone is not evidence of binding.

The contract checks that fee does not exceed its fixed pool denomination, that the root is known for
that pool, and that the nullifier is unspent in that pool. It spends the nullifier before
transferring denomination minus fee to recipient and fee to relayer. Those contract checks
complement the circuit; they do not replace membership or nullifier derivation constraints.

Pool IDs, token addresses, chain IDs and denominations are not additional public inputs in the
current five-signal ABI. A consumer requiring cryptographic domain separation must design it into
the commitment/circuit/key and demonstrate compatibility with the configured tree and deployment. Do
not silently append signals or reinterpret one of the five inputs.

## Verifying-key and setup boundary

A pool verifier must pin one audited circuit’s verifying key.
[PinnedWithdrawVerifier](../../src/examples/privacy/PinnedWithdrawVerifier.sol) shows a compiled-in
key; [HashPinnedGroth16Verifier](../../src/examples/privacy/HashPinnedGroth16Verifier.sol) shows
checking a fixed hash of a supplied key. Tests must accept the intended key and reject a valid proof
under another key. A replaceable verifier or writable key adds an administrator trust assumption and
is not equivalent to an immutable circuit commitment.

Record the circuit and dependency source revisions, compiler and optimization flags, constraint
system hash, proving/verification key hashes, ceremony provenance and verifier artifact/runtime
hash. Audit evidence must apply to those exact artifacts. Generic pairing verification does not
validate circuit semantics or the integrity of a trusted setup.

## Required evidence before consumer deployment

- Differential membership vectors match Lattice’s Poseidon LeanIMT for empty boundaries, first leaf, odd sizes, every supported depth and maximum depth.
- Negative witnesses cover wrong secrets, missing leaves, invalid depth/index/path bits and malformed/padded paths.
- Public-input substitution and wrong-key regressions pass against the exact optimized production artifacts.
- Integration covers duplicate spending, unknown/expired roots, fee bounds and failed or reentrant token transfers with atomic rollback.
- The deployed verifier, circuit/key fingerprints, supported tree limits and token assumptions are reviewed together. Use fixed-denomination assets whose transfer behavior preserves the pool’s accounting assumptions.

## Scope decisions

ShieldedPool retains the consumer-supplied audited-circuit model. This reference specification is
option (a), the selected follow-up to [#238](https://github.com/dadadave80/lattice/issues/238); the
repository’s test circuit is not adopted for production.

An integration with [0xbow Privacy
Pools](https://github.com/0xbow-io/privacy-pools-core/tree/c312dcd58f6ad085204be61923c49f8065e4e9ae)
is outside the current scope. Its cited
[withdrawal circuit](https://github.com/0xbow-io/privacy-pools-core/blob/c312dcd58f6ad085204be61923c49f8065e4e9ae/packages/circuits/circuits/withdraw.circom)
uses ASP/state/depth/context inputs, with eight public signals in its
[verification key](https://github.com/0xbow-io/privacy-pools-core/blob/c312dcd58f6ad085204be61923c49f8065e4e9ae/packages/circuits/trusted-setup/final-keys/withdraw.vkey).
It is not a drop-in verifier for ShieldedPool’s five-signal ABI. It would require a separately designed module, license and dependency/provenance review, and
authorization for any new dependency.

At that cited revision, the
[repository](https://github.com/0xbow-io/privacy-pools-core/blob/c312dcd58f6ad085204be61923c49f8065e4e9ae/LICENSE)
and [contracts
package](https://github.com/0xbow-io/privacy-pools-core/blob/c312dcd58f6ad085204be61923c49f8065e4e9ae/packages/contracts/LICENSE)
use Apache-2.0. The generated
[withdrawal](https://github.com/0xbow-io/privacy-pools-core/blob/c312dcd58f6ad085204be61923c49f8065e4e9ae/packages/contracts/src/contracts/verifiers/WithdrawalVerifier.sol)
and
[commitment](https://github.com/0xbow-io/privacy-pools-core/blob/c312dcd58f6ad085204be61923c49f8065e4e9ae/packages/contracts/src/contracts/verifiers/CommitmentVerifier.sol)
verifiers declare GPL-3.0. The [circuits
package](https://github.com/0xbow-io/privacy-pools-core/blob/c312dcd58f6ad085204be61923c49f8065e4e9ae/packages/circuits/package.json)
pins circomlib 2.0.5, whose [pinned
package](https://github.com/iden3/circomlib/blob/cff5ab6288b55ef23602221694a6a38a0239dcc0/package.json)
declares GPL-3.0. No GPL-licensed generated verifier, upstream circuit implementation or new dependency is
included here.

PrivateVoting remains anonymous one-person-one-vote. Token-weighted private voting is deferred and
requires a separate circuit and proposal; no MACI or new proving dependency is introduced.

References: [#238](https://github.com/dadadave80/lattice/issues/238), [ADR
0010](../adr/0010-groth16-bn254.md),
[IShieldedPool.sol](../../src/interfaces/privacy/IShieldedPool.sol),
[ShieldedPoolLib.sol](../../src/privacy/libraries/ShieldedPoolLib.sol),
[PinnedWithdrawVerifier.sol](../../src/examples/privacy/PinnedWithdrawVerifier.sol) and
[HashPinnedGroth16Verifier.sol](../../src/examples/privacy/HashPinnedGroth16Verifier.sol).
