# Semaphore test vector

A real Semaphore v4 proof used by `test/unit/SemaphoreTest.t.sol` to validate the `Semaphore` facet
end-to-end against the vendored audited verifier (`lib/semaphore/SemaphoreVerifier.sol`).

- `proof.json` — a group of 3 member identity commitments, a membership + signaling proof by member 0
  (message `42`, scope `7`), at the group's natural depth (2). `groupRoot == merkleTreeRoot`, so inserting
  the 3 commitments in order into `IncrementalMerkleTreeLib` reproduces the exact on-chain root
  (`5504274371000021352836406185992230687759203853005470845011606913465462220001`).
- `generate.mjs` — the generation script.

The Solidity test hard-codes these values. The proof passes `@semaphore-protocol/proof` verification
off-chain, and the test confirms the facet + vendored verifier accept it on-chain (and reject replays,
wrong roots, and unsupported depths).

## Regenerate

Requires Node + network (downloads the Semaphore circuit artifacts on first run):

```bash
npm install @semaphore-protocol/identity @semaphore-protocol/group @semaphore-protocol/proof
node generate.mjs
```

A fresh run produces a different identity/proof (the seeds are fixed here, but artifacts may update);
update the fixture and the test's hard-coded values if you regenerate.
