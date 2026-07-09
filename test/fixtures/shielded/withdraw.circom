pragma circom 2.1.5;

include "poseidon.circom";
include "binary-merkle-root.circom";

// Tornado-style shielded withdrawal (TEST FIXTURE ONLY — not audited, not for production).
// Proves knowledge of (nullifier, secret) whose commitment Poseidon(nullifier, secret) is a leaf of
// the Poseidon LeanIMT with the public `root`, and reveals nullifierHash = Poseidon(nullifier).
// recipient/relayer/fee are public and bound (anti-malleability) so a relayer cannot alter them.
template Withdraw(MAX_DEPTH) {
    signal input root;          // public
    signal input nullifierHash; // public
    signal input recipient;     // public
    signal input relayer;       // public
    signal input fee;           // public
    signal input nullifier;     // private
    signal input secret;        // private
    signal input depth;         // private
    signal input index;         // private
    signal input siblings[MAX_DEPTH]; // private

    signal commitment <== Poseidon(2)([nullifier, secret]);

    signal computedRoot <== BinaryMerkleRoot(MAX_DEPTH)(commitment, depth, index, siblings);
    computedRoot === root;

    signal nh <== Poseidon(1)([nullifier]);
    nh === nullifierHash;

    // Bind public signals into the proof (prevent malleability of recipient/relayer/fee).
    signal recipientSq <== recipient * recipient;
    signal relayerSq <== relayer * relayer;
    signal feeSq <== fee * fee;
}

component main {public [root, nullifierHash, recipient, relayer, fee]} = Withdraw(10);
