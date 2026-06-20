pragma circom 2.0.0;

// Minimal circuit to produce a real Groth16 test vector for Lattice's generic
// verifier: c = a * b, with `a` and the output `c` public (nPublic = 2), `b` private.
template Multiplier() {
    signal input a;
    signal input b;
    signal output c;
    c <== a * b;
}

component main {public [a]} = Multiplier();
