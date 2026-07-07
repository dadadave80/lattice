// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    DispatchPost,
    IIsmpDispatcher,
    IncomingPostRequest,
    PostRequest
} from "@lattice/interfaces/external/IIsmpDispatcher.sol";
import {IIsmpModule} from "@lattice/interfaces/external/IIsmpModule.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title MockIsmpHost
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test fixture implementing the vendored {IIsmpDispatcher}: records every `dispatch` arg VERBATIM
///         (including the raw body bytes, the relayer fee and the REFUND-CRITICAL `payer`), charges
///         `perByteFee * body.length + fee` in a settable ERC-20 fee token via `transferFrom(msg.sender, ...)`
///         — exactly the way the real `EvmHost` collects fees from the dispatching contract — and returns a
///         deterministic commitment. `setPullShortfall` makes the host UNDER-pull so the adapter's defensive
///         delta-sweep path is testable. The `deliverPostRequest`/`timeoutPostRequest` drivers call the
///         module's `IIsmpModule` hooks so inbound tests run through the real facet exactly the way the host
///         invokes it.
contract MockIsmpHost is IIsmpDispatcher {
    address internal _feeToken;
    uint256 internal _perByteFee;
    uint256 public pullShortfall;

    bytes public lastDest;
    bytes public lastTo;
    bytes public lastBody;
    uint64 public lastTimeout;
    uint256 public lastFee;
    address public lastPayer;
    uint256 public lastValue;
    uint256 public dispatches;

    constructor(address feeToken_, uint256 perByteFee_) {
        _feeToken = feeToken_;
        _perByteFee = perByteFee_;
    }

    /// @notice The host can migrate its fee token — integrators must read it live (this setter proves it).
    function setFeeToken(address feeToken_) external {
        _feeToken = feeToken_;
    }

    function setPerByteFee(uint256 perByteFee_) external {
        _perByteFee = perByteFee_;
    }

    /// @notice Makes `dispatch` pull `shortfall` LESS than the quoted total, leaving fee-token dust on the
    ///         caller (the adapter) that its delta-sweep must return to the user.
    function setPullShortfall(uint256 shortfall) external {
        pullShortfall = shortfall;
    }

    function feeToken() external view returns (address) {
        return _feeToken;
    }

    function perByteFee(bytes memory) external view returns (uint256) {
        return _perByteFee;
    }

    function dispatch(DispatchPost memory request) external payable returns (bytes32 commitment) {
        lastDest = request.dest;
        lastTo = request.to;
        lastBody = request.body;
        lastTimeout = request.timeout;
        lastFee = request.fee;
        lastPayer = request.payer;
        lastValue = msg.value;

        uint256 total = _perByteFee * request.body.length + request.fee;
        IERC20(_feeToken).transferFrom(msg.sender, address(this), total - pullShortfall);

        commitment = keccak256(abi.encode("ismp-commitment", ++dispatches));
    }

    /// @notice Inbound driver: invokes the module's `onAccept` the way the real host does after proof
    ///         verification (so `msg.sender` inside the hook is this host).
    function deliverPostRequest(address module, PostRequest memory request, address relayer) external {
        IIsmpModule(module).onAccept(IncomingPostRequest({request: request, relayer: relayer}));
    }

    /// @notice Timeout driver: invokes the module's `onPostRequestTimeout` the way the real host does when a
    ///         dispatched request's timeout elapses unproven.
    function timeoutPostRequest(address module, PostRequest memory request) external {
        IIsmpModule(module).onPostRequestTimeout(request);
    }
}
