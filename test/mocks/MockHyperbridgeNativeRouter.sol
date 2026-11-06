// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IMockHyperbridgeFeeMint {
    function mint(address to, uint256 amount) external;
}

/// @title MockHyperbridgeNativeRouter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Hyperbridge (https://github.com/polytope-labs/hyperbridge)
/// @notice Native exact-output fee fixture; surplus returns to the caller, which is the host.
contract MockHyperbridgeNativeRouter {
    uint256 public quotedNative;
    uint256 public spentNative;
    uint256 public quoteCalls;
    address public quotedInput;
    address public quotedOutput;
    uint256 public quotedFee;
    address public quoteHook;
    bytes public quoteHookData;
    uint256 public quoteHookValue;
    bool public hookDuringSwap;
    bool public hookSucceeded;
    bytes public hookResult;
    address public donationRecipient;
    uint256 public quoteDonation;

    constructor(uint256 nativeCost) {
        quotedNative = nativeCost;
        spentNative = nativeCost;
    }

    function WETH() external pure returns (address) {
        return address(0xC0FFEE);
    }

    function setCosts(uint256 quoted, uint256 spent) external {
        quotedNative = quoted;
        spentNative = spent;
    }

    function setQuoteHook(address target, bytes calldata data, uint256 value) external {
        quoteHook = target;
        quoteHookData = data;
        quoteHookValue = value;
        hookDuringSwap = false;
    }

    function setSwapHook(address target, bytes calldata data, uint256 value) external {
        quoteHook = target;
        quoteHookData = data;
        quoteHookValue = value;
        hookDuringSwap = true;
    }

    function setQuoteDonation(address recipient, uint256 value) external {
        donationRecipient = recipient;
        quoteDonation = value;
    }

    /// @dev Deliberately writes state: a STATICCALL declaration cannot support current quote wrappers.
    function getAmountsIn(uint256 output, address[] calldata path) external returns (uint256[] memory amounts) {
        require(path.length == 2 && path[0] == address(0xC0FFEE), "native fixture: invalid path");
        ++quoteCalls;
        quotedInput = path[0];
        quotedOutput = path[1];
        quotedFee = output;
        if (quoteHook != address(0) && !hookDuringSwap) {
            (hookSucceeded, hookResult) = quoteHook.call{value: quoteHookValue}(quoteHookData);
        }
        if (quoteDonation != 0) {
            (bool ok,) = donationRecipient.call{value: quoteDonation}("");
            require(ok, "native fixture: donation failed");
        }
        amounts = new uint256[](2);
        amounts[0] = quotedNative;
        amounts[1] = output;
    }

    function swapETHForExactTokens(uint256 output, address[] calldata path, address recipient, uint256)
        external
        payable
        returns (uint256[] memory amounts)
    {
        require(path.length == 2 && path[0] == address(0xC0FFEE), "native fixture: invalid swap path");
        require(msg.value >= spentNative, "native fixture: insufficient value");
        if (quoteHook != address(0) && hookDuringSwap) {
            (hookSucceeded, hookResult) = quoteHook.call{value: quoteHookValue}(quoteHookData);
        }
        IMockHyperbridgeFeeMint(path[1]).mint(recipient, output);
        if (msg.value > spentNative) {
            (bool ok,) = msg.sender.call{value: msg.value - spentNative}("");
            require(ok, "native fixture: refund failed");
        }
        amounts = new uint256[](2);
        amounts[0] = spentNative;
        amounts[1] = output;
    }
}
