// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Base64} from "@lattice/utils/libraries/Base64.sol";
import {Strings} from "@lattice/utils/libraries/Strings.sol";

/// @title CCTPHookReceiptRenderer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Uniswap v4 Periphery (https://github.com/Uniswap/v4-periphery)
/// @notice Builds fully on-chain JSON + SVG metadata for an immutable CCTP delivery receipt.
library CCTPHookReceiptRenderer {
    struct RenderParams {
        uint256 tokenId;
        uint32 sourceDomain;
        bytes32 sender;
        address originalRecipient;
        uint256 amount;
        uint64 recordedAt;
        uint256 destinationChainId;
    }

    struct Display {
        string source;
        string destination;
        string amount;
        string sender;
        string recipient;
        string accent;
        string accent2;
    }

    function tokenURI(RenderParams memory p) internal pure returns (string memory) {
        string memory source = sourceLabel(p.sourceDomain);
        string memory destination = destinationLabel(p.destinationChainId);
        string memory amount = formatUSDC(p.amount);
        string memory sender = Strings.toHexString(uint256(p.sender), 32);
        string memory recipient = Strings.toHexString(p.originalRecipient);
        string memory image = string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(_svg(p))));
        bytes memory coreAttributes = _coreAttributes(p, amount, source);
        bytes memory routeAttributes = _routeAttributes(p, destination, sender, recipient);
        bytes memory json = abi.encodePacked(
            '{"name":"Lattice CCTP Receipt #',
            Strings.toString(p.tokenId),
            '","description":"On-chain proof that Circle CCTP v2 delivered USDC through a Lattice hook.",',
            '"image":"',
            image,
            '","attributes":[',
            coreAttributes,
            ",",
            routeAttributes,
            "]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(json));
    }

    function _coreAttributes(RenderParams memory p, string memory amount, string memory source)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            '{"trait_type":"Status","value":"Delivered"},',
            '{"trait_type":"Asset","value":"USDC"},',
            '{"trait_type":"Amount","value":"',
            amount,
            '"},',
            '{"trait_type":"Amount (uUSDC)","value":',
            Strings.toString(p.amount),
            "},",
            '{"trait_type":"Source CCTP Domain","value":',
            Strings.toString(p.sourceDomain),
            "},",
            '{"trait_type":"Source Label","value":"',
            source,
            '"}'
        );
    }

    function _routeAttributes(
        RenderParams memory p,
        string memory destination,
        string memory sender,
        string memory recipient
    ) private pure returns (bytes memory) {
        return abi.encodePacked(
            '{"trait_type":"CCTP Message Sender","value":"',
            sender,
            '"},',
            '{"trait_type":"Destination Chain ID","value":',
            Strings.toString(p.destinationChainId),
            "},",
            '{"trait_type":"Destination Label","value":"',
            destination,
            '"},',
            '{"trait_type":"Original Recipient","value":"',
            recipient,
            '"},',
            '{"trait_type":"Recorded At","value":',
            Strings.toString(p.recordedAt),
            "}"
        );
    }

    function formatUSDC(uint256 amount) internal pure returns (string memory) {
        uint256 whole = amount / 1e6;
        uint256 fraction = amount % 1e6;
        string memory raw = Strings.toString(fraction);
        bytes memory padded = new bytes(6);
        uint256 offset = 6 - bytes(raw).length;
        for (uint256 i; i < offset; ++i) {
            padded[i] = "0";
        }
        bytes memory rawBytes = bytes(raw);
        for (uint256 i; i < rawBytes.length; ++i) {
            padded[offset + i] = rawBytes[i];
        }
        return string.concat(Strings.toString(whole), ".", string(padded));
    }

    function sourceLabel(uint32 domain) internal pure returns (string memory) {
        if (domain == 0) return "ETHEREUM";
        if (domain == 6) return "BASE";
        if (domain == 26) return "ARC";
        return string.concat("DOMAIN ", Strings.toString(domain));
    }

    function destinationLabel(uint256 chainId) internal pure returns (string memory) {
        if (chainId == 1) return "ETHEREUM";
        if (chainId == 8453) return "BASE";
        if (chainId == 84532) return "BASE SEPOLIA";
        if (chainId == 11_155_111) return "SEPOLIA";
        if (chainId == 5_042_002) return "ARC TESTNET";
        return string.concat("CHAIN ", Strings.toString(chainId));
    }

    function _svg(RenderParams memory p) private pure returns (string memory) {
        uint256 seed = uint256(
            keccak256(
                abi.encode(p.tokenId, p.sourceDomain, p.sender, p.originalRecipient, p.amount, p.destinationChainId)
            )
        );
        Display memory d;
        d.source = sourceLabel(p.sourceDomain);
        d.destination = destinationLabel(p.destinationChainId);
        d.amount = formatUSDC(p.amount);
        d.sender = _short(Strings.toHexString(uint256(p.sender), 32), 10, 8);
        d.recipient = _short(Strings.toHexString(p.originalRecipient), 8, 6);
        (d.accent, d.accent2) = _palette(seed % 6);

        bytes memory top =
            abi.encodePacked(_shell(d), _circles(seed, d.accent, d.accent2), _header(p.tokenId, d.accent));
        bytes memory bottom = abi.encodePacked(
            _amountAndRoute(d.amount, d.source, d.destination),
            _facts(d.sender, d.recipient, p.recordedAt),
            _footer(d.accent),
            "</svg>"
        );
        return string(abi.encodePacked(top, bottom));
    }

    function _shell(Display memory d) private pure returns (bytes memory) {
        return abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 900">',
            "<defs>",
            '<linearGradient id="bg" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#07111f"/><stop offset="1" stop-color="#111827"/></linearGradient>',
            '<linearGradient id="route" x1="0" y1="0" x2="1" y2="0"><stop stop-color="',
            d.accent,
            '"/><stop offset="1" stop-color="',
            d.accent2,
            '"/></linearGradient>',
            "</defs>",
            '<rect width="600" height="900" rx="38" fill="url(#bg)"/>',
            '<rect x="18" y="18" width="564" height="864" rx="28" fill="none" stroke="',
            d.accent,
            '" stroke-opacity=".55" stroke-width="2"/>'
        );
    }

    function _header(uint256 tokenId, string memory accent) private pure returns (bytes memory) {
        return abi.encodePacked(
            '<text x="52" y="78" fill="#f8fafc" font-family="monospace" font-size="20" font-weight="700">LATTICE x CIRCLE</text>',
            '<text x="548" y="78" text-anchor="end" fill="',
            accent,
            '" font-family="monospace" font-size="18">#',
            Strings.toString(tokenId),
            "</text>"
        );
    }

    function _amountAndRoute(string memory amount, string memory source, string memory destination)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            '<text x="300" y="246" text-anchor="middle" fill="#f8fafc" font-family="sans-serif" font-size="58" font-weight="800">',
            amount,
            "</text>",
            '<text x="300" y="286" text-anchor="middle" fill="#94a3b8" font-family="monospace" font-size="20">USDC RECEIVED</text>',
            '<rect x="58" y="346" width="484" height="126" rx="22" fill="#0f172a" stroke="#334155"/>',
            '<text x="104" y="413" fill="#f8fafc" font-family="monospace" font-size="24" font-weight="700">',
            source,
            "</text>",
            '<line x1="245" y1="405" x2="355" y2="405" stroke="url(#route)" stroke-width="7" stroke-linecap="round"/>',
            '<path d="M346 393 L362 405 L346 417" fill="none" stroke="#f8fafc" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>',
            '<text x="496" y="413" text-anchor="end" fill="#f8fafc" font-family="monospace" font-size="24" font-weight="700">',
            destination,
            "</text>"
        );
    }

    function _facts(string memory sender, string memory recipient, uint64 recordedAt)
        private
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(
            '<text x="58" y="550" fill="#64748b" font-family="monospace" font-size="16">SOURCE CONTRACT</text>',
            '<text x="58" y="584" fill="#e2e8f0" font-family="monospace" font-size="22">',
            sender,
            "</text>",
            '<text x="58" y="654" fill="#64748b" font-family="monospace" font-size="16">ORIGINAL RECIPIENT</text>',
            '<text x="58" y="688" fill="#e2e8f0" font-family="monospace" font-size="22">',
            recipient,
            "</text>",
            '<text x="58" y="758" fill="#64748b" font-family="monospace" font-size="16">RECORDED AT</text>',
            '<text x="58" y="792" fill="#e2e8f0" font-family="monospace" font-size="22">',
            Strings.toString(recordedAt),
            "</text>"
        );
    }

    function _footer(string memory accent) private pure returns (bytes memory) {
        return abi.encodePacked(
            '<circle cx="64" cy="840" r="10" fill="',
            accent,
            '"/><path d="M59 840 l4 4 7-9" fill="none" stroke="#07111f" stroke-width="3"/>',
            '<text x="86" y="847" fill="#f8fafc" font-family="monospace" font-size="20" font-weight="700">DELIVERED - CCTP V2</text>'
        );
    }

    function _circles(uint256 seed, string memory accent, string memory accent2) private pure returns (bytes memory) {
        return abi.encodePacked(
            '<circle cx="',
            Strings.toString(80 + seed % 440),
            '" cy="',
            Strings.toString(110 + (seed >> 16) % 220),
            '" r="150" fill="',
            accent,
            '" opacity=".07"/>',
            '<circle cx="',
            Strings.toString(80 + (seed >> 32) % 440),
            '" cy="',
            Strings.toString(480 + (seed >> 48) % 300),
            '" r="210" fill="',
            accent2,
            '" opacity=".05"/>'
        );
    }

    function _palette(uint256 index) private pure returns (string memory accent, string memory accent2) {
        if (index == 0) return ("#22d3ee", "#3b82f6");
        if (index == 1) return ("#a78bfa", "#ec4899");
        if (index == 2) return ("#34d399", "#22d3ee");
        if (index == 3) return ("#f59e0b", "#ef4444");
        if (index == 4) return ("#60a5fa", "#8b5cf6");
        return ("#2dd4bf", "#84cc16");
    }

    function _short(string memory value, uint256 leading, uint256 trailing) private pure returns (string memory) {
        bytes memory input = bytes(value);
        if (input.length <= leading + trailing + 3) return value;
        bytes memory output = new bytes(leading + trailing + 3);
        for (uint256 i; i < leading; ++i) {
            output[i] = input[i];
        }
        output[leading] = ".";
        output[leading + 1] = ".";
        output[leading + 2] = ".";
        for (uint256 i; i < trailing; ++i) {
            output[leading + 3 + i] = input[input.length - trailing + i];
        }
        return string(output);
    }
}
