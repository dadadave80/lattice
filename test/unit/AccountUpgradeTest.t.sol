// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {Base} from "@lattice-test/Base.t.sol";
import {Account6900BlueprintHelper} from "@lattice-test/helpers/Account6900BlueprintHelper.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";
import {Call} from "@lattice/interfaces/external/ercs/IERC7821.sol";

/// @title UpgradeProbeFacet
/// @notice One-selector probe cut onto the account AFTER init — calling through it proves the cut applied.
contract UpgradeProbeFacet {
    function probePing() external pure returns (uint256) {
        return 42;
    }
}

/// @title AccountUpgradeTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Regression proof that the account diamond's {DiamondCutFacet} is OPERABLE, not a decoy: the
///         account is its own Ownable owner (seeded by {AccountInit}), so the ONLY reachable cut path is a
///         self-call through the validated execution surface (ERC-7821 executor / EntryPoint) — and that
///         path actually works. Before the fix, `OwnableLib.initializeOwner` was never called, the owner
///         slot stayed zero, and `diamondCut` reverted `Unauthorized()` for every caller forever.
contract AccountUpgradeTest is Base {
    /// @dev Solady/diamond-lib Ownable owner slot (`OwnableLib._OWNER_SLOT`).
    bytes32 internal constant OWNER_SLOT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff74873927;

    /// @dev ERC-7821 single-batch execution mode (mirrors Account7702Test).
    bytes32 internal constant BATCH_MODE = 0x0100000000000000000000000000000000000000000000000000000000000000;

    address internal stranger = address(0xBAD);

    function _probeCuts() internal returns (FacetCut[] memory cuts) {
        UpgradeProbeFacet probe = new UpgradeProbeFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UpgradeProbeFacet.probePing.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(probe), action: FacetCutAction.Add, functionSelectors: selectors});
    }

    /// @notice The account's Ownable owner slot holds the account itself — the wiring the decoy bug lost.
    function test_AccountIsItsOwnUpgradeAuthority() public view {
        assertEq(
            address(uint160(uint256(vm.load(account, OWNER_SLOT)))),
            account,
            "account must be its own Ownable owner (upgrade authority)"
        );
    }

    /// @notice A self-call (the validated execution path's context) can actually cut — the upgrade path lives.
    function test_AccountCanUpgradeItself() public {
        FacetCut[] memory cuts = _probeCuts();
        vm.prank(account); // self-call context: exactly what the executor/EntryPoint path produces
        IDiamondCut(account).diamondCut(cuts, address(0), "");
        assertEq(UpgradeProbeFacet(account).probePing(), 42, "probe facet not routed after the cut");
    }

    /// @notice End-to-end through the REAL validated surface: the EntryPoint drives an ERC-7821 batch whose
    ///         single call is the account cutting itself.
    function test_AccountUpgradesThroughExecutorPath() public {
        FacetCut[] memory cuts = _probeCuts();
        Call[] memory calls = new Call[](1);
        calls[0] = Call({
            target: account, value: 0, data: abi.encodeCall(IDiamondCut.diamondCut, (cuts, address(0), bytes("")))
        });
        vm.prank(entryPoint);
        ERC7821Executor(payable(account)).execute(BATCH_MODE, abi.encode(calls));
        assertEq(UpgradeProbeFacet(account).probePing(), 42, "probe facet not routed after the executor cut");
    }

    /// @notice Anyone who is NOT the account still cannot cut (diamond-lib Ownable `Unauthorized()`).
    function test_StrangerCannotCut() public {
        FacetCut[] memory cuts = _probeCuts();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        IDiamondCut(account).diamondCut(cuts, address(0), "");
    }

    /// @notice The account advertises the cut + loupe interfaces it actually routes (ERC-165 truthfulness).
    function test_AccountAdvertisesCutAndLoupeInterfaces() public view {
        assertTrue(ERC165Facet(account).supportsInterface(0x1f931c1c), "IDiamondCut flag missing");
        assertTrue(ERC165Facet(account).supportsInterface(0x48e2b093), "IDiamondLoupe flag missing");
    }
}

/// @title Account6900UpgradeTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The SAME decoy-cut regression for the ERC-6900 modular account blueprint: {AccountInit6900} must
///         seed the account as its own Ownable owner (the {DiamondCutFacet} gate) and register the cut +
///         loupe ERC-165 flags — removing either from the init makes these fail.
contract Account6900UpgradeTest is Account6900BlueprintHelper {
    /// @dev Solady/diamond-lib Ownable owner slot (`OwnableLib._OWNER_SLOT`).
    bytes32 internal constant OWNER_SLOT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff74873927;

    address internal account;
    address internal owner = address(this);
    address internal entryPoint = address(0xE117);
    address internal stranger = address(0xBAD);

    function setUp() public {
        (FacetCut[] memory cuts, AccountInit6900 init) = _accountBlueprint6900(entryPoint);
        Diamond diamond = new Diamond();
        diamond.initialize(cuts, address(init), abi.encodeCall(AccountInit6900.init, (owner)));
        account = address(diamond);
    }

    function _probeCuts() internal returns (FacetCut[] memory cuts) {
        UpgradeProbeFacet probe = new UpgradeProbeFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = UpgradeProbeFacet.probePing.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(probe), action: FacetCutAction.Add, functionSelectors: selectors});
    }

    /// @notice The 6900 account's Ownable owner slot holds the account itself.
    function test_Account6900IsItsOwnUpgradeAuthority() public view {
        assertEq(
            address(uint160(uint256(vm.load(account, OWNER_SLOT)))),
            account,
            "6900 account must be its own Ownable owner (upgrade authority)"
        );
    }

    /// @notice A self-call (the validated execution path's context) can actually cut.
    function test_Account6900CanUpgradeItself() public {
        FacetCut[] memory cuts = _probeCuts();
        vm.prank(account);
        IDiamondCut(account).diamondCut(cuts, address(0), "");
        assertEq(UpgradeProbeFacet(account).probePing(), 42, "probe facet not routed after the cut");
    }

    /// @notice Anyone who is NOT the account still cannot cut (diamond-lib Ownable `Unauthorized()`).
    function test_StrangerCannotCut6900() public {
        FacetCut[] memory cuts = _probeCuts();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        IDiamondCut(account).diamondCut(cuts, address(0), "");
    }

    /// @notice The 6900 account advertises the cut + loupe interfaces it actually routes.
    function test_Account6900AdvertisesCutAndLoupeInterfaces() public view {
        assertTrue(ERC165Facet(account).supportsInterface(0x1f931c1c), "IDiamondCut flag missing");
        assertTrue(ERC165Facet(account).supportsInterface(0x48e2b093), "IDiamondLoupe flag missing");
    }
}
