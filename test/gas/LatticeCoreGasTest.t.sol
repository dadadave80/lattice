// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {RawCode} from "@lattice-test/helpers/LatticeCoreMocks.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {ILatticeFactory, RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Runs a raw CREATE of the given initcode. Foundry's dynamic test linking (on by default) turns a `new`
///         written in a test file into an unmetered cheatcode deployment, so creation gas is measured through
///         this explicit CREATE instead.
contract RawCreator {
    function create(bytes calldata initCode) external returns (address deployed) {
        bytes memory code = initCode;
        assembly ("memory-safe") {
            deployed := create(0, add(code, 0x20), mload(code))
        }
        require(deployed != address(0), "RawCreator: create failed");
    }
}

/// @title LatticeCoreGasTest
/// @notice #176 baselines for {LatticeRegistry} and {LatticeFactory}: runtime and initcode sizes, singleton
///         deployment, registry writes and reads across selector counts, and factory deploys for custom-only,
///         pinned, latest and mixed recipes across facet x selector shapes, the idempotent repeat, and the
///         production governed-vault recipe both as custom cuts and through the registry.
/// @dev Forge runs tests isolated (`isolate = true` is the default in the pinned Foundry): every top-level call
///      from a test is its own transaction, so each measured call starts from cold accounts and storage.
///      State-changing calls are measured as whole isolated transactions (21,000 intrinsic plus calldata plus
///      execution); view calls as cold execution only. Every measured call is prebuilt in `setUp`. Synthetic facets return a constant selector blob from code, as real facets
///      do. Gated by `make snapshot-check`; regenerate with `make snapshot`.
contract LatticeCoreGasTest is Test {
    LatticeRegistry internal registry;
    LatticeFactory internal factory;
    RawCreator internal creator;

    bytes32 internal constant LOUPE = keccak256("lattice.DiamondLoupeFacet");
    uint64 internal constant V1 = 1 << 48;

    address internal loupeFacet;
    address[6] internal registerTargets;
    bytes32[3] internal readNames;

    /// @dev Prebuilt `factory.deploy` calldata per shape.
    mapping(string shape => bytes) internal deployCalls;

    function setUp() public {
        creator = new RawCreator();
        registry = new LatticeRegistry(address(this));
        factory = new LatticeFactory(registry, address(0), address(0));
        loupeFacet = address(new DiamondLoupeFacet());
        registry.register(LOUPE, V1, loupeFacet);
        registry.setLatest(LOUPE, V1);

        uint16[6] memory counts = [uint16(1), 4, 16, 64, 128, 256];
        for (uint256 i; i < counts.length; ++i) {
            registerTargets[i] = RawCode.exporter(RawCode.selectorBlob(keccak256(abi.encode("reg", i)), counts[i]));
        }
        uint16[3] memory readCounts = [uint16(4), 16, 64];
        for (uint256 i; i < readCounts.length; ++i) {
            readNames[i] = keccak256(abi.encode("read", i));
            registry.register(readNames[i], V1, RawCode.exporter(RawCode.selectorBlob(readNames[i], readCounts[i])));
        }

        _prepareLoupeShapes();
        _prepareGrid("8x16", 8, 16);
        _prepareGrid("16x32", 16, 32);
        _prepareGovernedVault();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           SIZES AND DEPLOYMENT
    //////////////////////////////////////////////////////////////////////////*//

    function test_Gas_Sizes() public {
        vm.snapshotValue("LatticeRegistry.runtimeSize", address(registry).code.length);
        vm.snapshotValue("LatticeRegistry.initcodeSize", type(LatticeRegistry).creationCode.length);
        vm.snapshotValue("LatticeFactory.runtimeSize", address(factory).code.length);
        vm.snapshotValue("LatticeFactory.initcodeSize", type(LatticeFactory).creationCode.length);
        vm.snapshotValue("Lattice.runtimeSize", address(new Lattice()).code.length);
        vm.snapshotValue("Lattice.initcodeSize", type(Lattice).creationCode.length);
    }

    /// @dev Includes the helper call's intrinsic and calldata gas (the initcode travels as calldata, as it would
    ///      in a deployment transaction).
    function test_Gas_DeployRegistry() public {
        bytes memory initCode = abi.encodePacked(type(LatticeRegistry).creationCode, abi.encode(address(this)));
        vm.startSnapshotGas("LatticeRegistry.deploy");
        address r = creator.create(initCode);
        vm.stopSnapshotGas();
        assertEq(r.code.length, address(registry).code.length, "registry deployed");
    }

    function test_Gas_DeployFactory() public {
        bytes memory initCode =
            abi.encodePacked(type(LatticeFactory).creationCode, abi.encode(address(registry), address(0), address(0)));
        vm.startSnapshotGas("LatticeFactory.deploy");
        address f = creator.create(initCode);
        vm.stopSnapshotGas();
        assertEq(f.code.length, address(factory).code.length, "factory deployed");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                REGISTRY
    //////////////////////////////////////////////////////////////////////////*//

    function test_Gas_AttestNew() public {
        address facet = registerTargets[0];
        vm.startSnapshotGas("registry.attest.new");
        registry.attest(facet);
        vm.stopSnapshotGas();
    }

    function test_Gas_AttestRepeat() public {
        address facet = registerTargets[0];
        registry.attest(facet);
        vm.startSnapshotGas("registry.attest.repeat");
        registry.attest(facet);
        vm.stopSnapshotGas();
    }

    function _register(uint256 i, string memory label) internal {
        address facet = registerTargets[i];
        vm.startSnapshotGas(label);
        registry.register(keccak256("bench"), V1, facet);
        vm.stopSnapshotGas();
    }

    function test_Gas_Register1() public {
        _register(0, "registry.register.1");
    }

    function test_Gas_Register4() public {
        _register(1, "registry.register.4");
    }

    function test_Gas_Register16() public {
        _register(2, "registry.register.16");
    }

    function test_Gas_Register64() public {
        _register(3, "registry.register.64");
    }

    function test_Gas_Register128() public {
        _register(4, "registry.register.128");
    }

    function test_Gas_Register256() public {
        _register(5, "registry.register.256");
    }

    function test_Gas_SetLatest() public {
        bytes32 name = readNames[0];
        vm.startSnapshotGas("registry.setLatest");
        registry.setLatest(name, V1);
        vm.stopSnapshotGas();
    }

    function test_Gas_Get() public {
        bytes32 name = readNames[0];
        vm.startSnapshotGas("registry.get");
        registry.get(name, V1);
        vm.stopSnapshotGas();
    }

    function _getCut(uint256 i, string memory label) internal {
        bytes32 name = readNames[i];
        vm.startSnapshotGas(label);
        registry.getCut(name, V1);
        vm.stopSnapshotGas();
    }

    function test_Gas_GetCut4() public {
        _getCut(0, "registry.getCut.4");
    }

    function test_Gas_GetCut16() public {
        _getCut(1, "registry.getCut.16");
    }

    function test_Gas_GetCut64() public {
        _getCut(2, "registry.getCut.64");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 FACTORY
    //////////////////////////////////////////////////////////////////////////*//

    function _deploy(string memory shape) internal {
        bytes memory data = deployCalls[shape];
        vm.startSnapshotGas(string.concat("factory.deploy.", shape));
        (bool ok,) = address(factory).call(data);
        vm.stopSnapshotGas();
        assertTrue(ok, shape);
    }

    function test_Gas_DeployLoupeCustomOnly() public {
        _deploy("loupe.custom");
    }

    function test_Gas_DeployLoupePinned() public {
        _deploy("loupe.pinned");
    }

    function test_Gas_DeployLoupeLatest() public {
        _deploy("loupe.latest");
    }

    function test_Gas_DeployLoupeRepeat() public {
        (bool ok,) = address(factory).call(deployCalls["loupe.pinned"]);
        assertTrue(ok);
        _deploy("loupe.pinned.repeat");
    }

    function test_Gas_DeployGrid8x16Pinned() public {
        _deploy("8x16.pinned");
    }

    function test_Gas_DeployGrid8x16Custom() public {
        _deploy("8x16.custom");
    }

    function test_Gas_DeployGrid8x16Mixed() public {
        _deploy("8x16.mixed");
    }

    function test_Gas_DeployGrid16x32Pinned() public {
        _deploy("16x32.pinned");
    }

    function test_Gas_DeployGrid16x32Custom() public {
        _deploy("16x32.custom");
    }

    function test_Gas_DeployGovernedVaultCustom() public {
        _deploy("governedVault.custom");
    }

    function test_Gas_DeployGovernedVaultRegistry() public {
        _deploy("governedVault.registry");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              PREPARATION
    //////////////////////////////////////////////////////////////////////////*//

    function _call(RecipeEntry[] memory entries, FacetCut[] memory cuts, address init, bytes memory data, bytes32 salt)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(ILatticeFactory.deploy, (entries, cuts, init, data, salt));
    }

    function _loupeCut() internal view returns (FacetCut memory) {
        bytes4[] memory s = new bytes4[](4);
        s[0] = 0x7a0ed627;
        s[1] = 0xadfca15e;
        s[2] = 0x52ef6b2c;
        s[3] = 0xcdffacc6;
        return FacetCut(loupeFacet, FacetCutAction.Add, s);
    }

    function _prepareLoupeShapes() internal {
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = _loupeCut();
        deployCalls["loupe.custom"] = _call(new RecipeEntry[](0), cuts, address(0), "", "loupe.custom");

        RecipeEntry[] memory pinned = new RecipeEntry[](1);
        pinned[0] = RecipeEntry(LOUPE, V1);
        deployCalls["loupe.pinned"] = _call(pinned, new FacetCut[](0), address(0), "", "loupe.pinned");
        deployCalls["loupe.pinned.repeat"] = deployCalls["loupe.pinned"];

        RecipeEntry[] memory latest = new RecipeEntry[](1);
        latest[0] = RecipeEntry(LOUPE, 0);
        deployCalls["loupe.latest"] = _call(latest, new FacetCut[](0), address(0), "", "loupe.latest");
    }

    /// @dev `facets` registry facets of `selectors` selectors each, plus the loupe, three ways: all pinned
    ///      entries, all custom cuts, and half of each.
    function _prepareGrid(string memory label, uint256 facets, uint256 selectors) internal {
        RecipeEntry[] memory pinned = new RecipeEntry[](facets + 1);
        FacetCut[] memory custom = new FacetCut[](facets + 1);
        RecipeEntry[] memory mixedEntries = new RecipeEntry[](facets / 2 + 1);
        FacetCut[] memory mixedCuts = new FacetCut[](facets - facets / 2);
        pinned[0] = RecipeEntry(LOUPE, V1);
        custom[0] = _loupeCut();
        mixedEntries[0] = RecipeEntry(LOUPE, V1);
        for (uint256 i; i < facets; ++i) {
            bytes32 name = keccak256(abi.encode(label, i));
            bytes memory blob = RawCode.selectorBlob(name, selectors);
            address facet = RawCode.exporter(blob);
            registry.register(name, V1, facet);
            pinned[i + 1] = RecipeEntry(name, V1);
            custom[i + 1] = FacetCut(facet, FacetCutAction.Add, RawCode.unpack(blob));
            if (i < facets / 2) mixedEntries[i + 1] = pinned[i + 1];
            else mixedCuts[i - facets / 2] = custom[i + 1];
        }
        deployCalls[string.concat(label, ".pinned")] =
            _call(pinned, new FacetCut[](0), address(0), "", keccak256(abi.encode(label, "pinned")));
        deployCalls[string.concat(label, ".custom")] =
            _call(new RecipeEntry[](0), custom, address(0), "", keccak256(abi.encode(label, "custom")));
        deployCalls[string.concat(label, ".mixed")] =
            _call(mixedEntries, mixedCuts, address(0), "", keccak256(abi.encode(label, "mixed")));
    }

    /// @dev The production {DeployGovernedVault} recipe: 14 custom cuts, or its 8 whole facets as registry
    ///      entries plus its 6 partial facets as custom cuts.
    function _prepareGovernedVault() internal {
        GovernedVaultParams memory p;
        p.asset = address(0xA55E7);
        p.name = "Bench Vault";
        p.symbol = "bV";
        p.minDelay = 100;
        p.votingDelay = 1;
        p.votingPeriod = 50;
        p.quorumNumerator = 4;
        (FacetCut[] memory cuts, address init, bytes memory data) = new DeployGovernedVault().buildCuts(p);
        deployCalls["governedVault.custom"] = _call(new RecipeEntry[](0), cuts, init, data, "vault.custom");

        uint8[8] memory whole = [0, 1, 2, 9, 10, 11, 12, 13];
        uint8[6] memory partialIdx = [3, 4, 5, 6, 7, 8];
        RecipeEntry[] memory entries = new RecipeEntry[](8);
        for (uint256 i; i < 8; ++i) {
            bytes32 name = keccak256(abi.encode("vault-part", whole[i]));
            registry.register(name, V1, cuts[whole[i]].facetAddress);
            entries[i] = RecipeEntry(name, V1);
        }
        FacetCut[] memory partialCuts = new FacetCut[](6);
        for (uint256 i; i < 6; ++i) {
            partialCuts[i] = cuts[partialIdx[i]];
        }
        deployCalls["governedVault.registry"] = _call(entries, partialCuts, init, data, "vault.registry");
    }
}
