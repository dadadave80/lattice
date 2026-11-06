// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ArachnidDeployer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Arachnid deterministic-deployment-proxy (https://github.com/Arachnid/deterministic-deployment-proxy)
/// @notice Explicit raw-salt CREATE2 calls to the canonical shared-contract deployer.
library ArachnidDeployer {
    address internal constant PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    /// @notice The EIP-1014 address for the unmodified salt and complete constructor initcode hash.
    function predict(bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", PROXY, salt, initCodeHash)))));
    }

    /// @notice Deploys through the proxy and validates its raw 20-byte return and the resulting code.
    function deploy(bytes32 salt, bytes memory initCode) internal returns (address deployed) {
        require(PROXY.code.length != 0, "ArachnidDeployer: install proxy 0x4e59b44847b379578588920cA78FbF26c0B4956C");
        (bool ok, bytes memory result) = PROXY.call(abi.encodePacked(salt, initCode));
        require(ok, "ArachnidDeployer: proxy deployment reverted");
        require(result.length == 20, "ArachnidDeployer: invalid proxy return");
        deployed = address(bytes20(result));
        require(deployed == predict(salt, keccak256(initCode)), "ArachnidDeployer: unexpected deployment address");
        require(deployed.code.length != 0, "ArachnidDeployer: empty deployment");
    }
}
