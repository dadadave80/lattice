// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Selectors} from "@diamond-test/helpers/Selectors.sol";
import {MultiInit__StepFailed} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {GovernedDiamondCutTestBase} from "@lattice-test/base/GovernedDiamondCutTestBase.sol";
import {ENSResolver} from "@lattice/ens/ENSResolver.sol";
import {ENSResolverV2} from "@lattice/ens/ENSResolverV2.sol";
import {ENSResolverV2Init} from "@lattice/ens/ENSResolverV2Init.sol";
import {ENSSubnameIssuerV2} from "@lattice/ens/ENSSubnameIssuerV2.sol";
import {ENSSubnameIssuerV2Init} from "@lattice/ens/ENSSubnameIssuerV2Init.sol";
import {ENSResolverLib, ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSResolverLib.sol";
import {ENS_RESOLVER_V2_STORAGE_SLOT} from "@lattice/ens/libraries/ENSResolverV2Lib.sol";
import {UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IENSResolver} from "@lattice/interfaces/ens/IENSResolver.sol";
import {IENSResolverV2} from "@lattice/interfaces/ens/IENSResolverV2.sol";
import {IENSSubnameIssuerV2} from "@lattice/interfaces/ens/IENSSubnameIssuerV2.sol";
import {IAddrResolver} from "@lattice/interfaces/external/ens/IAddrResolver.sol";
import {IENS} from "@lattice/interfaces/external/ens/IENS.sol";
import {IUniversalHelper} from "@lattice/interfaces/external/ens/IUniversalHelper.sol";
import {IUniversalResolverV2} from "@lattice/interfaces/external/ens/IUniversalResolverV2.sol";
import {ReinitMultiInit} from "@lattice/utils/ReinitMultiInit.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev Fixture for a composed v1 diamond that already initialized AccessControl through its governance recipe.
contract LegacyResolverStep {
    function init(address registry) external {
        ENSResolverLib.__ENSResolver_init(registry);
    }
}

/// @title ENSV2UpgradeTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Installs both ENSv2 modules with one governed cut on a diamond already serving v1 names.
contract ENSV2UpgradeTest is GovernedDiamondCutTestBase {
    address constant LEGACY = address(0x111);
    address constant ENDPOINT = address(0x222);
    address constant MANAGER = address(0x333);
    address constant TARGET = address(0x444);
    bytes constant NAME = hex"0365746800";
    ENSResolver internal legacy;
    ENSResolverV2 internal resolver;
    ENSSubnameIssuerV2 internal issuer;
    ENSResolverV2Init internal resolverInit;
    ENSSubnameIssuerV2Init internal issuerInit;
    ReinitMultiInit internal batch;

    function setUp() public {
        diamond = _deployGovernedDiamondCut(address(this));
        legacy = new ENSResolver();
        resolver = new ENSResolverV2();
        issuer = new ENSSubnameIssuerV2();
        resolverInit = new ENSResolverV2Init();
        issuerInit = new ENSSubnameIssuerV2Init();
        batch = new ReinitMultiInit();
        ac.grantRole(ENS_MANAGER_ROLE, MANAGER);
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(address(legacy), FacetCutAction.Add, Selectors.decode(legacy.exportSelectors()));
        address[] memory targets = new address[](1);
        targets[0] = address(new LegacyResolverStep());
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(LegacyResolverStep.init, (LEGACY));
        _execute(2, cuts, targets, calls);
        bytes4[] memory frozen = new bytes4[](1);
        frozen[0] = IENSResolver.resolve.selector;
        vm.prank(diamond);
        cut.freezeSelectors(frozen);
        vm.etch(LEGACY, hex"00");
        vm.etch(ENDPOINT, hex"00");
        vm.mockCall(ENDPOINT, abi.encodeCall(IUniversalResolverV2.isENSv2, ()), abi.encode(true));
        vm.mockCall(ENDPOINT, abi.encodeCall(IUniversalHelper.ROOT_REGISTRY, ()), abi.encode(LEGACY));
    }

    function _execute(uint64 version, FacetCut[] memory cuts, address[] memory targets, bytes[] memory calls) internal {
        bytes memory payload = abi.encodeCall(ReinitMultiInit.reinitMulti, (version, targets, calls));
        vm.prank(diamond);
        cut.diamondCut(cuts, address(batch), payload);
    }

    function _v2Cuts() internal view returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](2);
        cuts[0] = FacetCut(address(resolver), FacetCutAction.Add, Selectors.decode(resolver.exportSelectors()));
        cuts[1] = FacetCut(address(issuer), FacetCutAction.Add, Selectors.decode(issuer.exportSelectors()));
    }

    function _steps(address helper) internal view returns (address[] memory targets, bytes[] memory calls) {
        targets = new address[](2);
        targets[0] = address(resolverInit);
        targets[1] = address(issuerInit);
        calls = new bytes[](2);
        calls[0] = abi.encodeCall(ENSResolverV2Init.init, (ENDPOINT));
        calls[1] = abi.encodeCall(ENSSubnameIssuerV2Init.init, (helper));
    }

    function _assertLegacy(uint64 version) internal view {
        assertEq(uint256(vm.load(diamond, InitializableLib.initializableSlot())), uint256(version) << 1);
        assertTrue(ac.hasRole(bytes32(0), address(this)));
        assertTrue(ac.hasRole(ENS_MANAGER_ROLE, MANAGER));
        assertFalse(ac.hasRole(ENS_MANAGER_ROLE, address(this)));
        assertTrue(ac.hasRole(UPGRADE_EXECUTOR_ROLE, diamond));
        assertFalse(ac.hasRole(UPGRADE_EXECUTOR_ROLE, address(this)));
        assertEq(ac.getRoleAdmin(UPGRADE_EXECUTOR_ROLE), UPGRADE_EXECUTOR_ROLE);
        assertTrue(cut.isSelectorFrozen(IENSResolver.resolve.selector));
        assertTrue(erc165.supportsInterface(type(IENSResolver).interfaceId));
        assertEq(loupe.facetAddress(IENSResolver.resolve.selector), address(legacy));
        assertEq(IENSResolver(diamond).ensRegistry(), LEGACY);
    }

    function test_AddV2AndKeepV1NamesAndAuthority() public {
        (address[] memory targets, bytes[] memory calls) = _steps(ENDPOINT);
        _execute(3, _v2Cuts(), targets, calls);
        _assertLegacy(3);
        assertTrue(erc165.supportsInterface(type(IENSResolverV2).interfaceId));
        assertTrue(erc165.supportsInterface(type(IENSSubnameIssuerV2).interfaceId));
        assertEq(IENSSubnameIssuerV2(diamond).ensUniversalHelper(), ENDPOINT);
        bytes32 node = keccak256(abi.encodePacked(bytes32(0), keccak256("eth")));
        bytes memory profile = abi.encodeCall(IAddrResolver.addr, (node));
        vm.mockCall(LEGACY, abi.encodeCall(IENS.resolver, (node)), abi.encode(LEGACY));
        vm.mockCall(LEGACY, profile, abi.encode(TARGET));
        vm.mockCall(
            ENDPOINT, abi.encodeCall(IUniversalResolverV2.findResolver, (NAME)), abi.encode(ENDPOINT, node, uint256(0))
        );
        vm.mockCall(
            ENDPOINT,
            abi.encodeCall(IUniversalResolverV2.resolve, (NAME, profile)),
            abi.encode(abi.encode(TARGET), ENDPOINT)
        );
        assertEq(IENSResolver(diamond).resolve(node), TARGET);
        assertEq(IENSResolverV2(diamond).resolveEnsAddressV2(NAME), TARGET);

        FacetCut[] memory empty = new FacetCut[](0);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiInit__StepFailed.selector,
                uint256(0),
                address(resolverInit),
                abi.encodeWithSelector(IENSResolverV2.ENSResolverV2AlreadyInitialized.selector)
            )
        );
        _execute(4, empty, targets, calls);
        _assertLegacy(3);
    }

    function test_ManagerCannotInitializeThroughRotation() public {
        FacetCut[] memory cuts = _v2Cuts();
        vm.prank(diamond);
        cut.diamondCut(cuts, address(0), bytes(""));
        vm.prank(MANAGER);
        vm.expectRevert(IENSResolverV2.ENSResolverV2NotInitialized.selector);
        IENSResolverV2(diamond).setEnsUniversalResolver(ENDPOINT);
        assertEq(IENSResolverV2(diamond).ensUniversalResolver(), address(0));
        assertFalse(erc165.supportsInterface(type(IENSResolverV2).interfaceId));
    }

    function test_FailedIssuerStepRollsBackBothModules() public {
        (address[] memory targets, bytes[] memory calls) = _steps(address(0));
        FacetCut[] memory cuts = _v2Cuts();
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiInit__StepFailed.selector,
                uint256(1),
                address(issuerInit),
                abi.encodeWithSelector(IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidHelper.selector, address(0))
            )
        );
        _execute(3, cuts, targets, calls);
        _assertLegacy(2);
        assertEq(vm.load(diamond, ENS_RESOLVER_V2_STORAGE_SLOT), bytes32(0));
        assertFalse(erc165.supportsInterface(type(IENSResolverV2).interfaceId));
        assertFalse(erc165.supportsInterface(type(IENSSubnameIssuerV2).interfaceId));
        assertEq(loupe.facetAddress(IENSResolverV2.resolveEnsAddressV2.selector), address(0));
        assertEq(loupe.facetAddress(IENSSubnameIssuerV2.issueEnsSubnameV2.selector), address(0));
    }
}
