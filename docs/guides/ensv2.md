# Using ENSv2 with a Lattice diamond

To give a diamond a primary name, set its forward record on the name's resolver and set its reverse name through the existing reverse registrar. The two v2 facets below are optional. Install them when the diamond itself needs to resolve names or issue subnames. Ethereum and Sepolia have distinct registries. Check the chain ID, published implementation and root before trusting an endpoint. [ENS deployments](https://docs.ens.domains/learn/deployments/)

## Resolve a name

Install `ENSResolverV2` with the chain's Universal Resolver **proxy**. Call `resolveEnsAddressV2(bytes)` with the normalized DNS wire name, including its zero terminator. For example, `alice.eth` encodes as `0x05616c6963650365746800`. The facet obtains the namehash from discovery and requests the ETH address record through the proxy. A zero ETH address differs from a resolver failure. When a lookup requires a gateway, a CCIP-Read capable client should call the proxy's `resolve(bytes,bytes)` directly. The legacy `ENSResolver.resolve(bytes32)` remains available for v1 direct-registry consumers. [Universal Resolver](https://docs.ens.domains/ensv2/universal-resolver-v2/)

## Issue a subname

Install `ENSSubnameIssuerV2` with the chain's UniversalHelper. The diamond administrator grants the operator `ENS_V2_SUBNAME_ISSUER_ROLE`. Separately, the parent registry administrator grants the diamond `ROLE_REGISTRAR` on the root resource of that parent's registry. Keep promotion of reserved names with the migration controller by withholding `ROLE_REGISTER_RESERVED` from the diamond. Configure the child's owner rights, expiry timestamp, resolver and optional subregistry explicitly. The facet takes a DNS-encoded parent and a single normalized child label. Its returned token ID belongs to the registry that issued it. Write the ETH record as an authorized manager of the selected resolver. Check for shared record bundles before changing a value on an existing resolver. [ENS subname issuance](https://docs.ens.domains/ensv2/subnames/)

For a new diamond, the v2 recipes compose the released AccessControl initialization with the module's own step. When adding a facet to an existing diamond, use its authorized cut and a strictly increasing reinitializer version with only the new module's step. Obtain the actual version and preflight selector ownership and frozen selectors. The endpoint manager can change who supplies names or registries. [Upgrading a diamond](upgrade-a-diamond.md)

## Register a fresh Sepolia .eth

Use an encrypted keystore and an owner-controlled resolver. Read the registrar's availability, minimum duration, commitment ages and payment-token quote. Use a dedicated payer or explicitly reconcile its existing allowance. For the secret use a new private random 32-byte value; retain it until reveal. Compute the commitment **locally** as keccak256 of the ABI encoding of `(string label,address owner,bytes32 secret,address subregistry,address resolver,uint64 duration,bytes32 referrer)`. The first transaction contains only this hash.

Run the following commands first as simulations. Broadcasting spends test tokens and requires the name operator's approval. Set `ENS_REGISTRATION_SECRET` through protected input for the reveal. Use the same registration fields for the commitment and reveal.

```sh
forge script script/config/RegisterEnsName.s.sol:RegisterEnsName --rpc-url sepolia \
  --account "$KEYSTORE" --sender "$PAYER" --sig 'commit(bytes32)' "$COMMITMENT"

forge script script/config/RegisterEnsName.s.sol:RegisterEnsName --rpc-url sepolia \
  --account "$KEYSTORE" --sender "$PAYER" --slow \
  --sig 'reveal((string,address,address,address,uint64,bytes32),address,uint256)' \
  "($LABEL,$OWNER,$SUBREGISTRY,$RESOLVER,$DURATION,$REFERRER)" "$PAYMENT_TOKEN" "$MAX_SPEND"
```

After the commit receipt, wait for the on-chain minimum age and reveal before the maximum. The registrar charges an ERC-20. Specify the spending cap in that token's base units. If approval is mined but registration fails, inspect the live commitment, quote, name owner and remaining allowance before re-running. Revoke an unused allowance. For a completed registration verify the owner and pointers, then set the ETH record using `setAddress(dnsName,60,abi.encodePacked(target))` on the authorized PermissionedResolver. A primary-name check calls `reverse(abi.encodePacked(target),60)` on the canonical proxy and compares the complete name. [ETH registrar](https://docs.ens.domains/ensv2/eth-registrar/)

## Rehearse the Sepolia studio.eth migration

```sh
forge test --match-contract ENSV2StudioMigrationFork -vv
```

Set `SEPOLIA_RPC_URL` to an archive endpoint. The fixture defaults to block 12,208,978. To recheck a later state, set `ENSV2_REHEARSAL_BLOCK` to a specific block number. Forge impersonates the observed registrant on its local fork. It deploys UserRegistry and PermissionedResolver proxies, stages the replacement hierarchy and the three historical ETH records, verifies a malformed transfer rolls back, and exercises the actual unlocked migration controller. It checks the vault, factory and registry against their original addresses and exact primary names both before and after the transfer.

The fixture covers the three published Lattice records. A live transfer of the second-level token affects **all of studio.eth** and sends the old token to the Graveyard. Before presenting a transfer for approval, inventory siblings, owners, expiries, resolvers, wildcard services, text and multichain records, approvals and recovery rights with the registrant. Stage every approved record, rehearse from a fresh block, confirm the signer for each step, and produce a decoded transaction list and before/after record comparison. A post-transfer repair uses the retained v2 resolver and registry permissions. Historical receipts in PROGRESS.md document the original deployments. [Migration rules](https://docs.ens.domains/ensv2/migration/)
