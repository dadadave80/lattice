// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20Burnable} from "@lattice-script/base/tokens/DeployERC20Burnable.s.sol";
import {DeployERC20FlashMint} from "@lattice-script/base/tokens/DeployERC20FlashMint.s.sol";
import {DeployERC20Votes} from "@lattice-script/base/tokens/DeployERC20Votes.s.sol";
import {DeployERC4626} from "@lattice-script/base/tokens/DeployERC4626.s.sol";
import {ERC20TestBase} from "@lattice-test/base/ERC20TestBase.sol";
import {ERC20VotesTestFacet} from "@lattice-test/helpers/ERC20VotesTestFacet.sol";
import {TemporaryApprovalActor as Actor} from "@lattice-test/helpers/TemporaryApprovalActor.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IERC3156FlashBorrower} from "@lattice/interfaces/external/ercs/IERC3156FlashBorrower.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IERC20Burnable} from "@lattice/interfaces/tokens/IERC20Burnable.sol";
import {IERC20TemporaryApproval} from "@lattice/interfaces/tokens/IERC20TemporaryApproval.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20FlashMint} from "@lattice/tokens/ERC20/ERC20FlashMint.sol";
import {ERC20TemporaryApproval} from "@lattice/tokens/ERC20/ERC20TemporaryApproval.sol";
import {ERC20TemporaryApprovalInit} from "@lattice/tokens/ERC20/ERC20TemporaryApprovalInit.sol";

/// @title TemporaryApprovalBorrower
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Test borrower repaying a flash mint exclusively through temporary approval.
contract TemporaryApprovalBorrower is IERC3156FlashBorrower {
    uint256 public balanceDuringCallback;

    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        balanceDuringCallback = ERC20(token).balanceOf(address(this));
        IERC20TemporaryApproval(token).temporaryApprove(token, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

/// @notice Each independent production recipe uses the shared allowance implementation without movement hooks.
/// forge-config: default.isolate = true
contract ERC20TemporaryApprovalCompositionTest is ERC20TestBase {
    Actor internal owner;
    Actor internal spender;
    address internal recipient = address(0xB0B);

    function setUp() public override {
        owner = new Actor();
        spender = new Actor();
    }

    function _assembleTemporary(
        FacetCut[] memory base,
        address[] memory baseInits,
        bytes[] memory baseData,
        address mintFacet
    ) internal returns (address result) {
        FacetCut[] memory cuts = new FacetCut[](base.length + 2);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IERC20TemporaryApproval.temporaryApprove.selector;
        cuts[base.length] = FacetCut(address(new ERC20TemporaryApproval()), FacetCutAction.Add, selectors);
        selectors = new bytes4[](1);
        selectors[0] = TokenTestFacet.mint.selector;
        cuts[base.length + 1] = FacetCut(mintFacet, FacetCutAction.Add, selectors);
        address[] memory inits = new address[](baseInits.length + 1);
        bytes[] memory data = new bytes[](baseData.length + 1);
        for (uint256 i; i < baseInits.length; ++i) {
            inits[i] = baseInits[i];
            data[i] = baseData[i];
        }
        inits[baseInits.length] = address(new ERC20TemporaryApprovalInit());
        data[baseData.length] = abi.encodeCall(ERC20TemporaryApprovalInit.init, ());
        Lattice d = new Lattice();
        d.initialize(cuts, address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, data)));
        result = address(d);
    }

    function _grantAndCall(address target, bytes memory spendData, uint256 amount) internal {
        Actor.Action[] memory nested = new Actor.Action[](1);
        nested[0] = Actor.Action(target, spendData, false);
        Actor.Action[] memory actions = new Actor.Action[](2);
        actions[0] = Actor.Action(
            target, abi.encodeCall(IERC20TemporaryApproval.temporaryApprove, (address(spender), amount)), false
        );
        actions[1] = Actor.Action(address(spender), abi.encodeCall(Actor.run, (nested)), false);
        owner.run(actions);
    }

    function test_BurnFromConsumesTemporaryAllowance() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC20Burnable().buildCuts("Burn", "BURN");
        address d = _assembleTemporary(cuts, inits, data, address(new TokenTestFacet()));
        TokenTestFacet(d).mint(address(owner), 100);
        _grantAndCall(d, abi.encodeCall(IERC20Burnable.burnFrom, (address(owner), 7)), 7);
        assertEq(ERC20(d).balanceOf(address(owner)), 93);
        assertEq(ERC20(d).totalSupply(), 93);
        assertEq(ERC20(d).allowance(address(owner), address(spender)), 0);
    }

    function test_VotesTransferFromConsumesTemporaryAndMovesCheckpoints() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC20Votes().buildCuts("Votes", "VOTE", address(this));
        address d = _assembleTemporary(cuts, inits, data, address(new ERC20VotesTestFacet()));
        ERC20VotesTestFacet(d).mint(address(owner), 100);
        Actor.Action[] memory delegate = new Actor.Action[](1);
        delegate[0] = Actor.Action(d, abi.encodeCall(IVotes.delegate, (address(owner))), false);
        owner.run(delegate);
        _grantAndCall(d, abi.encodeCall(ERC20.transferFrom, (address(owner), recipient, 7)), 7);
        assertEq(IVotes(d).getVotes(address(owner)), 93);
        assertEq(ERC20(d).balanceOf(recipient), 7);
        assertEq(ERC20(d).allowance(address(owner), address(spender)), 0);
    }

    function test_FlashMintRepaymentConsumesTemporaryApproval() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            new DeployERC20FlashMint().buildCuts("Flash", "FLASH");
        address d = _assembleTemporary(cuts, inits, data, address(new TokenTestFacet()));
        TemporaryApprovalBorrower borrower = new TemporaryApprovalBorrower();
        assertTrue(ERC20FlashMint(d).flashLoan(borrower, d, 77, ""));
        assertEq(borrower.balanceDuringCallback(), 77);
        assertEq(ERC20(d).balanceOf(address(borrower)), 0);
        assertEq(ERC20(d).totalSupply(), 0);
        assertEq(ERC20(d).allowance(address(borrower), d), 0);
    }

    function test_ApprovedVaultRedeemConsumesTemporaryShareAllowance() public {
        address asset = _deployERC20("Asset", "ASSET", new FacetCut[](0));
        (FacetCut[] memory cuts, address init, bytes memory initData) =
            new DeployERC4626().buildCuts(asset, "Vault", "VAULT", 0);
        address[] memory inits = new address[](1);
        inits[0] = init;
        bytes[] memory data = new bytes[](1);
        data[0] = initData;
        address d = _assembleTemporary(cuts, inits, data, address(new TokenTestFacet()));
        TokenTestFacet(asset).mint(address(owner), 100);
        Actor.Action[] memory deposit = new Actor.Action[](2);
        deposit[0] = Actor.Action(asset, abi.encodeCall(ERC20.approve, (d, 100)), false);
        deposit[1] = Actor.Action(d, abi.encodeCall(IERC4626.deposit, (100, address(owner))), false);
        owner.run(deposit);
        assertEq(ERC20(d).balanceOf(address(owner)), 100);
        _grantAndCall(d, abi.encodeCall(IERC4626.redeem, (7, recipient, address(owner))), 7);
        assertEq(ERC20(asset).balanceOf(recipient), 7);
        assertEq(ERC20(d).balanceOf(address(owner)), 93);
        assertEq(ERC20(d).allowance(address(owner), address(spender)), 0);
    }
}
