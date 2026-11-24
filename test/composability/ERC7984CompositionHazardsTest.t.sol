// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {IFacet} from "@diamond/interfaces/IFacet.sol";
import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC7984} from "@lattice-script/base/tokens/DeployERC7984.s.sol";
import {ERC7984TestBase} from "@lattice-test/base/ERC7984TestBase.sol";
import {ERC7984TestFacet} from "@lattice-test/helpers/ERC7984TestFacet.sol";
import {IACL} from "@lattice-test/helpers/fhevm/generated/interfaces/IACL.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {TimelockControllerInit} from "@lattice/governance/TimelockControllerInit.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IERC7984} from "@lattice/interfaces/tokens/IERC7984.sol";
import {IERC7984Mintable} from "@lattice/interfaces/tokens/IERC7984Mintable.sol";
import {FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";
import {ERC7984Init} from "@lattice/tokens/ERC7984/ERC7984Init.sol";
import {ERC7984_MINTER_ROLE} from "@lattice/tokens/ERC7984/libraries/ERC7984MintableLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {IERC165} from "forge-std/interfaces/IERC165.sol";

/// @dev A cut initializer that runs as the diamond and grants `who` access to `handle` on the ACL (access control
///      list) host.
contract Grabber {
    function grab(address acl, bytes32 handle, address who) external {
        IACL(acl).allow(handle, who);
    }
}

/// @dev An executor with a non-standard entry point, which no deny-list selector names.
contract OddExecutor {
    function run(address target, bytes calldata data) external returns (bytes memory result) {
        bool ok;
        (ok, result) = target.call(data);
        require(ok, "OddExecutor: call failed");
    }
}

/// @dev A third-party executor exporting the standard ERC-7579 `execute(bytes32,bytes)` (`0xe9ae5c53`).
contract ThirdPartyExecutor {
    function execute(bytes32, bytes calldata data) external payable {
        (address target, bytes memory call_) = abi.decode(data, (address, bytes));
        (bool ok,) = target.call(call_);
        require(ok, "ThirdPartyExecutor: call failed");
    }
}

/// @dev Runs a later cut's initializer inside a reinitialization window, as an upgrade initializer would.
contract TimelockReinit is Initializable {
    function run(address target, bytes calldata data) external reinitializer(2) {
        DiamondLib.initializeDiamondCut(target, data);
    }
}

/// @title ERC7984CompositionHazardsTest
/// @notice Pins the ERC-7984 (confidential fungible token) co-install hazards behind the compose guide's rows: the
///         deny-list binds only at initialization, so a later-cut timelock or an admin cut initializer runs as the
///         diamond and reaches any balance on the ACL (access control list); the entry guard refuses a self-call
///         relay; a non-standard executor slips past the deny-list; an ERC-1271 validator would meet every KMS (Key
///         Management Service) user-decryption rule; and the no-cut mintable layout gives its admin no grant.
contract ERC7984CompositionHazardsTest is ERC7984TestBase {
    address internal constant ADMIN = address(0xAD);
    uint256 internal constant DELAY = 60;

    address internal attacker = makeAddr("attacker");
    address internal minter;
    address internal aclAdd;
    address internal adminToken;
    bytes32 internal holderBalance;
    Grabber internal grabber;
    ERC7984Init internal tokenInit;

    function setUp() public override {
        super.setUp();
        aclAdd = FHEVMLib.hostsFor(block.chainid).acl;
        grabber = new Grabber();
        tokenInit = new ERC7984Init();

        (FacetCut[] memory cuts, address init, bytes memory cd) =
            new DeployERC7984().buildCuts("Tok", "TOK", "ipfs://t", ADMIN);
        Lattice d = new Lattice();
        d.initialize(cuts, init, cd);
        adminToken = address(d);

        FacetCut[] memory mintCut = new FacetCut[](1);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ERC7984TestFacet.mint.selector;
        mintCut[0] = FacetCut(address(new ERC7984TestFacet()), FacetCutAction.Add, selectors);
        vm.prank(ADMIN);
        IDiamondCut(adminToken).diamondCut(mintCut, address(0), "");

        ERC7984TestFacet(adminToken).mint(holder, 1_000_000);
        holderBalance = euint64.unwrap(IERC7984(adminToken).confidentialBalanceOf(holder));
        minter = makeAddr("minter");
    }

    /// @notice H-01, H-04: the deny-list binds only at init, so a timelock cut later reaches any balance.
    function test_LaterCutTimelockGrantsDecryptionOfAnyBalance() public {
        _adminCutTimelock(adminToken);
        _timelockExecute(adminToken, aclAdd, abi.encodeWithSignature("allow(bytes32,address)", holderBalance, attacker));
        assertTrue(_acl.persistAllowed(holderBalance, attacker));
    }

    function test_LaterCutTimelockMakesAnyBalancePublic() public {
        _adminCutTimelock(adminToken);
        _timelockExecute(
            adminToken, aclAdd, abi.encodeWithSignature("allowForDecryption(bytes32[])", _one32(holderBalance))
        );
        assertTrue(_acl.isAllowedForDecryption(holderBalance));
    }

    function test_SelfCallRelayCannotDisclose() public {
        _adminCutTimelock(adminToken);
        bytes memory call_ = abi.encodeWithSelector(bytes4(0xd8061806), holderBalance);
        _timelockSchedule(adminToken, adminToken, call_);
        // TimelockControllerLib bubbles the guard's revert
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984UnauthorizedCaller.selector, adminToken));
        _timelockRun(adminToken, adminToken, call_);
        assertFalse(_acl.isAllowedForDecryption(holderBalance));
    }

    function test_AdminCutInitializerGrantsDecryption() public {
        vm.prank(ADMIN);
        IDiamondCut(adminToken)
            .diamondCut(
                new FacetCut[](0), address(grabber), abi.encodeCall(Grabber.grab, (aclAdd, holderBalance, attacker))
            );
        assertTrue(_acl.persistAllowed(holderBalance, attacker));
    }

    /// @notice R3: an executor cut before init with a non-standard entry point passes {ERC7984Init}.
    function test_GuardMissesNonStandardExecutor() public {
        address d = _deployWithExtraFacet(address(new OddExecutor()), OddExecutor.run.selector);
        assertTrue(IERC165(d).supportsInterface(0x4958f2a4));
    }

    /// @notice P13, H-32: why `0x1626ba7e` is denied.
    function test_HolderAndDiamondBothAllowed_UserDecryptPrecondition() public {
        assertTrue(_acl.persistAllowed(holderBalance, adminToken));
        assertTrue(_acl.persistAllowed(holderBalance, holder));
        // the harness's KMS rules pass for user = diamond, contract = holder; only the signature check remains,
        // which an ERC-1271 validator next to the token would satisfy on the v0.14 unified path
        vm.expectRevert(InvalidUserDecryptSignature.selector);
        this.ud(holderBalance, adminToken, holder, new bytes(65));
    }

    function ud(bytes32 h, address u, address c, bytes memory sig) external returns (uint256) {
        return userDecrypt(h, u, c, sig);
    }

    function test_InitRejectsThirdPartyStandardExecutor() public {
        address f = address(new ThirdPartyExecutor());
        (Lattice d, FacetCut[] memory cuts, bytes memory data) = _prepareWithExtraFacet(f, bytes4(0xe9ae5c53));
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984DiamondCallerInstalled.selector, bytes4(0xe9ae5c53), f));
        d.initialize(cuts, address(tokenInit), data);
    }

    /// @notice H-04 avoided by `DeployERC7984Mintable`'s layout; the overflow bit remains (H-34).
    function test_NoCutMintableToken_AdminGetsNoAclGrant() public {
        address d = _deployMintable(ADMIN, minter);
        (externalEuint64 x1, bytes memory p1) = encryptUint64(1_000, minter, d);
        (externalEuint64 x2, bytes memory p2) = encryptUint64(1, ADMIN, d);
        vm.prank(minter);
        IERC7984Mintable(d).confidentialMint(holder, x1, p1);
        bytes32 hb = euint64.unwrap(IERC7984(d).confidentialBalanceOf(holder));
        // the admin can make itself a minter
        vm.prank(ADMIN);
        IAccessControl(d).grantRole(ERC7984_MINTER_ROLE, ADMIN);
        vm.prank(ADMIN);
        IERC7984Mintable(d).confidentialMint(ADMIN, x2, p2);
        assertEq(IDiamondLoupe(d).facetAddress(0x1f931c1c), address(0));
        assertFalse(_acl.persistAllowed(hb, ADMIN));
        assertFalse(_acl.persistAllowed(hb, minter));
        assertFalse(_acl.persistAllowed(euint64.unwrap(IERC7984(d).confidentialTotalSupply()), ADMIN));
    }

    /// @notice A fresh diamond, the immutable {DeployERC7984} cuts plus one cut routing `sel` to `f`, and the
    ///         {ERC7984Init.init} calldata.
    function _prepareWithExtraFacet(address f, bytes4 sel)
        internal
        returns (Lattice d, FacetCut[] memory cuts, bytes memory data)
    {
        d = new Lattice();
        (FacetCut[] memory base,,) = new DeployERC7984().buildCuts("Tok", "TOK", "ipfs://t");
        cuts = new FacetCut[](base.length + 1);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = sel;
        cuts[base.length] = FacetCut(f, FacetCutAction.Add, selectors);
        data = abi.encodeCall(ERC7984Init.init, ("Tok", "TOK", "ipfs://t"));
    }

    function _deployWithExtraFacet(address f, bytes4 sel) internal returns (address) {
        (Lattice d, FacetCut[] memory cuts, bytes memory data) = _prepareWithExtraFacet(f, sel);
        d.initialize(cuts, address(tokenInit), data);
        return address(d);
    }

    /// @notice As `ADMIN`, cuts {TimelockController} into `d` and runs {TimelockControllerInit} with this test as
    ///         proposer and executor.
    function _adminCutTimelock(address d) internal {
        address facet = address(new TimelockController());
        bytes memory packed = IFacet(facet).exportSelectors();
        bytes4[] memory selectors = new bytes4[](packed.length / 4);
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 selector;
            assembly ("memory-safe") {
                selector := mload(add(add(packed, 32), mul(i, 4)))
            }
            selectors[i] = selector;
        }
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(facet, FacetCutAction.Add, selectors);

        address[] memory roles = _one(address(this));
        bytes memory initData = abi.encodeCall(TimelockControllerInit.init, (DELAY, roles, roles, ADMIN));
        address reinit = address(new TimelockReinit());
        address timelockInit = address(new TimelockControllerInit());
        vm.prank(ADMIN);
        IDiamondCut(d).diamondCut(cuts, reinit, abi.encodeCall(TimelockReinit.run, (timelockInit, initData)));
    }

    function _timelockSchedule(address d, address target, bytes memory data) internal {
        TimelockController(payable(d)).schedule(target, 0, data, bytes32(0), bytes32(0), DELAY);
        vm.warp(block.timestamp + DELAY + 1);
    }

    function _timelockRun(address d, address target, bytes memory data) internal {
        TimelockController(payable(d)).execute(target, 0, data, bytes32(0), bytes32(0));
    }

    function _timelockExecute(address d, address target, bytes memory data) internal {
        _timelockSchedule(d, target, data);
        _timelockRun(d, target, data);
    }
}
