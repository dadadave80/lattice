# CCTP Hook Receipt NFT — implementation specification

Status: implementation-ready
Scope: contract, on-chain renderer, standalone live demo, `make demo` integration, tests, and documentation
Out of scope: executing live transactions, inventing deployment addresses, or replacing the existing vault demo

## 1. Objective

Add a `CCTPHookReceipt` example module that mints a position-style ERC-721 receipt whenever Circle CCTP v2
delivers USDC through Lattice's hooked relay path.

The USDC must be minted directly to the destination recipient. The receipt contract receives no USDC and
must never custody, withdraw, redeem, or control the transferred funds. After Circle's mint succeeds, the
existing `CCTPHookExecutor` calls the receipt contract, which mints an NFT to the same Circle-attested
recipient.

The NFT must behave visually like a Uniswap position NFT:

- the token is backed by structured on-chain state;
- `tokenURI` is generated from that state;
- the image is an on-chain SVG;
- the card prominently presents the amount and route;
- the complete facts are also exposed as machine-readable JSON attributes.

Unlike a Uniswap position NFT, this token represents an immutable historical delivery. It does not represent
a redeemable balance or confer control over USDC.

## 2. Required user-visible result

The live flow must be:

```text
Arc actor
  │
  │ depositForBurnWithHook(
  │   amount,
  │   Base recipient,
  │   HOOK_MAGIC || CCTPHookReceipt
  │ )
  ▼
Circle CCTP v2 burn + Iris attestation
  │
  ▼
Base Lattice diamond.relayMessageWithHook
  ├── Circle mints net USDC directly to recipient
  └── CCTPHookExecutor calls CCTPHookReceipt.onCCTPHook
        └── receipt NFT is minted to that same recipient
```

The terminal must finish with evidence for both effects:

1. the recipient's Base Sepolia USDC balance increased by the attested net amount; and
2. the receipt NFT was minted to the recipient with matching source, sender, recipient, and amount fields.

## 3. Architectural decisions

### 3.1 Preserve the existing hook seam

Do not change any of the following:

- `src/interfaces/crosschain/ICCTPHookReceiver.sol`
- `src/interfaces/crosschain/ICCTPHookExecutor.sol`
- `src/crosschain/circle/CCTPHookExecutor.sol`
- `src/crosschain/circle/CCTPBridgeAdapter.sol`
- `src/crosschain/circle/CCTPBridgeAdapterLib.sol`

The existing `ICCTPHookReceiver.onCCTPHook` interface already provides:

- `sourceDomain`: Circle-attested source CCTP domain;
- `sender`: Circle-attested BurnMessage `messageSender`;
- `mintRecipient`: Circle-attested destination recipient;
- `amount`: net USDC actually minted, after `feeExecuted`;
- `payload`: attacker-controlled bytes.

Those trusted fields are sufficient for the first version. The CCTP nonce is deliberately omitted because
the current receiver interface does not expose it. Do not introduce a receiver V2 interface merely to obtain
the nonce.

Circle's MessageTransmitter prevents replay of an attested message. Sequential receipt token IDs are
therefore sufficient: each successful hook call from the trusted executor corresponds to one consumed CCTP
message.

### 3.2 Keep the vault demo intact

Do not modify or delete:

- `src/examples/crosschain/CCTPHookVault.sol`
- `script/base/crosschain/CCTPHookDemo.s.sol`
- `script/config/cctp-hook-demo.sh`
- `test/unit/CCTPHookVaultTest.t.sol`
- `test/fork/CCTPHookDemoFork.t.sol`
- `test/fixtures/cctp/arc-to-base-hook-v2.json`
- the existing vault deployment addresses, transaction links, or broadcast evidence

The vault remains a separate programmable-USDC example. The receipt is a new example and a new demo.

### 3.3 Reuse the deployed routing stack

The receipt demo must reuse an existing compatible Arc hub and Base destination diamond.

The receipt contract is deployed on Base Sepolia with the Base diamond's current
`ICCTPBridgeAdapter.hookExecutor()` as its immutable trust anchor. It does not require a new Arc hub, Base
diamond, adapter facet, or executor.

Before any burn, the demo must prove:

- `CCTPHookReceipt.executor() == ICCTPBridgeAdapter(baseDiamond).hookExecutor()`; and
- the Arc hub's Base-domain `destinationCaller` equals the selected Base diamond.

Fail before spending if either check fails.

### 3.4 Receipt ownership

The receipt is a normal transferable ERC-721.

The stored `originalRecipient` never changes after transfer. Metadata must show `ORIGINAL RECIPIENT`, not
the NFT's current owner. A future soulbound variant is out of scope.

### 3.5 Lenient hook semantics

The adapter intentionally executes hooks leniently: a hook failure does not revert a successful Circle mint.
The receipt must minimize failure modes accordingly:

- authenticate the immutable executor;
- reject malformed EVM recipient words;
- use `ERC721Lib._mint`, not `_safeMint`, so a contract recipient cannot make receipt delivery fail by lacking
  `IERC721Receiver`;
- make no external call during `onCCTPHook`;
- ignore the untrusted payload;
- perform no USDC balance read or transfer.

## 4. Files

### 4.1 New files

```text
src/examples/crosschain/CCTPHookReceipt.sol
src/examples/crosschain/libraries/CCTPHookReceiptRenderer.sol
script/base/crosschain/CCTPHookReceiptDemo.s.sol
script/config/cctp-hook-receipt-demo.sh
test/unit/CCTPHookReceiptTest.t.sol
test/fork/CCTPHookReceiptDemoFork.t.sol
test/fixtures/cctp/arc-to-base-receipt-v2.json
```

The fork fixture must initially be a documented placeholder with empty `message` and `attestation` fields.
Only an operator performing a real run may populate it.

### 4.2 Existing files to modify

```text
Makefile
script/config/cctp-demo-interactive.sh
README.md
```

No other production file should need modification.

## 5. `CCTPHookReceipt` contract

### 5.1 Location and inheritance

Create:

```text
src/examples/crosschain/CCTPHookReceipt.sol
```

The contract should inherit:

```solidity
ERC721, ICCTPHookReceiver
```

Reuse the repository's existing modules:

- `ERC721` and `ERC721Lib`;
- `InitializableLib`;
- `ERC165Lib` for the standalone `supportsInterface` read;
- `CCTPHookReceiptRenderer` for metadata.

Do not add OpenZeppelin or any other dependency.

Because the existing `ERC721` contract is normally used as a diamond facet, this standalone contract must
perform its own initialization in the constructor:

```solidity
bytes32 slot = InitializableLib.preInitializer();
ERC721Lib.__ERC721_init("Lattice CCTP Receipt", "LCR");
InitializableLib.postInitializer(slot);
```

It must also expose:

```solidity
function supportsInterface(bytes4 interfaceId) external view returns (bool)
```

and delegate that read to `ERC165Lib.supportsInterface(interfaceId)`. Initialization already registers the
ERC-721 and ERC-721 metadata interface IDs in the shared ERC-165 storage.

Do not add an `IFacet` implementation or a second `exportSelectors` method.

### 5.2 Attribution

The position-style metadata design is inspired by Uniswap v4. Follow `CLAUDE.md` and add the required
attribution immediately after the personal author line in both new Solidity source files:

```solidity
/// @author Modified from Uniswap v4 Periphery (https://github.com/Uniswap/v4-periphery)
```

Do not copy Uniswap source verbatim. The implementation must use this repository's ERC-721, Base64, and
Strings modules.

### 5.3 Storage

Use:

```solidity
struct Receipt {
    uint32 sourceDomain;
    bytes32 sender;
    address originalRecipient;
    uint256 amount;
    uint64 recordedAt;
}

address public immutable executor;
uint256 public nextTokenId;
mapping(uint256 tokenId => Receipt receipt) private _receipts;
```

Initialize `nextTokenId` to `1`.

Do not store:

- current NFT owner, because ERC-721 storage already owns that fact;
- destination chain ID, because the receipt contract's `block.chainid` is authoritative;
- token URI or SVG strings;
- hook payload;
- USDC address;
- CCTP nonce, because it is not available at the receiver interface;
- a claimed source EOA.

### 5.4 Public interface

In addition to inherited ERC-721 functions, expose:

```solidity
function receipt(uint256 tokenId) external view returns (Receipt memory);
function tokenURI(uint256 tokenId) public view override returns (string memory);
```

`receipt(tokenId)` and `tokenURI(tokenId)` must revert with the repository's standard
`IERC721.ERC721NonexistentToken(tokenId)` for an unknown token.

Do not add setters, administrators, minters, pausers, metadata authorities, descriptor setters, or upgrade
hooks.

### 5.5 Constructor

```solidity
constructor(address executor_)
```

Requirements:

- revert if `executor_ == address(0)`;
- save it immutably;
- initialize ERC-721 name and symbol exactly as above.

Error:

```solidity
error CCTPHookReceipt__ZeroExecutor();
```

### 5.6 Hook implementation

Implement the existing interface exactly:

```solidity
function onCCTPHook(
    uint32 sourceDomain,
    bytes32 sender,
    bytes32 mintRecipient,
    uint256 amount,
    bytes calldata payload
) external;
```

Required order:

1. Require `msg.sender == executor`.
2. Validate that `mintRecipient` is a right-aligned EVM address:
   - `uint256(mintRecipient) <= type(uint160).max`;
   - converted address is not zero.
3. Read and increment `nextTokenId`.
4. Store the receipt using only the four attested callback facts plus `uint64(block.timestamp)`.
5. Mint with `ERC721Lib._mint(originalRecipient, tokenId)`.
6. Emit `ReceiptMinted`.

The payload parameter must be unnamed or explicitly ignored. It must not affect ownership, metadata, token
ID, amount, sender, source domain, or any other state.

Errors:

```solidity
error CCTPHookReceipt__NotExecutor();
error CCTPHookReceipt__InvalidRecipient(bytes32 mintRecipient);
```

Event:

```solidity
event ReceiptMinted(
    uint256 indexed tokenId,
    address indexed originalRecipient,
    uint32 indexed sourceDomain,
    bytes32 sender,
    uint256 amount,
    uint64 recordedAt
);
```

The event must be easy for the shell demo to identify by:

- emitting from the receipt contract;
- indexing `tokenId`, `originalRecipient`, and `sourceDomain`;
- placing `sender`, `amount`, and `recordedAt` in event data.

### 5.7 What “sender” means

The callback's `sender` is Circle's attested BurnMessage `messageSender`. In the current Lattice flow this is
normally the Arc hub diamond, not necessarily the actor EOA that initiated the burn.

Metadata and narration must label this field `SOURCE CONTRACT` or `CCTP MESSAGE SENDER`. Do not label it
`USER`, `WALLET`, or imply it is the originating EOA.

### 5.8 Transferability

Use the inherited standard ERC-721 transfer and approval behavior without overrides.

After an NFT transfer:

- `ownerOf(tokenId)` changes;
- `receipt(tokenId).originalRecipient` does not change;
- `tokenURI(tokenId)` continues to display the original recipient.

Do not implement burn support in this feature.

## 6. Renderer

### 6.1 Location and seam

Create:

```text
src/examples/crosschain/libraries/CCTPHookReceiptRenderer.sol
```

This is an internal rendering module, not a deployed descriptor contract. Its interface should accept one
parameter struct and return the final token URI:

```solidity
struct RenderParams {
    uint256 tokenId;
    uint32 sourceDomain;
    bytes32 sender;
    address originalRecipient;
    uint256 amount;
    uint64 recordedAt;
    uint256 destinationChainId;
}

function tokenURI(RenderParams memory params) internal pure returns (string memory);
```

Keep all SVG, JSON, formatting, labels, and deterministic visual generation in this file. Keep executor
authentication and receipt state in `CCTPHookReceipt`.

Do not create an external descriptor interface, deploy a descriptor contract, or add a mutable descriptor
address.

### 6.2 Encoding

Reuse:

```text
src/utils/libraries/Base64.sol
src/utils/libraries/Strings.sol
```

Return:

```text
data:application/json;base64,<base64 JSON>
```

The JSON `image` field must contain:

```text
data:image/svg+xml;base64,<base64 SVG>
```

No IPFS URL, HTTP URL, external font, external image, JavaScript, animation script, or remote CSS is allowed.

If the implementation uses visible Unicode characters such as `×`, `→`, `·`, or `…`, Solidity literals
must use the `unicode"..."` form. Plain ASCII equivalents are acceptable and preferable if they keep the
renderer simpler.

### 6.3 Card layout

Use a portrait SVG with a `600 × 900` view box.

Required visible hierarchy:

```text
LATTICE × CIRCLE                         #<tokenId>

<formatted amount> USDC

<source label>  ─────────▶  <destination label>

SOURCE CONTRACT
<short source sender>

ORIGINAL RECIPIENT
<short recipient>

DELIVERED · CCTP V2
```

The card must remain legible as a wallet thumbnail:

- amount is the largest text;
- source and destination labels are the second-largest;
- addresses are supporting details;
- status is visually distinct;
- no paragraph text inside the SVG.

Use native SVG shapes and text only.

### 6.4 Deterministic visual identity

Derive a seed:

```solidity
keccak256(
    abi.encode(
        tokenId,
        sourceDomain,
        sender,
        originalRecipient,
        amount,
        destinationChainId
    )
)
```

Use the seed only for presentation, such as:

- selecting one of a small fixed set of accent colors;
- positioning two or three translucent circles;
- choosing a route-line gradient.

Do not let visual generation change or obscure factual metadata. Avoid unbounded loops and expensive
procedural art.

### 6.5 Labels

Provide concise known-domain labels:

| CCTP domain | Display label |
|---:|---|
| `0` | `ETHEREUM` |
| `6` | `BASE` |
| `26` | `ARC` |

Unknown domains must display:

```text
DOMAIN <decimal domain>
```

Provide concise destination-chain labels:

| Chain ID | Display label |
|---:|---|
| `1` | `ETHEREUM` |
| `8453` | `BASE` |
| `84532` | `BASE SEPOLIA` |
| `11155111` | `SEPOLIA` |
| `5042002` | `ARC TESTNET` |

Unknown chains must display:

```text
CHAIN <decimal chainId>
```

These helpers are display-only. They must not participate in authentication or receipt identity.

### 6.6 Amount formatting

USDC uses six decimals. Format `amount` without rounding:

```text
1        -> 0.000001
1000000  -> 1.000000
1250000  -> 1.250000
```

Always render exactly six fractional digits. Keep the raw integer amount separately in JSON attributes.

### 6.7 Address formatting

The SVG may shorten values:

```text
address: 0x1234…cdef
bytes32: 0x12345678…89abcdef
```

The JSON attributes must contain full lowercase hexadecimal strings:

- recipient as a 20-byte `0x` address;
- sender as a 32-byte `0x` value.

All dynamic JSON and SVG text comes from integers or hex encoders owned by the renderer. Do not interpolate
the attacker-controlled hook payload.

### 6.8 JSON metadata

Required top-level fields:

```json
{
  "name": "Lattice CCTP Receipt #1",
  "description": "On-chain proof that Circle CCTP v2 delivered USDC through a Lattice hook.",
  "image": "data:image/svg+xml;base64,...",
  "attributes": []
}
```

Required attributes:

| Trait type | Value form |
|---|---|
| `Status` | `"Delivered"` |
| `Asset` | `"USDC"` |
| `Amount` | formatted six-decimal string |
| `Amount (uUSDC)` | unquoted JSON integer |
| `Source CCTP Domain` | unquoted JSON integer |
| `Source Label` | string |
| `CCTP Message Sender` | full bytes32 hex string |
| `Destination Chain ID` | unquoted JSON integer |
| `Destination Label` | string |
| `Original Recipient` | full address string |
| `Recorded At` | unquoted Unix timestamp |

Do not include:

- a redeemable value claim;
- a source transaction hash;
- a CCTP nonce;
- an originating user address;
- a live exchange-rate conversion;
- a claim that the current NFT owner received the USDC.

## 7. Standalone Forge demo

### 7.1 File

Create:

```text
script/base/crosschain/CCTPHookReceiptDemo.s.sol
```

This must be a new script. Do not modify or inherit `CCTPHookDemo`.

It may duplicate the small set of Base/Arc constants required for clarity. Do not introduce a shared demo
framework solely to remove those constants.

### 7.2 Constants

Use the existing testnet values already used by the hook demo:

```text
Arc testnet chain ID:       5042002
Arc CCTP domain:            26
Arc USDC:                   0x3600000000000000000000000000000000000000
Base Sepolia chain ID:      84532
Base CCTP domain:           6
Base Sepolia USDC:          0x036CbD53842c5426634e7929541eC2318f3dCF7e
```

Use the existing Foundry aliases:

```text
arc-testnet
base-sepolia
```

### 7.3 Script entrypoints and output markers

Implement these entrypoints:

```solidity
function receiptDemoSetup(address baseDiamond) external;
function receiptDemoRecipient(address recipient) external pure;
function receiptDemoEnvelope(address receipt) external pure;
function receiptDemoRelay(
    address baseDiamond,
    bytes calldata message,
    bytes calldata attestation
) external;
function receiptDemoArcBalance(address actor) external;
function receiptDemoBaseBalance(address recipient) external;
function receiptDemoNftBalance(address receipt, address recipient) external;
function receiptDemoData(address receipt, uint256 tokenId) external;
function receiptDemoMessage(bytes calldata message) external pure;
```

Required stable output markers:

```text
DEMO-RECEIPT-SETUP <receipt> <executor>
DEMO-RECEIPT-RECIPIENT <erc7930-bytes>
DEMO-RECEIPT-ENVELOPE <hook-bytes>
DEMO-RECEIPT-RELAY ok
DEMO-RECEIPT-ARCBAL <raw-usdc-units>
DEMO-RECEIPT-BASEBAL <raw-usdc-units>
DEMO-RECEIPT-NFTBAL <count>
DEMO-RECEIPT-DATA <tokenId> <sourceDomain> <sender> <recipient> <amount> <recordedAt>
DEMO-RECEIPT-MESSAGE <sourceDomain> <sender> <recipient> <grossAmount> <feeExecuted> <netAmount> <target>
```

Shell code must parse only these stable markers, never arbitrary Forge output.

### 7.4 Setup

`receiptDemoSetup(baseDiamond)` must:

1. select the Base Sepolia fork;
2. read `hookExecutor()` from `baseDiamond`;
3. reject a zero executor;
4. broadcast deployment of exactly one `CCTPHookReceipt(executor)`;
5. print the setup marker.

It must not deploy or configure a diamond, hub, adapter, vault, or USDC contract.

### 7.5 Recipient encoding

`receiptDemoRecipient(recipient)` must use the existing `InteroperableAddress.formatEvmV1` helper for Base
Sepolia and print the result.

The CCTP mint recipient is the actual recipient, not the receipt contract.

### 7.6 Hook envelope

`receiptDemoEnvelope(receipt)` must produce exactly:

```solidity
abi.encodePacked(HOOK_MAGIC, bytes20(receipt))
```

The envelope is exactly 24 bytes:

```text
HOOK_MAGIC (4) || receipt target (20)
```

There is no payload.

### 7.7 Relay

`receiptDemoRelay` must select Base Sepolia, broadcast one call to:

```solidity
ICCTPBridgeAdapter(baseDiamond).relayMessageWithHook(message, attestation)
```

and print the relay marker after success.

### 7.8 Read helpers

Read helpers must be broadcast-free and select the correct fork themselves.

`receiptDemoData` must use the receipt contract's public interface and print the stored immutable facts. It
must not parse metadata as the source of truth.

`receiptDemoMessage` is a broadcast-free verification helper. It must parse the CCTP v2 message using the
same documented offsets already grounded by `CCTPBridgeAdapterTest`:

```text
sourceDomain  @ 4    (uint32)
mintRecipient @ 184  (bytes32)
gross amount  @ 216  (uint256)
sender        @ 248  (bytes32)
feeExecuted   @ 312  (uint256)
hook data     @ 376  (HOOK_MAGIC || target || payload)
```

It must require a message long enough for the 24-byte receipt envelope, require
`feeExecuted <= grossAmount`, derive `netAmount = grossAmount - feeExecuted`, validate the hook magic, and
print the target from the envelope. Add a test grounded on the repository's real CCTP fixture bytes so a
shared incorrect offset cannot pass unnoticed.

## 8. Shell driver

### 8.1 File and target

Create:

```text
script/config/cctp-hook-receipt-demo.sh
```

Add:

```make
.PHONY: demo-cctp-receipt
demo-cctp-receipt: ## CCTP receipt NFT demo — Arc->Base USDC delivery + on-chain receipt
	@$(AUTH_WRAP) script/config/cctp-hook-receipt-demo.sh $(ARGS)
```

Usage:

```text
make demo-cctp-receipt KEYSTORE=<name>
make demo-cctp-receipt PRIVATE_KEY=0x<testnet-key>
make demo-cctp-receipt ... ARGS='<actor> <recipient>'
```

If actor is omitted, derive it from signing credentials. If recipient is omitted, use actor.

### 8.2 Receipt-only deployment target

Add:

```make
.PHONY: deploy-cctp-receipt
deploy-cctp-receipt: ## Deploy a receipt NFT against an existing Base CCTP diamond
	@$(AUTH_WRAP) script/config/cctp-hook-receipt-demo.sh --deploy-only $(ARGS)
```

`--deploy-only` deploys only `CCTPHookReceipt` on Base Sepolia and writes:

```text
.cctp-demo.receipt-deployment.env
```

Required keys:

```text
BASE_DIAMOND=<address>
RECEIPT=<address>
EXECUTOR=<address>
```

Do not store authentication material, RPC URLs, API keys, or private keys.

Refuse to overwrite an existing receipt deployment journal. Print the exact file and remediation instead.

### 8.3 Stack resolution

Resolve addresses in this order:

1. complete environment override:
   - `DEMO_ARC_HUB`
   - `DEMO_BASE_DIAMOND`
   - `DEMO_RECEIPT`
2. existing CCTP stack journal plus receipt deployment journal:
   - `.cctp-demo.deployment.env` for hub and diamond;
   - `.cctp-demo.receipt-deployment.env` for receipt;
3. canonical addresses committed only after a real deployment.

Do not invent, precompute, or placeholder-substitute a canonical receipt address.

Until a canonical receipt exists, fail with:

```text
No CCTPHookReceipt deployment found. Run make deploy-cctp-receipt ... or set DEMO_RECEIPT.
```

If the receipt journal's `BASE_DIAMOND` differs from the selected Base diamond, fail before the burn.

### 8.4 Preflight

Before any transaction:

- require `forge`, `cast`, `jq`, and `curl`;
- resolve both RPC URLs without printing them;
- validate every address;
- require signer authentication;
- derive actor where possible;
- query `receipt.executor()`;
- query `baseDiamond.hookExecutor()`;
- require equality;
- query the Arc hub's Base-domain configuration;
- require `destinationCaller` to equal the right-aligned Base diamond;
- read actor Arc USDC balance;
- require enough Arc USDC for amount plus gas headroom;
- read and journal recipient Base USDC and NFT balance baselines.

Arc's gas token is USDC. Do not use a check that allows the actor to burn their entire Arc USDC balance.
Reuse the existing hook demo's headroom behavior.

### 8.5 Run journal

Use:

```text
.cctp-demo.receipt.env
```

The run journal must survive interruption and allow safe re-entry.

Required keys as phases progress:

```text
DEPLOYMENT=<arcHub>:<baseDiamond>:<receipt>
ACTOR=<address>
RECIPIENT=<address>
AMOUNT=<raw-usdc-units>
BASE_USDC_BEFORE=<raw-usdc-units>
NFT_BALANCE_BEFORE=<count>
BURN_ATTEMPTED=1
BURN_TX=<hash>
MESSAGE=<hex>
ATTESTATION=<hex>
RELAY_TX=<hash>
TOKEN_ID=<integer>
```

On resume:

- journaled stack, actor, recipient, and amount win;
- authentication is requested again and is never journaled;
- completed phases are skipped;
- never issue a second burn for the same journal;
- a `BURN_ATTEMPTED` journal without a recoverable `BURN_TX` must stop with manual recovery instructions.

Delete the run journal only after all final checks pass.

Use atomic `KEY=VALUE` journal writes, restrictive temporary files, and traps consistent with the existing
CCTP hook driver.

### 8.6 Burn

Build:

```text
recipient = Base ERC-7930 address for RECIPIENT
hookData  = HOOK_MAGIC || RECEIPT
```

On Arc:

1. approve exactly `AMOUNT` USDC to the Arc hub;
2. call `depositForBurnWithHook(AMOUNT, recipient, hookData)`;
3. capture and journal the burn transaction hash.

Never print signing material or RPC URLs. Keep the current repo warning that raw testnet private keys may
appear in local process arguments.

### 8.7 Iris attestation

Use Circle's sandbox Iris endpoint and the existing hook driver's polling behavior:

```text
https://iris-api-sandbox.circle.com
```

Poll by Arc source domain and burn transaction hash. Journal the exact returned message and attestation.
Validate that both are nonempty hex before continuing.

Do not synthesize an attestation.

### 8.8 Relay

Relay on Base through the selected Base diamond using `receiptDemoRelay`.

Capture the Base relay transaction hash from the new script's broadcast journal:

```text
broadcast/CCTPHookReceiptDemo.s.sol/84532/...
```

Do not treat Forge console output alone as confirmation.

### 8.9 Event and state verification

Read the relay receipt and find exactly one `ReceiptMinted` log emitted by `RECEIPT`.

Decode:

- token ID;
- original recipient;
- source domain;
- sender;
- amount;
- recorded timestamp.

Use `receiptDemoMessage` to independently derive the attested source domain, sender, recipient, gross amount,
fee, net amount, and receipt target from the journaled message.

Require:

- event recipient equals journaled recipient;
- decoded message recipient equals journaled recipient;
- decoded message target equals the selected receipt contract;
- event source domain, sender, recipient, and amount equal the independently decoded message facts;
- event amount equals the decoded message's net-minted amount;
- `ownerOf(tokenId)` equals recipient;
- stored receipt fields equal the decoded event;
- recipient Base USDC balance increased by the same amount;
- recipient NFT balance increased by exactly one;
- `tokenURI(tokenId)` starts with `data:application/json;base64,`.

If the USDC or NFT balance changed concurrently for unrelated reasons, print the observed values and fail
without deleting the journal; the operator can inspect and resume verification.

Final terminal output should be concise and video-friendly:

```text
✓ Circle minted 1.000000 USDC directly to <recipient>
✓ Lattice minted CCTP Receipt #<tokenId> to the same recipient
  route: Arc (domain 26) -> Base Sepolia
  source contract: <sender>
  burn:  <Arc explorer URL>
  relay: <Base explorer URL>
  NFT:   <Base receipt contract URL>?a=<tokenId>
```

Use the explorer's actual supported token URL shape; if no token-specific URL is known, link the contract
address and print the token ID separately. Do not fabricate a URL format.

## 9. `make demo` integration

Modify:

```text
script/config/cctp-demo-interactive.sh
```

Add:

```text
[6] Receipt NFT  Arc -> Base
    USDC goes directly to the recipient and a position-style receipt NFT is minted alongside it.
```

Required changes:

- direction validation becomes `1-6`;
- add `.cctp-demo.receipt.env` to the pre-prompt resume scan;
- a receipt journal resumes as direction `6`;
- custom-stack mode additionally prompts for `CCTPHookReceipt` when direction is `6`;
- prompt for `recipient`, defaulting to the actor;
- preserve separate source actor and destination recipient values;
- show the actor's Arc balance and recipient's Base balance;
- summary text says `receipt NFT Arc -> Base`;
- dispatch `cctp-hook-receipt-demo.sh` with positional actor and recipient when needed;
- timing says Arc-sourced and attests in seconds;
- existing directions `1-5` retain their current behavior.

Do not rename or reorder the existing five choices.

The top-of-file usage comment must document direction `6`.

## 10. Tests

### 10.1 Unit test

Create:

```text
test/unit/CCTPHookReceiptTest.t.sol
```

Use the repository's existing Foundry test style. Required cases:

1. constructor rejects zero executor;
2. name is `Lattice CCTP Receipt`;
3. symbol is `LCR`;
4. `supportsInterface` reports ERC-721 and ERC-721 metadata;
5. non-executor hook call reverts;
6. zero mint recipient reverts;
7. a bytes32 value with nonzero upper 96 bits reverts;
8. valid right-aligned recipient receives token ID `1`;
9. receipt stores source domain, sender, original recipient, amount, and recorded timestamp;
10. `ReceiptMinted` contains the same facts;
11. arbitrary payload does not affect any stored fact;
12. second hook mints token ID `2`;
13. two receipts to one recipient accumulate ERC-721 balance;
14. transfer changes `ownerOf` but not `originalRecipient`;
15. minting to a contract without `IERC721Receiver` succeeds because `_mint` is intentionally used;
16. unknown `receipt(tokenId)` reverts with `ERC721NonexistentToken`;
17. unknown `tokenURI(tokenId)` reverts with `ERC721NonexistentToken`;
18. token URI has the JSON data-URI prefix;
19. different receipt facts produce different token URIs;
20. amount formatting covers `1`, `1_000_000`, and `1_250_000`.

For renderer-only helpers, use a test-local harness if necessary. Do not expose formatting helpers on the
production contract merely for testing.

### 10.2 Integration path in the unit test

Add one end-to-end test using a real Lattice diamond and its real `CCTPHookExecutor`, with only Circle's
MessageTransmitter mocked:

```text
relayMessageWithHook
  -> CCTPHookExecutor
  -> CCTPHookReceipt.onCCTPHook
  -> ERC-721 mint
```

Construct a valid CCTP v2 message with:

- source domain `26`;
- right-aligned recipient;
- net amount;
- `HOOK_MAGIC || receipt`;
- empty hook payload.

Assert that the NFT is minted to `mintRecipient`, not to the receipt contract, relay caller, actor, or source
sender.

### 10.3 Fork test

Create:

```text
test/fork/CCTPHookReceiptDemoFork.t.sol
```

Required tests:

- env-gated Base Sepolia setup deploys a receipt bound to the selected diamond's executor;
- placeholder fixture skips cleanly;
- after a real fixture is captured, fork at `receiveBlock - 1`, replay the real message and attestation,
  assert receipt state and ownership, then assert a second relay reverts because Circle consumed the nonce.

Follow the existing `CCTPHookDemoFork` RPC gating and pinned-block style.

### 10.4 Fixture

Create:

```text
test/fixtures/cctp/arc-to-base-receipt-v2.json
```

Initial shape:

```json
{
  "provenance": "Placeholder until a real Arc-to-Base receipt demo is relayed.",
  "todo": "Capture from Iris and the Base relay after the first live run.",
  "message": "0x",
  "attestation": "0x",
  "baseDiamond": "0x0000000000000000000000000000000000000000",
  "receipt": "0x0000000000000000000000000000000000000000",
  "recipient": "0x0000000000000000000000000000000000000000",
  "amount": 0,
  "tokenId": 0,
  "receiveBlock": 0,
  "burnTx": "0x",
  "relayTx": "0x"
}
```

The fork test must check `message.length` first and skip before using placeholder addresses.

## 11. Documentation

Update `README.md` without altering the existing vault evidence.

Add a fourth CCTP demo:

```text
Position-style receipt NFT (`make demo-cctp-receipt`):
USDC is minted directly to the Base recipient while the same attested relay mints a fully on-chain ERC-721
receipt showing the net amount, CCTP source domain, source contract, recipient, route, and delivery time.
```

Document:

- the receipt controls no USDC and is not redeemable;
- the displayed sender is Circle's attested message sender;
- metadata and SVG are fully on-chain;
- the command for an existing canonical deployment;
- the receipt-only deployment command;
- the receipt contract and live transaction evidence only after those values exist.

Do not claim a live deployment before an operator has produced it.

Update the Makefile demo comments so help output includes:

```text
demo-cctp-receipt
deploy-cctp-receipt
```

## 12. Security invariants

The implementation is unacceptable unless all of these hold:

1. Only the immutable executor can mint.
2. The executor cannot be changed.
3. The NFT recipient comes only from Circle-attested `mintRecipient`.
4. Amount comes only from the adapter's net-minted callback amount.
5. Source domain and sender come only from the attested callback.
6. Hook payload is ignored.
7. Receipt minting performs no external call.
8. Receipt minting never transfers or approves USDC.
9. Receipt metadata never describes the NFT as redeemable.
10. The current NFT owner is never confused with the original USDC recipient.
11. Demo stack compatibility is checked before the source burn.
12. An interrupted demo cannot silently issue a second burn.
13. No secret is written to a journal or printed.
14. A failed receipt hook cannot undo or hide the fact that Circle's USDC mint stands.

## 13. Non-goals

Do not implement:

- soulbound behavior;
- NFT burning;
- receipt redemption;
- USDC custody;
- a vault;
- an external metadata server;
- IPFS uploads;
- an upgradeable descriptor;
- arbitrary user-supplied artwork;
- cross-chain NFT bridging;
- source EOA authentication;
- CCTP nonce storage;
- on-chain transaction hashes;
- enumerable ERC-721;
- royalties;
- access-control roles;
- a new bridge adapter or hook interface;
- a frontend.

## 14. Implementation order

Implement in this order:

1. `CCTPHookReceiptRenderer`;
2. `CCTPHookReceipt`;
3. contract unit and end-to-end tests;
4. `CCTPHookReceiptDemo.s.sol`;
5. receipt shell driver;
6. Makefile targets;
7. `make demo` option `6`;
8. placeholder fork fixture and fork test;
9. README documentation;
10. formatting and verification.

Do not begin with shell or documentation changes before the contract interface and tests compile.

## 15. Verification commands

Run at minimum:

```sh
forge fmt --check
forge build --sizes
forge test --match-path test/unit/CCTPHookReceiptTest.t.sol -vvv
forge test --match-contract CCTPBridgeAdapterTest -vvv
bash -n script/config/cctp-hook-receipt-demo.sh
bash -n script/config/cctp-demo-interactive.sh
```

If the Base Sepolia RPC is available:

```sh
forge test --match-path test/fork/CCTPHookReceiptDemoFork.t.sol -vvv
```

The fork test must skip, not fail, when its RPC or live fixture is absent.

Do not run `make deploy-cctp-receipt` or `make demo-cctp-receipt` during implementation review without the
operator's explicit authorization: both send live testnet transactions.

## 16. Definition of done

The code implementation is complete when:

- all new contract tests pass;
- existing CCTP adapter and vault tests still pass unchanged;
- the existing vault demo files and evidence remain intact;
- `make help` lists the two receipt targets;
- `make demo` visibly offers option `6`;
- shell scripts pass syntax validation;
- the receipt demo refuses mismatched executor/diamond/receipt configurations before burning;
- no external dependency was added;
- the deployed `CCTPHookReceipt` bytecode remains below the EIP-170 size limit;
- no live address or transaction was fabricated;
- README distinguishes implemented code from live deployment status.

The live rollout is separately complete when:

- a receipt is deployed against the canonical Base diamond executor;
- one real Arc-to-Base receipt transfer succeeds;
- the recipient receives both USDC and the NFT;
- explorer links and the real fixture are captured;
- the canonical receipt address and evidence are committed;
- the grant video can run `make demo`, select option `6`, and show both delivery effects.

## 17. Review checklist for the supervising model

The reviewing model must inspect, not assume:

- the receipt uses `_mint`, not `_safeMint`;
- recipient conversion rejects nonzero upper 96 bits;
- payload is unused;
- no receiver/executor/adapter interface changed;
- existing vault demo files are unchanged;
- metadata distinguishes source contract from source user;
- metadata distinguishes original recipient from current NFT owner;
- all JSON values are syntactically valid and properly quoted;
- SVG and JSON contain no attacker-controlled raw strings;
- amount formatting always emits six decimals;
- event topics are decoded correctly by the shell;
- the shell checks executor and destination caller before burn;
- the run journal makes burn idempotence explicit;
- journal writes contain no secrets;
- fixture placeholder skips before parsing zero addresses;
- no canonical deployment claim exists without evidence;
- dirty worktree changes outside this feature were preserved.
