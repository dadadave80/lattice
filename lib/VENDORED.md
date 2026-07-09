# Vendored third-party dependencies

These directories hold **verbatim, audited** Solidity sources vendored into the
repo (byte-identical to upstream — no edits) because their canonical git remotes
are intermittently unreachable for submodule installation. Each is forge-
installable normally; vendoring is the fallback and keeps builds reproducible.
Swap for real submodules when convenient — the remappings already match the
upstream import paths, so no source change is needed.

| Path | Upstream | Version / commit | License |
|------|----------|------------------|---------|
| `poseidon-solidity/PoseidonT3.sol` | npm `poseidon-solidity` (chancehudson) | 0.0.5 | MIT |
| `zk-kit/lean-imt/` | github.com/privacy-scaling-explorations/zk-kit.solidity `packages/lean-imt/contracts` | a171c845ec7fdc50cdd1fe96c14c27d707cdfbed | MIT |
| `semaphore/` | github.com/semaphore-protocol/semaphore `packages/contracts/contracts` (SemaphoreVerifier + KeyPts + Constants + ISemaphoreVerifier) | 341475c66bee7473f8d25f44bc0dcf6b255b5a6c | MIT |

PoseidonT3 is the gas-optimized BN254 Poseidon used by every SNARK-friendly
incremental Merkle tree in the ecosystem; LeanIMT is the PSE-audited (Semaphore
v4 audit, PSE, Mar 2024) dynamic-depth incremental Merkle tree. Both are
required because Lattice's ZK circuits hash with Poseidon — a keccak tree would
not verify against them.

Pipeline note: `PoseidonT3.sol` is hand-tuned assembly optimized for solc's
**legacy** (non-`via_ir`) pipeline, where it deploys at ~23.5 KB — under the
EIP-170 24,576 B limit. Under `--via-ir` the IR optimizer restructures that
assembly and the contract balloons to ~29–55 KB, exceeding EIP-170 regardless of
`optimizer_runs`. Lattice's CI/deploy profile sets `via_ir = false`, so PoseidonT3
(and any Poseidon-based ZK module that links it) is deployed via the legacy
pipeline. The CI `via_ir` step still enforces EIP-170/EIP-3860 on every Lattice
contract but exempts PoseidonT3 specifically (the legacy `--sizes` build remains
its authoritative gate). Consumers compiling Lattice's ZK privacy modules should
likewise deploy PoseidonT3 with the legacy pipeline.

Note: upstream's `zk-kit/lean-imt/Constants.sol` ships an `UNLICENSED` SPDX tag
even though the zk-kit.solidity repository is MIT-licensed (Ethereum Foundation
2025, repo-root `LICENSE`). The file is vendored verbatim, so that per-file tag is
preserved as-is — faithful to upstream, not an injected edit. It holds only the
public BN254 scalar-field constant; Lattice's own libraries define
`SNARK_SCALAR_FIELD` first-party (MIT) rather than importing that file.

## Account passkey crypto (`src/utils/libraries/`)

The smart-account signer (`src/accounts/SignerECDSA`) verifies P256 (secp256r1) and
WebAuthn signatures using audited Solady crypto. Unlike the byte-identical `lib/`
vendors above, these are vendored into `src/utils/libraries/` with **minimal
mechanical edits** — see each file's header for the exact delta:

| Path | Upstream | Version / commit | License |
|------|----------|------------------|---------|
| `src/utils/libraries/P256.sol` | Vectorized/solady `src/utils/P256.sol` | ab96a830e705de13e0f58cfaefadab4ac8257655 | MIT |
| `src/utils/libraries/Base64.sol` | Vectorized/solady `src/utils/Base64.sol` | ab96a830e705de13e0f58cfaefadab4ac8257655 | MIT |
| `src/utils/libraries/WebAuthn.sol` | Vectorized/solady `src/utils/WebAuthn.sol` | ab96a830e705de13e0f58cfaefadab4ac8257655 | MIT |

Edits are limited to: pragma pinned to `^0.8.30`; and in `WebAuthn.sol`, the two
import paths rewritten to `@lattice/utils/libraries/{Base64,P256}.sol`. No logic or
assembly is changed. They are excluded from `forge fmt` (`[fmt] ignore` in
`foundry.toml`) so they stay diffable against upstream — re-sync from the pinned
commit rather than patching here. P256 verification uses the RIP-7212 precompile
(`0x100`) with a deployed-verifier fallback (`0x…D01eA45F9eFD5c54f037Fa57Ea1a`); on
a chain lacking both, passkey verification returns `false`, so gate passkey
enablement per target chain.
