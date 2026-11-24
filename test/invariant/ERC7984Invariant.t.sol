// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC7984TestBase} from "@lattice-test/base/ERC7984TestBase.sol";
import {
    AcceptReceiver,
    ReentrantReceiver,
    RejectReceiver,
    SpendThenRejectReceiver
} from "@lattice-test/helpers/ERC7984Actors.sol";
import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IERC7984, IERC7984Disclosure} from "@lattice/interfaces/tokens/IERC7984.sol";
import {IERC7984Mintable} from "@lattice/interfaces/tokens/IERC7984Mintable.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Drives a mintable ERC-7984 (confidential fungible token) diamond through transfers, operator transfers,
///         transfer-and-calls into accepting, rejecting, spend-then-reject and reentrant receivers, operator grants,
///         disclosure requests, confidential mints, and attempts to credit the diamond itself.
/// @dev It owns the vendored FHEVM (Fully Homomorphic Encryption Virtual Machine) harness, so its plaintext database
///      is the state committed between invariant steps, and it is both the token's admin and its only minter. Every
///      action rolls the block first, since handles are deterministic per block and two never-funded actors in one
///      block would otherwise share the trivial-zero balance handle, and processes the new host logs last. Inputs are
///      bounded to valid calls; an operator transfer without approval asserts its revert.
contract ERC7984Handler is ERC7984TestBase {
    struct Input {
        externalEuint64 handle;
        bytes proof;
    }

    uint256 internal constant AMOUNT_COUNT = 6;
    uint256 internal constant RECEIVER_COUNT = 5;

    /// @notice Everything minted through the handler, including the 1,000,000 seeded to `holder`.
    uint256 public mintedTotal;

    address[] internal _actors;
    /// @dev Accept, reject, spend-then-reject, reentrant `confidentialTransfer`, reentrant
    ///      `confidentialTransferAndCall`; the last three forward to `bob`.
    address[RECEIVER_COUNT] internal _receivers;
    uint64[AMOUNT_COUNT] internal _amounts = [0, 1, 7, 1_000, 999_999, 1_000_001];

    /// @dev Per actor, an input for each amount, proven for that actor on the diamond. Proofs are reusable (H-16).
    mapping(address actor => mapping(uint256 index => Input)) internal _inputs;
    /// @dev An input for each amount, proven for this handler (the minter) on the diamond.
    mapping(uint256 index => Input) internal _mintInputs;

    function init() external {
        setUp();
        diamond = _deployMintable(address(this), address(this));
        token = IERC7984(diamond);

        (externalEuint64 x, bytes memory p) = encryptUint64(1_000_000, address(this), diamond);
        IERC7984Mintable(diamond).confidentialMint(holder, x, p);
        mintedTotal = 1_000_000;

        _receivers[0] = address(new AcceptReceiver());
        _receivers[1] = address(new RejectReceiver());
        _receivers[2] = address(new SpendThenRejectReceiver(token, bob));
        _receivers[3] = address(new ReentrantReceiver(token, bob, 0));
        _receivers[4] = address(new ReentrantReceiver(token, bob, 1));
        address[5] memory people = [holder, alice, bob, mallory, op];
        for (uint256 i; i < people.length; ++i) {
            _actors.push(people[i]);
        }
        for (uint256 i; i < RECEIVER_COUNT; ++i) {
            _actors.push(_receivers[i]);
        }

        for (uint256 k; k < AMOUNT_COUNT; ++k) {
            for (uint256 i; i < _actors.length; ++i) {
                (x, p) = encryptUint64(_amounts[k], _actors[i], diamond);
                _inputs[_actors[i]][k] = Input(x, p);
            }
            (x, p) = encryptUint64(_amounts[k], address(this), diamond);
            _mintInputs[k] = Input(x, p);
        }
        _processNewLogs();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  ACTIONS
    //////////////////////////////////////////////////////////////////////////*//

    function transfer(uint256 actor, uint256 to, uint256 amt) external {
        vm.roll(block.number + 1);
        address from = _actor(actor);
        Input storage input = _inputs[from][amt % AMOUNT_COUNT];
        vm.prank(from);
        token.confidentialTransfer(_actor(to), input.handle, input.proof);
        _processNewLogs();
    }

    function transferFrom(uint256 operator, uint256 holderSeed, uint256 to, uint256 amt) external {
        vm.roll(block.number + 1);
        address spender = _actor(operator);
        address from = _actor(holderSeed);
        Input storage input = _inputs[spender][amt % AMOUNT_COUNT];
        bool approved = token.isOperator(from, spender);
        vm.prank(spender);
        if (!approved) {
            vm.expectRevert(abi.encodeWithSelector(IERC7984.ERC7984UnauthorizedSpender.selector, from, spender));
        }
        token.confidentialTransferFrom(from, _actor(to), input.handle, input.proof);
        _processNewLogs();
    }

    function transferAndCall(uint256 actor, uint256 receiverMode, uint256 amt) external {
        vm.roll(block.number + 1);
        address from = _actor(actor);
        Input storage input = _inputs[from][amt % AMOUNT_COUNT];
        vm.prank(from);
        token.confidentialTransferAndCall(_receivers[receiverMode % RECEIVER_COUNT], input.handle, input.proof, "");
        _processNewLogs();
    }

    function setOperator(uint256 holderSeed, uint256 operator, uint48 until) external {
        vm.roll(block.number + 1);
        vm.prank(_actor(holderSeed));
        token.setOperator(_actor(operator), until);
        _processNewLogs();
    }

    function requestDisclose(uint256 actor) external {
        vm.roll(block.number + 1);
        address who = _actor(actor);
        euint64 balance = token.confidentialBalanceOf(who);
        if (euint64.unwrap(balance) != 0) {
            vm.prank(who);
            IERC7984Disclosure(diamond).requestDiscloseEncryptedAmount(balance);
        }
        _processNewLogs();
    }

    function mint(uint256 to, uint256 amt) external {
        vm.roll(block.number + 1);
        uint256 k = amt % AMOUNT_COUNT;
        Input storage input = _mintInputs[k];
        IERC7984Mintable(diamond).confidentialMint(_actor(to), input.handle, input.proof);
        mintedTotal += _amounts[k];
        _processNewLogs();
    }

    /// @dev Attempts a transfer from an actor to the diamond and a mint to the diamond. Each must revert with
    ///      exactly `ERC7984InvalidReceiver(diamond)`; a success or any other revert fails the run.
    function tryCreditDiamond(uint256 actor, uint256 amt) external {
        vm.roll(block.number + 1);
        uint256 k = amt % AMOUNT_COUNT;
        address from = _actor(actor);
        bytes memory expected = abi.encodeWithSelector(IERC7984.ERC7984InvalidReceiver.selector, diamond);

        Input storage input = _inputs[from][k];
        vm.prank(from);
        try token.confidentialTransfer(diamond, input.handle, input.proof) returns (euint64) {
            assertTrue(false, "transfer credited the diamond");
        } catch (bytes memory reason) {
            assertEq(reason, expected, "transfer to the diamond: wrong revert");
        }

        Input storage mintInput = _mintInputs[k];
        try IERC7984Mintable(diamond).confidentialMint(diamond, mintInput.handle, mintInput.proof) returns (euint64) {
            assertTrue(false, "mint credited the diamond");
        } catch (bytes memory reason) {
            assertEq(reason, expected, "mint to the diamond: wrong revert");
        }
        _processNewLogs();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    function actorsLength() external view returns (uint256) {
        return _actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return _actors[i];
    }

    function sumDecryptedBalances() external returns (uint256 sum) {
        for (uint256 i; i < _actors.length; ++i) {
            sum += decrypt(token.confidentialBalanceOf(_actors[i]));
        }
    }

    function decryptedSupply() external returns (uint256) {
        return decrypt(token.confidentialTotalSupply());
    }

    /// @notice Each actor's non-zero balance handle is allowed to that actor and the diamond, and to no other actor
    ///         and not to this handler (the minter).
    function aclIsTight() external view returns (bool) {
        for (uint256 i; i < _actors.length; ++i) {
            bytes32 b = euint64.unwrap(token.confidentialBalanceOf(_actors[i]));
            if (b == 0) continue;
            if (!_acl.persistAllowed(b, _actors[i]) || !_acl.persistAllowed(b, diamond)) return false;
            if (_acl.persistAllowed(b, address(this))) return false;
            for (uint256 j; j < _actors.length; ++j) {
                if (j != i && _acl.persistAllowed(b, _actors[j])) return false;
            }
        }
        return true;
    }

    /// @notice The supply handle is allowed to the diamond, and not to this handler (the minter) or any actor
    ///         (hazard H-25).
    function supplyAllowedOnlyToDiamond() external view returns (bool) {
        bytes32 s = euint64.unwrap(token.confidentialTotalSupply());
        if (!_acl.persistAllowed(s, diamond) || _acl.persistAllowed(s, address(this))) return false;
        for (uint256 i; i < _actors.length; ++i) {
            if (_acl.persistAllowed(s, _actors[i])) return false;
        }
        return true;
    }

    function diamondBalanceHandle() external view returns (bytes32) {
        return euint64.unwrap(token.confidentialBalanceOf(diamond));
    }

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title ERC7984Invariant
/// @notice Stateful invariants of a mintable ERC-7984 (confidential fungible token) diamond under confidential
///         mints, transfers, operator transfers and reentrant receivers: the decrypted supply equals the sum of
///         decrypted balances and the plaintext minted total, each balance handle is allowed exactly to its holder and
///         the diamond, the supply handle only to the diamond, and the diamond never holds tokens.
/// @dev The handler, not this contract, owns the FHEVM harness: its plaintext database lives in the handler's
///      storage, so each check reads it instead of replaying the whole log history.
/// forge-config: ci.invariant.runs = 64
contract ERC7984Invariant is Test {
    ERC7984Handler internal handler;

    function setUp() public {
        handler = new ERC7984Handler();
        handler.init();

        // The six token actions and the diamond-credit probe; the handler's inherited public `setUp` is excluded.
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = ERC7984Handler.transfer.selector;
        selectors[1] = ERC7984Handler.transferFrom.selector;
        selectors[2] = ERC7984Handler.transferAndCall.selector;
        selectors[3] = ERC7984Handler.setOperator.selector;
        selectors[4] = ERC7984Handler.requestDisclose.selector;
        selectors[5] = ERC7984Handler.mint.selector;
        selectors[6] = ERC7984Handler.tryCreditDiamond.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice Mints plus moves: the supply equals the sum of balances and the plaintext minted total. A broken log
    ///         replay decrypts to 0 and fails here (R7).
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyConserved() public {
        assertEq(handler.decryptedSupply(), handler.mintedTotal());
        assertEq(handler.sumDecryptedBalances(), handler.mintedTotal());
    }

    /// @notice For each actor with a balance handle: allowed to that actor and the diamond, to no other actor and
    ///         not to the minter.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_BalanceHandlesAllowedOnlyToHolderAndDiamond() public view {
        assertTrue(handler.aclIsTight());
    }

    /// @notice Hazard H-25: the supply handle is never allowed to the honest (non-recomputing) minter or an actor.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_SupplyAllowedOnlyToDiamond() public view {
        assertTrue(handler.supplyAllowedOnlyToDiamond());
    }

    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_DiamondNeverHoldsTokens() public view {
        assertEq(handler.diamondBalanceHandle(), bytes32(0));
    }
}
