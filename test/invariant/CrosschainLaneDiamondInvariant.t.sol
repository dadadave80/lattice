// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployBridgeERC20} from "@lattice-script/base/crosschain/DeployBridgeERC20.s.sol";
import {DeployBridgeERC7802} from "@lattice-script/base/crosschain/DeployBridgeERC7802.s.sol";
import {DeployERC20Crosschain} from "@lattice-script/base/tokens/DeployERC20Crosschain.s.sol";
import {DeployERC7802} from "@lattice-script/base/tokens/DeployERC7802.s.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {FUNGIBLE_BRIDGE_TAG} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {ICrosschainLink} from "@lattice/interfaces/crosschain/ICrosschainLink.sol";
import {IERC7786MessageHandler} from "@lattice/interfaces/crosschain/IERC7786MessageHandler.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {CROSSCHAIN_BRIDGE_ROLE} from "@lattice/tokens/ERC7802/libraries/ERC7802Lib.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                 FIXTURES
//////////////////////////////////////////////////////////////////////////*//

/// @notice A local ERC-7786 relay. `sendMessage` queues a message; the handler later delivers it (in any order, any
///         number of times) to the recipient named in it, as the source the message came from.
contract RelayGateway is IERC7786GatewaySource {
    struct Message {
        address source;
        bytes recipient;
        bytes payload;
    }

    Message[] internal _messages;

    function supportsAttribute(bytes4) external pure returns (bool) {
        return false;
    }

    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata)
        external
        payable
        returns (bytes32)
    {
        _messages.push(Message(msg.sender, recipient, payload));
        return idOf(_messages.length - 1);
    }

    function count() external view returns (uint256) {
        return _messages.length;
    }

    function message(uint256 i) external view returns (Message memory) {
        return _messages[i];
    }

    function idOf(uint256 i) public view returns (bytes32) {
        return keccak256(abi.encode(address(this), i));
    }

    /// @notice Delivers message `i` to its recipient, presenting `sender` as its origin.
    function deliver(uint256 i, bytes calldata sender) external {
        Message storage m = _messages[i];
        (, address target) = InteroperableAddress.parseEvmV1(m.recipient);
        IERC7786Recipient(target).receiveMessage(idOf(i), sender, m.payload);
    }

    /// @notice Delivers arbitrary content under an arbitrary id (a forged or foreign delivery).
    function deliverRaw(address target, bytes32 id, bytes calldata sender, bytes calldata payload) external {
        IERC7786Recipient(target).receiveMessage(id, sender, payload);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @title CrosschainLaneHandler
/// @notice Drives two crosschain value lanes between recipe-built diamonds over one local relay, modelling two chains
///         in one EVM (each side keeps its own link table, so both sides can share the chain id):
///         - lane 1, burn/mint: {DeployERC20Crosschain} token A <-> {DeployERC20Crosschain} token B;
///         - lane 2, lock/mint: {DeployBridgeERC20} custody bridge over token A <-> {DeployBridgeERC7802} bridge over
///           a {DeployERC7802} token.
///         Actions: ERC-20 transfers on every token, sends in both directions on both lanes, out-of-order delivery,
///         replays, forged deliveries (a foreign gateway, a wrong origin) and direct calls to the message handlers.
/// @dev Revert-free under `fail_on_revert`: sends are bounded to the sender's balance, and every refused call arms the
///      exact revert. A ghost ledger tracks every balance and every in-flight amount independently of the tokens.
contract CrosschainLaneHandler is Test {
    struct Msg {
        uint8 lane; // 1 = burn/mint, 2 = lock/mint
        bool aToB;
        address source; // the sending diamond (the counterpart the destination trusts)
        address dest; // the receiving diamond
        address to;
        uint256 amount;
        bool delivered;
    }

    address public immutable tokenA;
    address public immutable tokenB;
    address public immutable bridgeA;
    address public immutable bridgeB;
    address public immutable token7802;
    RelayGateway public immutable gateway;
    RelayGateway public immutable rogue;

    address[4] internal _actors;
    Msg[] internal _msgs;

    mapping(address token => mapping(address account => uint256)) public ghostBalance;
    mapping(address token => uint256) public ghostSupply;
    uint256 public ghostInFlight1;
    uint256 public ghostInFlight2;
    uint256 public ghostEscrow;

    constructor(
        address tokenA_,
        address tokenB_,
        address bridgeA_,
        address bridgeB_,
        address token7802_,
        RelayGateway gateway_,
        RelayGateway rogue_
    ) {
        tokenA = tokenA_;
        tokenB = tokenB_;
        bridgeA = bridgeA_;
        bridgeB = bridgeB_;
        token7802 = token7802_;
        gateway = gateway_;
        rogue = rogue_;
        _actors[0] = address(0xA11CE);
        _actors[1] = address(0xB0B);
        _actors[2] = address(0xCA201);
        _actors[3] = address(0xD0D);
    }

    // ---- Views ----

    function actors() external view returns (address[4] memory) {
        return _actors;
    }

    function msgCount() external view returns (uint256) {
        return _msgs.length;
    }

    function msgAt(uint256 i) external view returns (Msg memory) {
        return _msgs[i];
    }

    // ---- Setup ----

    /// @notice Setup only: records the balances minted before the campaign.
    function seed(address token, address account, uint256 amount) external {
        ghostBalance[token][account] += amount;
        ghostSupply[token] += amount;
    }

    // ---- Helpers ----

    function _actor(uint256 seed_) internal view returns (address) {
        return _actors[seed_ % _actors.length];
    }

    function _to(address account) internal view returns (bytes memory) {
        return InteroperableAddress.formatEvmV1(block.chainid, account);
    }

    function _push(uint8 lane, bool aToB, address source, address dest, address to, uint256 amount, bytes32 sendId)
        internal
    {
        assertEq(sendId, gateway.idOf(_msgs.length), "send id != relay id");
        _msgs.push(Msg(lane, aToB, source, dest, to, amount, false));
        assertEq(gateway.count(), _msgs.length, "relay queue diverged");
    }

    /// @dev A message picked by `seed`: preferring one whose `delivered` flag is `want`, else any.
    function _pick(uint256 seed_, bool want) internal view returns (uint256) {
        uint256 n = _msgs.length;
        for (uint256 k; k < n; ++k) {
            uint256 i = (seed_ % n + k) % n;
            if (_msgs[i].delivered == want) return i;
        }
        return seed_ % n;
    }

    // ---- Local transfers ----

    function transfer(uint256 tokenSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address token = tokenSeed % 3 == 0 ? tokenA : tokenSeed % 3 == 1 ? tokenB : token7802;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[token][from]);
        vm.prank(from);
        IERC20(token).transfer(to, amount);
        ghostBalance[token][from] -= amount;
        ghostBalance[token][to] += amount;
    }

    // ---- Sends ----

    /// @dev Lane 1: burns on the source token and queues a mint on the other.
    function sendBurnMint(bool aToB, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address src = aToB ? tokenA : tokenB;
        address dst = aToB ? tokenB : tokenA;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[src][from]);
        vm.prank(from);
        bytes32 sendId = IBridgeFungible(src).crosschainTransfer(_to(to), amount);
        ghostBalance[src][from] -= amount;
        ghostSupply[src] -= amount;
        ghostInFlight1 += amount;
        _push(1, aToB, src, dst, to, amount, sendId);
    }

    /// @dev Lane 2, A to B: locks token A in the custody bridge and queues a mint of the ERC-7802 token.
    function sendLock(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[tokenA][from]);
        vm.startPrank(from);
        IERC20(tokenA).approve(bridgeA, amount);
        bytes32 sendId = IBridgeFungible(bridgeA).crosschainTransfer(_to(to), amount);
        vm.stopPrank();
        ghostBalance[tokenA][from] -= amount;
        ghostBalance[tokenA][bridgeA] += amount;
        ghostEscrow += amount;
        ghostInFlight2 += amount;
        _push(2, true, bridgeA, bridgeB, to, amount, sendId);
    }

    /// @dev Lane 2, B to A: burns the ERC-7802 token through its bridge and queues a release of locked token A.
    function sendBurnRelease(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[token7802][from]);
        vm.prank(from);
        bytes32 sendId = IBridgeFungible(bridgeB).crosschainTransfer(_to(to), amount);
        ghostBalance[token7802][from] -= amount;
        ghostSupply[token7802] -= amount;
        ghostInFlight2 += amount;
        _push(2, false, bridgeB, bridgeA, to, amount, sendId);
    }

    // ---- Delivery ----

    /// @dev Delivers a queued message (out of order), crediting its recipient on the destination side.
    function deliver(uint256 seed_) external {
        if (_msgs.length == 0) return;
        uint256 i = _pick(seed_, false);
        Msg storage m = _msgs[i];
        if (m.delivered) {
            vm.expectRevert(
                abi.encodeWithSelector(ICrosschainLink.CrosschainMessageAlreadyProcessed.selector, gateway.idOf(i))
            );
        }
        gateway.deliver(i, _to(m.source));
        if (m.delivered) return;
        m.delivered = true;
        if (m.lane == 1) {
            address dst = m.aToB ? tokenB : tokenA;
            ghostInFlight1 -= m.amount;
            ghostBalance[dst][m.to] += m.amount;
            ghostSupply[dst] += m.amount;
        } else if (m.aToB) {
            ghostInFlight2 -= m.amount;
            ghostBalance[token7802][m.to] += m.amount;
            ghostSupply[token7802] += m.amount;
        } else {
            ghostInFlight2 -= m.amount;
            ghostEscrow -= m.amount;
            ghostBalance[tokenA][bridgeA] -= m.amount;
            ghostBalance[tokenA][m.to] += m.amount;
        }
    }

    /// @dev Replays a delivered message through the same relay: refused, nothing is credited twice.
    function replay(uint256 seed_) external {
        if (_msgs.length == 0) return;
        uint256 i = _pick(seed_, true);
        Msg storage m = _msgs[i];
        if (!m.delivered) return;
        vm.expectRevert(
            abi.encodeWithSelector(ICrosschainLink.CrosschainMessageAlreadyProcessed.selector, gateway.idOf(i))
        );
        gateway.deliver(i, _to(m.source));
    }

    /// @dev Forged deliveries, all refused: a foreign gateway relaying a real message, the relay presenting the wrong
    ///      origin, and an actor calling the destination's message handler directly.
    function forge(uint256 seed_, uint256 kind, uint256 actorSeed) external {
        if (_msgs.length == 0) return;
        uint256 i = seed_ % _msgs.length;
        Msg storage m = _msgs[i];
        RelayGateway.Message memory raw = gateway.message(i);
        bytes32 id = gateway.idOf(i);
        kind %= 3;
        if (kind == 0) {
            bytes memory sender = _to(m.source);
            vm.expectRevert(
                abi.encodeWithSelector(ICrosschainLink.CrosschainUnauthorizedGateway.selector, address(rogue), sender)
            );
            rogue.deliverRaw(m.dest, id, sender, raw.payload);
        } else if (kind == 1) {
            bytes memory wrong = _to(_actor(actorSeed));
            vm.expectRevert(
                abi.encodeWithSelector(ICrosschainLink.CrosschainUnauthorizedGateway.selector, address(gateway), wrong)
            );
            gateway.deliver(i, wrong);
        } else {
            address caller = _actor(actorSeed);
            bytes memory body = new bytes(raw.payload.length - 4);
            for (uint256 k; k < body.length; ++k) {
                body[k] = raw.payload[k + 4];
            }
            vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeUnauthorizedCaller.selector, caller));
            vm.prank(caller);
            IERC7786MessageHandler(m.dest).processMessage(id, _to(m.source), body);
        }
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                 INVARIANTS
//////////////////////////////////////////////////////////////////////////*//

/// @title CrosschainLaneDiamondInvariant
/// @notice Stateful properties of the crosschain value rails on recipe-built diamonds (#231):
///         - burn/mint conservation: supply(A) + supply(B) + in flight on lane 1 is constant;
///         - lock/mint conservation: token A locked in the custody bridge = ERC-7802 supply + in flight on lane 2;
///         - every balance and supply matches an independent ghost ledger, and supplies equal the sum of holders;
///         - each message is processed at most once per relay: the destination marks exactly the delivered ids, and
///           replays, foreign gateways, wrong origins and direct handler calls never credit anything.
/// forge-config: ci.invariant.runs = 64
contract CrosschainLaneDiamondInvariant is Test {
    CrosschainLaneHandler internal handler;
    RelayGateway internal gateway;
    RelayGateway internal rogue;
    address internal tokenA;
    address internal tokenB;
    address internal bridgeA;
    address internal bridgeB;
    address internal token7802;

    address internal constant ADMIN = address(0xAD);
    uint256 internal constant SEED_BALANCE = 1e24;
    uint256 public seeded;

    function _assemble(FacetCut[] memory cuts, address init, bytes memory initCalldata) internal returns (address) {
        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        return address(d);
    }

    /// @dev A {DeployERC20Crosschain} diamond plus the test-only {TokenTestFacet}, so balances can be seeded.
    function _selfBridgingToken(string memory name) internal returns (address) {
        (FacetCut[] memory prod, address init, bytes memory initCalldata) =
            new DeployERC20Crosschain().buildCuts(ADMIN, name, name);
        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = TokenTestFacet.mint.selector;
        sels[1] = TokenTestFacet.burn.selector;
        cuts[prod.length] = FacetCut({
            facetAddress: address(new TokenTestFacet()), action: FacetCutAction.Add, functionSelectors: sels
        });
        return _assemble(cuts, init, initCalldata);
    }

    function _link(address local, address counterpart) internal {
        vm.startPrank(ADMIN);
        ICrosschainLink(local)
            .setLink(address(gateway), InteroperableAddress.formatEvmV1(block.chainid, counterpart), false);
        ICrosschainLink(local).setHandler(FUNGIBLE_BRIDGE_TAG, local);
        vm.stopPrank();
    }

    function setUp() public {
        gateway = new RelayGateway();
        rogue = new RelayGateway();

        tokenA = _selfBridgingToken("Lane A");
        tokenB = _selfBridgingToken("Lane B");
        {
            (FacetCut[] memory c, address i, bytes memory d) = new DeployBridgeERC20().buildCuts(ADMIN, tokenA);
            bridgeA = _assemble(c, i, d);
        }
        {
            (FacetCut[] memory c, address i, bytes memory d) =
                new DeployERC7802().buildCuts(ADMIN, ADMIN, "Lane 7802", "L7802");
            token7802 = _assemble(c, i, d);
        }
        {
            (FacetCut[] memory c, address i, bytes memory d) = new DeployBridgeERC7802().buildCuts(ADMIN, token7802);
            bridgeB = _assemble(c, i, d);
        }
        // The ERC-7802 token's mint/burn role moves from the deploy-time placeholder to the bridge.
        vm.startPrank(ADMIN);
        IAccessControl(token7802).grantRole(CROSSCHAIN_BRIDGE_ROLE, bridgeB);
        IAccessControl(token7802).revokeRole(CROSSCHAIN_BRIDGE_ROLE, ADMIN);
        vm.stopPrank();

        _link(tokenA, tokenB);
        _link(tokenB, tokenA);
        _link(bridgeA, bridgeB);
        _link(bridgeB, bridgeA);

        handler = new CrosschainLaneHandler(tokenA, tokenB, bridgeA, bridgeB, token7802, gateway, rogue);
        address[4] memory a = handler.actors();
        for (uint256 i; i < a.length; ++i) {
            TokenTestFacet(tokenA).mint(a[i], SEED_BALANCE);
            TokenTestFacet(tokenB).mint(a[i], SEED_BALANCE);
            handler.seed(tokenA, a[i], SEED_BALANCE);
            handler.seed(tokenB, a[i], SEED_BALANCE);
            seeded += 2 * SEED_BALANCE;
        }

        bytes4[] memory selectors = new bytes4[](10);
        selectors[0] = CrosschainLaneHandler.transfer.selector;
        selectors[1] = CrosschainLaneHandler.sendBurnMint.selector;
        selectors[2] = CrosschainLaneHandler.sendBurnMint.selector;
        selectors[3] = CrosschainLaneHandler.sendLock.selector;
        selectors[4] = CrosschainLaneHandler.sendBurnRelease.selector;
        selectors[5] = CrosschainLaneHandler.deliver.selector;
        selectors[6] = CrosschainLaneHandler.deliver.selector;
        selectors[7] = CrosschainLaneHandler.deliver.selector;
        selectors[8] = CrosschainLaneHandler.replay.selector;
        selectors[9] = CrosschainLaneHandler.forge.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice Lane 1 burns on one side and mints on the other: the two supplies plus what is in flight never change.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_BurnMintConserved() public view {
        uint256 total = IERC20(tokenA).totalSupply() + IERC20(tokenB).totalSupply() + handler.ghostInFlight1();
        assertEq(total, seeded, "lane 1 created or destroyed value");
    }

    /// @notice Lane 2 locks token A and mints the ERC-7802 token: the escrow always backs the minted supply plus what
    ///         is in flight in either direction.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_LockMintConserved() public view {
        uint256 escrow = IERC20(tokenA).balanceOf(bridgeA);
        assertEq(escrow, handler.ghostEscrow(), "escrow != ghost");
        assertEq(escrow, IERC20(token7802).totalSupply() + handler.ghostInFlight2(), "escrow != minted + in flight");
    }

    /// @notice Every holder's balance and every supply match the ghost ledger, and each supply is the sum of holders.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_BalancesMatchLedger() public view {
        address[4] memory a = handler.actors();
        address[3] memory tokens = [tokenA, tokenB, token7802];
        for (uint256 t; t < tokens.length; ++t) {
            uint256 sum = tokens[t] == tokenA ? IERC20(tokenA).balanceOf(bridgeA) : 0;
            for (uint256 i; i < a.length; ++i) {
                uint256 bal = IERC20(tokens[t]).balanceOf(a[i]);
                assertEq(bal, handler.ghostBalance(tokens[t], a[i]), "balance != ghost");
                sum += bal;
            }
            assertEq(IERC20(tokens[t]).totalSupply(), handler.ghostSupply(tokens[t]), "supply != ghost");
            assertEq(IERC20(tokens[t]).totalSupply(), sum, "supply != sum of holders");
        }
    }

    /// @notice Each destination marks exactly the delivered ids of its relay as processed, the source never marks
    ///         its own outbound ids, and nothing from the foreign gateway is ever marked.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_EachMessageProcessedOnce() public view {
        uint256 n = handler.msgCount();
        for (uint256 i; i < n; ++i) {
            CrosschainLaneHandler.Msg memory m = handler.msgAt(i);
            bytes32 id = gateway.idOf(i);
            assertEq(ICrosschainLink(m.dest).isProcessed(address(gateway), id), m.delivered, "processed != delivered");
            assertFalse(ICrosschainLink(m.source).isProcessed(address(gateway), id), "source marked its own send");
            assertFalse(ICrosschainLink(m.dest).isProcessed(address(rogue), id), "foreign delivery marked");
        }
    }
}
