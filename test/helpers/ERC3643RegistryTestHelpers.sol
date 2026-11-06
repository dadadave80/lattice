// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {OwnableFacet} from "@diamond/facets/OwnableFacet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IERC3643ClaimIssuer} from "@lattice/interfaces/external/erc3643/IERC3643ClaimIssuer.sol";
import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ERC3643AgentRole} from "@lattice/tokens/ERC3643/ERC3643AgentRole.sol";
import {ERC3643ClaimTopicsRegistry} from "@lattice/tokens/ERC3643/ERC3643ClaimTopicsRegistry.sol";
import {ERC3643Compliance} from "@lattice/tokens/ERC3643/ERC3643Compliance.sol";
import {ERC3643IdentityRegistry} from "@lattice/tokens/ERC3643/ERC3643IdentityRegistry.sol";
import {ERC3643IdentityRegistryStorage} from "@lattice/tokens/ERC3643/ERC3643IdentityRegistryStorage.sol";
import {ERC3643TrustedIssuersRegistry} from "@lattice/tokens/ERC3643/ERC3643TrustedIssuersRegistry.sol";
import {ERC3643AgentRoleLib} from "@lattice/tokens/ERC3643/libraries/ERC3643AgentRoleLib.sol";
import {ERC3643ClaimTopicsRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ClaimTopicsRegistryLib.sol";
import {ERC3643ComplianceLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ComplianceLib.sol";
import {ERC3643ExecutionLib} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";
import {ERC3643IdentityRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643IdentityRegistryLib.sol";
import {
    ERC3643IdentityRegistryStorageLib
} from "@lattice/tokens/ERC3643/libraries/ERC3643IdentityRegistryStorageLib.sol";
import {ERC3643TrustedIssuersRegistryLib} from "@lattice/tokens/ERC3643/libraries/ERC3643TrustedIssuersRegistryLib.sol";
import {Test} from "forge-std/Test.sol";

interface RegistrySelectorExport {
    function exportSelectors() external pure returns (bytes memory);
}

/// @notice Unit-only initializer; production's closed admission is tested separately by the canonical recipe.
contract RegistryComponentsUnitInit {
    function init(address owner, address store) external {
        ERC3643ExecutionLib.enter();
        OwnableLib.initializeOwner(owner);
        address[] memory agents = new address[](1);
        agents[0] = owner;
        ERC3643AgentRoleLib.__ERC3643AgentRole_init(agents);
        ERC3643IdentityRegistryStorageLib.__ERC3643IdentityRegistryStorage_init();
        ERC3643IdentityRegistryStorageLib._bindIdentityRegistry(address(this));
        ERC3643TrustedIssuersRegistryLib.__ERC3643TrustedIssuersRegistry_init();
        ERC3643ClaimTopicsRegistryLib.__ERC3643ClaimTopicsRegistry_init();
        ERC3643ComplianceLib.__ERC3643Compliance_init();
        ERC3643ComplianceLib._bindToken(address(this));
        ERC3643IdentityRegistryLib.__ERC3643IdentityRegistry_init(
            store == address(0) ? address(this) : store, address(this), address(this)
        );
        ERC3643ExecutionLib.exit();
    }
}

contract RegistryStorageUnitInit {
    function init(address owner) external {
        OwnableLib.initializeOwner(owner);
        ERC3643IdentityRegistryStorageLib.__ERC3643IdentityRegistryStorage_init();
    }
}

contract RegistryExecutionProbe {
    function attempt(bytes calldata input) external returns (bool, bytes memory) {
        ERC3643ExecutionLib.enter();
        (bool ok, bytes memory result) = address(this).call(input);
        ERC3643ExecutionLib.exit();
        return (ok, result);
    }

    function localCallbacks() external {
        ERC3643ExecutionLib.enter();
        ERC3643ComplianceLib._transferred(address(1), address(2), 3);
        ERC3643ComplianceLib._created(address(2), 3);
        ERC3643ComplianceLib._destroyed(address(1), 3);
        ERC3643ExecutionLib.exit();
    }
}

contract RegistryIdentityMock is IERC3643Identity {
    struct Claim {
        uint256 topic;
        uint256 scheme;
        address issuer;
        bytes signature;
        bytes data;
        string uri;
    }
    mapping(bytes32 => Claim) internal claims;
    mapping(bytes32 => bool) internal management;
    bool public revertClaims;
    address public reentryTarget;
    bytes public reentryInput;

    function setManagement(address wallet, bool allowed) external {
        management[keccak256(abi.encode(wallet))] = allowed;
    }

    function setClaim(uint256 topic, address issuer, bytes calldata signature, bytes calldata data) external {
        claims[keccak256(abi.encode(issuer, topic))] = Claim(topic, 1, issuer, signature, data, "");
    }

    function clearClaim(uint256 topic, address issuer) external {
        delete claims[keccak256(abi.encode(issuer, topic))];
    }

    function setRevert(bool value) external {
        revertClaims = value;
    }

    function setReentry(address target, bytes calldata input) external {
        reentryTarget = target;
        reentryInput = input;
    }

    function keyHasPurpose(bytes32 key, uint256 purpose) external view returns (bool) {
        return purpose == 1 && management[key];
    }

    function getClaim(bytes32 claimId)
        external
        view
        returns (uint256, uint256, address, bytes memory, bytes memory, string memory)
    {
        require(!revertClaims, "claim failure");
        if (reentryTarget != address(0)) {
            (bool ok,) = reentryTarget.staticcall(reentryInput);
            require(!ok, "reentrant mutation succeeded");
        }
        Claim storage c = claims[claimId];
        return (c.topic, c.scheme, c.issuer, c.signature, c.data, c.uri);
    }
}

contract RegistryIssuerMock is IERC3643ClaimIssuer {
    bool public valid = true;
    bool public revertValidation;
    uint256 public returnMode;
    address public expectedIdentity;
    uint256 public expectedTopic;
    bool public bindSubject;

    function setValid(bool value) external {
        valid = value;
    }

    function setRevert(bool value) external {
        revertValidation = value;
    }

    function setReturnMode(uint256 value) external {
        returnMode = value;
    }

    function setSubject(address identity_, uint256 topic) external {
        expectedIdentity = identity_;
        expectedTopic = topic;
        bindSubject = true;
    }

    function isClaimValid(IERC3643Identity identity_, uint256 topic, bytes calldata signature, bytes calldata data)
        external
        view
        returns (bool)
    {
        require(!revertValidation, "issuer failure");
        if (returnMode == 1) {
            assembly ("memory-safe") { return(0, 0) }
        }
        if (returnMode == 2) {
            assembly ("memory-safe") {
                mstore(0, 2)
                return(0, 32)
            }
        }
        return valid && (!bindSubject || (address(identity_) == expectedIdentity && topic == expectedTopic))
            && keccak256(signature) == keccak256(hex"cafe") && keccak256(data) == keccak256(hex"beef");
    }
}

contract RegistryRawIdentity {
    bytes internal reply;

    function setReply(bytes calldata value) external {
        reply = value;
    }

    fallback(bytes calldata) external returns (bytes memory) {
        return reply;
    }
}

contract RegistryCallbackCaller {
    function notify(address compliance) external {
        ICompliance(compliance).transferred(address(1), address(2), 3);
        ICompliance(compliance).created(address(2), 3);
        ICompliance(compliance).destroyed(address(1), 3);
    }
}

abstract contract ERC3643RegistryTestBase is Test {
    function _selectors(address facet) internal view returns (bytes4[] memory selectors) {
        bytes memory packed = RegistrySelectorExport(facet).exportSelectors();
        selectors = new bytes4[](packed.length / 4);
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 selector;
            assembly ("memory-safe") { selector := mload(add(add(packed, 32), mul(i, 4))) }
            selectors[i] = selector;
        }
    }

    function _cut(address facet) internal view returns (FacetCut memory) {
        return FacetCut(facet, FacetCutAction.Add, _selectors(facet));
    }

    function _registryCuts() internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](9);
        cuts[0] = _cut(address(new OwnableFacet()));
        cuts[1] = _cut(address(new ERC165Facet()));
        cuts[2] = _cut(address(new ERC3643AgentRole()));
        cuts[3] = _cut(address(new ERC3643IdentityRegistry()));
        cuts[4] = _cut(address(new ERC3643IdentityRegistryStorage()));
        cuts[5] = _cut(address(new ERC3643TrustedIssuersRegistry()));
        cuts[6] = _cut(address(new ERC3643ClaimTopicsRegistry()));
        cuts[7] = _cut(address(new ERC3643Compliance()));
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = RegistryExecutionProbe.attempt.selector;
        selectors[1] = RegistryExecutionProbe.localCallbacks.selector;
        cuts[8] = FacetCut(address(new RegistryExecutionProbe()), FacetCutAction.Add, selectors);
    }

    function _deployRegistry(address store) internal returns (address) {
        Lattice d = new Lattice();
        if (store != address(0)) IIdentityRegistryStorage(store).bindIdentityRegistry(address(d));
        d.initialize(
            _registryCuts(),
            address(new RegistryComponentsUnitInit()),
            abi.encodeCall(RegistryComponentsUnitInit.init, (address(this), store))
        );
        return address(d);
    }

    function _deployStorage() internal returns (address) {
        FacetCut[] memory cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new OwnableFacet()));
        cuts[1] = _cut(address(new ERC165Facet()));
        cuts[2] = _cut(address(new ERC3643IdentityRegistryStorage()));
        Lattice d = new Lattice();
        d.initialize(
            cuts, address(new RegistryStorageUnitInit()), abi.encodeCall(RegistryStorageUnitInit.init, (address(this)))
        );
        return address(d);
    }

    function _topics(uint256 a) internal pure returns (uint256[] memory values) {
        values = new uint256[](1);
        values[0] = a;
    }
}
