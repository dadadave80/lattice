// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MockHyperbridgeNativeRouter} from "@lattice-test/mocks/MockHyperbridgeNativeRouter.sol";
import {
    DispatchPost,
    IIsmpDispatcher,
    IncomingPostRequest,
    PostRequest
} from "@lattice/interfaces/external/hyperbridge/IIsmpDispatcher.sol";
import {IIsmpModule} from "@lattice/interfaces/external/hyperbridge/IIsmpModule.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";

/// @title MockIsmpHost
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Hyperbridge (https://github.com/polytope-labs/hyperbridge)
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
    address public nativeRouter;
    bool public forwardNativeSurplus;
    uint256 public dispatchNativePayout;

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

    function setNativeRouter(address router) external {
        nativeRouter = router;
    }

    /// @notice Nonstandard control: forwards router surplus to the adapter instead of retaining it.
    function setForwardNativeSurplus(bool enabled) external {
        forwardNativeSurplus = enabled;
    }

    /// @notice Adversarial custody control: spend part of the host's standing native balance.
    function setDispatchNativePayout(uint256 amount) external {
        dispatchNativePayout = amount;
    }

    function uniswapV2Router() external view returns (address) {
        return nativeRouter;
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
        if (msg.value != 0) {
            uint256 nativeBefore = address(this).balance - msg.value;
            address[] memory path = new address[](2);
            path[0] = MockHyperbridgeNativeRouter(nativeRouter).WETH();
            path[1] = _feeToken;
            MockHyperbridgeNativeRouter(nativeRouter).swapETHForExactTokens{value: msg.value}(
                total, path, address(this), block.timestamp
            );
            if (forwardNativeSurplus && address(this).balance > nativeBefore) {
                (bool ok,) = msg.sender.call{value: address(this).balance - nativeBefore}("");
                require(ok, "native fixture: adapter rejected refund");
            }
            if (dispatchNativePayout != 0) {
                (bool ok,) = request.payer.call{value: dispatchNativePayout}("");
                require(ok, "native fixture: payout rejected");
            }
        } else {
            IERC20(_feeToken).transferFrom(msg.sender, address(this), total - pullShortfall);
        }

        commitment = keccak256(abi.encode("ismp-commitment", ++dispatches));
    }

    receive() external payable {}

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

    /// @notice Source-faithful refund destination/asset control, not a proof/timeout validation fixture.
    function refundLastDispatchTimeout(address module, PostRequest memory request) external {
        IIsmpModule(module).onPostRequestTimeout(request);
        uint256 relayerFee = lastFee;
        lastFee = 0;
        IERC20(_feeToken).transfer(lastPayer, relayerFee);
    }
}
