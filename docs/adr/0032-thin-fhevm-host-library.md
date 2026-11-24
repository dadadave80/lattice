# 0032. Confidential modules call Zama hosts through a thin Lattice library

- **Status:** Accepted
- **Date:** 2026-11-22

## Context

Confidential modules need fully homomorphic encryption operations from Zama's FHEVM (fully
homomorphic encryption virtual machine) host contracts: arithmetic, comparison and access control list
(ACL) grants on encrypted values. Zama's own `FHE.sol` library wraps those calls. Its import closure is
9,818 to 11,068 lines of Solidity; the part Lattice needs is about 300.

[ADR (architecture decision record) 0011](0011-no-stateless-utility-duplicates.md) forbids new copies of
stateless libraries that a consumer can install from Solady or OpenZeppelin. `FHE.sol` is such a
library, so a Lattice-authored replacement departs from that rule, and this record scopes the departure.
Importing Zama's library would put a large foreign tree into every production contract.

## Decision

Production code uses `src/privacy/libraries/FHEVMLib.sol`, a Lattice-authored library over three
vendored minimal interfaces (`IACL`, `IFHEVMExecutor`, `IKMSVerifier` in
`src/interfaces/external/fhevm/`). The only production dependency is the vendored `encrypted-types`
0.0.4 type definitions, which sit beside them under `src/` so that production code never imports from
`lib/`.

**Glue generation.** Zama's library has had three generations of the glue between the library and the
hosts. `FHEVMLib` reproduces the middle one, published as `@fhevm/solidity` 0.13.4, whose `FHE.sol` is
identical to the code of the host line deployed on Ethereum mainnet and used by the test harness. The
earlier generation lacks `checkHandleType`, the check that rejects a handle of the wrong encrypted
type, so a wrong-typed handle was accepted; that was publicly disclosed. The later generation only
drops the library's temporary grant to the caller after an input proof verifies, which gains no
confidentiality. A compile-time switch between generations would mean two bytecodes and a silent
flip, so the choice is fixed. Moving to the later generation is a separate reviewed change.

**Chain table.** `hostsFor(chainId)` is a constant table with three rows: Ethereum mainnet (1), Sepolia
(11155111) and chain id 31337. Any other chain reverts `FHEVMUnsupportedChain(uint256)`. The 31337 row
exists for local tests only. Its addresses are CREATE (contract-creation opcode) addresses derived from
the deployer key in Zama's published example deployment, so anyone with that key can place code at them
on any network that reuses chain id 31337. The ERC-7984 deployment recipes planned for a later pull
request will omit 31337 from their supported chains, and `SECURITY.md` states the limit now.

**Foreign storage namespace.** The library stores the host addresses in Zama's own coprocessor
configuration slot, the ERC-7201 (namespaced storage) location of `confidential.storage.config`, with
the upstream struct layout, so a diamond that also uses Zama's library reads the same configuration.
Lattice does not rename it. Setting the configuration follows the repeat semantics of
[ADR 0016](0016-shared-initialization-identity.md): an empty slot is written, an identical value is a
no-op, and a conflicting value reverts.

**Test-only vendoring.** The test harness (Zama's forge-fhevm rebuilt on host line v0.13.9) and the
`FHE.sol` 0.13.4 oracle live in `test/helpers/fhevm/`, beside their tests, not in `lib/`. `lib/` holds
only copies that are byte-identical to upstream (`lib/VENDORED.md` says so), and the harness is edited,
so it belongs beside its users, as the edited Solady files in `src/utils/libraries/` do. No remapping
is added and no compiled artifact changes.

**Differential gate.** `FHEVMLibDifferentialFuzz` runs every member of `FHEVMLib` against
`FHE.sol` 0.13.4 for every operand class (uninitialized, well-typed and allowed, wrong-typed, and
others the test documents) and requires identical results and reverts, and it fuzzes arbitrary
handles. A change that makes the library diverge from the oracle fails the gate.

**Ported helpers.** `FHEVMLib` includes `tryIncrease` and `tryDecrease`, ported from OpenZeppelin
Confidential Contracts 0.5.3 `FHESafeMath`. That package imports `FHE.sol`, so installing it would pull
in the closure this decision avoids.

**Patent position.** Zama's code is licensed BSD-3-Clause-Clear, which grants no patent rights, and
Zama's README states that commercial use of its technology needs Zama's patent licence. The maintainer
decided to proceed and to document the position in the README and `SECURITY.md`, and later in the
module guide. It is not a release blocker.

## Alternatives and consequences

An `@fhevm/solidity` git submodule under `lib/` is rejected: Foundry derives a remapping for each
directory under `lib/`, solc records remappings in every contract's metadata, and so one new directory
rotates every artifact's codehash, every deterministic release address and the ERC-3643 (permissioned
token standard) profile (the repository's record of that standard's identity). A vendored `FHE.sol` copy
under `src/` is rejected because it adds the roughly 10,000-line closure to production and would be
edited.

Consequences:

- Lattice's `euint64` is a distinct Solidity type from Zama's, because `encrypted-types` is vendored
  under `src/`. A consumer that also imports Zama's types remaps
  `encrypted-types/=lib/lattice/src/interfaces/external/fhevm/`.
- Nothing from the harness is visible to projects that install Lattice.
- A future directory under Lattice's `lib/` would rotate every codehash; the pull request gates compare
  `remappings.txt`, `foundry.lock`, `snapshots/` and the ERC-3643 profile against `origin/dev`.
- Moving to the later glue generation changes the library's bytecode and so rotates every facet that
  embeds it.
- Production code now trusts the Zama hosts, the key management service (KMS), the coprocessors and the
  upgrade authority described in [`SECURITY.md`](../../SECURITY.md).

## Confirmation

`FHEVMLibConfigTest` checks the chain table (including that the 31337 row is the example deployer's
CREATE addresses), the unsupported-chain revert, the configuration write semantics and the slot and
layout against upstream. `FHEVMLibDifferentialFuzz` checks every member against the `FHE.sol` oracle.
`FhevmHarnessTest` checks that the harness runs host line v0.13.9 and that the upstream library works
against it.

## References

- [ADR 0011](0011-no-stateless-utility-duplicates.md)
- [ADR 0016](0016-shared-initialization-identity.md)
- [`lib/VENDORED.md`](../../lib/VENDORED.md)
- [`SECURITY.md`](../../SECURITY.md)
