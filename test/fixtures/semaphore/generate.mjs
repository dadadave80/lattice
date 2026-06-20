import { Identity } from "@semaphore-protocol/identity"
import { Group } from "@semaphore-protocol/group"
import { generateProof } from "@semaphore-protocol/proof"

const members = [new Identity("alice-seed"), new Identity("bob-seed"), new Identity("carol-seed")]
const commitments = members.map(m => m.commitment)
const group = new Group(commitments)
const message = 42n
const scope = 7n
// no explicit depth -> Semaphore uses the group's natural LeanIMT depth
const proof = await generateProof(members[0], group, message, scope)
console.log(JSON.stringify({
  groupDepth: group.depth.toString(),
  groupRoot: group.root.toString(),
  commitments: commitments.map(c => c.toString()),
  merkleTreeDepth: proof.merkleTreeDepth.toString(),
  merkleTreeRoot: proof.merkleTreeRoot.toString(),
  nullifier: proof.nullifier.toString(),
  message: proof.message.toString(),
  scope: proof.scope.toString(),
  points: proof.points.map(p => p.toString()),
}, null, 1))
