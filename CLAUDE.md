# Lattice — repo conventions

These rules are mandatory for every change in this repo.

## External-source attribution (always)

Any file whose code is ported, adapted, vendored from, or inspired by an external source — including
integration adapters/facades that exist to wrap one specific external protocol — MUST credit that source with
a single natspec line placed immediately after the personal `@author` line (or after `@title` if there is no
author line):

```solidity
/// @author Modified from <SourceName> (<github-link|resource-link>)
```

- The facet, its `*Lib`, AND its first-party interface each carry the line (precedent: `BandAdapter`,
  `BandAdapterLib`, `IBandAdapter`).
- Files under `src/interfaces/external/` use the vendored style instead:
  `/// @author Vendored minimal subset of <SourceName> (<link>).` (+ upstream license note when known).
- OZ-ported modules may use `/// @author Adapted for EIP-2535 from OpenZeppelin ... (<link>[, commit <sha>])`.
- Every attribution line must contain a link. Use a file-precise `blob/master` link only when certain the
  upstream path exists; a repo-root link is the accepted fallback. Never fabricate a source or deep path.
- `*Init.sol` contracts, deploy scripts, and genuinely original Lattice logic carry NO attribution line.
- When creating any new file, add the attribution line at creation time — not retroactively.

## `registerInterface` standard (always)

ERC-165 registration in a `*Lib` uses a **precomputed** file-level map-slot constant and a single `sstore` —
never a runtime keccak, never a bare hex literal in the `sstore`, and never a local copy of the ERC-165
storage root (`0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200`):

```solidity
/// @dev 0xa777cf1b is `type(ICCTPBridgeAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xa777cf1b), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICCTPBRIDGEADAPTER_SLOT =
    0x30c377002135d1e8af7caedae6ec2adb3221e5a36ce695d62defb43a35cd29eb;

function registerInterface() internal {
    assembly ("memory-safe") {
        sstore(ERC165_MAP_ICCTPBRIDGEADAPTER_SLOT, true)
    }
}
```

- Constant name: `ERC165_MAP_<INTERFACE-NAME-UPPERCASED>_SLOT`; the `@dev` comment states the interfaceId and
  the full derivation.
- Multiple interfaces → `registerInterfaces()` with one `sstore` per precomputed constant (precedent:
  `ERC721Lib`).
- Adapters registering a SHARED interface id (e.g. `IERC7786GatewaySource`, `0x11967553`) declare the same
  constant/value in their own file with the SHARED note (precedent: `LayerZeroGatewayAdapterLib`).
- Verify the precomputed value with a throwaway forge test and keep the module's `test_SupportsInterface`
  test — the read path recomputes the keccak at runtime, so it catches a wrong constant.
