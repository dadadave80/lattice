// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployAccessControl} from "@lattice-script/base/access/DeployAccessControl.s.sol";
import {DeployERC20Permit} from "@lattice-script/base/tokens/DeployERC20Permit.s.sol";
import {DeployERC20Votes} from "@lattice-script/base/tokens/DeployERC20Votes.s.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {TimelockControllerStandalone} from "@lattice/governance/TimelockControllerStandalone.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IEIP712} from "@lattice/interfaces/utils/IEIP712.sol";
import {ERC6538RegistryInit} from "@lattice/privacy/ERC6538RegistryInit.sol";
import {ERC20Permit} from "@lattice/tokens/ERC20/ERC20Permit.sol";
import {ERC20PermitInit} from "@lattice/tokens/ERC20/ERC20PermitInit.sol";
import {EIP712} from "@lattice/utils/EIP712.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

contract InitializationProbe is Initializable {
    function reinitAccess(uint64 version, address admin) external reinitializer(version) {
        AccessControlLib.__AccessControl_init(admin);
    }

    function reinitDomain(uint64 version, string memory name, string memory domainVersion)
        external
        reinitializer(version)
    {
        EIP712Lib.__EIP712_init(name, domainVersion);
    }

    function initDomain(string memory name, string memory domainVersion) external {
        EIP712Lib.__EIP712_init(name, domainVersion);
    }

    function reinitNonces(uint64 version) external reinitializer(version) {
        NoncesLib.__Nonces_init();
    }

    function domainSeparator() external view returns (bytes32) {
        return EIP712Lib.domainSeparatorV4();
    }
}

contract SelfAdminTimelockProbe is TimelockControllerStandalone {
    constructor() TimelockControllerStandalone(0, new address[](0), new address[](0), address(0)) {}

    function repeatBootstrap() external reinitializer(2) {
        AccessControlLib.__AccessControl_init(address(this));
    }
}

contract LegacySigningInit {
    function init() external {
        EIP712Lib.__EIP712_init("Legacy", "1");
        NoncesLib.__Nonces_init();
        EIP712Lib.registerInterface();
        NoncesLib.registerInterface();
    }
}

contract LegacyAccessInit {
    function init(address admin) external {
        AccessControlLib._grantRole(bytes32(0), admin);
        AccessControlLib.registerInterface();
    }
}

/// @notice Real diamond compositions, including legacy storage and later initialization windows.
contract InitializationCompositionTest is Test {
    address private constant ADMIN = address(0xA11CE);
    address private constant OTHER = address(0xB0B);
    bytes4 private constant CONFLICTING_ADMIN =
        bytes4(keccak256("AccessControlConflictingInitialization(address,address)"));
    bytes4 private constant LEGACY_ADMIN = bytes4(keccak256("AccessControlLegacyInitialization()"));
    bytes4 private constant CONFLICTING_DOMAIN = bytes4(keccak256("EIP712ConflictingDomain()"));
    Lattice private diamond;

    function setUp() public {
        diamond = new Lattice();
    }

    function test_ConflictingInitialAdminsRevertAtomically() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = _accessRecipe(ADMIN);
        address[] memory inits = new address[](2);
        bytes[] memory calls = new bytes[](2);
        inits[0] = init;
        calls[0] = data;
        inits[1] = address(new AccessControlInit());
        calls[1] = abi.encodeCall(AccessControlInit.init, (OTHER));
        MultiInit multi = new MultiInit();
        vm.expectRevert(abi.encodeWithSelector(CONFLICTING_ADMIN, ADMIN, OTHER));
        diamond.initialize(cuts, address(multi), abi.encodeCall(MultiInit.multiInit, (inits, calls)));
        // Rollback includes the proxy initialization guard: a valid retry still succeeds.
        diamond.initialize(cuts, init, data);
        assertTrue(IAccessControl(address(diamond)).hasRole(bytes32(0), ADMIN));
        assertFalse(IAccessControl(address(diamond)).hasRole(bytes32(0), OTHER));
    }

    function test_SameAdminReinitDoesNotRestoreRevokedRole() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = _accessRecipe(ADMIN);
        diamond.initialize(cuts, init, data);
        vm.prank(ADMIN);
        IAccessControl(address(diamond)).renounceRole(bytes32(0), ADMIN);
        InitializationProbe(address(diamond)).reinitAccess(2, ADMIN);
        assertFalse(IAccessControl(address(diamond)).hasRole(bytes32(0), ADMIN));
    }

    function test_InitializedAdminCannotChangeInLaterWindow() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = _accessRecipe(ADMIN);
        diamond.initialize(cuts, init, data);
        vm.expectRevert(abi.encodeWithSelector(CONFLICTING_ADMIN, ADMIN, OTHER));
        InitializationProbe(address(diamond)).reinitAccess(2, OTHER);
        assertFalse(IAccessControl(address(diamond)).hasRole(bytes32(0), OTHER));
    }

    function test_ZeroAdminIsInitializedConfiguration() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = _accessRecipe(address(0));
        diamond.initialize(cuts, init, data);
        vm.expectRevert(abi.encodeWithSelector(CONFLICTING_ADMIN, address(0), OTHER));
        InitializationProbe(address(diamond)).reinitAccess(2, OTHER);
    }

    function test_LegacyRegisteredAccessControlFailsClosed() public {
        (FacetCut[] memory cuts,,) = _accessRecipe(ADMIN);
        LegacyAccessInit legacy = new LegacyAccessInit();
        diamond.initialize(cuts, address(legacy), abi.encodeCall(LegacyAccessInit.init, (ADMIN)));
        vm.expectRevert(LEGACY_ADMIN);
        InitializationProbe(address(diamond)).reinitAccess(2, OTHER);
        assertTrue(IAccessControl(address(diamond)).hasRole(bytes32(0), ADMIN));
        assertFalse(IAccessControl(address(diamond)).hasRole(bytes32(0), OTHER));
    }

    function test_LegacySameAdminStillRequiresMigration() public {
        (FacetCut[] memory cuts,,) = _accessRecipe(ADMIN);
        LegacyAccessInit legacy = new LegacyAccessInit();
        diamond.initialize(cuts, address(legacy), abi.encodeCall(LegacyAccessInit.init, (ADMIN)));
        vm.expectRevert(LEGACY_ADMIN);
        InitializationProbe(address(diamond)).reinitAccess(2, ADMIN);
        assertTrue(IAccessControl(address(diamond)).hasRole(bytes32(0), ADMIN));
    }

    function test_FreshSelfAdminTimelockCanRepeatBootstrap() public {
        SelfAdminTimelockProbe timelock = new SelfAdminTimelockProbe();
        timelock.repeatBootstrap();
        assertTrue(timelock.hasRole(bytes32(0), address(timelock)));
        assertFalse(timelock.hasRole(bytes32(0), address(0)));
    }

    function test_FirstAccessControlInitializationAtVersionTwo() public {
        (FacetCut[] memory cuts,,) = _accessRecipe(ADMIN);
        diamond.initialize(cuts, address(0), "");
        InitializationProbe(address(diamond)).reinitAccess(2, ADMIN);
        assertTrue(IAccessControl(address(diamond)).hasRole(bytes32(0), ADMIN));
    }

    function test_PermitAndVotesShareIdenticalDomain() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls) = _votesAndPermit();
        MultiInit multi = new MultiInit();
        diamond.initialize(cuts, address(multi), abi.encodeCall(MultiInit.multiInit, (inits, calls)));
        (, string memory name, string memory version,,,,) = IEIP712(address(diamond)).eip712Domain();
        assertEq(name, "Shared token");
        assertEq(version, "1");
        assertTrue(ERC165Facet(address(diamond)).supportsInterface(type(IEIP712).interfaceId));
        assertTrue(ERC165Facet(address(diamond)).supportsInterface(0x7ecebe00));
        assertEq(
            ERC20Permit(address(diamond)).DOMAIN_SEPARATOR(), InitializationProbe(address(diamond)).domainSeparator()
        );
    }

    function test_PermitAndRegistryConflictingDomainReverts() public {
        (FacetCut[] memory cuts, address[] memory permitInits, bytes[] memory permitCalls) =
            new DeployERC20Permit().buildCuts("Shared token", "SHR");
        address[] memory inits = new address[](permitInits.length + 1);
        bytes[] memory calls = new bytes[](permitCalls.length + 1);
        for (uint256 i; i < permitInits.length; ++i) {
            inits[i] = permitInits[i];
            calls[i] = permitCalls[i];
        }
        inits[permitInits.length] = address(new ERC6538RegistryInit());
        calls[permitCalls.length] = abi.encodeCall(ERC6538RegistryInit.init, ());
        MultiInit multi = new MultiInit();
        vm.expectRevert(CONFLICTING_DOMAIN);
        diamond.initialize(cuts, address(multi), abi.encodeCall(MultiInit.multiInit, (inits, calls)));
    }

    function test_UpgradedInitializersClearLegacyUnroutedViewFlags() public {
        (FacetCut[] memory cuts,,) = _accessRecipe(ADMIN);
        LegacySigningInit init = new LegacySigningInit();
        diamond.initialize(cuts, address(init), abi.encodeCall(LegacySigningInit.init, ()));
        ERC165Facet discovery = ERC165Facet(address(diamond));
        assertTrue(discovery.supportsInterface(0x84b0196e));
        assertTrue(discovery.supportsInterface(0x7ecebe00));
        InitializationProbe(address(diamond)).reinitDomain(2, "Legacy", "1");
        InitializationProbe(address(diamond)).reinitNonces(3);
        assertFalse(discovery.supportsInterface(0x84b0196e));
        assertFalse(discovery.supportsInterface(0x7ecebe00));
    }

    function test_DomainNameConflictAtIdenticalVersionReverts() public {
        (FacetCut[] memory cuts,,) = _accessRecipe(ADMIN);
        InitializationProbe init = new InitializationProbe();
        diamond.initialize(cuts, address(init), abi.encodeCall(InitializationProbe.initDomain, ("Original", "1")));
        vm.expectRevert(CONFLICTING_DOMAIN);
        InitializationProbe(address(diamond)).reinitDomain(2, "Different", "1");
    }

    function test_IdenticalLongDomainIsNoOpAndConflictsPreserveIt() public {
        string memory name = "A domain name longer than thirty one bytes";
        string memory version = "A domain version longer than thirty one bytes";
        (FacetCut[] memory cuts,,) = _accessRecipe(ADMIN);
        cuts = _append(cuts, address(new EIP712()), _one(IEIP712.eip712Domain.selector));
        InitializationProbe init = new InitializationProbe();
        diamond.initialize(cuts, address(init), abi.encodeCall(InitializationProbe.initDomain, (name, version)));
        bytes32 separator = InitializationProbe(address(diamond)).domainSeparator();
        InitializationProbe(address(diamond)).reinitDomain(2, name, version);
        assertEq(InitializationProbe(address(diamond)).domainSeparator(), separator);
        vm.expectRevert(CONFLICTING_DOMAIN);
        InitializationProbe(address(diamond)).reinitDomain(3, name, "different");
        (, string memory actualName, string memory actualVersion,,,,) = IEIP712(address(diamond)).eip712Domain();
        assertEq(actualName, name);
        assertEq(actualVersion, version);
        assertEq(InitializationProbe(address(diamond)).domainSeparator(), separator);
    }

    function _accessRecipe(address admin) private returns (FacetCut[] memory cuts, address init, bytes memory data) {
        (cuts, init, data) = new DeployAccessControl().buildCuts(admin);
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = InitializationProbe.reinitAccess.selector;
        selectors[1] = InitializationProbe.reinitDomain.selector;
        selectors[2] = InitializationProbe.initDomain.selector;
        selectors[3] = InitializationProbe.domainSeparator.selector;
        selectors[4] = InitializationProbe.reinitNonces.selector;
        cuts = _append(cuts, address(new InitializationProbe()), selectors);
    }

    function _votesAndPermit() private returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory calls) {
        (FacetCut[] memory base, address[] memory baseInits, bytes[] memory baseCalls) =
            new DeployERC20Votes().buildCuts("Shared token", "SHR", ADMIN);
        ERC20Permit permitFacet = new ERC20Permit();
        cuts = _append(base, address(permitFacet), _decode(permitFacet.exportSelectors()));
        cuts = _append(cuts, address(new EIP712()), _one(IEIP712.eip712Domain.selector));
        cuts = _append(cuts, address(new InitializationProbe()), _one(InitializationProbe.domainSeparator.selector));
        inits = new address[](2);
        calls = new bytes[](2);
        inits[0] = address(new MultiInit());
        calls[0] = abi.encodeCall(MultiInit.multiInit, (baseInits, baseCalls));
        inits[1] = address(new ERC20PermitInit());
        calls[1] = abi.encodeCall(ERC20PermitInit.init, ("Shared token"));
    }

    function _append(FacetCut[] memory base, address facet, bytes4[] memory selectors)
        private
        pure
        returns (FacetCut[] memory cuts)
    {
        cuts = new FacetCut[](base.length + 1);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        cuts[base.length] = FacetCut(facet, FacetCutAction.Add, selectors);
    }

    function _one(bytes4 selector) private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = selector;
    }

    function _decode(bytes memory packed) private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](packed.length / 4);
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 selector;
            assembly ("memory-safe") { selector := mload(add(add(packed, 32), mul(i, 4))) }
            selectors[i] = selector;
        }
    }
}
