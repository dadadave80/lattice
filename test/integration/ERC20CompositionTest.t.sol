// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC3156FlashBorrower} from "@lattice/interfaces/external/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@lattice/interfaces/external/IERC3156FlashLender.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Burnable} from "@lattice/interfaces/tokens/IERC20Burnable.sol";
import {IERC20Capped} from "@lattice/interfaces/tokens/IERC20Capped.sol";
import {PausableLib} from "@lattice/security/libraries/PausableLib.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Burnable} from "@lattice/tokens/ERC20/ERC20Burnable.sol";
import {ERC20Capped} from "@lattice/tokens/ERC20/ERC20Capped.sol";
import {ERC20FlashMint} from "@lattice/tokens/ERC20/ERC20FlashMint.sol";
import {ERC20Pausable} from "@lattice/tokens/ERC20/ERC20Pausable.sol";
import {ERC20BurnableLib} from "@lattice/tokens/ERC20/libraries/ERC20BurnableLib.sol";
import {ERC20CappedLib} from "@lattice/tokens/ERC20/libraries/ERC20CappedLib.sol";
import {ERC20FlashMintLib} from "@lattice/tokens/ERC20/libraries/ERC20FlashMintLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice One token composing FIVE previously-mutually-exclusive facets. Before the de-inheritance refactor each
///         `ERC20Foo is ERC20` re-exported the base selectors, so no two could coexist; now each owns only its own
///         selectors over the shared {ERC20Lib} storage. The transfer/transferFrom override resolution here is the
///         inheritance-flattened analog of a Diamond `Replace` of those selectors with {ERC20Pausable}.
contract ComposedToken is ERC20, ERC20Burnable, ERC20Capped, ERC20FlashMint, ERC20Pausable {
    function initialize(uint256 cap_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init("Composed", "CMP");
        ERC20BurnableLib.__ERC20Burnable_init();
        ERC20CappedLib.__ERC20Capped_init(cap_);
        ERC20FlashMintLib.__ERC20FlashMint_init();
        PausableLib.__Pausable_init();
        InitializableLib.postInitializer(s);
    }

    /// @dev Cap-enforced mint (ERC20Capped._mint is the only `_mint` in scope).
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function pauseIt() external {
        PausableLib._pause();
    }

    // Diamond would `Replace` these with ERC20Pausable; flattened, we resolve the inheritance explicitly.
    function transfer(address to, uint256 value) public override(ERC20, ERC20Pausable) returns (bool) {
        return ERC20Pausable.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value)
        public
        override(ERC20, ERC20Pausable)
        returns (bool)
    {
        return ERC20Pausable.transferFrom(from, to, value);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

contract Borrower is IERC3156FlashBorrower {
    function onFlashLoan(address, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        IERC20(token).approve(token, amount + fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }
}

/// @title ERC20CompositionTest
/// @notice Proof that the de-inherited ERC20 extensions COMPOSE: base + Burnable + Capped + FlashMint + Pausable on
///         a single token, all features working over one shared balance ledger.
contract ERC20CompositionTest is Test {
    ComposedToken token;
    address alice = address(0x1);
    address bob = address(0x2);
    uint256 constant CAP = 1_000_000e18;

    function setUp() public {
        token = new ComposedToken();
        token.initialize(CAP);
        token.mint(alice, 100_000e18);
    }

    function test_AllExtensionInterfacesRegisteredOnOneToken() public view {
        assertTrue(token.supportsInterface(type(IERC20).interfaceId), "IERC20");
        assertTrue(token.supportsInterface(type(IERC20Burnable).interfaceId), "IERC20Burnable");
        assertTrue(token.supportsInterface(type(IERC20Capped).interfaceId), "IERC20Capped");
        assertTrue(token.supportsInterface(type(IERC3156FlashLender).interfaceId), "IERC3156FlashLender");
    }

    function test_CapEnforcedAcrossMint() public {
        assertEq(token.cap(), CAP);
        vm.expectRevert(abi.encodeWithSelector(IERC20Capped.ERC20ExceededCap.selector, CAP + 1, CAP));
        token.mint(bob, CAP - 100_000e18 + 1); // 100k already minted in setUp => pushes supply to CAP+1
    }

    function test_BurnAndTransferShareOneLedger() public {
        vm.prank(alice);
        token.transfer(bob, 40_000e18);
        assertEq(token.balanceOf(bob), 40_000e18);
        vm.prank(bob);
        token.burn(10_000e18);
        assertEq(token.balanceOf(bob), 30_000e18);
        assertEq(token.totalSupply(), 90_000e18, "mint+transfer+burn all hit the same ERC20Lib storage");
    }

    function test_PauseGatesTransferButNotOtherFacets() public {
        token.pauseIt();
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        token.transfer(bob, 1e18);
        // a different facet (burn) still operates while paused
        vm.prank(alice);
        token.burn(1e18);
        assertEq(token.balanceOf(alice), 99_999e18);
    }

    function test_FlashMintComposesWithCappedSupply() public {
        Borrower borrower = new Borrower();
        uint256 supplyBefore = token.totalSupply();
        token.flashLoan(borrower, address(token), 500e18, "");
        assertEq(token.totalSupply(), supplyBefore, "flash principal minted then burned; ledger restored");
    }
}
