// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAxelarGatewayAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin community-contracts `AxelarGatewayAdapter`
///         (https://github.com/OpenZeppelin/openzeppelin-community-contracts/blob/f7e5f08e8fd42023084eb41f4a992d7be897b915/contracts/crosschain/axelar/AxelarGatewayAdapter.sol)
/// @notice Admin/read/inbound surface of the Axelar ERC-7786 gateway adapter. The standard source-gateway
///         ABI (`sendMessage`/`supportsAttribute`) is declared by `IERC7786GatewaySource`; this adds the
///         Axelar chain-name ↔ ERC-7930 equivalence registry, the trusted remote-gateway registry, and the
///         Axelar inbound `execute` entrypoint. EVM chains only.
interface IAxelarGatewayAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a CAIP-2 ↔ Axelar chain-name equivalence is registered.
    event RegisteredChainEquivalence(bytes chain, string axelar);

    /// @notice Emitted when a trusted remote gateway adapter is registered for a chain.
    event RegisteredRemoteGateway(bytes remote);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice `sendMessage` was called with non-zero `msg.value` (native transfer is unsupported).
    error UnsupportedNativeTransfer();

    /// @notice The interoperable chain type is not supported (only EVM / chainType `0x0000`).
    error UnsupportedChainType(bytes2 chainType);

    /// @notice A chain equivalence is already registered for this CAIP-2 chain or Axelar name.
    error ChainEquivalenceAlreadyRegistered(bytes chain);

    /// @notice A remote gateway is already registered for this chain.
    error RemoteGatewayAlreadyRegistered(bytes chain);

    /// @notice The inbound call's source did not match the registered remote gateway for its chain.
    error InvalidOriginGateway(string sourceChain, string sourceAddress);

    /// @notice The Axelar gateway has not approved this inbound contract call.
    error NotApprovedByGateway();

    /// @notice The recipient's `receiveMessage` did not return the ERC-7786 magic value.
    error RecipientExecutionFailed();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The configured Axelar gateway contract.
    function gateway() external view returns (address);

    /// @notice Returns the Axelar chain name for a "chain-only" ERC-7930 interoperable address.
    function getAxelarChain(bytes calldata chain) external view returns (string memory);

    /// @notice Returns the "chain-only" ERC-7930 interoperable address for an Axelar chain name.
    function getErc7930Chain(string calldata axelar) external view returns (bytes memory);

    /// @notice Returns the trusted remote gateway address-bytes registered for a "chain-only" address.
    function getRemoteGateway(bytes calldata chain) external view returns (bytes memory);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers a CAIP-2 ↔ Axelar chain-name equivalence (both directions). Admin only.
    /// @param chain A "chain-only" ERC-7930 interoperable address (empty address part).
    /// @param axelar The Axelar chain name (e.g. "ethereum", "optimism").
    function registerChainEquivalence(bytes calldata chain, string calldata axelar) external;

    /// @notice Registers a trusted remote gateway adapter. Admin only.
    /// @param remote The full ERC-7930 interoperable address of the remote adapter (chain + address).
    function registerRemoteGateway(bytes calldata remote) external;

    // -------------------------------------------------------------------------
    //                               Inbound (Axelar)
    // -------------------------------------------------------------------------

    /// @notice Axelar inbound entrypoint. Validates the approved call + the source gateway, then delivers to
    ///         the ERC-7786 recipient. Called by the Axelar relayer.
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;
}
