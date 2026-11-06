# Integrate a Lattice release

A release has shared code, a curated registry and a factory. Your diamond has its own storage and
initialization plan. Start with the release's frozen manifest and compiler inputs, then check the
separate observation for your target chain. A code address or RPC alias alone is not release evidence.

Canonical builds use Foundry **1.9.0**, Solidity **0.8.36**, **Cancun**, the legacy pipeline,
1,000,000 optimizer runs and IPFS/CBOR metadata. Changing source, metadata, compiler settings or
constructor arguments can change addresses. Live module namespaces and interface IDs remain frozen;
read the [versioning policy](../../README.md#versioning-and-compatibility) before upgrading state.

## Run a private example

The commands below run, in order, in one Bash shell from a clean Lattice checkout with its pinned
submodules initialized. They require the shared Foundry tools, Git and jq. They create a **partial
local catalog**, using version `99.0.0` and an unlocked Anvil test owner. They are neither a published
release nor a canonical-owner decision. No canonical initial owner or public schema-v1 golden has
been confirmed in this repository.

Use an unused port. The example owns its node and stops it when the shell exits:

```bash
set -euo pipefail
export FOUNDRY_PROFILE=ci
RPC_URL=http://127.0.0.1:18557
ACCOUNT=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
GUIDE_TMP=$(mktemp -d)
if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
  echo 'Port 18557 already has an RPC node; choose another unused port.' >&2
  exit 1
fi
anvil --host 127.0.0.1 --port 18557 --hardfork cancun > "$GUIDE_TMP/anvil.log" 2>&1 &
ANVIL_PID=$!
trap 'kill "$ANVIL_PID" 2>/dev/null || true; wait "$ANVIL_PID" 2>/dev/null || true; rm -rf "$GUIDE_TMP"' EXIT
for _ in {1..50}; do
  kill -0 "$ANVIL_PID"
  if cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
test "$(cast chain-id --rpc-url "$RPC_URL")" = 31337
git submodule update --init --recursive
```

Generate the identities offline. Constructors execute in Forge's local EVM; this command does not
deploy to the RPC node. Keep the exact standard-JSON compiler-input package with the manifest:

```bash
VERSION=99.0.0
MANIFEST=deployments/fixtures/integrator-manifest.json
make release-manifest VERSION="$VERSION" TAG=fixture/integrator OWNER="$ACCOUNT" PUBLICATION=fixture DESTINATION="$MANIFEST"
cp out/release-build-inputs.json "$GUIDE_TMP/build-inputs.json"
jq '{publication,lattice,compiler,proxy,accountPairs:(.accounts|length)}' "$MANIFEST"
```

A real release uses `deployments/release-<version>.json` with `publication: release`. Its source commit
must already be retained by `origin/dev` or `origin/main`, and its owner must be confirmed independently.
Release preparation first imports Release Please's generated version into reviewed source, refreshes
the build-bound ERC-3643 profile, freezes that merged source, then adds manifest-only evidence.
The eventual tag must preserve those inputs. See
[the complete source-freeze sequence](../../REGISTRY_DEPLOYMENTS.md#release-source-preparation).
Do not change `LatticeVersion` or accept new profile hashes merely to make a check pass.

## Predict and deploy shared code

Shared contracts use the Arachnid proxy at `0x4e59b44847b379578588920cA78FbF26c0B4956C`.
Their address is the last 20 bytes of
`keccak256(0xff ++ deployer ++ salt ++ keccak256(creationCode ++ constructorArgs))`.
The salt is raw: the proxy adds no broadcaster or chain-ID prefix.

The following local-only RPC operation installs the repository's test proxy runtime. Public chains
require the actual canonical proxy; `anvil_setCode` is not a deployment procedure for them.

```bash
ARACHNID=0x4e59b44847b379578588920cA78FbF26c0B4956C
PROXY_RUNTIME=$(sed -n 's/.*hex"\([[:xdigit:]]*\)";.*/0x\1/p' test/helpers/ArachnidProxy.sol)
cast rpc --rpc-url "$RPC_URL" anvil_setCode "$ARACHNID" "$PROXY_RUNTIME" >/dev/null

address_of() {
  jq -er --arg name "$1" '.contracts[] | select(.name==$name) | .address' "$MANIFEST"
}
deploy_shared() {
  local record artifact source contract code args salt init_hash digest at expected
  record=$(jq -cer --arg name "$1" '.contracts[] | select(.name==$name)' "$MANIFEST")
  artifact=$(jq -r .artifact <<< "$record")
  source=${artifact%:*}
  contract=${artifact##*:}
  code=$(jq -r '.bytecode.object' "out/${source##*/}/$contract.json")
  args=$(jq -r .constructorArgs <<< "$record")
  salt=$(jq -r .salt <<< "$record")
  init_hash=$(cast keccak "$code${args#0x}")
  test "$init_hash" = "$(jq -r .initCodeHash <<< "$record")"
  digest=$(cast keccak "0xff${ARACHNID#0x}${salt#0x}${init_hash#0x}")
  at="0x${digest:26}"
  expected=$(jq -r '.address|ascii_downcase' <<< "$record")
  test "$at" = "$expected"
  if [ "$(cast code "$at" --rpc-url "$RPC_URL")" = 0x ]; then
    cast send "$ARACHNID" --data "$salt${code#0x}${args#0x}" --from "$ACCOUNT" --unlocked --rpc-url "$RPC_URL" >/dev/null
  fi
  test "$(cast code "$at" --rpc-url "$RPC_URL" | cast keccak)" = "$(jq -r .codehash <<< "$record")"
}
for name in LatticeRegistry LatticeFactory DiamondLoupeFacet ERC165Facet AccessControl AccessControlDiamondCut ERC20 ERC20Burnable MultiInit AccessControlInit ERC20Init DiamondIntrospectionInit ERC20BurnableInit ReinitMultiInit; do
  deploy_shared "$name"
done
REGISTRY=$(address_of LatticeRegistry)
FACTORY=$(address_of LatticeFactory)
```

The helper verifies full initcode and resulting runtime hashes. Constructor arguments matter:
the registry owner changes its address, and the factory binds its registry and proxy build.
The proxy returns a raw 20-byte address; deriving the prediction and checking code avoids treating
that return as a 32-byte ABI value. Versioned facet/init salts use
`keccak256("lattice.<identity-name>.<version>")`; core singleton salts are versionless.
The manifest records the exact salt and arguments for every identity, including linked libraries.

## Read the registry

Tier B is the owner-curated, append-only catalog. For this local example, curate the facets we use:

```bash
PACKED_VERSION=$((99 << 48))
for name in DiamondLoupeFacet ERC165Facet AccessControl AccessControlDiamondCut ERC20 ERC20Burnable; do
  key=$(cast keccak "lattice.$name")
  cast send "$REGISTRY" 'register(bytes32,uint64,address)' "$key" "$PACKED_VERSION" "$(address_of "$name")" --from "$ACCOUNT" --unlocked --rpc-url "$RPC_URL" >/dev/null
  cast send "$REGISTRY" 'setLatest(bytes32,uint64)' "$key" "$PACKED_VERSION" --from "$ACCOUNT" --unlocked --rpc-url "$RPC_URL" >/dev/null
done
NAME_HASH=$(cast keccak lattice.ERC20)
cast call "$REGISTRY" 'get(bytes32,uint64)((address,uint64,uint48,bytes32,bytes32))' "$NAME_HASH" "$PACKED_VERSION" --rpc-url "$RPC_URL"
cast call "$REGISTRY" 'latest(bytes32)((address,uint64,uint48,bytes32,bytes32))' "$NAME_HASH" --rpc-url "$RPC_URL"
cast call "$REGISTRY" 'getCut(bytes32,uint64)((address,uint8,bytes4[]))' "$NAME_HASH" "$PACKED_VERSION" --rpc-url "$RPC_URL"
```

Versions pack as `(major << 48) | (minor << 24) | patch`, with 16/24/24-bit components.
Use a full-width unsigned integer in clients; the bounded fixture above is `99.0.0`.
Version zero in non-strict factory entries and `getMany` keys means the curator's movable `latest`
pointer, not a version pin. Direct `get`, `getCut` and `getSelectors` reads require a concrete version;
use `latest` to obtain the pointer's record.
`get` returns stored evidence; `getCut` and `getSelectors` recheck live code and selector commitments.
Their exporter reads are bounded. A reported selector surface still does not prove correct behavior.

Tier A is a permissionless, first-write-wins runtime-code index. It supplies no selectors or approval:

```bash
ERC20_INIT=$(address_of ERC20Init)
cast send "$REGISTRY" 'attest(address)' "$ERC20_INIT" --from "$ACCOUNT" --unlocked --rpc-url "$RPC_URL" >/dev/null
INIT_CODEHASH=$(cast code "$ERC20_INIT" --rpc-url "$RPC_URL" | cast keccak)
cast call "$REGISTRY" 'resolve(bytes32)(address)' "$INIT_CODEHASH" --rpc-url "$RPC_URL"
```

Pin the manifest address when version identity matters. Two factories can have equal runtime code
but different stored blueprints; a Tier-A result cannot select the canonical account factory.
Use its constructor-bound manifest address. Registry curation is a separate trust decision from
runtime code identity and public source verification.

## Deploy and initialize atomically

This example combines curated facets, then runs released init steps inside one factory-opened window.
It uses the admin-gated `AccessControlDiamondCut`, not the owner-gated or governed cut flavor.
Admin authority is an explicit init argument: inside an init, `msg.sender` is the factory.

```bash
ENTRIES='['
for name in DiamondLoupeFacet ERC165Facet AccessControl AccessControlDiamondCut ERC20; do
  if [ "$ENTRIES" != '[' ]; then ENTRIES="$ENTRIES,"; fi
  ENTRIES="$ENTRIES($(cast keccak "lattice.$name"),$PACKED_VERSION,[])"
done
ENTRIES="$ENTRIES]"
ACCESS_INIT=$(address_of AccessControlInit)
INTROSPECTION_INIT=$(address_of DiamondIntrospectionInit)
MULTI_INIT=$(address_of MultiInit)
ADMIN_DATA=$(cast calldata 'init(address)' "$ACCOUNT")
TOKEN_DATA=$(cast calldata 'init(string,string)' 'Guide Token' GUIDE)
INTROSPECTION_DATA=$(cast calldata 'initUpgradeable()')
INIT_DATA=$(cast calldata 'multiInit(address[],bytes[])' "[$ACCESS_INIT,$ERC20_INIT,$INTROSPECTION_INIT]" "[$ADMIN_DATA,$TOKEN_DATA,$INTROSPECTION_DATA]")
SALT=$(cast keccak lattice.integrator.token)
DIAMOND=$(cast call "$FACTORY" 'predict(address,bytes32)(address)' "$ACCOUNT" "$SALT" --rpc-url "$RPC_URL")
PROXY_HASH=$(cast call "$FACTORY" 'diamondInitCodeHash()(bytes32)' --rpc-url "$RPC_URL")
SENDER_SALT=$(cast abi-encode 'salt(address,bytes32)' "$ACCOUNT" "$SALT" | cast keccak)
digest=$(cast keccak "0xff${FACTORY#0x}${SENDER_SALT#0x}${PROXY_HASH#0x}")
test "$(printf '%s' "$DIAMOND" | tr '[:upper:]' '[:lower:]')" = "0x${digest:26}"
cast send "$FACTORY" 'deployStrict((bytes32,uint64,bytes4[])[],(address,uint8,bytes4[])[],address,bytes,bytes32)' "$ENTRIES" '[]' "$MULTI_INIT" "$INIT_DATA" "$SALT" --from "$ACCOUNT" --unlocked --rpc-url "$RPC_URL" >/dev/null
cast call "$DIAMOND" 'name()(string)' --rpc-url "$RPC_URL"
cast call "$DIAMOND" 'hasRole(bytes32,address)(bool)' "0x$(printf '%064d' 0)" "$ACCOUNT" --rpc-url "$RPC_URL"
cast call "$DIAMOND" 'supportsInterface(bytes4)(bool)' 0x01ffc9a7 --rpc-url "$RPC_URL"
```

The generic factory's address formula commits to **sender and salt only**, not the entries, cuts or
init data. `deploy` returns an occupied address and ignores that new recipe. `deployStrict` requires
a fresh address and pinned versions; interfaces should normally use it.

```bash
ZERO_ADDRESS=0x0000000000000000000000000000000000000000
adopted=$(cast call "$FACTORY" 'deploy((bytes32,uint64,bytes4[])[],(address,uint8,bytes4[])[],address,bytes,bytes32)(address)' "$ENTRIES" '[]' "$ZERO_ADDRESS" 0x "$SALT" --from "$ACCOUNT" --rpc-url "$RPC_URL")
test "$(printf '%s' "$adopted" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$DIAMOND" | tr '[:upper:]' '[:lower:]')"
if cast call "$FACTORY" 'deployStrict((bytes32,uint64,bytes4[])[],(address,uint8,bytes4[])[],address,bytes,bytes32)(address)' "$ENTRIES" '[]' "$ZERO_ADDRESS" 0x "$SALT" --from "$ACCOUNT" --rpc-url "$RPC_URL" > "$GUIDE_TMP/occupied.log" 2>&1; then
  echo 'Expected an occupied-address rejection.' >&2; exit 1
fi
OCCUPIED_ERROR=$(cast sig 'LatticeFactory__AlreadyDeployed(address)')
grep -q "${OCCUPIED_ERROR#0x}" "$GUIDE_TMP/occupied.log"
UNPINNED="[($NAME_HASH,0,[])]"
if cast call "$FACTORY" 'deployStrict((bytes32,uint64,bytes4[])[],(address,uint8,bytes4[])[],address,bytes,bytes32)(address)' "$UNPINNED" '[]' "$ZERO_ADDRESS" 0x "$(cast keccak lattice.integrator.unpinned)" --from "$ACCOUNT" --rpc-url "$RPC_URL" > "$GUIDE_TMP/unpinned.log" 2>&1; then
  echo 'Expected an unpinned-version rejection.' >&2; exit 1
fi
UNPINNED_ERROR=$(cast sig 'LatticeFactory__UnpinnedEntry(bytes32)')
grep -q "${UNPINNED_ERROR#0x}" "$GUIDE_TMP/unpinned.log"
```

A shared forwarder, relayer or Multicall address is one `msg.sender` salt namespace for all its users.
Call directly from the deploying account, design a separate authenticated namespace, or use strict
deployment so collisions fail instead of adopting another user's diamond. Neither salt nor a
successful deployment proves your custom cuts/init code are safe.

## Add an init step during an authorized upgrade

New module init steps also need an initialization window. The released `ReinitMultiInit` opens one
at a strictly greater uint64 version; a failed step rolls back the cut, earlier steps and version.
The existing cut authority remains in charge. Never route the helper as a facet or deploy and
initialize a proxy in separate transactions.

```bash
BURNABLE=$(address_of ERC20Burnable)
BURNABLE_INIT=$(address_of ERC20BurnableInit)
REINIT=$(address_of ReinitMultiInit)
BURN_SELECTORS=$(jq -r '.contracts[] | select(.name=="ERC20Burnable") | .selectors[2:] | "["+([scan(".{8}")|"0x"+.]|join(","))+"]"' "$MANIFEST")
CUTS="[($BURNABLE,0,$BURN_SELECTORS)]"
BURN_DATA=$(cast calldata 'init()')
REINIT_DATA=$(cast calldata 'reinitMulti(uint64,address[],bytes[])' 2 "[$BURNABLE_INIT]" "[$BURN_DATA]")
cast send "$DIAMOND" 'diamondCut((address,uint8,bytes4[])[],address,bytes)' "$CUTS" "$REINIT" "$REINIT_DATA" --from "$ACCOUNT" --unlocked --rpc-url "$RPC_URL" >/dev/null
cast send "$DIAMOND" 'burn(uint256)' 0 --from "$ACCOUNT" --unlocked --rpc-url "$RPC_URL" >/dev/null
INIT_SLOT=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132
INIT_WORD=$(cast storage "$DIAMOND" "$INIT_SLOT" --rpc-url "$RPC_URL")
test "$(cast to-dec "$INIT_WORD")" = 4
if cast call "$DIAMOND" 'diamondCut((address,uint8,bytes4[])[],address,bytes)' '[]' "$REINIT" "$REINIT_DATA" --from "$ACCOUNT" --rpc-url "$RPC_URL" > "$GUIDE_TMP/replay.log" 2>&1; then
  echo 'Expected the repeated initialization version to revert.' >&2; exit 1
fi
```

Bit 0 of the initialization word is the open-window flag; bits 1–64 hold the version.
The closed version-2 example is `4`. General tooling decodes with a full-width integer:
`version = (word >> 1) & (2^64 - 1)`. See the
[stable read definition](../../STORAGE_REGISTRY.md#initialization-version-read).
Successful empty batches and a zero-address terminator still advance the version; uint64 maximum
is terminal. Read each init's raw compiler metadata and library preconditions, preserve the original
bootstrap identity where required, and order steps deliberately. Metadata describes code facts.
Use `make recipes` to generate `out/recipes.json`, the
[descriptive recipe catalog](../../script/README.md#recipe-data-and-checked-composition)
checked against compiler ABIs. There is no automatic recipe planner.

Governed cuts have a different authority model. Use zero/self timelocks with the canonical Governor
policy, or explicitly acknowledge and separately validate an external executor design. See
[the topology guide](compose-your-own-diamond.md#governor-and-governed-cut-executors).
The [five-step upgrade walkthrough](upgrade-a-diamond.md) runs a version2 batch through an actual governed proposal.

## Account factories are a separate proxy family

Generic `LatticeFactory` creates plain `Lattice`. Account templates use the manifest's
EntryPoint-specific `AccountFactory` / `AccountFactory6900` and their constructor-bound inits.
Their specialized proxies provide ERC-7579 fallback handlers or ERC-6900 execution-module dispatch.
Here is the v0.9 7579 pair; the `ModularAccount6900` binding uses the same factory API:

```bash
ACCOUNT_FACTORY_NAME=$(jq -r '.accounts[] | select(.proxyKind=="AccountDiamond" and .entryPointVersion=="0.9") | .factory' "$MANIFEST")
ACCOUNT_INIT_NAME=$(jq -r --arg factory "$ACCOUNT_FACTORY_NAME" '.accounts[] | select(.factory==$factory) | .initializer' "$MANIFEST")
FACTORY_ARGS=$(jq -r --arg name "$ACCOUNT_FACTORY_NAME" '.contracts[] | select(.name==$name) | .constructorArgs' "$MANIFEST")
for at in $(cast abi-decode --json 'f()((address,uint8,bytes4[])[],address)' "$FACTORY_ARGS" | jq -r '.data[0][] | .[0]'); do
  name=$(jq -r --arg at "$at" '.contracts[] | select((.address|ascii_downcase)==($at|ascii_downcase)) | .name' "$MANIFEST")
  deploy_shared "$name"
done
deploy_shared "$ACCOUNT_INIT_NAME"
deploy_shared "$ACCOUNT_FACTORY_NAME"
ACCOUNT_FACTORY=$(address_of "$ACCOUNT_FACTORY_NAME")
ACCOUNT_SALT=$(cast keccak lattice.integrator.account)
SMART_ACCOUNT=$(cast call "$ACCOUNT_FACTORY" 'getAddress(address,bytes32)(address)' "$ACCOUNT" "$ACCOUNT_SALT" --rpc-url "$RPC_URL")
cast send "$ACCOUNT_FACTORY" 'createAccount(address,bytes32)' "$ACCOUNT" "$ACCOUNT_SALT" --from "$ACCOUNT" --unlocked --rpc-url "$RPC_URL" >/dev/null
cast call "$SMART_ACCOUNT" 'owner()(address)' --rpc-url "$RPC_URL"
ENTRY_POINT=$(jq -r --arg factory "$ACCOUNT_FACTORY_NAME" '.accounts[] | select(.factory==$factory) | .entryPoint' "$MANIFEST")
cast call "$SMART_ACCOUNT" 'entryPoint()(address)' --rpc-url "$RPC_URL"
cast code "$ENTRY_POINT" --rpc-url "$RPC_URL"
```

The account factory folds `keccak256(abi.encode(owner, salt))` into its prediction. Its own address
binds the EntryPoint/init and stored blueprint through full constructor initcode. Reusing owner and
salt is idempotent. A nonzero pinned EntryPoint is configuration, not proof of compatible code,
bundler availability or EIP-7702 support: this Anvil node has no EntryPoint code and the example does
not submit a user operation. Custom EntryPoints are explicitly noncanonical profiles.

## Errors and chain observations

Generate the checked error/event catalog and decode the strict-mode error's signature from it:

```bash
make abi-catalog
jq --arg selector "$OCCUPIED_ERROR" '.errors[$selector]' out/errors.json
make release-notes PREVIOUS="$MANIFEST" CURRENT="$MANIFEST"
STATUS=deployments/fixtures/integrator-chain.json
make release-status MANIFEST="$MANIFEST" RPC_URL="$RPC_URL" DESTINATION="$STATUS"
jq '{chain,registryOwner,verified:([.contracts[].verified]|unique),present:([.contracts[]|select(.deployed!=null)]|length)}' "$STATUS"
```

The offline file contains source/compiler commitments, addresses, constructors, selectors and account
bindings ([release schema](../../deployments/schema/release.schema.json)). Its separate observation at
`deployments/<chain-id>/release-<version>.json` records a specific block, runtime matches, verification and curation state
([chain schema](../../deployments/schema/chain.schema.json)). `pre-existing` means observed code
without a transaction claim; `verified: false` is unknown verification. Observation resets positive
verification flags. This partial fixture leaves many shared contracts absent and is not a ready chain.

A public release needs reviewed source and owner, all shared identities deployed with matching code,
actual source verification, and the required curated records/latest pointers. The verifier's operational
command submits sources to Sourcify; it is intentionally not run here. Its offline preparation mode
reproduces the exact frozen input witness without verifier requests. See
[release evidence and verification](../../REGISTRY_DEPLOYMENTS.md#chain-readiness-and-ownership).

Cancun is the minimum EVM target for canonical artifacts. RPC aliases are configuration options;
no public chain is currently certified ready by schema-v1 evidence. Do not silently rebuild for an older
EVM or change metadata and call the result the same release. Initialization authority, custom code,
upgrade storage compatibility and external protocol assumptions still need review.

Matching ERC20 allowance readers and spenders require EIP-1153 even when the public temporary-approval
facet is absent. Adding that facet to an older diamond requires upgrading every allowance reader/spender,
including custom code compiled against the old shared library; adding the facet alone cannot change them.
Temporary grants cover grant and spend within one transaction, and ordinary approve/permit changes do not
revoke a temporary grant already live in that transaction. See
[the temporary-allowance composition limits](selector-compatibility.md#erc-7674-temporary-allowances).

Clean up only the example's files and owned node:

```bash
rm -f "$MANIFEST" "$STATUS"
rmdir deployments/fixtures 2>/dev/null || true
kill "$ANVIL_PID"
wait "$ANVIL_PID" 2>/dev/null || true
rm -rf "$GUIDE_TMP"
trap - EXIT
```

