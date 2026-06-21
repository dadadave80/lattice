import { Identity } from "@semaphore-protocol/identity"
import { Group } from "@semaphore-protocol/group"
import { generateProof } from "@semaphore-protocol/proof"
const members = [new Identity("alice-seed"), new Identity("bob-seed"), new Identity("carol-seed")]
const commitments = members.map(m => m.commitment)
const group = new Group(commitments)
const pollId = 1n, choice = 1n // scope = pollId, message = vote choice
async function mk(idx){ const p = await generateProof(members[idx], group, choice, pollId); return {
  nullifier: p.nullifier.toString(), message: p.message.toString(), scope: p.scope.toString(),
  merkleTreeDepth: p.merkleTreeDepth.toString(), merkleTreeRoot: p.merkleTreeRoot.toString(),
  points: p.points.map(x=>x.toString()) }; }
const alice = await mk(0)
const bobAgainst = await (async()=>{ const p = await generateProof(members[1], group, 0n, pollId); return {
  nullifier:p.nullifier.toString(), message:p.message.toString(), scope:p.scope.toString(),
  merkleTreeDepth:p.merkleTreeDepth.toString(), merkleTreeRoot:p.merkleTreeRoot.toString(), points:p.points.map(x=>x.toString())}; })()
console.log(JSON.stringify({ groupRoot: group.root.toString(), commitments: commitments.map(c=>c.toString()), pollId: pollId.toString(), aliceFor: alice, bobAgainst }, null, 1))
