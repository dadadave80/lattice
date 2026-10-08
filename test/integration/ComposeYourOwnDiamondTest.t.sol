// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {DiamondValidationLib} from "@lattice/governance/libraries/DiamondValidationLib.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Burnable} from "@lattice/interfaces/tokens/IERC20Burnable.sol";
import {IERC20Capped} from "@lattice/interfaces/tokens/IERC20Capped.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Burnable} from "@lattice/tokens/ERC20/ERC20Burnable.sol";
import {ERC20Capped} from "@lattice/tokens/ERC20/ERC20Capped.sol";
import {ERC20CappedLib} from "@lattice/tokens/ERC20/libraries/ERC20CappedLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Constructor-style parameters for {CappedTokenInit}.
struct CappedTokenParams {
    address admin; // receives DEFAULT_ADMIN_ROLE, which gates `diamondCut`
    string name;
    string symbol;
    uint256 cap; // maximum total supply
    address holder; // receives the initial supply
    uint256 supply; // initial supply, at most `cap`
}

/// @title CappedTokenInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The worked example from "Compose your own Diamond": one initializer that runs every module init in
///         dependency order inside the proxy's single initializing window. It opens no window of its own.
contract CappedTokenInit {
    function init(CappedTokenParams calldata p) external {
        // 1. Authority first: the cut facet checks DEFAULT_ADMIN_ROLE on every later upgrade.
        AccessControlLib.__AccessControl_init(p.admin);
        ERC165Lib.registerInterface(); // ERC-165 flag for IERC165 itself (0x01ffc9a7)
        DiamondLib.registerInterface(); // ERC-165 flags for the cut and loupe facets this recipe installs
        // 2. The token, then the cap that constrains it.
        ERC20Lib.__ERC20_init(p.name, p.symbol);
        ERC20CappedLib.__ERC20Capped_init(p.cap);
        // 3. Seed supply only once the cap exists, and enforce it.
        ERC20CappedLib._checkCap(ERC20Lib.totalSupply() + p.supply);
        ERC20Lib._mint(p.holder, p.supply);
    }
}

/// @title DeployCappedToken
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The worked example from "Compose your own Diamond": an admin-upgradeable, capped ERC-20 built from
///         existing facets, following the same four steps as the governed vault.
contract DeployCappedToken is BaseDeploy {
    /// @notice Step 1: pick modules. Each facet is cut for its own exported selectors. These facets share no
    ///         selector, so no `_cutExcept` reconciliation is needed (the vault recipe shows that case).
    function buildCuts(CappedTokenParams memory p)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        // Step 2: validate the declared storage owners before deploying anything.
        DiamondValidationLib.assertNamespacesDisjoint(storageNamespaces());
        cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new AccessControlDiamondCut()));
        cuts[3] = _cut(address(new DiamondLoupeFacet()));
        cuts[4] = _cut(address(new ERC20()));
        cuts[5] = _cut(address(new ERC20Capped()));
        // Step 3: one initializer, run in dependency order.
        init = address(new CappedTokenInit());
        initCalldata = abi.encodeCall(CappedTokenInit.init, (p));
    }

    /// @notice Every ERC-7201 owner the composition writes, including transitive ones. The cut facet calls
    ///         `EmergencyStopLib.checkNotStopped`, so EmergencyStop storage is an owner even though no
    ///         EmergencyStop facet is cut.
    function storageNamespaces() public pure virtual returns (string[] memory ids) {
        ids = new string[](6);
        ids[0] = "diamond.lib.storage";
        ids[1] = "diamond.lib.storage.ERC165";
        ids[2] = "lattice.storage.AccessControl";
        ids[3] = "lattice.storage.EmergencyStop";
        ids[4] = "lattice.storage.ERC20";
        ids[5] = "lattice.storage.ERC20Capped";
    }

    /// @notice Step 4: create and initialize the proxy in one transaction through the factory.
    function deployAtomic(CappedTokenParams memory p, LatticeFactory factory, bytes32 salt)
        public
        returns (address token)
    {
        (FacetCut[] memory cuts, address init, bytes memory data) = buildCuts(p);
        token = factory.deploy(new RecipeEntry[](0), cuts, init, data, salt);
    }
}

/// @title ComposeYourOwnDiamondTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Keeps the guide's worked example compiling and correct.
contract ComposeYourOwnDiamondTest is Test {
    DeployCappedToken internal recipe;
    LatticeFactory internal factory;
    address internal token;

    address internal admin = address(0xAD);
    address internal holder = address(0xB0B);
    address internal stranger = address(0xC3);

    function _params() internal view returns (CappedTokenParams memory) {
        return CappedTokenParams(admin, "Capped Token", "CAP", 1_000_000 ether, holder, 400_000 ether);
    }

    function setUp() public {
        recipe = new DeployCappedToken();
        factory = new LatticeFactory(new LatticeRegistry(address(this)), address(0), address(0));
        token = recipe.deployAtomic(_params(), factory, bytes32(0));
    }

    function test_ComposedTokenIsInitializedInOneTransaction() public view {
        assertEq(token, factory.predict(address(recipe), bytes32(0)), "deployed at the predicted address");
        assertEq(IERC20(token).name(), "Capped Token");
        assertEq(IERC20Capped(token).cap(), 1_000_000 ether);
        assertEq(IERC20(token).balanceOf(holder), 400_000 ether);
        assertTrue(IAccessControl(token).hasRole(DEFAULT_ADMIN_ROLE, admin), "admin holds the upgrade role");
        assertFalse(IAccessControl(token).hasRole(DEFAULT_ADMIN_ROLE, address(factory)), "the factory holds none");
        assertEq(IDiamondLoupe(token).facetAddresses().length, 6, "six facets routed");
        assertTrue(ERC165Facet(token).supportsInterface(0x01ffc9a7), "answers IERC165 (ERC-165 compliant)");
        assertFalse(ERC165Facet(token).supportsInterface(0xffffffff), "rejects the ERC-165 invalid id");
    }

    function test_InitialSupplyAboveCapReverts() public {
        CappedTokenParams memory p = _params();
        p.supply = p.cap + 1;
        vm.expectRevert(abi.encodeWithSelector(IERC20Capped.ERC20ExceededCap.selector, p.cap + 1, p.cap));
        recipe.deployAtomic(p, factory, bytes32(uint256(1)));
        assertEq(factory.predict(address(recipe), bytes32(uint256(1))).code.length, 0, "no partial proxy");
    }

    function test_DuplicateNamespaceRejected() public {
        CollidingCappedToken colliding = new CollidingCappedToken();
        string[] memory ids = colliding.storageNamespaces();
        vm.expectRevert(
            abi.encodeWithSelector(
                DiamondValidationLib.NamespaceCollision.selector,
                DiamondValidationLib.erc7201Slot(ids[0]),
                ids[0],
                ids[0]
            )
        );
        colliding.deployAtomic(_params(), factory, bytes32(0));
    }

    /// @notice A later upgrade: the admin adds ERC20Burnable. A stranger cannot.
    function test_AdminUpgradeAddsBurnable() public {
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({
            facetAddress: address(new ERC20Burnable()), action: FacetCutAction.Add, functionSelectors: _burnSelectors()
        });

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, DEFAULT_ADMIN_ROLE
            )
        );
        IDiamondCut(token).diamondCut(cuts, address(0), "");

        vm.prank(admin);
        IDiamondCut(token).diamondCut(cuts, address(0), "");

        vm.prank(holder);
        IERC20Burnable(token).burn(100_000 ether);
        assertEq(IERC20(token).totalSupply(), 300_000 ether, "burn routed through the new facet");
        assertEq(IERC20Capped(token).cap(), 1_000_000 ether, "existing state preserved");
    }

    function _burnSelectors() internal pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = IERC20Burnable.burn.selector;
        s[1] = IERC20Burnable.burnFrom.selector;
    }
}

/// @notice The worked example with one storage owner declared twice.
contract CollidingCappedToken is DeployCappedToken {
    function storageNamespaces() public pure override returns (string[] memory ids) {
        ids = super.storageNamespaces();
        ids[1] = ids[0];
    }
}
