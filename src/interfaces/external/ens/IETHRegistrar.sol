// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IETHRegistrar
/// @author Vendored minimal subset of ENSv2 ETHRegistrar (https://github.com/ensdomains/contracts-v2/blob/07e55a056f5b6a9c90119f501bdd05714e67dddd/contracts/src/registrar/ETHRegistrar.sol).
///         Upstream license: MIT.
/// @notice Commit/reveal registration of new second-level .eth labels using an accepted ERC-20.
interface IETHRegistrar {
    function ETH_REGISTRY() external view returns (address);
    function MIN_COMMITMENT_AGE() external view returns (uint64);
    function MAX_COMMITMENT_AGE() external view returns (uint64);
    function MIN_REGISTER_DURATION() external view returns (uint64);
    function commitmentAt(bytes32 hash) external view returns (uint64);
    function makeCommitment(
        string calldata label,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint64 duration,
        bytes32 referrer
    ) external pure returns (bytes32);
    function commit(bytes32 hash) external;
    function isAvailable(string calldata label) external view returns (bool);
    function getRegisterPrice(string calldata label, uint64 duration, address paymentToken)
        external
        view
        returns (uint256 base, uint256 premium);
    function register(
        string calldata label,
        address owner,
        bytes32 secret,
        address subregistry,
        address resolver,
        uint64 duration,
        address paymentToken,
        bytes32 referrer
    ) external returns (uint256 tokenId);
}
