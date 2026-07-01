// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {SafeHarborAdopter} from "@lattice/governance/SafeHarborAdopter.sol";
import {SAFE_HARBOR_ADMIN_ROLE, SafeHarborAdopterLib} from "@lattice/governance/libraries/SafeHarborAdopterLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {
    Account as ShAccount,
    AgreementDetails,
    BountyTerms,
    Chain as ShChain,
    ChildContractScope,
    Contact,
    IAgreementFactory,
    IdentityRequirements
} from "@lattice/interfaces/external/IAgreementFactory.sol";
import {ISafeHarborRegistry} from "@lattice/interfaces/external/ISafeHarborRegistry.sol";
import {ISafeHarborAdopter} from "@lattice/interfaces/governance/ISafeHarborAdopter.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockSafeHarborRegistry
/// @notice Minimal SEAL registry: records adoption keyed by msg.sender; reverts on empty getAgreement.
contract MockSafeHarborRegistry is ISafeHarborRegistry {
    mapping(address adopter => address agreement) public adopted;

    function adoptSafeHarbor(address agreementAddress) external {
        adopted[msg.sender] = agreementAddress;
        emit SafeHarborAdoption(msg.sender, agreementAddress);
    }

    function getAgreement(address adopter) external view returns (address) {
        address a = adopted[adopter];
        if (a == address(0)) revert SafeHarborRegistry__NoAgreement();
        return a;
    }
}

/// @title MockAgreementFactory
/// @notice Minimal SEAL factory: records the create() args and returns a fixed agreement address.
contract MockAgreementFactory is IAgreementFactory {
    address public lastChainValidator;
    address public lastOwner;
    bytes32 public lastSalt;
    string public lastProtocolName;
    address public nextAgreement = address(0xA9);

    function create(AgreementDetails memory details, address chainValidator, address owner, bytes32 salt)
        external
        returns (address)
    {
        lastChainValidator = chainValidator;
        lastOwner = owner;
        lastSalt = salt;
        lastProtocolName = details.protocolName;
        return nextAgreement;
    }

    function setNextAgreement(address a) external {
        nextAgreement = a;
    }
}

/// @title MockRevertingRegistry
/// @notice Registry whose getAgreement reverts with a NON-NoAgreement error (simulates a mis-set registry).
contract MockRevertingRegistry is ISafeHarborRegistry {
    error Boom();

    function adoptSafeHarbor(address) external {}

    function getAgreement(address) external pure returns (address) {
        revert Boom();
    }
}

/// @title MockSafeHarborAdopterContract
/// @notice Wrapper that inherits the SafeHarborAdopter facet and wires AccessControl + init.
contract MockSafeHarborAdopterContract is SafeHarborAdopter {
    function initialize(address admin, address registry, address factory) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin);
        SafeHarborAdopterLib.__SafeHarborAdopter_init(registry, factory);
        InitializableLib.postInitializer(s);
    }

    function grantRole(bytes32 role, address account) external {
        AccessControlLib.grantRole(role, account);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title SafeHarborAdopterTest
/// @notice Unit tests for the SEAL Safe Harbor adopter facet.
contract SafeHarborAdopterTest is Test {
    MockSafeHarborAdopterContract adopter;
    MockSafeHarborRegistry registry;
    MockAgreementFactory factory;

    address admin = address(0xA1);
    address manager = address(0xB2);
    address stranger = address(0xC3);
    address agreementX = address(0x7A7A);
    address chainValidator = address(0xC0DE);
    address agreementOwner = address(0x0FFE);

    event SafeHarborAdopted(address indexed agreement);
    event SafeHarborRegistrySet(address indexed registry);
    event AgreementFactorySet(address indexed factory);

    function setUp() public {
        registry = new MockSafeHarborRegistry();
        factory = new MockAgreementFactory();
        adopter = new MockSafeHarborAdopterContract();
        adopter.initialize(admin, address(registry), address(factory));
        vm.prank(admin);
        adopter.grantRole(SAFE_HARBOR_ADMIN_ROLE, manager);
    }

    function _details() internal pure returns (AgreementDetails memory d) {
        d.protocolName = "MyProto";
        d.agreementURI = "ipfs://QmAgreement";
        d.contactDetails = new Contact[](1);
        d.contactDetails[0] = Contact("Security", "security@myproto.xyz");
        ShAccount[] memory accts = new ShAccount[](1);
        accts[0] = ShAccount("eip155:1:0x000000000000000000000000000000000000dEaD", ChildContractScope.All);
        d.chains = new ShChain[](1);
        d.chains[0] = ShChain("eip155:1:0x000000000000000000000000000000000000bEEF", accts, "eip155:1");
        d.bountyTerms = BountyTerms(10, 1_000_000, false, IdentityRequirements.Named, "KYC required", 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              adoptSafeHarbor
    //////////////////////////////////////////////////////////////////////////*//

    function test_AdoptSafeHarborSelfAdoptsViaRegistry() public {
        vm.expectEmit(true, false, false, false, address(adopter));
        emit SafeHarborAdopted(agreementX);
        vm.prank(manager);
        adopter.adoptSafeHarbor(agreementX);
        // The diamond called the registry as msg.sender, so it is recorded as the adopter.
        assertEq(registry.adopted(address(adopter)), agreementX);
        assertEq(adopter.safeHarborAgreement(), agreementX);
    }

    function test_AdoptSafeHarborUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, SAFE_HARBOR_ADMIN_ROLE
            )
        );
        vm.prank(stranger);
        adopter.adoptSafeHarbor(agreementX);
    }

    function test_AdoptSafeHarborZeroAgreementReverts() public {
        vm.expectRevert(ISafeHarborAdopter.SafeHarborAdopterZeroAgreement.selector);
        vm.prank(manager);
        adopter.adoptSafeHarbor(address(0));
    }

    function test_SafeHarborAgreementNoneReturnsZero() public view {
        assertEq(adopter.safeHarborAgreement(), address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              createAndAdopt
    //////////////////////////////////////////////////////////////////////////*//

    function test_CreateAndAdoptCreatesThenAdopts() public {
        vm.prank(manager);
        address created = adopter.createAndAdopt(_details(), chainValidator, agreementOwner, bytes32(uint256(7)));

        assertEq(created, factory.nextAgreement());
        assertEq(factory.lastChainValidator(), chainValidator);
        assertEq(factory.lastOwner(), agreementOwner);
        assertEq(factory.lastSalt(), bytes32(uint256(7)));
        assertEq(factory.lastProtocolName(), "MyProto");
        // The created agreement is adopted for the diamond.
        assertEq(registry.adopted(address(adopter)), created);
        assertEq(adopter.safeHarborAgreement(), created);
    }

    function test_CreateAndAdoptUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, SAFE_HARBOR_ADMIN_ROLE
            )
        );
        vm.prank(stranger);
        adopter.createAndAdopt(_details(), chainValidator, agreementOwner, bytes32(0));
    }

    function test_CreateAndAdoptZeroAgreementFromFactoryReverts() public {
        factory.setNextAgreement(address(0));
        vm.expectRevert(ISafeHarborAdopter.SafeHarborAdopterZeroAgreement.selector);
        vm.prank(manager);
        adopter.createAndAdopt(_details(), chainValidator, agreementOwner, bytes32(0));
    }

    function test_SafeHarborAgreementSurfacesUnexpectedRevert() public {
        MockRevertingRegistry bad = new MockRevertingRegistry();
        vm.prank(manager);
        adopter.setSafeHarborRegistry(address(bad));
        // A non-NoAgreement revert from the registry must be re-surfaced, not masked as address(0).
        vm.expectRevert(MockRevertingRegistry.Boom.selector);
        adopter.safeHarborAgreement();
    }

    function test_CreateAndAdoptNoFactoryReverts() public {
        // Deploy an adopter with no factory configured.
        MockSafeHarborAdopterContract noFactory = new MockSafeHarborAdopterContract();
        noFactory.initialize(admin, address(registry), address(0));
        vm.prank(admin);
        noFactory.grantRole(SAFE_HARBOR_ADMIN_ROLE, manager);

        vm.expectRevert(ISafeHarborAdopter.SafeHarborAdopterZeroFactory.selector);
        vm.prank(manager);
        noFactory.createAndAdopt(_details(), chainValidator, agreementOwner, bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              configuration
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConfiguredAtInit() public view {
        assertEq(adopter.safeHarborRegistry(), address(registry));
        assertEq(adopter.agreementFactory(), address(factory));
    }

    function test_SetSafeHarborRegistry() public {
        MockSafeHarborRegistry reg2 = new MockSafeHarborRegistry();
        vm.expectEmit(true, false, false, false, address(adopter));
        emit SafeHarborRegistrySet(address(reg2));
        vm.prank(manager);
        adopter.setSafeHarborRegistry(address(reg2));
        assertEq(adopter.safeHarborRegistry(), address(reg2));
    }

    function test_SetSafeHarborRegistryZeroReverts() public {
        vm.expectRevert(ISafeHarborAdopter.SafeHarborAdopterZeroRegistry.selector);
        vm.prank(manager);
        adopter.setSafeHarborRegistry(address(0));
    }

    function test_SetSafeHarborRegistryUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, SAFE_HARBOR_ADMIN_ROLE
            )
        );
        vm.prank(stranger);
        adopter.setSafeHarborRegistry(address(registry));
    }

    function test_SetAgreementFactory() public {
        MockAgreementFactory f2 = new MockAgreementFactory();
        vm.expectEmit(true, false, false, false, address(adopter));
        emit AgreementFactorySet(address(f2));
        vm.prank(manager);
        adopter.setAgreementFactory(address(f2));
        assertEq(adopter.agreementFactory(), address(f2));
    }

    function test_SetAgreementFactoryZeroReverts() public {
        vm.expectRevert(ISafeHarborAdopter.SafeHarborAdopterZeroFactory.selector);
        vm.prank(manager);
        adopter.setAgreementFactory(address(0));
    }

    function test_InitZeroRegistryReverts() public {
        MockSafeHarborAdopterContract c = new MockSafeHarborAdopterContract();
        vm.expectRevert(ISafeHarborAdopter.SafeHarborAdopterZeroRegistry.selector);
        c.initialize(admin, address(0), address(factory));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsISafeHarborAdopter() public view {
        assertTrue(adopter.supportsInterface(type(ISafeHarborAdopter).interfaceId));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(ISafeHarborAdopter).interfaceId, bytes4(0x2a3e8e12), "ISafeHarborAdopter interfaceId moved");
    }
}
