# PLONK test vector

A real PLONK proof used by `test/unit/PlonkVerifierTester.t.sol` to validate the generic
`PlonkVerifier` against ground truth. Same circuit as the Groth16 fixture — `c = a * b` with `a`/`c`
public, `b` private (`nPublic = 2`) — proven with `snarkjs plonk` (universal setup, no per-circuit
ceremony). Public signals are `[c, a] = [33, 3]`.

## Files
- `vkey.json` — PLONK verifying key (BN254). G1 points are projective `[x, y, z]`; `z="0"` is the point
  at infinity → `(0, 0)` affine (e.g. `Qr`, `Qc`).
- `proof.json` — the proof (named fields A,B,C,Z,T1,T2,T3,Wxi,Wxiw + eval_*).
- `public.json` — `[33, 3]`.

The Solidity test hard-codes these. Each **G2** pair in `X_2` is swapped to precompile order `(c1, c0)`.

## Regenerate
Requires `circom` 2.x + `npx`. With `pot_final.ptau` and `mult.r1cs`/`mult_js` from the groth16 fixture:
```bash
snarkjs plonk setup mult.r1cs pot_final.ptau mult_plonk.zkey
snarkjs zkey export verificationkey mult_plonk.zkey vkey.json
snarkjs plonk prove mult_plonk.zkey witness.wtns proof.json public.json
snarkjs plonk verify vkey.json public.json proof.json    # -> OK!
```
