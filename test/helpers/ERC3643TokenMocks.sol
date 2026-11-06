// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";

/// @title ERC3643TokenIdentityMock
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Test-only ABI peer; no identity implementation or cryptography is imported.
contract ERC3643TokenIdentityMock {
    struct Claim {
        uint256 topic;
        uint256 scheme;
        address issuer;
        bytes signature;
        bytes data;
        string uri;
    }
    mapping(bytes32 => Claim) internal claims;
    mapping(bytes32 => bool) internal managers;

    function setManagement(address wallet, bool enabled) external {
        managers[keccak256(abi.encode(wallet))] = enabled;
    }

    function keyHasPurpose(bytes32 key, uint256 purpose) external view returns (bool) {
        return purpose == 1 && managers[key];
    }

    function setClaim(address issuer, uint256 topic, bytes calldata signature, bytes calldata data) external {
        claims[keccak256(abi.encode(issuer, topic))] = Claim(topic, 1, issuer, signature, data, "");
    }

    function getClaim(bytes32 id)
        external
        view
        returns (uint256, uint256, address, bytes memory, bytes memory, string memory)
    {
        Claim storage c = claims[id];
        return (c.topic, c.scheme, c.issuer, c.signature, c.data, c.uri);
    }
}

/// @title ERC3643TokenPolicyMock
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Test-only owner/binding peer and adversarial lifecycle callback.
contract ERC3643TokenPolicyMock is ICompliance {
    error PolicyFailure();
    address public owner;
    address internal bound;
    bool public permitted = true;
    bool public failChecks;
    bool public failCallbacks;
    uint256 public transfers;
    uint256 public creations;
    uint256 public destructions;
    address public reentryTarget;
    bytes public reentryData;
    bool public reentrySucceeded;
    bytes public reentryResult;
    uint256 public balanceSeen;
    uint256 public frozenSeen;

    constructor(address owner_) {
        owner = owner_;
    }

    function setOwner(address next) external {
        require(msg.sender == owner);
        owner = next;
    }

    function bindToken(address token) external {
        require(msg.sender == owner);
        require(token != address(0) && (bound == address(0) || bound == token));
        bound = token;
        emit TokenBound(token);
    }

    function unbindToken(address token) external {
        require(msg.sender == owner);
        require(token == bound && token != address(0));
        bound = address(0);
        emit TokenUnbound(token);
    }

    function getTokenBound() external view returns (address) {
        return bound;
    }

    function configure(bool allow, bool rejectChecks, bool rejectCallbacks) external {
        permitted = allow;
        failChecks = rejectChecks;
        failCallbacks = rejectCallbacks;
    }

    function setReentry(address target, bytes calldata data) external {
        reentryTarget = target;
        reentryData = data;
    }

    function canTransfer(address, address, uint256) external view returns (bool) {
        if (failChecks) revert PolicyFailure();
        return permitted;
    }

    function transferred(address from, address, uint256) external {
        _caller();
        ++transfers;
        _observe(from);
        _callback();
    }

    function created(address to, uint256) external {
        _caller();
        ++creations;
        _observe(to);
        _callback();
    }

    function destroyed(address from, uint256) external {
        _caller();
        ++destructions;
        _observe(from);
        _callback();
    }

    function _caller() private view {
        require(msg.sender == bound && bound != address(0));
    }

    function _observe(address wallet) private {
        balanceSeen = IERC20(bound).balanceOf(wallet);
        frozenSeen = IERC3643(bound).getFrozenTokens(wallet);
    }

    function _callback() private {
        if (reentryTarget != address(0)) (reentrySucceeded, reentryResult) = reentryTarget.call(reentryData);
        if (failCallbacks) revert PolicyFailure();
    }
}
