// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IAddrResolver} from "@lattice/interfaces/external/ens/IAddrResolver.sol";
import {IENS} from "@lattice/interfaces/external/ens/IENS.sol";
import {IPermissionedResolver} from "@lattice/interfaces/external/ens/IPermissionedResolver.sol";
import {IUniversalResolverV2} from "@lattice/interfaces/external/ens/IUniversalResolverV2.sol";
import {Test} from "forge-std/Test.sol";

struct RehearsalGrant {
    address account;
    uint256 roleBitmap;
}

struct MigrationData {
    string label;
    address owner;
    address subregistry;
    address resolver;
}

interface IRehearsalFactory {
    function deployProxy(address implementation, uint256 salt, bytes calldata init) external returns (address);
}

interface IRehearsalRegistry {
    function hasRoles(uint256 id, uint256 roles, address account) external view returns (bool);
    function setParent(address parent, string calldata label) external;
    function register(
        string calldata label,
        address owner,
        address subregistry,
        address resolver,
        uint256 roles,
        uint64 expiry
    ) external returns (uint256);
    function getStatus(uint256 id) external view returns (uint8);
    function getOwner(uint256 id) external view returns (address);
    function getExpiry(uint256 id) external view returns (uint64);
    function getSubregistry(string calldata label) external view returns (address);
}

interface IRehearsalBase {
    function ownerOf(uint256 id) external view returns (address);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

/// @title Sepolia studio.eth migration rehearsal
/// @author David Dada
/// @author Modified from ENSv2 (https://github.com/ensdomains/contracts-v2/tree/07e55a056f5b6a9c90119f501bdd05714e67dddd/contracts)
/// @notice Replays the existing estate against deployed ENS contracts inside a disposable fork.
contract ENSV2StudioMigrationFork is Test {
    address constant OWNER = 0xDAdaDA4E8038641212262Fd94E816d4A57CDC751;
    address constant ETH = 0xD4eBcbBdF463C9c45784603Db0dDD499BC44A8B4;
    address constant FACTORY = 0xDa70306C98E97eCe36F997a21368e53298572991;
    address constant MIGRATOR = 0x2a35B94DF22cc7354570be2284655E2CDC0e64A2;
    address constant USER_IMPL = 0x9BD8a88719068D09ecee662f36C0E3856708366a;
    address constant RESOLVER_IMPL = 0x115eb53F0c60696633855F90b138178Fb40b2b2C;
    address constant MIRROR = 0x322B7581cA210a69c6D0e0D7c88a7688D2789Cb0;
    IRehearsalBase constant BASE = IRehearsalBase(0x57f1887a8BF19b14fC0dF6Fd9B2acc9Af147eA85);
    IUniversalResolverV2 constant UR = IUniversalResolverV2(0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe);
    uint256 constant STUDIO = uint256(keccak256("studio"));
    // Token owner may manage resolver and child registry and delegate those rights or transfer.
    uint256 constant RECORD_ROLES = (1 << 20) | (1 << 24);
    uint256 constant OWNER_ROLES = RECORD_ROLES | ((RECORD_ROLES | (1 << 28)) << 128);
    bytes constant PARENT = hex"076c6174746963650673747564696f0365746800";
    string[3] labels = ["milestone1vault", "factory", "registry"];
    address[3] targets = [
        0x7a498c34A8Dc3B6502889C21218Da0F8696b7bb6,
        0x9E49FB5CDBb09ECf65513F7c690909E093170037,
        0x563f372b4E970fe9976cFFeec614d07a2c353684
    ];

    function setUp() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc, vm.envOr("ENSV2_REHEARSAL_BLOCK", uint256(12_208_978)));
        assertEq(block.chainid, 11155111);
    }

    function _dns(uint256 i) private view returns (bytes memory) {
        bytes memory label = bytes(labels[i]);
        return bytes.concat(bytes1(uint8(label.length)), label, PARENT);
    }

    function _checkNames(address expectedResolver) private view {
        for (uint256 i; i < labels.length; ++i) {
            bytes memory dns = _dns(i);
            (, bytes32 node,) = UR.findResolver(dns);
            (bytes memory record, address viaResolver) = UR.resolve(dns, abi.encodeCall(IAddrResolver.addr, (node)));
            assertEq(abi.decode(record, (address)), targets[i]);
            assertEq(viaResolver, expectedResolver);
            (string memory primary,,) = UR.reverse(abi.encodePacked(targets[i]), 60);
            assertEq(primary, string.concat(labels[i], ".lattice.studio.eth"));
        }
    }

    function _checkLegacyOwner(bytes memory name, address expectedResolver) private view {
        (, bytes32 node,) = UR.findResolver(name);
        IENS legacy = IENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);
        assertEq(legacy.owner(node), OWNER);
        assertEq(legacy.resolver(node), expectedResolver);
    }

    function _stage() private returns (address studio, address lattice, address resolver) {
        RehearsalGrant[] memory grants = new RehearsalGrant[](1);
        grants[0] = RehearsalGrant(OWNER, 1 | (1 << 8)); // registrar and set-parent
        bytes memory init = abi.encodeWithSignature("initialize((address,uint256)[])", grants);
        studio = IRehearsalFactory(FACTORY).deployProxy(USER_IMPL, 1, init);
        lattice = IRehearsalFactory(FACTORY).deployProxy(USER_IMPL, 2, init);
        grants[0].roleBitmap = 1; // set-address
        resolver = IRehearsalFactory(FACTORY)
            .deployProxy(
                RESOLVER_IMPL,
                3,
                abi.encodeWithSignature("initialize((address,uint256)[],bytes[])", grants, new bytes[](0))
            );
        IRehearsalRegistry(studio).setParent(ETH, "studio");
        IRehearsalRegistry(lattice).setParent(studio, "lattice");
        uint64 expiry = IRehearsalRegistry(ETH).getExpiry(STUDIO);
        IRehearsalRegistry(studio).register("lattice", OWNER, lattice, resolver, OWNER_ROLES, expiry);
        for (uint256 i; i < labels.length; ++i) {
            IRehearsalRegistry(lattice).register(labels[i], OWNER, address(0), resolver, OWNER_ROLES, expiry);
            IPermissionedResolver(resolver).setAddress(_dns(i), 60, abi.encodePacked(targets[i]));
        }
    }

    function test_RehearseUnwrappedStudioMigration() public {
        assertTrue(UR.isENSv2());
        assertEq(BASE.ownerOf(STUDIO), OWNER);
        assertEq(IRehearsalRegistry(ETH).getStatus(STUDIO), 1);
        assertEq(IRehearsalRegistry(ETH).getSubregistry("studio"), address(0));
        address publicResolver = 0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5;
        _checkLegacyOwner(hex"0673747564696f0365746800", address(0));
        _checkLegacyOwner(PARENT, publicResolver);
        for (uint256 i; i < labels.length; ++i) {
            _checkLegacyOwner(_dns(i), publicResolver);
        }
        _checkNames(MIRROR);
        vm.startPrank(OWNER);
        (address studio, address lattice, address resolver) = _stage();
        MigrationData memory md = MigrationData("studio", OWNER, studio, address(0));
        vm.expectRevert(bytes4(keccak256("InvalidData()")));
        BASE.safeTransferFrom(OWNER, MIGRATOR, STUDIO, hex"00");
        assertEq(BASE.ownerOf(STUDIO), OWNER);
        BASE.safeTransferFrom(OWNER, MIGRATOR, STUDIO, abi.encode(md));
        vm.stopPrank();
        assertEq(IRehearsalRegistry(ETH).getStatus(STUDIO), 2);
        assertEq(IRehearsalRegistry(ETH).getOwner(STUDIO), OWNER);
        assertEq(IRehearsalRegistry(ETH).getSubregistry("studio"), studio);
        assertEq(IRehearsalRegistry(studio).getSubregistry("lattice"), lattice);
        _checkNames(resolver);
        for (uint256 i; i < labels.length; ++i) {
            uint256 id = uint256(keccak256(bytes(labels[i])));
            assertEq(IRehearsalRegistry(lattice).getOwner(id), OWNER);
            assertEq(IRehearsalRegistry(lattice).getExpiry(id), IRehearsalRegistry(ETH).getExpiry(STUDIO));
            assertTrue(IRehearsalRegistry(lattice).hasRoles(id, OWNER_ROLES, OWNER));
        }
    }
}
