// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ILatticeFactory, RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";

/// @title RawCode
/// @notice Deploys contracts whose runtime returns a fixed byte string verbatim for ANY call, so a test controls
///         the exact return data an `exportSelectors()` staticcall sees: canonical encodings, malformed offsets
///         and lengths, truncated data, trailing bytes. The answer is baked into the code, so the contract is
///         `pure`-equivalent and its codehash commits to the answer.
library RawCode {
    /// @notice A contract that returns `ret` verbatim for every call.
    /// @dev Runtime = 15-byte stub ++ `ret`. The stub copies `ret` out of its own code and returns it.
    ///      Initcode = 12-byte loader ++ runtime.
    function deploy(bytes memory ret) internal returns (address deployed) {
        uint256 len = ret.length;
        require(len + 15 <= 24_576, "RawCode: runtime over EIP-170");
        bytes memory runtime = abi.encodePacked(
            hex"61", uint16(len), hex"61", uint16(15), hex"600039", hex"61", uint16(len), hex"6000f3", ret
        );
        bytes memory initCode = abi.encodePacked(hex"61", uint16(runtime.length), hex"80600c6000396000f3", runtime);
        assembly ("memory-safe") {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(deployed != address(0), "RawCode: create failed");
    }

    /// @notice A well-formed ERC-8153 exporter: returns the canonical ABI encoding of `blob`.
    function exporter(bytes memory blob) internal returns (address) {
        return deploy(abi.encode(blob));
    }

    /// @notice A packed blob of `n` distinct selectors derived from `tag`, avoiding the ERC-8153 self-selector.
    function selectorBlob(bytes32 tag, uint256 n) internal pure returns (bytes memory blob) {
        blob = new bytes(4 * n);
        for (uint256 i; i < n; ++i) {
            bytes4 s = bytes4(keccak256(abi.encode(tag, i)));
            if (s == 0x0ef22643) s = bytes4(keccak256(abi.encode(tag, i, "retry")));
            for (uint256 k; k < 4; ++k) {
                blob[4 * i + k] = s[k];
            }
        }
    }

    /// @notice Unpacks a packed selector blob into `bytes4[]`.
    function unpack(bytes memory blob) internal pure returns (bytes4[] memory selectors) {
        uint256 n = blob.length / 4;
        selectors = new bytes4[](n);
        for (uint256 i; i < n; ++i) {
            bytes4 s;
            assembly ("memory-safe") {
                s := mload(add(add(blob, 0x20), mul(i, 4)))
            }
            selectors[i] = s;
        }
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                         HOSTILE SELECTOR EXPORTERS
//////////////////////////////////////////////////////////////////////////*//

/// @notice A stateful exporter: `exportSelectors()` reads the facet's OWN storage, so two instances share a
///         codehash but can export different selectors. Legal under a `staticcall`, which cannot enforce `pure`.
contract CoreFlippingExporter {
    bool public flipped;

    function flip() external {
        flipped = !flipped;
    }

    function exportSelectors() external view returns (bytes memory) {
        return flipped ? abi.encodePacked(bytes4(0xAAAAAAAA)) : abi.encodePacked(bytes4(0x11111111));
    }
}

/// @notice A stateful raw exporter: every call except {set} returns the stored bytes verbatim. It keeps one
///         codehash, so a record registered while it answers canonically passes the code pin after {set}
///         switches it to a malformed answer. That reaches the registry's LIVE read path.
contract CoreSwitchableRawExporter {
    bytes internal _ret;

    function set(bytes calldata ret) external {
        _ret = ret;
    }

    fallback() external {
        bytes memory ret = _ret;
        assembly ("memory-safe") {
            return(add(ret, 0x20), mload(ret))
        }
    }
}

/// @notice An exporter that never returns: it burns all the gas the `staticcall` forwards.
contract CoreLoopExporter {
    function exportSelectors() external pure returns (bytes memory selectors) {
        while (true) {}
        selectors = "";
    }
}

/// @notice A return-data bomb: a valid one-selector encoding followed by `size - 96` zero bytes. The registry
///         copies the whole return into memory before decoding, so the caller pays for every byte.
contract CoreReturnBombExporter {
    uint256 public immutable size;

    constructor(uint256 size_) {
        size = size_;
    }

    function exportSelectors() external view returns (bytes memory) {
        uint256 n = size;
        assembly ("memory-safe") {
            mstore(0x00, 0x20)
            mstore(0x20, 4)
            mstore(0x40, shl(224, 0x12345678))
            return(0x00, n)
        }
    }
}

/// @notice An exporter that tries to write to the registry from inside the registry's own `staticcall`.
contract CoreReentrantAttestExporter {
    ILatticeRegistry public immutable registry;

    constructor(ILatticeRegistry registry_) {
        registry = registry_;
    }

    function exportSelectors() external returns (bytes memory) {
        registry.attest(address(this));
        return abi.encodePacked(bytes4(0x13131313));
    }
}

/// @notice An exporter that lists the {Lattice} proxy's own `initialize` selector. The cut succeeds, but the
///         proxy's own function shadows it, so the facet is never reached through the diamond for it.
contract CoreShadowedSelectorFacet {
    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(Lattice.initialize.selector, CoreShadowedSelectorFacet.shadowPing.selector);
    }

    function shadowPing() external pure returns (uint256) {
        return 31;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                         DISPATCHABLE ERC-8153 FACETS
//////////////////////////////////////////////////////////////////////////*//

/// @notice A curated ERC-8153 facet whose `value()` returns a constructor-chosen constant. Each distinct value is
///         distinct bytecode, so value 1 and value 2 behave as two registry versions of one facet.
contract CoreValueFacet {
    uint256 public immutable fixedValue;

    constructor(uint256 v) {
        fixedValue = v;
    }

    function value() external view returns (uint256) {
        return fixedValue;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(CoreValueFacet.value.selector);
    }
}

/// @notice A second ERC-8153 facet, selector-disjoint from {CoreValueFacet}.
contract CorePingFacet {
    function ping() external pure returns (uint256) {
        return 7;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(CorePingFacet.ping.selector);
    }
}

/// @notice An ERC-8153 facet that also exports {CoreValueFacet.value}'s selector: a registry/registry collision.
contract CoreValueCollidingFacet {
    function value() external pure returns (uint256) {
        return 99;
    }

    function exportSelectors() external pure returns (bytes memory) {
        return abi.encodePacked(CoreValueCollidingFacet.value.selector);
    }
}

/// @notice A plain facet with no ERC-8153 surface, cut through `customCuts`.
contract CorePongFacet {
    function pong() external pure returns (uint256) {
        return 42;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                 INITIALIZERS
//////////////////////////////////////////////////////////////////////////*//

/// @notice Grants `DEFAULT_ADMIN_ROLE` to `msg.sender`. Delegatecalled by {Lattice.initialize}, whose caller is
///         the FACTORY, so the factory (not the deployer) becomes the admin.
contract CoreGrantSenderInit {
    function init() external {
        AccessControlLib.__AccessControl_init(msg.sender);
    }
}

/// @notice Reverts with a custom error, so the factory's atomic rollback can be checked against an exact reason.
contract CoreRevertingInit {
    error CoreInitRefused(uint256 code);

    function init(uint256 code) external pure {
        revert CoreInitRefused(code);
    }
}

/// @notice Writes a marker into a fixed slot of the diamond, so a test can see whether the init ran.
contract CoreMarkerInit {
    bytes32 public constant MARKER_SLOT = keccak256("lattice.test.core.marker");

    function init(uint256 marker) external {
        bytes32 slot = MARKER_SLOT;
        assembly ("memory-safe") {
            sstore(slot, marker)
        }
    }
}

/// @notice Re-enters the proxy's own `initialize` from inside the first initialization (the initializer guard
///         must refuse it, and the whole deploy must roll back).
contract CoreReinitializeInit {
    function init(FacetCut[] calldata extra) external {
        Lattice(payable(address(this))).initialize(extra, address(0), "");
    }
}

/// @notice Self-destructs the diamond from inside its own initialization. The diamond was created in the same
///         transaction, so under EIP-6780 the account is deleted when the transaction ends.
contract CoreSelfDestructInit {
    function init() external {
        selfdestruct(payable(address(0)));
    }
}

/// @notice Re-enters `factory.deploy` from inside the diamond's initialization. The nested call's `msg.sender`
///         is the new diamond, so its salt is bound to the diamond, never to the outer deployer.
contract CoreNestedDeployInit {
    bytes32 public constant CHILD_SLOT = keccak256("lattice.test.core.child");

    function init(ILatticeFactory factory, FacetCut[] calldata cuts, bytes32 salt) external {
        address child = factory.deploy(new RecipeEntry[](0), cuts, address(0), "", salt);
        bytes32 slot = CHILD_SLOT;
        assembly ("memory-safe") {
            sstore(slot, child)
        }
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                         HOSTILE REGISTRY / FORWARDER
//////////////////////////////////////////////////////////////////////////*//

/// @notice A non-canonical registry that answers `latest` and `getCut` with whatever cut the test configured.
///         A factory bound to it trusts that cut: registry-resolved cuts are never re-validated by the factory.
contract CoreHostileRegistry {
    address internal _facet;
    FacetCutAction internal _action;
    bytes4[] internal _selectors;

    function configure(address facet, FacetCutAction action, bytes4[] calldata selectors) external {
        _facet = facet;
        _action = action;
        _selectors = selectors;
    }

    function latest(bytes32) external pure returns (ILatticeRegistry.Record memory record) {
        record.version = 1;
    }

    function getCut(bytes32, uint64) external view returns (FacetCut memory cut) {
        cut = FacetCut({facetAddress: _facet, action: _action, functionSelectors: _selectors});
    }
}

/// @notice A shared call forwarder (the shape of Multicall3 or a relayer): every user behind it reaches the
///         factory with the SAME `msg.sender`.
contract CoreForwarder {
    function forward(address target, bytes calldata data) external returns (bytes memory ret) {
        bool ok;
        (ok, ret) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}
