// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {IEIP712} from "@lattice/interfaces/utils/IEIP712.sol";
import {EIP712} from "@lattice/utils/EIP712.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockEIP712Contract
/// @notice Mock contract with EIP712 facet and initialization for testing.
contract MockEIP712Contract is EIP712, Initializable {
    /// @notice Initialize EIP-712 with the given name and version.
    function initialize(string memory name, string memory version) external initializer {
        EIP712Lib.__EIP712_init(name, version);
    }

    /// @notice Exposes domainSeparatorV4 for testing.
    function domainSeparatorV4() external view returns (bytes32) {
        return EIP712Lib.domainSeparatorV4();
    }

    /// @notice Exposes hashTypedDataV4 for testing.
    function hashTypedDataV4(bytes32 structHash) external view returns (bytes32) {
        return EIP712Lib.hashTypedDataV4(structHash);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

contract EIP712Test is Test {
    MockEIP712Contract eip712;

    string constant NAME = "MyApp";
    string constant VERSION = "1";

    // EIP-712 type hash for the domain struct
    bytes32 constant DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    function setUp() public {
        eip712 = new MockEIP712Contract();
        eip712.initialize(NAME, VERSION);
    }

    // -------------------------------------------------------------------------
    // eip712Domain() returns expected fields
    // -------------------------------------------------------------------------

    function test_EIP712Domain_Fields() public view {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = eip712.eip712Domain();

        assertEq(fields, hex"0f");
        assertEq(name, NAME);
        assertEq(version, VERSION);
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(eip712));
        assertEq(salt, bytes32(0));
        assertEq(extensions.length, 0);
    }

    // -------------------------------------------------------------------------
    // domainSeparatorV4 matches manually computed value
    // -------------------------------------------------------------------------

    function test_DomainSeparatorV4_MatchesManual() public view {
        bytes32 expected = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(eip712)
            )
        );
        assertEq(eip712.domainSeparatorV4(), expected);
    }

    // -------------------------------------------------------------------------
    // hashTypedDataV4 matches \x19\x01 ++ domain ++ struct
    // -------------------------------------------------------------------------

    function test_HashTypedDataV4_MatchesManual() public view {
        bytes32 structHash = keccak256("Transfer(address to,uint256 amount)");
        bytes32 domainSep = eip712.domainSeparatorV4();
        bytes32 expected = keccak256(abi.encodePacked("\x19\x01", domainSep, structHash));
        assertEq(eip712.hashTypedDataV4(structHash), expected);
    }

    // -------------------------------------------------------------------------
    // Chain ID change forces recomputation of domain separator
    // -------------------------------------------------------------------------

    function test_ChainIdChange_ForcesDomainRecompute() public {
        bytes32 originalDomain = eip712.domainSeparatorV4();

        // Switch to a different chain ID
        vm.chainId(9999);

        bytes32 newDomain = eip712.domainSeparatorV4();

        // Domain separator should have changed
        assertTrue(newDomain != originalDomain, "domain separator should differ after chainId change");

        // Verify the new domain is correctly computed for chain 9999
        bytes32 expected = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), uint256(9999), address(eip712)
            )
        );
        assertEq(newDomain, expected);
    }

    // -------------------------------------------------------------------------
    // ERC-165 interface registration
    // -------------------------------------------------------------------------

    function test_SupportsIEIP712Interface() public view {
        assertTrue(eip712.supportsInterface(type(IEIP712).interfaceId));
    }

    // -------------------------------------------------------------------------
    // Long name/version (>31 bytes) with fallback storage
    // -------------------------------------------------------------------------

    function test_LongNameAndVersion() public {
        MockEIP712Contract longEip712 = new MockEIP712Contract();
        string memory longName = "VeryLongApplicationNameThatExceedsThirtyOne";
        string memory longVersion = "2.0.0-release-candidate-1-final";
        longEip712.initialize(longName, longVersion);

        (, string memory name, string memory version,,,,) = longEip712.eip712Domain();
        assertEq(name, longName);
        assertEq(version, longVersion);

        // Domain separator should still be computed correctly
        bytes32 expected = keccak256(
            abi.encode(
                DOMAIN_TYPE_HASH,
                keccak256(bytes(longName)),
                keccak256(bytes(longVersion)),
                block.chainid,
                address(longEip712)
            )
        );
        assertEq(longEip712.domainSeparatorV4(), expected);
    }
}
