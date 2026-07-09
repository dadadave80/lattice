// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ShieldedPoolTestBase} from "@lattice-test/base/ShieldedPoolTestBase.sol";
import {IGroth16Verifier} from "@lattice/interfaces/privacy/IGroth16Verifier.sol";
import {IShieldedPool, IShieldedWithdrawVerifier} from "@lattice/interfaces/privacy/IShieldedPool.sol";
import {Groth16Verifier} from "@lattice/privacy/Groth16Verifier.sol";
import {ShieldedPool} from "@lattice/privacy/ShieldedPool.sol";

/// @notice Minimal ERC-20 for the pool test.
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Adapts the generic Groth16Verifier to the pool's 5-signal withdraw-verifier interface, with
///         the test circuit's verifying key. This is exactly what a consumer writes for their circuit.
contract TestWithdrawVerifier is IShieldedWithdrawVerifier {
    Groth16Verifier private immutable groth16;

    constructor(Groth16Verifier g) {
        groth16 = g;
    }

    function verifyProof(
        uint256[2] calldata a,
        uint256[2][2] calldata b,
        uint256[2] calldata c,
        uint256[5] calldata pub
    ) external view returns (bool) {
        IGroth16Verifier.Proof memory proof = IGroth16Verifier.Proof({a: a, b: b, c: c});
        uint256[] memory input = new uint256[](5);
        for (uint256 i; i < 5; ++i) {
            input[i] = pub[i];
        }
        return groth16.verifyProof(_vk(), proof, input);
    }

    function _vk() internal pure returns (IGroth16Verifier.VerifyingKey memory vk) {
        vk.alpha = [
            uint256(5302751435839650088604561552279609711324887400042066289421145452492691845022),
            13438726559250473472158480636620069781305400611484529818512448705339208676218
        ];
        vk.beta = [
            [
                uint256(13537669330110998904979446114501428553344809619374592611432667224956055555704),
                8208558165811728026600697726502946714707425666074839797823128464197010380045
            ],
            [
                uint256(1605268472525291172497028610377750436828043015386995812683078469456048510155),
                18961220506339502078994364071396144377629278165255115633857481500611527704813
            ]
        ];
        vk.gamma = [
            [
                uint256(11559732032986387107991004021392285783925812861821192530917403151452391805634),
                10857046999023057135944570762232829481370756359578518086990519993285655852781
            ],
            [
                uint256(4082367875863433681332203403145435568316851327593401208105741076214120093531),
                8495653923123431417604973247489272438418190587263600148770280649306958101930
            ]
        ];
        vk.delta = [
            [
                uint256(9487840020944190812842229820164412711795975978274293585184008648994964373585),
                7249253487578679435429818407221902176373727001963415926155817653860663191767
            ],
            [
                uint256(3434165818315914404207936314086735710793714657820041307317610135605389044470),
                21519082486935391664909137982566576958000198719491307067642038093271808783491
            ]
        ];
        vk.ic = new uint256[2][](6);
        vk.ic[0] = [
            uint256(14330608352630660750906838748327660245137407024483434315079708048474262318303),
            13718593365017292217322575880681804220864808776641744803462348433522279335736
        ];
        vk.ic[1] = [
            uint256(19651056018071856925504501696809795299319844270250303657518216033853634615358),
            14678907699362174310362880496475105965552818481284752979298708568602512686870
        ];
        vk.ic[2] = [
            uint256(10055340604266861013475041180105879816171058095357478174923944137340013976792),
            223584751289044745961173428600847216502107337102516029771485919196699471512
        ];
        vk.ic[3] = [
            uint256(2671175592865746420713145315476284529102439312131124434319441005817297987287),
            7252212506678134808196892779818857284449991587272419517105258030642234649683
        ];
        vk.ic[4] = [
            uint256(10711449297826149595983615947535620250931826213785943404895269883958026740884),
            13552271061216026084699421704392655167967440528235997361712982388814480941089
        ];
        vk.ic[5] = [
            uint256(2741540396598746820940569516996657996878656083038436703535950452279064803299),
            12403846918302773974008520078117675212953238205380179476013593296404723527705
        ];
    }
}

/// @title ShieldedPoolTest
/// @notice Tests the deposit -> withdraw flow through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployShieldedPool} script (see {ShieldedPoolTestBase}) with a REAL Groth16 withdrawal proof (3
///         commitments, depth 2, recipient 0xbeef, relayer 0xc0fe, fee 5). The proof passes `snarkjs groth16
///         verify`. Every deposit/withdraw call routes through the diamond's `delegatecall` dispatch;
///         `supportsInterface` is served by the cut-in `ERC165Facet`. The pool's ERC-20 token and its Groth16
///         `TestWithdrawVerifier` adapter stay external dependencies (NOT the facet under test).
contract ShieldedPoolTest is ShieldedPoolTestBase {
    MockERC20 token;
    TestWithdrawVerifier verifier;

    uint256 poolId;

    uint256 constant DENOM = 1000;
    uint256 constant ROOT = 18957209925966657462584645419155802083555560412888865451941054255438714672993;
    uint256 constant NULLIFIER_HASH = 13377623690824916797327209540443066247715962236839283896963055328700043345550;
    address constant RECIPIENT = address(0xBeEF); // 0xbeef -> uint160 48879 (matches the proof)
    address constant RELAYER = address(0xC0fE); // 0xc0fe -> uint160 49406
    uint256 constant FEE = 5;

    function setUp() public {
        Groth16Verifier g = new Groth16Verifier();
        verifier = new TestWithdrawVerifier(g);
        token = new MockERC20();
        diamond = _deployShieldedPool(address(this));
        pool = ShieldedPool(diamond);
        poolId = pool.createPool(address(token), DENOM, address(verifier));

        // This contract is the depositor: fund + approve 3 deposits.
        token.mint(address(this), 3 * DENOM);
        token.approve(address(pool), 3 * DENOM);
        uint256[] memory c = _commitments();
        for (uint256 i; i < c.length; ++i) {
            pool.deposit(poolId, c[i]);
        }
    }

    function _commitments() internal pure returns (uint256[] memory c) {
        c = new uint256[](3);
        c[0] = 20595346326572914964186581639484694308224330290454662633399973481953444150659;
        c[1] = 20403006909364192806930024120627684483381303094884559877071101381067530732246;
        c[2] = 6494326098466164952080577608230455345257528668955319299844368625460411395488;
    }

    function _proof() internal pure returns (IShieldedPool.WithdrawProof memory p) {
        p.a = [
            uint256(19513610530500703525524032632172051670901552822733031087886268921118077906542),
            20278967013227174522877930728711965345583377353233099555490592684330218564017
        ];
        p.b = [
            [
                uint256(4830322330531715376663318176023629436430524537236056058153414788124590539920),
                236425937072759341948539963754869024714418696157274351591524557828586274191
            ],
            [
                uint256(21314074659677681581030697505857891516132015626298135153610681307173636950297),
                7024785950739992390797048697337510292156234599111926317239263146849754282256
            ]
        ];
        p.c = [
            uint256(6721427163943066382911463888536112878501946696568816223619970043264778411083),
            1913743312881955787981026244149874475447370939801164212009468150976711862742
        ];
    }

    function _withdraw() internal {
        pool.withdraw(poolId, _proof(), ROOT, NULLIFIER_HASH, RECIPIENT, RELAYER, FEE);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_DepositsMatchProofRoot() public view {
        (,,, uint256 root, uint256 numLeaves) = pool.getPool(poolId);
        assertEq(root, ROOT, "on-chain root != proof root");
        assertEq(numLeaves, 3);
        assertEq(token.balanceOf(address(pool)), 3 * DENOM);
    }

    function test_WithdrawRealProof() public {
        _withdraw();
        assertEq(token.balanceOf(RECIPIENT), DENOM - FEE, "recipient amount");
        assertEq(token.balanceOf(RELAYER), FEE, "relayer fee");
        assertEq(token.balanceOf(address(pool)), 2 * DENOM, "pool keeps the other two deposits");
        assertTrue(pool.isSpent(poolId, NULLIFIER_HASH));
    }

    function test_DoubleWithdrawReverts() public {
        _withdraw();
        vm.expectRevert(IShieldedPool.ShieldedPoolNullifierAlreadySpent.selector);
        _withdraw();
    }

    function test_UnknownRootReverts() public {
        vm.expectRevert(IShieldedPool.ShieldedPoolUnknownRoot.selector);
        pool.withdraw(poolId, _proof(), ROOT + 1, NULLIFIER_HASH, RECIPIENT, RELAYER, FEE);
    }

    function test_FeeExceedsDenominationReverts() public {
        vm.expectRevert(IShieldedPool.ShieldedPoolFeeExceedsDenomination.selector);
        pool.withdraw(poolId, _proof(), ROOT, NULLIFIER_HASH, RECIPIENT, RELAYER, DENOM + 1);
    }

    function test_TamperedProofReverts() public {
        IShieldedPool.WithdrawProof memory p = _proof();
        unchecked {
            p.a[0] = p.a[0] + 1;
        }
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidProof.selector);
        pool.withdraw(poolId, p, ROOT, NULLIFIER_HASH, RECIPIENT, RELAYER, FEE);
    }

    function test_WrongRecipientReverts() public {
        // recipient is bound in the proof; changing it makes the public signals mismatch -> false.
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidProof.selector);
        pool.withdraw(poolId, _proof(), ROOT, NULLIFIER_HASH, address(0xDEAD), RELAYER, FEE);
    }

    function test_CreatePoolOnlyAdmin() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        pool.createPool(address(token), DENOM, address(verifier));
    }

    function test_CreatePoolInvalidConfigReverts() public {
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidConfig.selector);
        pool.createPool(address(0), DENOM, address(verifier));
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidConfig.selector);
        pool.createPool(address(token), 0, address(verifier));
        vm.expectRevert(IShieldedPool.ShieldedPoolInvalidConfig.selector);
        pool.createPool(address(token), DENOM, address(0));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IShieldedPool).interfaceId, bytes4(0x8f5cc2c7), "IShieldedPool interfaceId moved");
    }

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IShieldedPool).interfaceId));
    }
}
