// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccountBlueprintHelper} from "@lattice-test/helpers/AccountBlueprintHelper.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ERC1271Signature} from "@lattice/accounts/ERC1271Signature.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {Account7702Diamond} from "@lattice/accounts/erc7579/Account7702Diamond.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";
import {PackedUserOperation} from "@lattice/interfaces/external/ercs/IAccount.sol";
import {Call} from "@lattice/interfaces/external/ercs/IERC7821.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";

contract Target {
    uint256 public value;

    function bump(uint256 v) external {
        value = v;
    }
}

/// @title Account7702Test
/// @author David Dada
/// @notice #58 item 7 — exercises the Diamond as an EIP-7702 delegate: an EOA delegates to a shared Diamond and
///         self-initializes its OWN storage (owner = the EOA), then validates and executes in the EOA context.
///         Also pins the 7702-specific hardening (self-owner signature path must not recurse) and the
///         storage-collision safety (residual EOA storage cannot corrupt the namespaced account slots).
contract Account7702Test is AccountBlueprintHelper {
    LatticeDiamond diamondImpl; // shared delegate code; each EOA uses its own storage
    Account7702Diamond diamond7702; // optional hardened delegate (signed onboarding)
    AccountInit accountInit;
    FacetCut[] blueprint;

    address entryPoint = address(0xE417);
    address eoa;
    uint256 eoaPk;
    Target target;

    bytes32 constant BATCH_MODE = 0x0100000000000000000000000000000000000000000000000000000000000000;
    bytes4 constant MAGIC_1271 = 0x1626ba7e;

    function setUp() public {
        (FacetCut[] memory cuts, AccountInit init) = _accountBlueprint(entryPoint);
        for (uint256 i; i < cuts.length; ++i) {
            blueprint.push(cuts[i]);
        }
        accountInit = init;
        diamondImpl = new LatticeDiamond();
        diamond7702 = new Account7702Diamond();
        (eoa, eoaPk) = makeAddrAndKey("eoa");
        target = new Target();
    }

    /// @dev 7702-delegate the EOA to the shared Diamond and initialize its own storage (owner = the EOA).
    function _onboard() internal {
        vm.signAndAttachDelegation(address(diamondImpl), eoaPk);
        FacetCut[] memory cuts = blueprint;
        LatticeDiamond(payable(eoa)).initialize(cuts, address(accountInit), abi.encodeCall(AccountInit.init7702, ()));
    }

    function _userOp(uint256 pk, bytes32 hash) internal pure returns (PackedUserOperation memory op) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toEthSignedMessageHash(hash));
        op.signature = abi.encodePacked(r, s, v);
    }

    function test_SelfOwnedAfterOnboard() public {
        _onboard();
        assertEq(AccountSigner(eoa).owner(), eoa, "owner is not the EOA");
        assertEq(DiamondLoupeFacet(eoa).facetAddresses().length, 8, "blueprint not wired into EOA storage");
        assertTrue(AccessControl(eoa).hasRole(0x00, eoa), "EOA is not its own admin");
    }

    function test_ExecuteFromSelf() public {
        _onboard();
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.bump, (42))});
        vm.prank(eoa); // self-call: msg.sender == address(this) == the EOA → authorized
        ERC7821Executor(payable(eoa)).execute(BATCH_MODE, abi.encode(calls));
        assertEq(target.value(), 42, "batch not executed in EOA context");
    }

    function test_ValidateUserOp_ValidOwnerSig() public {
        _onboard();
        bytes32 h = keccak256("op");
        vm.prank(entryPoint);
        uint256 vd = ERC4337Validation(payable(eoa)).validateUserOp(_userOp(eoaPk, h), h, 0);
        assertEq(vd, 0, "valid owner sig rejected");
    }

    /// @dev The 7702 hardening: a bad signature to a SELF-owned account (owner == address(this), which now has
    ///      code) must fail CHEAPLY. Without the self-owner ECDSA-only guard it recurses through its own ERC-1271
    ///      path and burns ~2.5M gas; asserts both the SIG_VALIDATION_FAILED result and a bounded cost.
    function test_ValidateUserOp_BadSig_FailsCheaply() public {
        _onboard();
        (, uint256 strangerPk) = makeAddrAndKey("stranger");
        bytes32 h = keccak256("op");
        PackedUserOperation memory op = _userOp(strangerPk, h);
        vm.prank(entryPoint);
        uint256 g0 = gasleft();
        uint256 vd = ERC4337Validation(payable(eoa)).validateUserOp(op, h, 0);
        uint256 used = g0 - gasleft();
        assertEq(vd, 1, "bad sig did not return SIG_VALIDATION_FAILED");
        assertLt(used, 500_000, "self-owner bad-sig recursion not guarded (excessive gas)");
    }

    /// @dev Same guard via the ERC-1271 entry point: a bad signature returns non-magic, cheaply (no recursion).
    function test_IsValidSignature_BadSig_FailsCheaply() public {
        _onboard();
        (, uint256 strangerPk) = makeAddrAndKey("stranger");
        bytes32 h = keccak256("digest");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerPk, h);
        bytes memory sig = abi.encodePacked(r, s, v);
        uint256 g0 = gasleft();
        bytes4 result = ERC1271Signature(eoa).isValidSignature(h, sig);
        uint256 used = g0 - gasleft();
        assertTrue(result != MAGIC_1271, "bad sig accepted");
        assertLt(used, 500_000, "self-owner 1271 bad-sig recursion not guarded (excessive gas)");
    }

    /// @dev (Option A) Once onboarded, the InitializableLib once-guard blocks re-initialization, so a correctly
    ///      onboarded account cannot be re-hijacked.
    function test_ReInitialize_Reverts() public {
        _onboard();
        FacetCut[] memory cuts = blueprint;
        vm.expectRevert();
        LatticeDiamond(payable(eoa)).initialize(cuts, address(accountInit), abi.encodeCall(AccountInit.init7702, ()));
    }

    // --- Option B: hardened delegate (Account7702Diamond) with EOA-signed onboarding ---

    function test_Authorized7702_Onboards() public {
        vm.signAndAttachDelegation(address(diamond7702), eoaPk);
        FacetCut[] memory cuts = blueprint;
        bytes memory data = abi.encodeCall(AccountInit.init7702, ());
        bytes32 digest = Account7702Diamond(payable(eoa)).onboardingDigest(cuts, address(accountInit), data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, digest);
        Account7702Diamond(payable(eoa))
            .initializeAuthorized(cuts, address(accountInit), data, abi.encodePacked(r, s, v));
        assertEq(AccountSigner(eoa).owner(), eoa, "authorized onboarding did not self-own");
        assertEq(DiamondLoupeFacet(eoa).facetAddresses().length, 8, "blueprint not wired");
    }

    /// @dev A front-runner cannot forge the EOA's signature.
    function test_Authorized7702_RejectsForgedSig() public {
        vm.signAndAttachDelegation(address(diamond7702), eoaPk);
        FacetCut[] memory cuts = blueprint;
        bytes memory data = abi.encodeCall(AccountInit.init7702, ());
        bytes32 digest = Account7702Diamond(payable(eoa)).onboardingDigest(cuts, address(accountInit), data);
        (, uint256 strangerPk) = makeAddrAndKey("stranger");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(strangerPk, digest);
        vm.expectRevert(Account7702Diamond.UnauthorizedOnboarding.selector);
        Account7702Diamond(payable(eoa))
            .initializeAuthorized(cuts, address(accountInit), data, abi.encodePacked(r, s, v));
    }

    /// @dev A signature for one onboarding cannot authorize a substituted (hostile) one.
    function test_Authorized7702_RejectsTamperedOnboarding() public {
        vm.signAndAttachDelegation(address(diamond7702), eoaPk);
        FacetCut[] memory cuts = blueprint;
        bytes memory signed = abi.encodeCall(AccountInit.init7702, ());
        bytes32 digest = Account7702Diamond(payable(eoa)).onboardingDigest(cuts, address(accountInit), signed);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(eoaPk, digest);
        bytes memory tampered = abi.encodeCall(AccountInit.init, (address(0xBAD))); // hostile owner
        vm.expectRevert(Account7702Diamond.UnauthorizedOnboarding.selector);
        Account7702Diamond(payable(eoa))
            .initializeAuthorized(cuts, address(accountInit), tampered, abi.encodePacked(r, s, v));
    }

    /// @dev The unauthenticated `initialize` is disabled on the hardened delegate.
    function test_Authorized7702_UnauthenticatedInitializeReverts() public {
        vm.signAndAttachDelegation(address(diamond7702), eoaPk);
        FacetCut[] memory cuts = blueprint;
        vm.expectRevert(Account7702Diamond.UnauthorizedOnboarding.selector);
        Account7702Diamond(payable(eoa))
            .initialize(cuts, address(accountInit), abi.encodeCall(AccountInit.init7702, ()));
    }

    /// @dev Residual storage in the EOA (e.g. from a prior 7702 delegate that used low/sequential slots) cannot
    ///      corrupt the account: every account slot is ERC-7201-namespaced / hashed, never low-sequential.
    function test_ResidualLowStorageDoesNotCollide() public {
        for (uint256 i; i < 6; ++i) {
            vm.store(eoa, bytes32(i), bytes32(uint256(0xdead0000 + i)));
        }
        _onboard();
        assertEq(AccountSigner(eoa).owner(), eoa, "residual storage corrupted owner");
        Call[] memory calls = new Call[](1);
        calls[0] = Call({target: address(target), value: 0, data: abi.encodeCall(Target.bump, (7))});
        vm.prank(eoa);
        ERC7821Executor(payable(eoa)).execute(BATCH_MODE, abi.encode(calls));
        assertEq(target.value(), 7, "residual storage broke execution");
    }
}
