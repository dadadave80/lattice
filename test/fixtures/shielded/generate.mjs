import { poseidon1, poseidon2 } from "poseidon-lite"
import { LeanIMT } from "@zk-kit/lean-imt"

const MAX_DEPTH = 10
// 3 depositors; we withdraw member 0.
const members = [ {n:111n,s:222n}, {n:333n,s:444n}, {n:555n,s:666n} ]
const commitments = members.map(m => poseidon2([m.n, m.s]))

const tree = new LeanIMT((a, b) => poseidon2([a, b]))
tree.insertMany(commitments)

const idx = 0
const proof = tree.generateProof(idx)        // { root, leaf, index, siblings }
const siblings = proof.siblings.map(s => s.toString())
while (siblings.length < MAX_DEPTH) siblings.push("0")

const recipient = 0xbeefn, relayer = 0xc0fen, fee = 5n
const nullifierHash = poseidon1([members[idx].n])

const input = {
  root: proof.root.toString(),
  nullifierHash: nullifierHash.toString(),
  recipient: recipient.toString(),
  relayer: relayer.toString(),
  fee: fee.toString(),
  nullifier: members[idx].n.toString(),
  secret: members[idx].s.toString(),
  depth: proof.siblings.length.toString(),
  index: proof.index.toString(),
  siblings,
}
import fs from "fs"
fs.writeFileSync("withdraw_input.json", JSON.stringify(input, null, 1))
fs.writeFileSync("withdraw_fixture.json", JSON.stringify({
  commitments: commitments.map(c => c.toString()),
  root: proof.root.toString(),
  nullifierHash: nullifierHash.toString(),
  recipient: "0x000000000000000000000000000000000000beef",
  relayer: "0x000000000000000000000000000000000000c0fe",
  fee: fee.toString(),
}, null, 1))
console.log("root:", proof.root.toString())
console.log("depth:", proof.siblings.length, "siblings(non-pad):", proof.siblings.length)
console.log("commitments:", commitments.map(c=>c.toString()))
