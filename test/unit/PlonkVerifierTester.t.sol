// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IPlonkVerifier} from "@lattice/interfaces/IPlonkVerifier.sol";
import {PlonkVerifier} from "@lattice/privacy/PlonkVerifier.sol";
import {PlonkVerifierLib} from "@lattice/privacy/libraries/PlonkVerifierLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Wrapper exposing init + ERC-165 discovery for the stateless verifier facet.
contract MockPlonkVerifierContract is PlonkVerifier {
    function initialize() external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        PlonkVerifierLib.__PlonkVerifier_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title PlonkVerifierTester
/// @notice Tests the generic PLONK verifier against a REAL proof generated off-chain with circom +
///         snarkjs for `c = a * b` (a,c public, b private). The proof passes `snarkjs plonk verify`
///         (OK) with public signals `[c, a] = [33, 3]`.
contract PlonkVerifierTester is Test {
    uint256 constant Q = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint256 constant QF = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    MockPlonkVerifierContract v;

    function setUp() public {
        v = new MockPlonkVerifierContract();
        v.initialize();
    }

    function _vk() internal pure returns (IPlonkVerifier.VerifyingKey memory vk) {
        vk.qm = [
            uint256(2045539740388439860476202099532772201491859907078559980193540400033225489081),
            uint256(20465625989647707971974685804794147283943133784406516286284871163926372465103)
        ];
        vk.ql = [
            uint256(9201030023637016062397770143630857128528326588472179973000933880103535999009),
            uint256(9636654696219779516622618199927239534407524357032632876729858941405784537294)
        ];
        vk.qr = [uint256(0), uint256(0)];
        vk.qo = [
            uint256(2045539740388439860476202099532772201491859907078559980193540400033225489081),
            uint256(1422616882191567250271719940463127804753177372891307376404166730718853743480)
        ];
        vk.qc = [uint256(0), uint256(0)];
        vk.s1 = [
            uint256(19498434000252824315604084444399191084706099280795376298537396886453091422571),
            uint256(1228781577196861151758776483323463615089429923763136758840687815483810313452)
        ];
        vk.s2 = [
            uint256(1353076601847648275905309855949013601036310461542339779295531814255522572146),
            uint256(19006937875923657849303050412769478900069457158188307283823495097673271045624)
        ];
        vk.s3 = [
            uint256(12421313498735604432194395909776141347000697273588956971497059947991044659944),
            uint256(10996829005306989823570421219913769146536800166829450334485163938884751923698)
        ];
        vk.k1 = 2;
        vk.k2 = 3;
        vk.power = 3;
        vk.omega = 19540430494807482326159819597004422086093766032135589407132600596362845576832;
        vk.x2 = [
            [
                uint256(5836581748334560687157202983301426456211671209607272894396852138510683480252),
                uint256(9956249196530796326172995376240405754720236753760489870341914739159035231312)
            ],
            [
                uint256(20105869391181433642488494045631175918938840337318694015183833120373361904118),
                uint256(1786886711241978399710698101154851275560970880778549024667590512525417833868)
            ]
        ];
    }

    function _proof() internal pure returns (IPlonkVerifier.Proof memory p) {
        p.a = [
            uint256(21300932100471031688150716843857209989309786740870771176899016873685099750407),
            uint256(20748719418757495899719754577418662583365136782756496991987612334311085403853)
        ];
        p.b = [
            uint256(14474877147479248980819971019547952484098364800551494309084383342768600651344),
            uint256(3706152444159322561273787666581195190713629001944291551653241603919945305548)
        ];
        p.c = [
            uint256(4712675047444008533310480726704816246582231318669568717003434369767136127375),
            uint256(2744319211905146301391841854340331377240079185898242053919930879014709171707)
        ];
        p.z = [
            uint256(12475907089275526991351942350957825623387220278329577265069204442672139493962),
            uint256(7786502424860251391995392422739897048623953550965541006655542187904642490900)
        ];
        p.t1 = [
            uint256(13774774181938359964372294898809175220250746557586334746688471790234733349705),
            uint256(14292485925388643743364692356920928742269778286027407470236178576866791072501)
        ];
        p.t2 = [
            uint256(6386375647173348112991204390401928917617661179172643781638905557194404800961),
            uint256(4519972260637516150370412778668993846290854807954403488858226283070532967107)
        ];
        p.t3 = [
            uint256(16288666715826238113599034974933754734704699563915762842989667093947613540715),
            uint256(2123448880589966701759249372744617556318517231932696147387843881053307117018)
        ];
        p.wxi = [
            uint256(20013029917281059810610423780901925028400973445899002299968065029083542001948),
            uint256(21288249106199676466896149813517861466053682981588299202776453757088141419325)
        ];
        p.wxiw = [
            uint256(16843962671572826300832094040946335182218117419438261120652671321019269845936),
            uint256(19293434322295996160029972210727226434006762462717365891920277527154770359234)
        ];
        p.eval_a = 16929526713579330712613491955490934338024901554302988400837123493249110124157;
        p.eval_b = 20757963509342560794713634463283919610930449565350897838610983981964001760522;
        p.eval_c = 19085839467351038833313154814369916884361903883776742723900897250833135635422;
        p.eval_s1 = 14143124952947544309407874146003118039184234421840305354680427299909755592921;
        p.eval_s2 = 2686596714631874814024684830137401102304432477254997570751278922151845363207;
        p.eval_zw = 18669137922579414431287791319153459940017239969906078630336862190662633022424;
    }

    function _input() internal pure returns (uint256[] memory input) {
        input = new uint256[](2);
        input[0] = 33; // c
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
        bad[0] = 34;
        assertFalse(v.verifyProof(_vk(), _proof(), bad));
    }

    function test_RejectTamperedProof() public view {
        IPlonkVerifier.Proof memory p = _proof();
        unchecked {
            p.a[0] = p.a[0] + 1; // off-curve -> rejected by isWellConstructed
        }
        assertFalse(v.verifyProof(_vk(), p, _input()));
    }

    function test_RejectOutOfRangePublicInput() public view {
        uint256[] memory bad = _input();
        bad[0] = Q;
        assertFalse(v.verifyProof(_vk(), _proof(), bad));
    }

    function test_RejectOutOfRangeProofCoordinate() public view {
        IPlonkVerifier.Proof memory p = _proof();
        p.a[0] = QF;
        assertFalse(v.verifyProof(_vk(), p, _input()));
    }

    function test_RejectOutOfRangeEval() public view {
        // A non-canonical eval (eval + Q) must be rejected, keeping the transcript snarkjs-identical.
        IPlonkVerifier.Proof memory p = _proof();
        unchecked {
            p.eval_a = p.eval_a + Q;
        }
        assertFalse(v.verifyProof(_vk(), p, _input()));
    }

    function test_RejectMalformedVerifyingKey() public view {
        // An off-curve vk commitment returns false (does not revert inside a precompile).
        IPlonkVerifier.VerifyingKey memory vk = _vk();
        unchecked {
            vk.qm[0] = vk.qm[0] + 1; // off-curve
        }
        assertFalse(v.verifyProof(vk, _proof(), _input()));
    }

    function test_RejectBadDomainPower() public view {
        IPlonkVerifier.VerifyingKey memory vk = _vk();
        vk.power = 0;
        assertFalse(v.verifyProof(vk, _proof(), _input()));
        vk.power = 29; // beyond the BN254 2-adicity (28)
        assertFalse(v.verifyProof(vk, _proof(), _input()));
    }

    function test_RevertOnEmptyInput() public {
        uint256[] memory empty = new uint256[](0);
        vm.expectRevert(IPlonkVerifier.PlonkInvalidInputs.selector);
        v.verifyProof(_vk(), _proof(), empty);
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IPlonkVerifier).interfaceId, bytes4(0x5d484314), "IPlonkVerifier interfaceId moved");
    }

    function test_SupportsInterface() public view {
        assertTrue(v.supportsInterface(type(IPlonkVerifier).interfaceId));
    }
}
