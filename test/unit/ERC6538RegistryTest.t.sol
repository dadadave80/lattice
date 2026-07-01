// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC6538RegistryTestBase} from "@lattice-test/base/ERC6538RegistryTestBase.sol";
import {IERC6538Registry} from "@lattice/interfaces/privacy/IERC6538Registry.sol";
import {ERC6538Registry} from "@lattice/privacy/ERC6538Registry.sol";

/// @title Mock1271Wallet
/// @notice Minimal ERC-1271 wallet that accepts a signature iff it recovers to a fixed owner key.
contract Mock1271Wallet {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        if (signature.length != 65) return 0xffffffff;
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }
        return ecrecover(hash, v, r, s) == owner ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
    }
}

/// @title ERC6538RegistryTest
/// @notice Exercises the ERC-6538 stealth meta-address registry through a REAL {Diamond} assembled by the
///         ready-to-deploy {DeployERC6538Registry} script (see {ERC6538RegistryTestBase}) — every registration and
///         the EIP-712 `registerKeysOnBehalf` signature path route through the diamond's `delegatecall` dispatch,
///         not a flattened inheritance mock. The registry facet `is EIP712`, so `DOMAIN_SEPARATOR`/`eip712Domain`
///         are served by the same facet; `supportsInterface` by the cut-in `ERC165Facet`. `Mock1271Wallet` is kept
///         as a test fixture (it is NOT the facet under test).
contract ERC6538RegistryTest is ERC6538RegistryTestBase {
    uint256 registrantKey = 0xA11CE;
    address registrant;
    address relayer = address(0xBEEF);

    uint256 constant SCHEME_ID = 1;

    event StealthMetaAddressSet(address indexed registrant, uint256 indexed schemeId, bytes stealthMetaAddress);
    event NonceIncremented(address indexed registrant, uint256 newNonce);

    function setUp() public {
        registrant = vm.addr(registrantKey);
        diamond = _deployERC6538Registry();
        registry = ERC6538Registry(diamond);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    function _meta() internal pure returns (bytes memory) {
        return hex"03a1b2c3d4e5f6a7b8c9dae1f2031405";
    }

    function _entryTypeHash() internal pure returns (bytes32) {
        return keccak256("Erc6538RegistryEntry(uint256 schemeId,bytes stealthMetaAddress,uint256 nonce)");
    }

    function _entryDigest(uint256 schemeId, bytes memory sma, uint256 nonce) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(_entryTypeHash(), schemeId, keccak256(sma), nonce));
        return keccak256(abi.encodePacked("\x19\x01", registry.DOMAIN_SEPARATOR(), structHash));
    }

    function _sign(bytes32 digest, uint256 key) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            registerKeys (self)
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterKeysStoresAndEmits() public {
        vm.expectEmit(true, true, false, true, address(registry));
        emit StealthMetaAddressSet(registrant, SCHEME_ID, _meta());

        vm.prank(registrant);
        registry.registerKeys(SCHEME_ID, _meta());

        assertEq(registry.stealthMetaAddressOf(registrant, SCHEME_ID), _meta());
    }

    function test_RegisterKeysOverwriteLastWriteWins() public {
        bytes memory meta2 = hex"04ddccbbaa";
        vm.startPrank(registrant);
        registry.registerKeys(SCHEME_ID, _meta());
        registry.registerKeys(SCHEME_ID, meta2);
        vm.stopPrank();
        assertEq(registry.stealthMetaAddressOf(registrant, SCHEME_ID), meta2);
    }

    function test_UnsetReturnsEmpty() public view {
        assertEq(registry.stealthMetaAddressOf(address(0xDEAD), SCHEME_ID), "");
    }

    function test_RegisterKeysAllowsEmptyMeta() public {
        vm.prank(registrant);
        registry.registerKeys(SCHEME_ID, "");
        assertEq(registry.stealthMetaAddressOf(registrant, SCHEME_ID), "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            registerKeysOnBehalf
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterKeysOnBehalfValid() public {
        uint256 nonce = registry.nonceOf(registrant);
        bytes memory sig = _sign(_entryDigest(SCHEME_ID, _meta(), nonce), registrantKey);

        vm.prank(relayer);
        registry.registerKeysOnBehalf(registrant, SCHEME_ID, sig, _meta());

        assertEq(registry.stealthMetaAddressOf(registrant, SCHEME_ID), _meta());
        assertEq(registry.nonceOf(registrant), nonce + 1);
    }

    function test_RegisterKeysOnBehalfBadSignatureReverts() public {
        uint256 nonce = registry.nonceOf(registrant);
        bytes memory sig = _sign(_entryDigest(SCHEME_ID, _meta(), nonce), 0xBAD);

        vm.expectRevert(IERC6538Registry.ERC6538Registry__InvalidSignature.selector);
        registry.registerKeysOnBehalf(registrant, SCHEME_ID, sig, _meta());
    }

    function test_RegisterKeysOnBehalfReplayReverts() public {
        uint256 nonce = registry.nonceOf(registrant);
        bytes memory sig = _sign(_entryDigest(SCHEME_ID, _meta(), nonce), registrantKey);

        registry.registerKeysOnBehalf(registrant, SCHEME_ID, sig, _meta());

        // Nonce advanced; the same signature no longer verifies against the new nonce.
        vm.expectRevert(IERC6538Registry.ERC6538Registry__InvalidSignature.selector);
        registry.registerKeysOnBehalf(registrant, SCHEME_ID, sig, _meta());
    }

    function test_NonceRollsBackAfterFailedOnBehalf() public {
        uint256 nonce = registry.nonceOf(registrant);
        bytes memory sig = _sign(_entryDigest(SCHEME_ID, _meta(), nonce), 0xBAD);

        vm.expectRevert(IERC6538Registry.ERC6538Registry__InvalidSignature.selector);
        registry.registerKeysOnBehalf(registrant, SCHEME_ID, sig, _meta());

        assertEq(registry.nonceOf(registrant), nonce, "nonce must roll back on failed verification");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          ERC-1271 contract signer
    //////////////////////////////////////////////////////////////////////////*//

    function test_RegisterKeysOnBehalfERC1271() public {
        Mock1271Wallet wallet = new Mock1271Wallet(registrant);
        uint256 nonce = registry.nonceOf(address(wallet));
        bytes memory sig = _sign(_entryDigest(SCHEME_ID, _meta(), nonce), registrantKey);

        registry.registerKeysOnBehalf(address(wallet), SCHEME_ID, sig, _meta());

        assertEq(registry.stealthMetaAddressOf(address(wallet), SCHEME_ID), _meta());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               incrementNonce
    //////////////////////////////////////////////////////////////////////////*//

    function test_IncrementNonceEmitsAndBumps() public {
        uint256 nonce = registry.nonceOf(registrant);
        vm.expectEmit(true, false, false, true, address(registry));
        emit NonceIncremented(registrant, nonce + 1);

        vm.prank(registrant);
        registry.incrementNonce();

        assertEq(registry.nonceOf(registrant), nonce + 1);
    }

    function test_IncrementNonceInvalidatesSignature() public {
        uint256 nonce = registry.nonceOf(registrant);
        bytes memory sig = _sign(_entryDigest(SCHEME_ID, _meta(), nonce), registrantKey);

        vm.prank(registrant);
        registry.incrementNonce();

        vm.expectRevert(IERC6538Registry.ERC6538Registry__InvalidSignature.selector);
        registry.registerKeysOnBehalf(registrant, SCHEME_ID, sig, _meta());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   MISC
    //////////////////////////////////////////////////////////////////////////*//

    function test_EntryTypeHashMatchesCanonical() public view {
        assertEq(registry.ERC6538REGISTRY_ENTRY_TYPE_HASH(), _entryTypeHash(), "entry typehash diverged from canonical");
    }

    function test_DomainSeparatorIsNonZero() public view {
        assertNotEq(registry.DOMAIN_SEPARATOR(), bytes32(0));
    }

    function test_SupportsIERC6538Registry() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC6538Registry).interfaceId));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IERC6538Registry).interfaceId, bytes4(0x7b1f57cb), "IERC6538Registry interfaceId moved");
    }
}
