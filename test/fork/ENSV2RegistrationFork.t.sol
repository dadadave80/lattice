// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ENSResolverV2TestBase} from "../base/ENSResolverV2TestBase.sol";
import {ENSSubnameIssuerV2TestBase} from "../base/ENSSubnameIssuerV2TestBase.sol";
import {IRehearsalFactory, IRehearsalRegistry, RehearsalGrant} from "./ENSV2StudioMigrationFork.t.sol";
import {IETHRegistryRecords, RegisterEnsName} from "@lattice-script/config/RegisterEnsName.s.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IENSResolverV2} from "@lattice/interfaces/ens/IENSResolverV2.sol";
import {IAddrResolver} from "@lattice/interfaces/external/ens/IAddrResolver.sol";
import {IETHRegistrar} from "@lattice/interfaces/external/ens/IETHRegistrar.sol";
import {IPermissionedResolver} from "@lattice/interfaces/external/ens/IPermissionedResolver.sol";
import {IReverseRegistrar} from "@lattice/interfaces/external/ens/IReverseRegistrar.sol";
import {IUniversalHelper} from "@lattice/interfaces/external/ens/IUniversalHelper.sol";
import {IUniversalResolverV2} from "@lattice/interfaces/external/ens/IUniversalResolverV2.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title Native ENSv2 registration and Lattice issuance on Sepolia
/// @author David Dada
/// @author Modified from ENSv2 (https://github.com/ensdomains/contracts-v2/tree/07e55a056f5b6a9c90119f501bdd05714e67dddd/contracts)
contract ENSV2RegistrationFork is ENSResolverV2TestBase, ENSSubnameIssuerV2TestBase {
    IETHRegistrar constant REGISTRAR = IETHRegistrar(0xf633e7FC17e2bbE0D0965D18ec1821dcB754a3d3);
    IETHRegistryRecords constant ETH = IETHRegistryRecords(0xD4eBcbBdF463C9c45784603Db0dDD499BC44A8B4);
    IERC20 constant TOKEN = IERC20(0x240b0316Df57887DBBE58b586508b19e633a14aa);
    IRehearsalFactory constant FACTORY = IRehearsalFactory(0xDa70306C98E97eCe36F997a21368e53298572991);
    address constant REGISTRY_IMPL = 0x9BD8a88719068D09ecee662f36C0E3856708366a;
    address constant RESOLVER_IMPL = 0x115eb53F0c60696633855F90b138178Fb40b2b2C;
    IUniversalResolverV2 constant UR = IUniversalResolverV2(0xeEeEEEeE14D718C2B47D9923Deab1335E144EeEe);
    address constant HELPER = address(bytes20(hex"d453e5bdb62cc3bea84341b1e306319c8ffd7dfe"));
    IReverseRegistrar constant REVERSE = IReverseRegistrar(0xA0a1AbcDAe1a2a4A2EF8e9113Ff0e02DD81DC0C6);
    string constant LABEL = "latticev2rehearsal";
    bytes constant NAME = hex"126c617474696365763272656865617273616c0365746800";

    address owner;
    address payer;
    RegisterEnsName script;
    IPermissionedResolver resolver;
    IRehearsalRegistry parent;
    IENSResolverV2 forward;

    function setUp() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) vm.skip(true);
        vm.createSelectFork(rpc, vm.envOr("ENSV2_REHEARSAL_BLOCK", uint256(12_208_978)));
        assertEq(block.chainid, 11155111);
        assertTrue(UR.isENSv2());
        owner = makeAddr("v2 name owner");
        payer = address(this);
        script = new RegisterEnsName();
        forward = _deployENSResolverV2(owner, address(UR));
        _deployENSSubnameIssuerV2(owner, HELPER);
        vm.prank(owner);
        IAccessControl(diamond).grantRole(keccak256("ENS_V2_SUBNAME_ISSUER_ROLE"), owner);

        RehearsalGrant[] memory registryGrants = new RehearsalGrant[](2);
        registryGrants[0] = RehearsalGrant(diamond, 1); // ROOT_RESOURCE ROLE_REGISTRAR
        registryGrants[1] = RehearsalGrant(owner, 1 << 8); // ROLE_SET_PARENT
        parent = IRehearsalRegistry(
            FACTORY.deployProxy(
                REGISTRY_IMPL, 1, abi.encodeWithSignature("initialize((address,uint256)[])", registryGrants)
            )
        );
        vm.prank(owner);
        parent.setParent(address(ETH), LABEL);
        RehearsalGrant[] memory resolverGrants = new RehearsalGrant[](1);
        resolverGrants[0] = RehearsalGrant(owner, 1); // ROLE_SET_ADDRESS
        resolver = IPermissionedResolver(
            FACTORY.deployProxy(
                RESOLVER_IMPL,
                2,
                abi.encodeWithSignature("initialize((address,uint256)[],bytes[])", resolverGrants, new bytes[](0))
            )
        );
    }

    function _register() private {
        bytes32 testSecret = bytes32(uint256(42)); // public test vector, shared with the script unit tests
        vm.setEnv("ENS_REGISTRATION_SECRET", vm.toString(testSecret));
        RegisterEnsName.Registration memory r =
            RegisterEnsName.Registration(LABEL, owner, address(parent), address(resolver), 365 days, bytes32(0));
        bytes32 hash =
            keccak256(abi.encode(r.label, r.owner, testSecret, r.subregistry, r.resolver, r.duration, r.referrer));
        assertEq(
            REGISTRAR.makeCommitment(r.label, r.owner, testSecret, r.subregistry, r.resolver, r.duration, r.referrer),
            hash
        );
        script.commit(hash);
        uint64 committedAt = REGISTRAR.commitmentAt(hash);
        assertEq(committedAt, vm.getBlockTimestamp());
        vm.warp(uint256(committedAt) + REGISTRAR.MIN_COMMITMENT_AGE());
        (uint256 base, uint256 premium) = REGISTRAR.getRegisterPrice(LABEL, r.duration, address(TOKEN));
        uint256 quote = base + premium;
        deal(address(TOKEN), payer, quote);
        vm.recordLogs();
        uint256 tokenId = script.reveal(r, address(TOKEN), quote);
        _checkRegistrationReceipt(vm.getRecordedLogs());
        assertEq(tokenId, ETH.findTokenId(LABEL));
        assertEq(ETH.findOwner(LABEL), owner);
        assertEq(ETH.getSubregistry(LABEL), address(parent));
        assertEq(ETH.getResolver(LABEL), address(resolver));
        assertEq(REGISTRAR.commitmentAt(hash), 0);
        assertEq(TOKEN.allowance(payer, address(REGISTRAR)), 0);
        assertEq(TOKEN.balanceOf(payer), 0);
    }

    function _checkRegistrationReceipt(Vm.Log[] memory logs) private pure {
        bytes32 topic =
            keccak256("NameRegistered(uint256,string,address,address,address,uint64,address,bytes32,uint256,uint256)");
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(REGISTRAR) && logs[i].topics[0] == topic) return;
        }
        revert("Missing ENSv2 NameRegistered event");
    }

    function test_Fork_RegisterAndIssueNativeName() public {
        _register();
        vm.prank(owner);
        resolver.setAddress(NAME, 60, abi.encodePacked(owner));
        assertEq(forward.resolveEnsAddressV2(NAME), owner);

        bytes memory childName = bytes.concat(hex"047465616d", NAME);
        address childOwner = makeAddr("team owner");
        uint64 expiry = uint64(block.timestamp + 30 days);
        vm.prank(owner);
        uint256 tokenId =
            subnameIssuer.issueEnsSubnameV2(NAME, "team", childOwner, address(0), address(resolver), 1 << 24, expiry);
        assertEq(IETHRegistryRecords(address(parent)).findTokenId("team"), tokenId);
        assertEq(IETHRegistryRecords(address(parent)).findOwner("team"), childOwner);
        assertEq(parent.getExpiry(tokenId), expiry);
        vm.prank(owner);
        resolver.setAddress(childName, 60, abi.encodePacked(childOwner));
        assertEq(forward.resolveEnsAddressV2(childName), childOwner);
        (, bytes32 node,) = UR.findResolver(childName);
        assertGt(resolver.getRecordId(node), 0);
        (bytes memory record, address viaResolver) = UR.resolve(childName, abi.encodeCall(IAddrResolver.addr, (node)));
        assertEq(abi.decode(record, (address)), childOwner);
        assertEq(viaResolver, address(resolver));
        string memory child = string.concat("team.", LABEL, ".eth");
        vm.prank(childOwner);
        REVERSE.setName(child);
        (string memory primary,,) = UR.reverse(abi.encodePacked(childOwner), 60);
        assertEq(primary, child);
        vm.prank(owner);
        resolver.setAddress(childName, 60, abi.encodePacked(owner));
        vm.expectPartialRevert(bytes4(keccak256("ReverseAddressMismatch(string,bytes)")));
        UR.reverse(abi.encodePacked(childOwner), 60);
    }

    // Separate tests begin from identical fork state and perform the same registration and record write.
    function test_Fork_GasDirectLookupAndIssue() public {
        _compareGas(false);
    }

    function test_Fork_GasDiamondLookupAndIssue() public {
        _compareGas(true);
    }

    function _compareGas(bool throughDiamond) private {
        _register();
        vm.prank(owner);
        resolver.setAddress(NAME, 60, abi.encodePacked(owner));
        address answer;
        uint256 beforeRead = gasleft();
        if (throughDiamond) {
            answer = forward.resolveEnsAddressV2(NAME);
        } else {
            (, bytes32 node,) = UR.findResolver(NAME);
            (bytes memory record,) = UR.resolve(NAME, abi.encodeCall(IAddrResolver.addr, (node)));
            answer = abi.decode(record, (address));
        }
        uint256 readGas = beforeRead - gasleft();
        assertEq(answer, owner);

        address childOwner = makeAddr("team owner");
        uint64 expiry = uint64(block.timestamp + 30 days);
        // Both paths discover the canonical registry. The direct caller impersonates the same ENS-authorized diamond.
        vm.startPrank(throughDiamond ? owner : diamond);
        uint256 beforeWrite = gasleft();
        uint256 tokenId;
        if (throughDiamond) {
            tokenId = subnameIssuer.issueEnsSubnameV2(
                NAME, "team", childOwner, address(0), address(resolver), 1 << 24, expiry
            );
        } else {
            address registry = IUniversalHelper(HELPER).findCanonicalRegistry(NAME);
            tokenId = IRehearsalRegistry(registry)
                .register("team", childOwner, address(0), address(resolver), 1 << 24, expiry);
        }
        uint256 writeGas = beforeWrite - gasleft();
        vm.stopPrank();
        assertEq(IETHRegistryRecords(address(parent)).findTokenId("team"), tokenId);
        emit log_named_uint("ETH lookup gas", readGas);
        emit log_named_uint("Subname issuance gas", writeGas);
    }
}
