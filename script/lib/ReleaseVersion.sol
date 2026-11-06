// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ReleaseVersion
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Shared semver parser for release deployment and read-only observation.
library ReleaseVersion {
    error DeployRelease__MalformedVersion(string version);

    function packVersion(string memory version) internal pure returns (uint64 packed) {
        bytes memory b = bytes(version);
        uint256[3] memory parts;
        uint256 component;
        uint256 digits;
        for (uint256 i; i < b.length; ++i) {
            bytes1 c = b[i];
            if (c == ".") {
                if (digits == 0 || component == 2) revert DeployRelease__MalformedVersion(version);
                ++component;
                digits = 0;
            } else if (c >= "0" && c <= "9") {
                // Leading zeros are refused: "0.01.0" would pack identically to "0.1.0" while deriving
                // DIFFERENT facet salts — a duplicate facet set the registry would never serve.
                if (digits != 0 && parts[component] == 0) revert DeployRelease__MalformedVersion(version);
                parts[component] = parts[component] * 10 + (uint8(c) - 48);
                if (parts[component] > type(uint24).max) revert DeployRelease__MalformedVersion(version);
                ++digits;
            } else {
                revert DeployRelease__MalformedVersion(version);
            }
        }
        if (component != 2 || digits == 0 || parts[0] > type(uint16).max) {
            revert DeployRelease__MalformedVersion(version);
        }
        packed = (uint64(parts[0]) << 48) | (uint64(parts[1]) << 24) | uint64(parts[2]);
        if (packed == 0) revert DeployRelease__MalformedVersion(version);
    }
}
