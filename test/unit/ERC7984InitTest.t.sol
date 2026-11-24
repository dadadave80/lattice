// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {MultiInit, MultiInit__StepFailed} from "@diamond/initializers/MultiInit.sol";
import {IFacet} from "@diamond/interfaces/IFacet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {IERC7984, IERC7984Disclosure} from "@lattice/interfaces/tokens/IERC7984.sol";
import {FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";
import {ERC7984Init} from "@lattice/tokens/ERC7984/ERC7984Init.sol";
import {ERC7984Lib} from "@lattice/tokens/ERC7984/libraries/ERC7984Lib.sol";
import {Multicall} from "@lattice/utils/Multicall.sol";
import {Test} from "forge-std/Test.sol";
import {IERC165} from "forge-std/interfaces/IERC165.sol";

/// @dev An empty contract, so a cut can route a selector to an address that has code.
contract SelectorStub {}

/// @dev Writes `value` at `slot` of the diamond, to seed state before another init step.
contract StoreInit {
    function init(bytes32 slot, bytes32 value) external {
        assembly ("memory-safe") {
            sstore(slot, value)
        }
    }
}

/// @dev A composite initializer that calls the library init directly, as Lattice's composite inits do.
contract CompositeInit {
    function init() external {
        ERC7984Lib.__ERC7984_init("C", "C", "");
    }
}

abstract contract ERC7984InitHelpers is Test {
    ERC7984Init erc7984Init;
    ERC165Facet erc165Facet;
    DiamondLoupeFacet loupeFacet;
    StoreInit storeInit;
    MultiInit multiInit;

    /// @dev The 15 deny-list selectors.
    bytes4[15] DENIED = [
        bytes4(0x1cff79cd),
        0x134008d3,
        0xe38335e5,
        0x2656227d,
        0xe9ae5c53,
        0xd691c964,
        0x51945447,
        0xb61d27f6,
        0x34fcd5be,
        0xf2680c0f,
        0x8e845c30,
        0x6f5bfde8,
        0x193704bb,
        0x8670ca3b,
        0x1626ba7e
    ];

    function setUp() public virtual {
        erc7984Init = new ERC7984Init();
        erc165Facet = new ERC165Facet();
        loupeFacet = new DiamondLoupeFacet();
        storeInit = new StoreInit();
        multiInit = new MultiInit();
    }

    function _selectors(address facet) internal view returns (bytes4[] memory selectors) {
        bytes memory packed = IFacet(facet).exportSelectors();
        selectors = new bytes4[](packed.length / 4);
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 selector;
            assembly ("memory-safe") {
                selector := mload(add(add(packed, 32), mul(i, 4)))
            }
            selectors[i] = selector;
        }
    }

    function _none() internal pure returns (FacetCut[] memory) {
        return new FacetCut[](0);
    }

    function _cutOne(address facet, bytes4 selector) internal pure returns (FacetCut[] memory cuts) {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut(facet, FacetCutAction.Add, selectors);
    }

    function _cuts(address a, address b) internal view returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](2);
        cuts[0] = FacetCut(a, FacetCutAction.Add, _selectors(a));
        cuts[1] = FacetCut(b, FacetCutAction.Add, _selectors(b));
    }

    function _baseCuts() internal view returns (FacetCut[] memory) {
        return _cuts(address(erc165Facet), address(loupeFacet));
    }

    function _prepare(FacetCut[] memory extra) internal returns (Lattice d, FacetCut[] memory cuts) {
        d = new Lattice();
        FacetCut[] memory base = _baseCuts();
        cuts = new FacetCut[](base.length + extra.length);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        for (uint256 i; i < extra.length; ++i) {
            cuts[base.length + i] = extra[i];
        }
    }

    function _initData() internal pure returns (bytes memory) {
        return abi.encodeCall(ERC7984Init.init, ("Confidential Token", "cTKN", "ipfs://contract"));
    }

    function _deploy(FacetCut[] memory extra) internal returns (address) {
        return _deployWith(address(erc7984Init), _initData(), extra);
    }

    function _deployWith(address init, bytes memory data, FacetCut[] memory extra) internal returns (address) {
        (Lattice d, FacetCut[] memory cuts) = _prepare(extra);
        d.initialize(cuts, init, data);
        return address(d);
    }

    function _multi(address first, bytes memory firstData) private view returns (address, bytes memory) {
        address[] memory inits = new address[](2);
        bytes[] memory datas = new bytes[](2);
        (inits[0], datas[0]) = (first, firstData);
        (inits[1], datas[1]) = (address(erc7984Init), _initData());
        return (address(multiInit), abi.encodeCall(MultiInit.multiInit, (inits, datas)));
    }

    function _storeThenInit(bytes32 slot, bytes32 value) internal view returns (address, bytes memory) {
        return _multi(address(storeInit), abi.encodeCall(StoreInit.init, (slot, value)));
    }

    function _initTwice() internal view returns (address, bytes memory) {
        return _multi(address(erc7984Init), _initData());
    }
}

/// @title ERC7984InitTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice {ERC7984Init}: the chain-pinned coprocessor configuration, the diamond-caller deny-list and the
///         ERC-165 (interface detection) registration.
contract ERC7984InitTest is ERC7984InitHelpers {
    function test_Init_WritesLocalCoprocessorConfig() public {
        address d = _deploy(_none());
        assertEq(
            vm.load(d, FHEVMLib.CONFIG_SLOT), bytes32(uint256(uint160(0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D)))
        );
        assertEq(
            vm.load(d, bytes32(uint256(FHEVMLib.CONFIG_SLOT) + 1)),
            bytes32(uint256(uint160(0xe3a9105a3a932253A70F126eb1E3b589C643dD24)))
        );
        assertEq(
            vm.load(d, bytes32(uint256(FHEVMLib.CONFIG_SLOT) + 2)),
            bytes32(uint256(uint160(0x901F8942346f7AB3a01F6D7613119Bca447Bb030)))
        );
    }

    function test_Init_RevertWhen_UnsupportedChain() public {
        vm.chainId(8453);
        (Lattice d, FacetCut[] memory cuts) = _prepare(_none());
        vm.expectRevert(abi.encodeWithSelector(FHEVMLib.FHEVMUnsupportedChain.selector, 8453));
        d.initialize(cuts, address(erc7984Init), _initData());
    }

    function test_Init_RevertWhen_ConflictingCoprocessor() public {
        (Lattice d, FacetCut[] memory cuts) = _prepare(_none());
        (address multi, bytes memory data) = _storeThenInit(FHEVMLib.CONFIG_SLOT, bytes32(uint256(0xdead)));
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiInit__StepFailed.selector,
                uint256(1),
                address(erc7984Init),
                abi.encodeWithSelector(
                    FHEVMLib.FHEVMConflictingCoprocessor.selector, address(0xdead), address(0), address(0)
                )
            )
        );
        d.initialize(cuts, multi, data);
    }

    function test_Init_IdenticalRepeatSucceeds() public {
        (address multi, bytes memory data) = _initTwice();
        address d = _deployWith(multi, data, _none());
        assertEq(
            vm.load(d, FHEVMLib.CONFIG_SLOT), bytes32(uint256(uint160(0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D)))
        );
    }

    function testFuzz_Init_RevertWhen_DiamondCallerInstalled(uint8 i) public {
        bytes4 sel = DENIED[bound(i, 0, 14)];
        address stub = address(new SelectorStub());
        (Lattice d, FacetCut[] memory cuts) = _prepare(_cutOne(stub, sel));
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984DiamondCallerInstalled.selector, sel, stub));
        d.initialize(cuts, address(erc7984Init), _initData());
    }

    function test_LibInit_RevertWhen_DiamondCallerInstalled() public {
        address stub = address(new SelectorStub());
        address composite = address(new CompositeInit());
        (Lattice d, FacetCut[] memory cuts) = _prepare(_cutOne(stub, 0x1626ba7e));
        vm.expectRevert(
            abi.encodeWithSelector(IERC7984.ERC7984DiamondCallerInstalled.selector, bytes4(0x1626ba7e), stub)
        );
        d.initialize(cuts, composite, abi.encodeCall(CompositeInit.init, ()));
    }

    function test_Init_AcceptsAdminCutAndMulticall() public {
        address d = _deploy(_cuts(address(new AccessControlDiamondCut()), address(new Multicall())));
        assertTrue(IERC165(d).supportsInterface(0x4958f2a4));
    }

    function test_Init_MakesNoHostCall() public {
        vm.expectCall(0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D, "", 0);
        vm.expectCall(0xe3a9105a3a932253A70F126eb1E3b589C643dD24, "", 0);
        vm.expectCall(0x901F8942346f7AB3a01F6D7613119Bca447Bb030, "", 0);
        _deploy(_none());
    }

    function test_SupportsInterface_OnlyIERC7984() public {
        address d = _deploy(_none());
        assertTrue(IERC165(d).supportsInterface(0x4958f2a4));
        assertFalse(IERC165(d).supportsInterface(0xee3fb15c));
        assertFalse(IERC165(d).supportsInterface(type(IERC7984Disclosure).interfaceId));
    }
}

/// @title ERC7984InitPragueTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice {ERC7984Init} refuses an EIP-7702 (code delegation for externally owned accounts) delegated host.
/// forge-config: default.hardfork = "prague"
contract ERC7984InitPragueTest is ERC7984InitHelpers {
    function test_Init_RevertWhen_HostIsDelegatedEoa() public {
        (address eoa, uint256 pk) = makeAddrAndKey("host");
        vm.signAndAttachDelegation(address(new Lattice()), pk);
        FacetCut[] memory cuts = _baseCuts();
        vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984DelegatedHost.selector, eoa));
        Lattice(payable(eoa)).initialize(cuts, address(erc7984Init), _initData());
    }
}
