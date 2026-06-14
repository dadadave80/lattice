// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {UpgradeDiamond} from "@lattice-script/UpgradeDiamond.s.sol";
import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/IGovernedDiamondCut.sol";
import {Test} from "forge-std/Test.sol";

/// @notice A trivial facet-like contract (constructor-less) to deploy via the script's CREATE3 path.
contract FacetStub {
    function tag() external pure returns (uint256) {
        return 0xFACE;
    }
}

/// @notice A trivial "Diamond-like" contract with a constructor arg, to prove CREATE3 ignores initcode
///         (i.e. the deployed address is independent of constructor args / bytecode).
contract DiamondStub {
    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }
}

/// @notice Faithful mock of CreateX's CREATE3 path: implements the SAME `_guard` transform and the
///         SAME `computeCreate3Address(guardedSalt)` derivation as the canonical contract, so an
///         etched instance at the canonical address lets us test the {UpgradeDiamond} script's
///         deterministic-deploy methods without a mainnet fork.
contract MockCreateX {
    error FailedContractCreation();
    error InvalidSalt();

    bytes internal constant PROXY_CHILD_BYTECODE = hex"67363d3d37363d34f03d5260086018f3";

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            hash := keccak256(0x00, 0x40)
        }
    }

    function _guard(bytes32 salt) internal view returns (bytes32 guardedSalt) {
        bool senderIsMsgSender = address(bytes20(salt)) == msg.sender;
        bool senderIsZero = address(bytes20(salt)) == address(0);
        bytes1 flag = bytes1(salt[20]);
        if (senderIsMsgSender && flag == hex"01") {
            guardedSalt = keccak256(abi.encode(msg.sender, block.chainid, salt));
        } else if (senderIsMsgSender && flag == hex"00") {
            guardedSalt = _efficientHash(bytes32(uint256(uint160(msg.sender))), salt);
        } else if (senderIsMsgSender) {
            revert InvalidSalt();
        } else if (senderIsZero && flag == hex"01") {
            guardedSalt = _efficientHash(bytes32(block.chainid), salt);
        } else if (senderIsZero) {
            revert InvalidSalt();
        } else {
            guardedSalt = keccak256(abi.encode(salt));
        }
    }

    function computeCreate3Address(bytes32 salt, address deployer) public pure returns (address) {
        bytes32 proxyInitHash = keccak256(PROXY_CHILD_BYTECODE);
        address proxy = address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", deployer, salt, proxyInitHash)))));
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", proxy, hex"01")))));
    }

    function computeCreate3Address(bytes32 salt) external view returns (address) {
        return computeCreate3Address(salt, address(this));
    }

    function deployCreate3(bytes32 salt, bytes memory initCode) public payable returns (address newContract) {
        bytes32 guardedSalt = _guard(salt);
        bytes memory proxyChildBytecode = PROXY_CHILD_BYTECODE;
        address proxy;
        assembly ("memory-safe") {
            proxy := create2(0, add(proxyChildBytecode, 32), mload(proxyChildBytecode), guardedSalt)
        }
        if (proxy == address(0)) revert FailedContractCreation();
        newContract = computeCreate3Address(guardedSalt, address(this));
        (bool success,) = proxy.call{value: msg.value}(initCode);
        if (!success || newContract.code.length == 0) revert FailedContractCreation();
    }

    function deployCreate3(bytes memory initCode) external payable returns (address newContract) {
        newContract = deployCreate3(keccak256(abi.encode(block.number, msg.sender)), initCode);
    }
}

/// @notice Exercises the {UpgradeDiamond} script's deterministic CreateX CREATE3 deploy helpers and
///         its governed-cut proposal assembly, with a faithful MockCreateX etched at the canonical
///         singleton address (no fork, no `--broadcast`). The load-bearing assertion is that the
///         Diamond deployed via the script equals the address {predictDiamond} pre-computes.
contract UpgradeDiamondScriptTest is Test {
    address internal constant CANONICAL = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    UpgradeDiamond internal script;

    function setUp() public {
        MockCreateX impl = new MockCreateX();
        vm.etch(CANONICAL, address(impl).code);
        script = new UpgradeDiamond();
    }

    /// @notice The Diamond deployed via the script lands at exactly the address `predictDiamond`
    ///         pre-computes — the core cross-chain-stable invariant.
    /// @dev CreateX pins the deterministic address to ITS OWN `msg.sender`. When the script forwards a
    ///      deploy, the nested call into CreateX has `msg.sender == address(script)`; under real
    ///      `forge script --broadcast`, Foundry rewrites each broadcasted call to originate from the
    ///      deployer EOA as a standalone tx, so CreateX sees that EOA. To reproduce that alignment in a
    ///      plain unit test (no script runtime), we prank the script call FROM `address(script)` so the
    ///      salt the script mints (pinned to its `msg.sender`) matches the deployer CreateX observes.
    function test_DeployedDiamondEqualsPredicted() public {
        bytes11 entropy = bytes11(uint88(0x0102030405060708090A0B));
        address deployer = address(script);

        vm.prank(deployer);
        address predicted = script.predictDiamond(entropy);

        bytes memory diamondInitCode = abi.encodePacked(type(DiamondStub).creationCode, abi.encode(deployer));
        vm.prank(deployer);
        address deployed = script.deployDiamond(entropy, diamondInitCode);

        assertEq(deployed, predicted, "deployed Diamond != predicted address");
        assertGt(deployed.code.length, 0, "no code at deployed Diamond");
        assertEq(DiamondStub(deployed).owner(), deployer, "deployed Diamond not functional");
    }

    /// @notice CREATE3 ignores initcode: a different Diamond bytecode/args at the SAME (deployer,
    ///         entropy) yields the SAME address as `predictDiamond` — proving upgrade/bytecode stability.
    function test_DeployedAddressIsInitcodeIndependent() public {
        bytes11 entropy = bytes11(uint88(0x0A0B0C0D0E0F1011121314));
        address deployer = address(script);

        vm.prank(deployer);
        address predicted = script.predictDiamond(entropy);

        // Deploy a contract with a different ctor arg at the same salt; address must be unchanged.
        bytes memory differentInitCode = abi.encodePacked(type(DiamondStub).creationCode, abi.encode(address(0xCAFE)));
        vm.prank(deployer);
        address deployed = script.deployDiamond(entropy, differentInitCode);

        assertEq(deployed, predicted, "address must be independent of initcode");
    }

    /// @notice A facet deployed via the script lands at its own deterministic CREATE3 address and is
    ///         live code, with a distinct salt from the Diamond (no collision).
    function test_DeployFacetIsDeterministicAndLive() public {
        bytes11 entropy = bytes11(uint88(0xAABBCCDDEEFF0011223344));
        address deployer = address(script);

        bytes32 salt = CreateXDeployer._guardedSalt(deployer, entropy);
        address predictedFacet = CreateXDeployer.predict(salt);

        vm.prank(deployer);
        address facet = script.deployFacet(entropy, type(FacetStub).creationCode);

        assertEq(facet, predictedFacet, "facet != predicted");
        assertGt(facet.code.length, 0, "no code at facet");
        assertEq(FacetStub(facet).tag(), 0xFACE, "facet not functional");
    }

    /// @notice The deterministic address is sender-bound: predicting for one deployer (0xAAAA) but
    ///         deploying as a different caller produces a DIFFERENT address. The script's internal
    ///         `require(deployed == predicted)` is what catches this mismatch in practice, so the salt's
    ///         pinned deployer MUST equal the broadcaster — a deploy can never silently land elsewhere
    ///         than the address predicted for the true deployer.
    function test_DeterministicAddressIsSenderBound() public {
        bytes11 entropy = bytes11(uint88(0x0102030405060708090A0B));
        bytes memory initCode = abi.encodePacked(type(DiamondStub).creationCode, abi.encode(address(0x1)));

        // Address predicted for deployer 0xAAAA (salt pinned to 0xAAAA).
        bytes32 foreignSalt = CreateXDeployer._guardedSalt(address(0xAAAA), entropy);
        address predictedForForeign = CreateXDeployer.predict(foreignSalt);

        // Deploy that foreign-pinned salt, but the actual CreateX caller is this test contract.
        address deployed = CreateXDeployer.deploy(foreignSalt, initCode);

        // Because the deployer (this test) != the salt's pinned deployer (0xAAAA), the address differs
        // from what `predict` computes for 0xAAAA — proving the address binds to the real caller.
        assertTrue(deployed != predictedForForeign, "address must bind to the actual deployer");
    }

    /// @notice The governed-cut proposal assembly encodes a `diamondCut(0x1f931c1c)` call to the
    ///         diamond as the single proposal action.
    function test_BuildProposalEncodesDiamondCut() public view {
        address diamond = address(0xD1A);
        address newFacet = address(0xFACE7);
        bytes4 selector = bytes4(0x12345678);

        bytes4[] memory sels = new bytes4[](1);
        sels[0] = selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: newFacet, action: FacetCutAction.Add, functionSelectors: sels});

        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas,) =
            script.buildProposal(diamond, cuts, address(0), bytes(""), "desc");

        assertEq(targets.length, 1, "one target");
        assertEq(targets[0], diamond, "target is the diamond");
        assertEq(values[0], 0, "zero value");
        assertEq(bytes4(calldatas[0]), IGovernedDiamondCut.diamondCut.selector, "must call diamondCut");
        assertEq(IGovernedDiamondCut.diamondCut.selector, bytes4(0x1f931c1c), "diamondCut selector is 0x1f931c1c");
    }
}
