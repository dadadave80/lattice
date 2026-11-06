// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {
    RecipeAuthority,
    RecipeAuthorityKind,
    RecipeFacet,
    RecipeInitStep,
    RecipeParameter,
    RecipeSeam,
    RecipeSpec
} from "@lattice-script/lib/RecipeSpec.sol";
import {RecipeSpecLib} from "@lattice-script/lib/RecipeSpecLib.sol";
import {Test} from "forge-std/Test.sol";

struct RecipeCodecProbe {
    address account;
    bytes32 hash;
    bytes data;
    string hexLike;
    uint64 aboveJavaScriptInteger;
    uint256 large;
}

/// @title RecipeSerializationTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Native named ABI serialization preserves strings, opaque bytes and integers without type guessing.
contract RecipeSerializationTest is Test {
    function test_ActualCompilerDerivedRecipeSchemaRoundtripsCompleteABI() public {
        string[] memory command = new string[](4);
        command[0] = "jq";
        command[1] = "-jerf";
        command[2] = "script/recipes/type-description.jq";
        command[3] = "out/RecipeSpec.sol/IRecipeSpec.json";
        string memory description = string(vm.ffi(command));
        RecipeSpec memory spec = RecipeSpecLib.spec("RecipeCodec", "fixture-only", 1);
        spec.variants[0].id = "RecipeCodec:fixture";
        spec.variants[0].buildSignature = "buildCuts()";
        spec.variants[0].facets = new RecipeFacet[](1);
        spec.variants[0].facets[0] = RecipePlanLib.all("ERC20");
        spec.variants[0].seams = new RecipeSeam[](1);
        spec.variants[0].seams[0] = RecipePlanLib.seam2(
            "codec", 0xa9059cbb, "ERC20", "ERC20Pausable", "ERC20Pausable", "quoted \"reason\"\nwith \\ slash"
        );
        RecipeParameter[] memory parameters = new RecipeParameter[](1);
        parameters[0] = RecipeParameter(
            "value",
            "string",
            "opaque-text",
            "0x00000000000000000000000000000000000000000000000000000000000000ff",
            "keep as string"
        );
        string[] memory bindings = new string[](1);
        bindings[0] = "quoted \"binding\"\n\\";
        spec.variants[0].initPlan = RecipeSpecLib.leaf("Fixture", "init(string)", parameters, bindings);
        spec.variants[0].inputs = parameters;
        spec.variants[0].authorities = new RecipeAuthority[](1);
        spec.variants[0].authorities[0] = RecipeAuthority(
            RecipeAuthorityKind.RoleGrant,
            "AccessControl",
            "EXACT",
            "bytes32",
            bytes32(uint256(255)),
            "caller",
            "fixture"
        );
        bytes memory encoded = abi.encode(spec);
        string memory json = vm.serializeJsonType(description, encoded);
        assertEq(vm.parseJsonType(json, description), encoded);
        assertEq(vm.parseJsonString(json, ".variants[0].inputs[0].example"), parameters[0].example);
        assertEq(vm.parseJsonString(json, ".variants[0].initPlan[0].parent"), vm.toString(type(uint256).max));
    }

    function test_Opaque32ByteValuesAndIntegerBoundariesRoundtrip() public {
        RecipeCodecProbe memory probe = RecipeCodecProbe(
            address(0xAD),
            bytes32(uint256(255)),
            abi.encode(bytes32(uint256(255))),
            "0x00000000000000000000000000000000000000000000000000000000000000ff",
            uint64((uint256(1) << 53) + 1),
            type(uint256).max
        );
        string memory description =
            "RecipeCodecProbe(address account,bytes32 hash,bytes data,string hexLike,uint64 aboveJavaScriptInteger,uint256 large)";
        bytes memory encoded = abi.encode(probe);
        string memory json = vm.serializeJsonType(description, encoded);
        assertEq(probe.data.length, 32);
        assertEq(vm.parseJsonType(json, description), encoded);
        assertEq(vm.parseJsonString(json, ".hexLike"), probe.hexLike);
        assertEq(vm.parseJsonBytes(json, ".data"), probe.data);
        assertEq(vm.parseJsonBytes32(json, ".hash"), probe.hash);
        assertEq(vm.parseJsonAddress(json, ".account"), probe.account);
        assertEq(vm.parseJsonUint(json, ".aboveJavaScriptInteger"), probe.aboveJavaScriptInteger);
        assertEq(vm.parseJsonString(json, ".large"), vm.toString(type(uint256).max));
    }
}
