// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ArachnidProxy
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from deterministic-deployment-proxy (https://github.com/Arachnid/deterministic-deployment-proxy)
/// @notice The LIVE runtime bytecode of the Arachnid deterministic-deployment proxy — the raw-salt CREATE2
///         fallback {CreateXDeployer} takes on chains CreateX never reached (Hedera mainnet entity
///         `0.0.6264020`, testnet `0.0.4283707`). `vm.etch(PROXY, RUNTIME)` gives a Foundry run the exact
///         deployer those chains have, with no fork and no RPC.
/// @dev Source: the deployed proxy at `0x4e59b44847b379578588920cA78FbF26c0B4956C`, fetched 2026-09-12 with
///      `cast code 0x4e59b44847b379578588920cA78FbF26c0B4956C --rpc-url https://ethereum-rpc.publicnode.com`
///      (69 bytes). Semantics: calldata is `salt (32 bytes) ++ initCode`; it CREATE2-deploys, reverts when
///      the CREATE2 fails, and otherwise returns the RAW 20-byte address (`return(0x0c, 0x14)`) — not an
///      ABI-encoded one. It applies NO guard to the salt, which is exactly why an Arachnid chain's release
///      addresses differ from a CreateX chain's.
library ArachnidProxy {
    /// @notice The proxy's address, identical on every chain that has it.
    address internal constant PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice The proxy's 69-byte runtime bytecode (see the fetch note above).
    bytes internal constant RUNTIME =
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";
}
