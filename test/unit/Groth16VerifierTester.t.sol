// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IGroth16Verifier} from "@lattice/interfaces/privacy/IGroth16Verifier.sol";
import {Groth16Verifier} from "@lattice/privacy/Groth16Verifier.sol";
import {Groth16VerifierLib} from "@lattice/privacy/libraries/Groth16VerifierLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Wrapper exposing init + ERC-165 discovery for the stateless verifier facet.
contract MockGroth16VerifierContract is Groth16Verifier {
    function initialize() external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        Groth16VerifierLib.__Groth16Verifier_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title Groth16VerifierTester
/// @notice Tests the generic Groth16 verifier against a REAL proof generated off-chain with circom +
///         snarkjs for the circuit `c = a * b` (a,c public, b private). The proof verifies with
///         `snarkjs groth16 verify` (OK) and the public signals are `[c, a] = [33, 3]` (a=3, b=11).
contract Groth16VerifierTester is Test {
    uint256 constant R = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint256 constant Q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    MockGroth16VerifierContract v;

    function setUp() public {
        v = new MockGroth16VerifierContract();
        v.initialize();
    }

    // ---- Fixture (snarkjs vkey.json with G2 coords swapped to (c1,c0); proof from soliditycalldata) ----

    function _vk() internal pure returns (IGroth16Verifier.VerifyingKey memory vk) {
        vk.alpha = [
            uint256(10369828742970636993042294390388337162513020679959217667694455683134751194400),
            uint256(19974095441937955069939384745243512798819498370827747132064307452065972126376)
        ];
        vk.beta = [
            [
                uint256(15851940447923058315237630580024948944105131241140729775955896604511386756235),
                uint256(11792517039822149762951273635265823613013755161500951838539604976348453585007)
            ],
            [
                uint256(18976180947269208770841827413156939173051686403990592833239950362059117666345),
                uint256(20271913866393690176432252682013827815386946644854064911796072333957806364808)
            ]
        ];
        vk.gamma = [
            [
                uint256(11559732032986387107991004021392285783925812861821192530917403151452391805634),
                uint256(10857046999023057135944570762232829481370756359578518086990519993285655852781)
            ],
            [
                uint256(4082367875863433681332203403145435568316851327593401208105741076214120093531),
                uint256(8495653923123431417604973247489272438418190587263600148770280649306958101930)
            ]
        ];
        vk.delta = [
            [
                uint256(21509716472485773628604389522625590143982678303004793501324440377631597260332),
                uint256(19116436156408402658684972169220506999587819992114480716810371191054063064815)
            ],
            [
                uint256(20991075162718859676875506041075209333768164310498984258500152085990055087093),
                uint256(17203009423555614821758094796418369135968335326867150435929470737564880985999)
            ]
        ];
        vk.ic = new uint256[2][](3);
        vk.ic[0] = [
            uint256(20396563903213897410823373173604559038560154265684888333944632525619964540091),
            uint256(17199760516336151887904499187345023895396867804405696814107390573641535492680)
        ];
        vk.ic[1] = [
            uint256(5805018020126439150067192733919004208867424290466216170889516505047170063781),
            uint256(9503319448942565718424655129761678370858596615552148644971623637946293691928)
        ];
        vk.ic[2] = [
            uint256(15205123467021962902500751241686615568414095750413025561910755536950226849890),
            uint256(3149536883466464981847113672938161153010873537045132724611151981680914306876)
        ];
    }

    function _proof() internal pure returns (IGroth16Verifier.Proof memory p) {
        p.a = [
            uint256(12106361047243834037909879595749647999481183390946685980338051047958912951772),
            uint256(20665867928626699599187679854483651504242536839369898080253506560059915410875)
        ];
        p.b = [
            [
                uint256(11523057275448346238289380258676888438096910030746440803880981731373125944611),
                uint256(3231421728073224764595745377772651159388461104506432981720641915346208951137)
            ],
            [
                uint256(15268115177599294973993658420154416760513492348160532251597192219434220029204),
                uint256(7696105830832633726162955139492063773678348895721089034067260510676715824481)
            ]
        ];
        p.c = [
            uint256(21250951700901524377849233608530859087085949457588714111285718091910146848990),
            uint256(18971731494262419814794276175099760351742374636628831052711103495189794270675)
        ];
    }

    function _input() internal pure returns (uint256[] memory input) {
        input = new uint256[](2);
        input[0] = 33; // c = a * b = 3 * 11
        input[1] = 3; // a
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_VerifyValidProof() public view {
        assertTrue(v.verifyProof(_vk(), _proof(), _input()));
    }

    function test_RejectWrongPublicInput() public view {
        uint256[] memory bad = _input();
        bad[0] = 34; // c should be 33; a wrong statement must not verify
        assertFalse(v.verifyProof(_vk(), _proof(), bad));
    }

    function test_RejectTamperedProof() public view {
        IGroth16Verifier.Proof memory p = _proof();
        unchecked {
            p.a[0] = p.a[0] + 1; // off-curve point -> pairing precompile fails -> false
        }
        assertFalse(v.verifyProof(_vk(), p, _input()));
    }

    function test_RejectOutOfRangePublicInput() public view {
        uint256[] memory bad = _input();
        bad[0] = R; // >= scalar field -> rejected by the range check
        assertFalse(v.verifyProof(_vk(), _proof(), bad));
    }

    function test_RejectOutOfRangeProofCoordinate() public view {
        IGroth16Verifier.Proof memory p = _proof();
        p.a[0] = Q; // >= base field -> rejected by the coordinate range check
        assertFalse(v.verifyProof(_vk(), p, _input()));
    }

    function test_RevertOnArityMismatch() public {
        uint256[] memory bad = new uint256[](1); // ic.length (3) != 1 + 1
        bad[0] = 33;
        vm.expectRevert(IGroth16Verifier.Groth16InvalidVerifyingKey.selector);
        v.verifyProof(_vk(), _proof(), bad);
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IGroth16Verifier).interfaceId, bytes4(0x6d832d8e), "IGroth16Verifier interfaceId moved");
    }

    function test_SupportsInterface() public view {
        assertTrue(v.supportsInterface(type(IGroth16Verifier).interfaceId));
    }
}
