# Groth16 test vector

A real, self-contained Groth16 proof used by `test/unit/Groth16VerifierTest.t.sol` to validate the
generic `Groth16Verifier` against ground truth. The circuit is the minimal `c = a * b` with `a` and the
output `c` public, `b` private (`nPublic = 2`).

## Files

- `mult.circom` — the circuit.
- `input.json` — witness inputs `{a: 3, b: 11}`.
- `vkey.json` — the snarkjs verifying key (BN254 / groth16).
- `proof.json` — the proof.
- `public.json` — the public signals `[c, a] = [33, 3]`.

The Solidity test hard-codes these values. For the `VerifyingKey`, each **G2** coordinate pair is swapped
to precompile order `(c1, c0)` — e.g. `beta.x = [vk_beta_2[0][1], vk_beta_2[0][0]]`. The proof `b` from
`snarkjs zkey export soliditycalldata` is already in `(c1, c0)` order.

## Regenerate

Requires `circom` (2.x) and `npx`. From a scratch dir:

```bash
snarkjs powersoftau new bn128 8 pot_00.ptau
snarkjs powersoftau contribute pot_00.ptau pot_01.ptau --name=c1 -e="lattice-entropy-1"
snarkjs powersoftau prepare phase2 pot_01.ptau pot_final.ptau
circom mult.circom --r1cs --wasm -o .
snarkjs groth16 setup mult.r1cs pot_final.ptau mult_0.zkey
snarkjs zkey contribute mult_0.zkey mult_final.zkey --name=c1 -e="lattice-entropy-2"
snarkjs zkey export verificationkey mult_final.zkey vkey.json
node mult_js/generate_witness.js mult_js/mult.wasm input.json witness.wtns
snarkjs groth16 prove mult_final.zkey witness.wtns proof.json public.json
snarkjs groth16 verify vkey.json public.json proof.json   # -> OK!
snarkjs zkey export soliditycalldata public.json proof.json
```

A fresh trusted setup yields different proof/key values (both verify equally); update the test fixture
if you regenerate. The point of the test is that the on-chain generic verifier agrees with
`snarkjs groth16 verify`.
