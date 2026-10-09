// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC7786OpenBridge} from "@lattice-script/base/crosschain/DeployERC7786OpenBridge.s.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {ERC7786_OPEN_BRIDGE_STORAGE_SLOT} from "@lattice/crosschain/libraries/ERC7786OpenBridgeLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IERC7786OpenBridge} from "@lattice/interfaces/crosschain/IERC7786OpenBridge.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

//*//////////////////////////////////////////////////////////////////////////
//                            BRIDGE STORAGE READS
//////////////////////////////////////////////////////////////////////////*//

/// @dev Slot of word `offset` of the open bridge's namespace: 0 the gateway set's length, 2 `_threshold`, 3 `_nonce`,
///      5 the `_trackers` mapping. The suite reads B's tracker and A's nonce straight from storage, since the
///      module exposes neither; {OpenBridgeDiamondInvariant-test_StorageReadsAreAligned} pins these offsets.
function bridgeSlot(uint256 offset) pure returns (bytes32) {
    return bytes32(uint256(ERC7786_OPEN_BRIDGE_STORAGE_SLOT) + offset);
}

/// @dev Base slot of the tracker for message `id`: `receivedBy` lives here, and the next word holds `countReceived`
///      (byte 0) and `executed` (byte 1).
function trackerSlot(bytes32 id) pure returns (bytes32) {
    return keccak256(abi.encode(id, bridgeSlot(5)));
}

/// @dev `countReceived` and `executed` of the tracker for message `id` on `bridge`.
function readTracker(Vm vm_, address bridge, bytes32 id) view returns (uint8 count, bool executed) {
    uint256 word = uint256(vm_.load(bridge, bytes32(uint256(trackerSlot(id)) + 1)));
    count = uint8(word);
    executed = uint8(word >> 8) != 0;
}

/// @dev Whether `gateway` has attested message `id` on `bridge`.
function readReceivedBy(Vm vm_, address bridge, bytes32 id, address gateway) view returns (bool) {
    return vm_.load(bridge, keccak256(abi.encode(gateway, trackerSlot(id)))) != bytes32(0);
}

//*//////////////////////////////////////////////////////////////////////////
//                                 FIXTURES
//////////////////////////////////////////////////////////////////////////*//

/// @notice One of the gateways an open bridge fans out over. It records each outbound message and later attests
///         arbitrary content to a destination, as the handler directs.
contract FanGateway is IERC7786GatewaySource {
    struct Message {
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
        _messages.push(Message(recipient, payload));
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

    function attest(address target, bytes32 receiveId, bytes calldata sender, bytes calldata payload) external {
        IERC7786Recipient(target).receiveMessage(receiveId, sender, payload);
    }
}

/// @notice The application the open bridge delivers to. Counts deliveries per message id and can be set to fail. On
///         each delivery it also snapshots, from the calling bridge itself, the threshold and the attestation count
///         the bridge executed under, so the quorum invariant reads the bridge rather than the handler's model.
contract OpenRecipient is IERC7786Recipient {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    mapping(bytes32 id => uint256) public hits;
    mapping(bytes32 id => uint8) public thresholdAt;
    mapping(bytes32 id => uint8) public attestationsAt;
    mapping(bytes32 id => bytes) public senderOf;
    mapping(bytes32 id => bytes) public payloadOf;
    uint256 public total;
    bool public failing;

    function setFailing(bool failing_) external {
        failing = failing_;
    }

    function receiveMessage(bytes32 id, bytes calldata sender, bytes calldata payload)
        external
        payable
        returns (bytes4)
    {
        require(!failing, "recipient failing");
        ++hits[id];
        thresholdAt[id] = IERC7786OpenBridge(msg.sender).getThreshold();
        (attestationsAt[id],) = readTracker(VM, msg.sender, id);
        senderOf[id] = sender;
        payloadOf[id] = payload;
        ++total;
        return IERC7786Recipient.receiveMessage.selector;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @title OpenBridgeHandler
/// @notice Drives two recipe-built {DeployERC7786OpenBridge} diamonds (source A fans out over three gateways;
///         destination B executes a message once enough of its gateways attest it) through sends, attestations from
///         member and non-member gateways, plain deliveries from non-gateways, forged origins, threshold and gateway
///         set changes on B, and a recipient that can fail (so a failed execution is retried later).
/// @dev Revert-free under `fail_on_revert`: every call is valid or arms the exact revert. A ghost model of B's
///      tracker (who attested each message, whether it executed) predicts every execution independently.
contract OpenBridgeHandler is Test {
    struct OMsg {
        bytes wrapped;
        bytes32 id;
        address sender;
        bytes payload;
        uint8 count;
        bool executed;
    }

    address public immutable bridgeA;
    address public immutable bridgeB;
    OpenRecipient public immutable recipient;
    address public immutable admin;
    FanGateway[4] internal _gateways;
    address[3] internal _actors;

    OMsg[] internal _msgs;
    mapping(uint256 msgIdx => mapping(address gateway => bool)) public ghostReceived;
    mapping(address gateway => bool) public ghostMember;
    uint256 public ghostMembers;
    uint8 public ghostThreshold;
    uint256 public ghostExecuted;
    uint256 public ghostNonce;

    constructor(
        address bridgeA_,
        address bridgeB_,
        OpenRecipient recipient_,
        address admin_,
        FanGateway[4] memory gateways_,
        uint8 threshold_
    ) {
        bridgeA = bridgeA_;
        bridgeB = bridgeB_;
        recipient = recipient_;
        admin = admin_;
        _gateways = gateways_;
        for (uint256 i; i < 3; ++i) {
            ghostMember[address(gateways_[i])] = true;
        }
        ghostMembers = 3;
        ghostThreshold = threshold_;
        _actors[0] = address(0xA11CE);
        _actors[1] = address(0xB0B);
        _actors[2] = address(0xCA201);
    }

    // ---- Views ----

    function gateways() external view returns (FanGateway[4] memory) {
        return _gateways;
    }

    function msgCount() external view returns (uint256) {
        return _msgs.length;
    }

    function msgAt(uint256 i) external view returns (OMsg memory) {
        return _msgs[i];
    }

    function fmt(address a) public view returns (bytes memory) {
        return InteroperableAddress.formatEvmV1(block.chainid, a);
    }

    // ---- Helpers ----

    function _gateway(uint256 seed) internal view returns (FanGateway) {
        return _gateways[seed % 4];
    }

    /// @dev Applies a delivery of message `i` from `from` to the ghost tracker and checks the outcome on the recipient.
    function _settleDelivery(uint256 i, address from) internal {
        OMsg storage m = _msgs[i];
        if (ghostMember[from] && !ghostReceived[i][from]) {
            ghostReceived[i][from] = true;
            ++m.count;
        }
        if (!m.executed && ghostThreshold != 0 && m.count >= ghostThreshold && !recipient.failing()) {
            m.executed = true;
            ++ghostExecuted;
        }
        assertEq(recipient.hits(m.id), m.executed ? 1 : 0, "execution diverged from the tracker model");
    }

    // ---- Sends ----

    /// @dev An actor sends through A, which fans out over its three gateways with the next nonce.
    function send(uint256 actorSeed, uint256 data) external {
        address sender = _actors[actorSeed % _actors.length];
        bytes memory payload = abi.encode(data, _msgs.length);
        vm.prank(sender);
        bytes32 sendId = IERC7786GatewaySource(bridgeA).sendMessage(fmt(address(recipient)), payload, new bytes[](0));

        uint256 i = _msgs.length;
        bytes32[] memory outbox = new bytes32[](3);
        bytes memory wrapped = _gateways[0].message(i).payload;
        for (uint256 g; g < 3; ++g) {
            FanGateway gw = _gateways[g];
            assertEq(gw.count(), i + 1, "fan-out skipped a gateway");
            FanGateway.Message memory rec = gw.message(i);
            assertEq(rec.recipient, fmt(bridgeB), "fan-out to the wrong remote bridge");
            assertEq(keccak256(rec.payload), keccak256(wrapped), "gateways got different payloads");
            outbox[g] = gw.idOf(i);
        }
        assertEq(sendId, keccak256(abi.encode(outbox)), "sendId != hash of the outbox");
        (uint256 nonce, bytes memory origin, bytes memory to, bytes memory inner) =
            abi.decode(wrapped, (uint256, bytes, bytes, bytes));
        assertEq(nonce, ++ghostNonce, "outbound nonce not +1");
        assertEq(origin, fmt(sender), "wrapped origin != sender");
        assertEq(to, fmt(address(recipient)), "wrapped recipient changed");
        assertEq(inner, payload, "wrapped payload changed");

        OMsg storage m = _msgs.push();
        m.wrapped = wrapped;
        m.id = keccak256(abi.encode(fmt(bridgeA), wrapped));
        m.sender = sender;
        m.payload = payload;
    }

    // ---- Deliveries ----

    /// @dev A gateway (member of B's set or not) attests message `i` to B under its own receive id.
    function attest(uint256 msgSeed, uint256 gwSeed) external {
        if (_msgs.length == 0) return;
        uint256 i = msgSeed % _msgs.length;
        FanGateway gw = _gateway(gwSeed);
        gw.attest(bridgeB, gw.idOf(i), fmt(bridgeA), _msgs[i].wrapped);
        _settleDelivery(i, address(gw));
    }

    /// @dev Anyone may hand B a message: it never counts as an attestation, but triggers an execution that is due.
    function deliverDirect(uint256 actorSeed, uint256 msgSeed) external {
        if (_msgs.length == 0) return;
        uint256 i = msgSeed % _msgs.length;
        address caller = _actors[actorSeed % _actors.length];
        vm.prank(caller);
        IERC7786Recipient(bridgeB).receiveMessage(bytes32(msgSeed), fmt(bridgeA), _msgs[i].wrapped);
        _settleDelivery(i, caller);
    }

    /// @dev An attestation claiming any origin but bridge A is refused.
    function forgeOrigin(uint256 msgSeed, uint256 gwSeed, uint256 actorSeed) external {
        if (_msgs.length == 0) return;
        uint256 i = msgSeed % _msgs.length;
        FanGateway gw = _gateway(gwSeed);
        bytes memory wrong = fmt(_actors[actorSeed % _actors.length]);
        bytes32 rid = gw.idOf(i);
        vm.expectRevert(IERC7786OpenBridge.InvalidCrosschainSender.selector);
        gw.attest(bridgeB, rid, wrong, _msgs[i].wrapped);
    }

    // ---- B's configuration ----

    function setThreshold(uint256 callerSeed, uint8 t) external {
        address caller = callerSeed % 4 == 0 ? _actors[callerSeed % 3] : admin;
        t = uint8(bound(t, 0, 5));
        bool ok;
        if (caller != admin) {
            vm.expectRevert(
                abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, bytes32(0))
            );
        } else if (t == 0 || t > ghostMembers) {
            vm.expectRevert(IERC7786OpenBridge.ThresholdViolation.selector);
        } else {
            ok = true;
        }
        vm.prank(caller);
        IERC7786OpenBridge(bridgeB).setThreshold(t);
        if (ok) ghostThreshold = t;
    }

    function addGateway(uint256 gwSeed) external {
        address gw = address(_gateway(gwSeed));
        vm.prank(admin);
        IERC7786OpenBridge(bridgeB).addGateway(gw);
        if (!ghostMember[gw]) {
            ghostMember[gw] = true;
            ++ghostMembers;
        }
    }

    /// @dev Removing a gateway that would leave fewer members than the threshold is refused.
    function removeGateway(uint256 gwSeed) external {
        address gw = address(_gateway(gwSeed));
        uint256 after_ = ghostMember[gw] ? ghostMembers - 1 : ghostMembers;
        bool ok = ghostThreshold <= after_;
        if (!ok) vm.expectRevert(IERC7786OpenBridge.ThresholdViolation.selector);
        vm.prank(admin);
        IERC7786OpenBridge(bridgeB).removeGateway(gw);
        if (ok && ghostMember[gw]) {
            ghostMember[gw] = false;
            --ghostMembers;
        }
    }

    /// @dev Flips whether the recipient fails, so due executions fail and are retried by a later delivery.
    function toggleRecipient() external {
        recipient.setFailing(!recipient.failing());
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                 INVARIANTS
//////////////////////////////////////////////////////////////////////////*//

/// @title OpenBridgeDiamondInvariant
/// @notice Stateful properties of the ERC-7786 open bridge (N-of-M gateway attestation) on recipe-built diamonds
///         (#231):
///         - replay protection: each message executes at most once, however many gateways or callers deliver it,
///           and a failed execution is retried, never doubled;
///         - a message executes only once at least `threshold` distinct member gateways have attested it;
///         - the outbound nonce rises by exactly one per send, and every gateway carries the same wrapped message;
///         - B's gateway set and threshold match the ghost, with 1 <= threshold <= members.
/// forge-config: ci.invariant.runs = 64
contract OpenBridgeDiamondInvariant is Test {
    OpenBridgeHandler internal handler;
    OpenRecipient internal recipient;
    address internal bridgeA;
    address internal bridgeB;

    address internal constant ADMIN = address(0xAD);
    uint8 internal constant THRESHOLD = 2;

    function _deploy() internal returns (address) {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            new DeployERC7786OpenBridge().buildCuts(ADMIN);
        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        return address(d);
    }

    function setUp() public {
        bridgeA = _deploy();
        bridgeB = _deploy();
        recipient = new OpenRecipient();
        FanGateway[4] memory g;
        for (uint256 i; i < 4; ++i) {
            g[i] = new FanGateway();
        }

        vm.startPrank(ADMIN);
        for (uint256 i; i < 3; ++i) {
            IERC7786OpenBridge(bridgeA).addGateway(address(g[i]));
            IERC7786OpenBridge(bridgeB).addGateway(address(g[i]));
        }
        IERC7786OpenBridge(bridgeA).setThreshold(1);
        IERC7786OpenBridge(bridgeB).setThreshold(THRESHOLD);
        IERC7786OpenBridge(bridgeA).registerRemoteBridge(InteroperableAddress.formatEvmV1(block.chainid, bridgeB));
        IERC7786OpenBridge(bridgeB).registerRemoteBridge(InteroperableAddress.formatEvmV1(block.chainid, bridgeA));
        vm.stopPrank();

        handler = new OpenBridgeHandler(bridgeA, bridgeB, recipient, ADMIN, g, THRESHOLD);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = OpenBridgeHandler.send.selector;
        selectors[1] = OpenBridgeHandler.send.selector;
        selectors[2] = OpenBridgeHandler.attest.selector;
        selectors[3] = OpenBridgeHandler.attest.selector;
        selectors[4] = OpenBridgeHandler.attest.selector;
        selectors[5] = OpenBridgeHandler.deliverDirect.selector;
        selectors[6] = OpenBridgeHandler.forgeOrigin.selector;
        selectors[7] = OpenBridgeHandler.setThreshold.selector;
        selectors[8] = OpenBridgeHandler.addGateway.selector;
        selectors[9] = OpenBridgeHandler.removeGateway.selector;
        selectors[10] = OpenBridgeHandler.toggleRecipient.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// @notice Each message reached the recipient at most once, exactly when the tracker model executed it, with the
    ///         original sender and payload.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ExecutedAtMostOnce() public view {
        uint256 n = handler.msgCount();
        for (uint256 i; i < n; ++i) {
            OpenBridgeHandler.OMsg memory m = handler.msgAt(i);
            assertEq(recipient.hits(m.id), m.executed ? 1 : 0, "message executed other than once");
            if (m.executed) {
                assertEq(recipient.senderOf(m.id), handler.fmt(m.sender), "delivered under the wrong origin");
                assertEq(recipient.payloadOf(m.id), m.payload, "delivered payload changed");
            }
        }
        assertEq(recipient.total(), handler.ghostExecuted(), "recipient ran an unknown message");
    }

    /// @notice Read from B itself: every delivery ran while B's threshold was at least one and B's tracker held at
    ///         least that many attestations (both snapshotted by the recipient during the call). B's tracker for
    ///         every message matches the ghost: which gateways attested it, how many distinct members that is, and
    ///         whether it executed.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ExecutedOnlyWithQuorum() public view {
        FanGateway[4] memory g = handler.gateways();
        uint256 n = handler.msgCount();
        for (uint256 i; i < n; ++i) {
            OpenBridgeHandler.OMsg memory m = handler.msgAt(i);
            (uint8 count, bool executed) = readTracker(vm, bridgeB, m.id);
            assertEq(count, m.count, "B counted other than the distinct member attestations");
            assertEq(executed, m.executed, "B's executed flag diverged from the tracker model");
            for (uint256 k; k < 4; ++k) {
                assertEq(
                    readReceivedBy(vm, bridgeB, m.id, address(g[k])),
                    handler.ghostReceived(i, address(g[k])),
                    "B's attestation record diverged from the ghost"
                );
            }
            if (recipient.hits(m.id) == 0) continue;
            assertGe(recipient.thresholdAt(m.id), 1, "executed under a zero threshold");
            assertGe(recipient.attestationsAt(m.id), recipient.thresholdAt(m.id), "executed below the threshold");
        }
    }

    /// @notice A's outbound nonce rose by one per send: A's stored nonce equals the sends, and every gateway holds
    ///         message `i` with nonce `i + 1`.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_NonceMonotonic() public view {
        uint256 n = handler.msgCount();
        assertEq(uint256(vm.load(bridgeA, bridgeSlot(3))), n, "A's nonce != sends");
        FanGateway[4] memory g = handler.gateways();
        for (uint256 k; k < 3; ++k) {
            assertEq(g[k].count(), n, "gateway missed a send");
            for (uint256 i; i < n; ++i) {
                (uint256 nonce,,,) = abi.decode(g[k].message(i).payload, (uint256, bytes, bytes, bytes));
                assertEq(nonce, i + 1, "nonce not strictly +1");
            }
        }
        assertEq(g[3].count(), 0, "A fanned out to a gateway outside its set");
    }

    /// @notice B's gateway set and threshold match the ghost, and 1 <= threshold <= members.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ConfigMatchesGhost() public view {
        address[] memory set = IERC7786OpenBridge(bridgeB).getGateways();
        uint8 t = IERC7786OpenBridge(bridgeB).getThreshold();
        assertEq(set.length, handler.ghostMembers(), "gateway count != ghost");
        for (uint256 i; i < set.length; ++i) {
            assertTrue(handler.ghostMember(set[i]), "unexpected gateway");
        }
        assertEq(t, handler.ghostThreshold(), "threshold != ghost");
        assertGe(t, 1, "threshold zero");
        assertLe(t, set.length, "threshold above members");
        assertEq(uint256(vm.load(bridgeB, bridgeSlot(0))), set.length, "gateway-set slot misaligned");
        assertEq(uint256(vm.load(bridgeB, bridgeSlot(2))), t, "threshold slot misaligned");
    }

    /// @notice Pins the storage offsets the invariants read: A's nonce counts sends, and one member attestation on
    ///         B shows up as `countReceived == 1`, `receivedBy` set for that gateway only, and not executed (the
    ///         threshold is two); a second attestation executes it.
    function test_StorageReadsAreAligned() public {
        assertEq(uint256(vm.load(bridgeA, bridgeSlot(3))), 0, "nonce slot misaligned");
        handler.send(0, 7);
        assertEq(uint256(vm.load(bridgeA, bridgeSlot(3))), 1, "nonce slot misaligned");

        FanGateway[4] memory g = handler.gateways();
        bytes32 id = handler.msgAt(0).id;
        handler.attest(0, 0);
        (uint8 count, bool executed) = readTracker(vm, bridgeB, id);
        assertEq(count, 1, "countReceived misaligned");
        assertFalse(executed, "executed misaligned");
        assertTrue(readReceivedBy(vm, bridgeB, id, address(g[0])), "receivedBy misaligned");
        assertFalse(readReceivedBy(vm, bridgeB, id, address(g[1])), "receivedBy set for a silent gateway");

        handler.attest(0, 1);
        (count, executed) = readTracker(vm, bridgeB, id);
        assertEq(count, 2, "countReceived misaligned");
        assertTrue(executed, "executed misaligned");
        assertEq(recipient.hits(id), 1, "not delivered at the threshold");
        assertEq(recipient.thresholdAt(id), THRESHOLD, "recipient snapshot of the threshold");
        assertEq(recipient.attestationsAt(id), 2, "recipient snapshot of the attestation count");
    }
}
