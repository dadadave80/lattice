// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IFacet} from "@diamond/interfaces/IFacet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {FhevmTestBase} from "@lattice-test/base/FhevmTestBase.sol";
import {HandleMaker} from "@lattice-test/helpers/ERC7984Actors.sol";
import {ERC7984TestFacet} from "@lattice-test/helpers/ERC7984TestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IERC7984} from "@lattice/interfaces/tokens/IERC7984.sol";
import {CoprocessorConfig, FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";
import {ERC7984} from "@lattice/tokens/ERC7984/ERC7984.sol";
import {ERC7984Init} from "@lattice/tokens/ERC7984/ERC7984Init.sol";
import {Multicall} from "@lattice/utils/Multicall.sol";

/// @dev Writes the chain's three coprocessor host addresses at {FHEVMLib.CONFIG_SLOT}, as another `FHE.sol`
///      facet's initializer would, without running `__ERC7984_init`.
contract ConfigStoreInit {
    function init() external {
        CoprocessorConfig memory hosts = FHEVMLib.hostsFor(block.chainid);
        bytes32 slot = FHEVMLib.CONFIG_SLOT;
        (address acl, address executor, address kmsVerifier) = (hosts.acl, hosts.executor, hosts.kmsVerifier);
        assembly ("memory-safe") {
            sstore(slot, acl)
            sstore(add(slot, 1), executor)
            sstore(add(slot, 2), kmsVerifier)
        }
    }
}

/// @title ERC7984TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-7984 (confidential fungible token) tests over a real {Lattice} diamond and the vendored
///         FHEVM (Fully Homomorphic Encryption Virtual Machine) harness. `setUp` cuts ERC165, the loupe, the
///         {ERC7984} facet, the test-only {ERC7984TestFacet} and {Multicall}, runs {ERC7984Init}, and mints
///         1,000,000 to `holder`.
abstract contract ERC7984TestBase is FhevmTestBase {
    address internal holder = makeAddr("holder");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal mallory = makeAddr("mallory");
    address internal op = makeAddr("op");

    address internal diamond;
    IERC7984 internal token;
    HandleMaker internal maker;

    /// @dev A diamond with the same cuts and no initializer.
    address internal bare;

    address private erc165Facet;
    address private loupeFacet;
    address private erc7984Facet;
    address private testFacet;
    address private multicallFacet;
    address private erc7984Init;

    function setUp() public virtual override {
        super.setUp();
        erc165Facet = address(new ERC165Facet());
        loupeFacet = address(new DiamondLoupeFacet());
        erc7984Facet = address(new ERC7984());
        testFacet = address(new ERC7984TestFacet());
        multicallFacet = address(new Multicall());
        erc7984Init = address(new ERC7984Init());
        maker = new HandleMaker();

        diamond = _deployToken();
        token = IERC7984(diamond);
        ERC7984TestFacet(diamond).mint(holder, 1_000_000);

        Lattice b = new Lattice();
        b.initialize(_cuts(), address(0), "");
        bare = address(b);
    }

    /// @notice An encrypted input of `v` from `user`, bound to the token diamond.
    function _input(address user, uint64 v) internal returns (externalEuint64, bytes memory) {
        return encryptUint64(v, user, diamond);
    }

    /// @notice A fresh, initialized token diamond with no balances.
    function _deployToken() internal returns (address) {
        Lattice d = new Lattice();
        d.initialize(
            _cuts(), erc7984Init, abi.encodeCall(ERC7984Init.init, ("Confidential Token", "cTKN", "ipfs://contract"))
        );
        return address(d);
    }

    /// @notice A diamond with the same cuts whose initializer only writes the shared coprocessor configuration.
    function _bareWithConfig() internal returns (address) {
        Lattice d = new Lattice();
        address init = address(new ConfigStoreInit());
        d.initialize(_cuts(), init, abi.encodeCall(ConfigStoreInit.init, ()));
        return address(d);
    }

    function _cuts() internal view returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](5);
        cuts[0] = _cut(erc165Facet);
        cuts[1] = _cut(loupeFacet);
        cuts[2] = _cut(erc7984Facet);
        cuts[3] = _cut(testFacet);
        cuts[4] = _cut(multicallFacet);
    }

    function _cut(address facet) private view returns (FacetCut memory) {
        bytes memory packed = IFacet(facet).exportSelectors();
        bytes4[] memory selectors = new bytes4[](packed.length / 4);
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 selector;
            assembly ("memory-safe") {
                selector := mload(add(add(packed, 32), mul(i, 4)))
            }
            selectors[i] = selector;
        }
        return FacetCut(facet, FacetCutAction.Add, selectors);
    }

    function _one(address a) internal pure returns (address[] memory list) {
        list = new address[](1);
        list[0] = a;
    }

    function _two(address a, address b) internal pure returns (address[] memory list) {
        list = new address[](2);
        (list[0], list[1]) = (a, b);
    }

    function _one32(bytes32 h) internal pure returns (bytes32[] memory list) {
        list = new bytes32[](1);
        list[0] = h;
    }
}
