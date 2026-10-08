// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {Test, console} from "forge-std/Test.sol";

/// @title SelectorCompatibilityTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The selector-compatibility matrix (#240). Deploys every {FacetInventory} facet, reads its ERC-8153
///         `exportSelectors()` (no FFI), and finds each selector two or more facets export. Two facets that
///         share a selector cannot both `Add` it to one diamond: the second cut reverts
///         `CannotAddFunctionToDiamondThatAlreadyExists`, and a `Replace` silently routes it to the later facet.
///         Every shared selector must carry a hand classification below, with the exact set of facets that
///         share it. A new clash, a changed set of sharers, or a row that no longer clashes fails the test,
///         so the published matrix (docs/guides/selector-compatibility.md) cannot drift. Run with `-vv` to print
///         the matrix as Markdown, after a full `forge build`: the facets load by artifact path, and a filtered
///         `forge test` compiles only what this file imports.
/// @dev Classes:
///      - Variant: alternative implementations of one Lattice module (cut gates, AccessControl and account
///        flavours). Cut exactly one.
///      - Override: a documented seam where a recipe routes the selector to one facet with `_cutExcept` or
///        `Replace` over shared storage (ERC4626/VaultCore/GovernedVault, ERC1155/ERC1155URIStorage,
///        ERC1155/ERC1155Pausable). Votes' delegations are replaced by ERC20Votes or ERC721Votes, but the two
///        replacements read different balances, so that row is Incompatible.
///      - Identical: the same function over the same storage. Cut one copy.
///      - OnePerDiamond: providers with one ABI and independent backends (price adapters, ERC-7786 gateways
///        and handlers, VRF providers, the ERC-20 and ERC-721 movement-replacing extensions and the ERC-1155 burns
///        per D25). One per diamond.
///      - Incompatible: the same selector means different things, from two standards or a Lattice-chosen name.
///        A row with mixed relations takes the most restrictive class; the note names the rest.
///      Inventory facets only: VestingWallet and ERC20Wrapper export no selectors yet (#176), so they are absent.
///      By hand: VestingWallet shares nothing; ERC20Wrapper shares only `decimals()` with ERC20 and ERC4626, and
///      `underlying()` with ERC721Wrapper (Incompatible). ERC721Wrapper's `onERC721Received` is also served by
///      UniswapV3Adapter, which is not in the inventory (Incompatible: the receiver seam, #201). ERC1363 shares no
///      selector, yet D25 makes it exclusive with ERC20Pausable, ERC20Votes and GovernedVault; that bypass is pinned
///      by {CompositionHazardsTest}, not here.
contract SelectorCompatibilityTest is Test {
    enum Class {
        Variant,
        Override,
        Identical,
        OnePerDiamond,
        Incompatible
    }

    struct Row {
        string signature;
        string facets;
        Class class;
        string note;
        bytes4 selector;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                THE MATRIX
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Every selector shared by two or more inventory facets is classified, with its exact sharers.
    function test_EverySharedSelectorIsClassified() public {
        (bytes4[] memory selectors, string[] memory sharers) = _sharedSelectors();
        Row[] memory rows = _rows();
        (bool ok, string memory reason) = _check(selectors, sharers, rows);
        assertTrue(ok, reason);
        _logMatrix(rows);
    }

    /// @notice Each row's signature hashes to its selector, so the published signatures are the real ones.
    function test_RowSignaturesMatchSelectors() public pure {
        Row[] memory rows = _rows();
        for (uint256 i; i < rows.length; ++i) {
            assertEq(bytes4(keccak256(bytes(rows[i].signature))), rows[i].selector, rows[i].signature);
        }
    }

    /// @notice The checker rejects a shared selector with no row.
    function test_Harness_FlagsUnclassifiedClash() public pure {
        Row[] memory rows = _rows();
        bytes4[] memory selectors = new bytes4[](1);
        string[] memory sharers = new string[](1);
        selectors[0] = 0xdeadbeef;
        sharers[0] = "A, B";
        (bool ok, string memory reason) = _check(selectors, sharers, rows);
        assertFalse(ok);
        assertEq(reason, "unclassified shared selector 0xdeadbeef (A, B)");
    }

    /// @notice The checker rejects a row whose sharers changed (a facet joined or left the clash).
    function test_Harness_FlagsChangedSharers() public pure {
        Row[] memory rows = _rows();
        bytes4[] memory selectors = new bytes4[](1);
        string[] memory sharers = new string[](1);
        selectors[0] = rows[0].selector;
        sharers[0] = string.concat(rows[0].facets, ", NewFacet");
        (bool ok, string memory reason) = _check(selectors, sharers, rows);
        assertFalse(ok);
        assertEq(reason, string.concat("sharers changed for ", rows[0].signature, ": ", rows[0].facets, ", NewFacet"));
    }

    /// @notice The checker rejects a row whose selector is no longer shared.
    function test_Harness_FlagsStaleRow() public pure {
        Row[] memory rows = _rows();
        (bool ok, string memory reason) = _check(new bytes4[](0), new string[](0), rows);
        assertFalse(ok);
        assertEq(reason, string.concat("stale row (no longer shared): ", rows[0].signature));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             CLASSIFICATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Sorted by selector. Facets are listed in {FacetInventory} order.
    function _rows() internal pure returns (Row[] memory r) {
        r = new Row[](74);
        r[0] = _row(
            "totalAssets()",
            "ERC4626, VaultCore",
            Class.Override,
            "VaultCore's strategy-aware NAV replaces ERC4626's idle balance",
            0x01e1d114
        );
        r[1] = _row(
            "name()",
            "ERC20, ERC721, GovernedVault, Governor",
            Class.Incompatible,
            "ERC-20 vs ERC-721 metadata (standard); GovernedVault owns the ERC-20/Governor name",
            0x06fdde03
        );
        r[2] = _row(
            "verifyInterfaceRegistered(bytes4)",
            "GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut",
            Class.Variant,
            "cut-gate variants: cut one",
            0x0746a956
        );
        r[3] = _row(
            "latestAnswer(bytes32)",
            "API3Adapter, BandAdapter, ChainlinkAdapter, ChronicleAdapter, DIAAdapter, PythAdapter, RedStoneAdapter, TellorAdapter",
            Class.OnePerDiamond,
            "price adapters: one per diamond",
            0x084d4783
        );
        r[4] = _row(
            "approve(address,uint256)", "ERC20, ERC721", Class.Incompatible, "ERC-20 vs ERC-721 (standard)", 0x095ea7b3
        );
        r[5] = _row(
            "uri(uint256)",
            "ERC1155, ERC1155URIStorage",
            Class.Override,
            "ERC1155URIStorage's per-token URI replaces ERC1155's template",
            0x0e89341c
        );
        r[6] = _row(
            "gateway()",
            "AxelarGatewayAdapter, ZetaChainGatewayAdapter",
            Class.OnePerDiamond,
            "ERC-7786 gateways: one per diamond",
            0x116191b6
        );
        r[7] = _row(
            "isOperationReady(bytes32)",
            "GovernedSafeDiamondCut, TimelockController",
            Class.Incompatible,
            "GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6)",
            0x13bc9f20
        );
        r[8] = _row(
            "isValidSignature(bytes32,bytes)",
            "ERC1271Signature, ERC6900Signature",
            Class.Variant,
            "account flavours: cut one",
            0x1626ba7e
        );
        r[9] = _row(
            "totalSupply()",
            "ERC1155Supply, ERC20, ERC721Enumerable",
            Class.Incompatible,
            "ERC-20 supply vs ERC-721 enumeration vs ERC-1155 supply (standard)",
            0x18160ddd
        );
        r[10] = _row(
            "safe()", "GovernedSafeDiamondCut, SafeDiamondCut", Class.Variant, "cut-gate variants: cut one", 0x186f0354
        );
        r[11] = _row(
            "validateUserOp((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes),bytes32,uint256)",
            "ERC4337Validation, ERC6900Validation",
            Class.Variant,
            "account flavours: cut one",
            0x19822f7c
        );
        r[12] = _row(
            "diamondCut((address,uint8,bytes4[])[],address,bytes)",
            "AccessControlDiamondCut, GovernedDiamondCut, SafeDiamondCut, DiamondCutFacet",
            Class.Variant,
            "cut-gate variants: cut one",
            0x1f931c1c
        );
        r[13] = _row(
            "frozenSelectors()",
            "GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut",
            Class.Variant,
            "cut-gate variants: cut one",
            0x22cabf70
        );
        r[14] = _row(
            "transferFrom(address,address,uint256)",
            "ERC20, ERC20Pausable, ERC20Votes, ERC721, ERC721Enumerable, ERC721Pausable, ERC721Votes, GovernedVault",
            Class.Incompatible,
            "ERC-20 vs ERC-721 (standard); one ERC-20 and one ERC-721 movement-replacing extension per diamond (D25)",
            0x23b872dd
        );
        r[15] = _row(
            "receiveMessage(bytes32,bytes,bytes)",
            "CrosschainLink, ERC7786OpenBridge",
            Class.OnePerDiamond,
            "inbound ERC-7786 recipients: one per diamond",
            0x2432ef26
        );
        r[16] = _row(
            "getRoleAdmin(bytes32)",
            "AccessControl, AccessControlEnumerable, AccessControlTimed",
            Class.Variant,
            "AccessControl flavours: cut one",
            0x248a9ca3
        );
        r[17] = _row(
            "getFeed(bytes32)",
            "API3Adapter, BandAdapter, ChainlinkAdapter, ChronicleAdapter, DIAAdapter, PythAdapter, RedStoneAdapter, TellorAdapter",
            Class.OnePerDiamond,
            "price adapters: one per diamond",
            0x280aebcf
        );
        r[18] = _row(
            "crosschainTransfer(bytes,uint256)",
            "BridgeERC20, BridgeERC7802, ERC20Crosschain",
            Class.OnePerDiamond,
            "fungible bridges: one per diamond",
            0x28dcc8d8
        );
        r[19] = _row(
            "unregisterFeed(bytes32)",
            "API3Adapter, BandAdapter, ChainlinkAdapter, ChronicleAdapter, DIAAdapter, PythAdapter, RedStoneAdapter, TellorAdapter",
            Class.OnePerDiamond,
            "price adapters: one per diamond",
            0x2a589908
        );
        r[20] = _row(
            "isOperationDone(bytes32)",
            "GovernedSafeDiamondCut, TimelockController",
            Class.Incompatible,
            "GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6)",
            0x2ab0f529
        );
        r[21] = _row(
            "safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)",
            "ERC1155, ERC1155Pausable",
            Class.Override,
            "ERC1155Pausable's pause-gated transfer replaces ERC1155's (D25)",
            0x2eb2c2d6
        );
        r[22] = _row(
            "grantRole(bytes32,address)",
            "AccessControl, AccessControlEnumerable, AccessControlTimed",
            Class.Variant,
            "AccessControl flavours: cut one",
            0x2f2ff15d
        );
        r[23] = _row(
            "decimals()", "ERC20, ERC4626", Class.Override, "ERC4626's share decimals replace ERC20's", 0x313ce567
        );
        r[24] = _row(
            "previewCut((address,uint8,bytes4[])[])",
            "GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut",
            Class.Variant,
            "cut-gate variants: cut one",
            0x35342750
        );
        r[25] = _row(
            "DOMAIN_SEPARATOR()",
            "ERC20Permit, ERC6538Registry",
            Class.Identical,
            "both return EIP712Lib.domainSeparatorV4(): cut one copy",
            0x3644e515
        );
        r[26] = _row(
            "renounceRole(bytes32,address)",
            "AccessControl, AccessControlEnumerable, AccessControlTimed",
            Class.Variant,
            "AccessControl flavours: cut one",
            0x36568abe
        );
        r[27] = _row(
            "getCutRecord(uint256)",
            "GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut",
            Class.Variant,
            "cut-gate variants: cut one",
            0x3adda78e
        );
        r[28] = _row(
            "messenger()",
            "L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter",
            Class.OnePerDiamond,
            "OP messenger gateways: one per diamond",
            0x3cb747bf
        );
        r[29] = _row(
            "maxDeposit(address)",
            "ERC4626, VaultCore",
            Class.Override,
            "VaultCore's deposit-latch-aware cap replaces ERC4626's",
            0x402d267d
        );
        r[30] = _row(
            "safeTransferFrom(address,address,uint256)",
            "ERC721, ERC721Enumerable, ERC721Pausable, ERC721Votes",
            Class.OnePerDiamond,
            "ERC721Enumerable, ERC721Pausable and ERC721Votes each replace ERC721's: one per diamond (D25)",
            0x42842e0e
        );
        r[31] = _row(
            "burn(uint256)",
            "ERC20Burnable, ERC721Burnable",
            Class.Incompatible,
            "ERC-20 vs ERC-721 (standard)",
            0x42966c68
        );
        r[32] = _row(
            "freezeSelectors(bytes4[])",
            "GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut",
            Class.Variant,
            "cut-gate variants: cut one",
            0x4487678f
        );
        r[33] = _row(
            "CLOCK_MODE()",
            "GovernedVault, Governor, Votes",
            Class.Override,
            "GovernedVault owns it; Governor's version reads its token's clock(), here the diamond itself",
            0x4bf5d7e9
        );
        r[34] = _row(
            "isOperationPending(bytes32)",
            "GovernedSafeDiamondCut, TimelockController",
            Class.Incompatible,
            "GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6)",
            0x584b153e
        );
        r[35] = _row(
            "quoteFee(bytes,bytes)",
            "CCIPGatewayAdapter, HyperlaneGatewayAdapter, LayerZeroGatewayAdapter",
            Class.OnePerDiamond,
            "ERC-7786 gateways: one per diamond",
            0x58d14c04
        );
        r[36] = _row(
            "delegate(address)",
            "ERC20Votes, ERC721Votes, Votes",
            Class.Incompatible,
            "ERC20Votes' and ERC721Votes' balance-aware delegation each replace Votes' (Override); ERC-20 vs ERC-721 units",
            0x5c19a95c
        );
        r[37] = _row(
            "setSafe(address)",
            "GovernedSafeDiamondCut, SafeDiamondCut",
            Class.Variant,
            "cut-gate variants: cut one",
            0x5db0cb94
        );
        r[38] = _row(
            "receiveCrossChainMessage(bytes,bytes,bytes,uint256)",
            "L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter",
            Class.OnePerDiamond,
            "OP messenger gateways: one per diamond",
            0x610683bc
        );
        r[39] = _row(
            "burnBatch(address,uint256[],uint256[])",
            "ERC1155Burnable, ERC1155Pausable, ERC1155Supply",
            Class.OnePerDiamond,
            "plain, pause-gated and supply-tracking ERC-1155 burns: one per diamond (D25)",
            0x6b20c454
        );
        r[40] = _row(
            "deposit(uint256,address)",
            "ERC4626, GovernedVault, VaultCore",
            Class.Override,
            "ERC4626 < VaultCore < GovernedVault checkpoint seam",
            0x6e553f65
        );
        r[41] =
            _row("balanceOf(address)", "ERC20, ERC721", Class.Incompatible, "ERC-20 vs ERC-721 (standard)", 0x70a08231);
        r[42] = _row(
            "getRemoteGateway(uint256)",
            "CCIPGatewayAdapter, WormholeGatewayAdapter",
            Class.OnePerDiamond,
            "ERC-7786 gateways: one per diamond",
            0x752bcf06
        );
        r[43] = _row(
            "owner()",
            "AccountSigner, OwnableFacet",
            Class.Incompatible,
            "AccountSigner's signer vs ERC-173 diamond owner (separate storage)",
            0x8da5cb5b
        );
        r[44] = _row(
            "castVoteBySig(uint256,uint8,address,bytes)",
            "GovernedVault, Governor",
            Class.Override,
            "GovernedVault's ballot-nonce reconciliation replaces Governor's",
            0x8ff262e3
        );
        r[45] = _row(
            "processMessage(bytes32,bytes,bytes)",
            "BridgeERC20, BridgeERC7802, CrosschainTimelockHandler, ERC20Crosschain",
            Class.OnePerDiamond,
            "ERC-7786 handlers: one per link diamond",
            0x902d5027
        );
        r[46] = _row(
            "registerFeed(bytes32,address,uint48)",
            "API3Adapter, ChainlinkAdapter, ChronicleAdapter",
            Class.OnePerDiamond,
            "price adapters: one per diamond",
            0x915d3063
        );
        r[47] = _row(
            "hasRole(bytes32,address)",
            "AccessControl, AccessControlEnumerable, AccessControlTimed",
            Class.Variant,
            "AccessControl flavours: cut one",
            0x91d14854
        );
        r[48] = _row(
            "clock()",
            "GovernedVault, Governor, Votes",
            Class.Override,
            "GovernedVault owns it; Governor's version reads its token's clock(), here the diamond itself",
            0x91ddadf4
        );
        r[49] = _row(
            "mint(uint256,address)",
            "ERC4626, GovernedVault, VaultCore",
            Class.Override,
            "ERC4626 < VaultCore < GovernedVault checkpoint seam",
            0x94bf804d
        );
        r[50] =
            _row("symbol()", "ERC20, ERC721", Class.Incompatible, "ERC-20 vs ERC-721 metadata (standard)", 0x95d89b41);
        r[51] = _row(
            "registerRemoteGateway(uint256,address)",
            "CCIPGatewayAdapter, WormholeGatewayAdapter",
            Class.OnePerDiamond,
            "ERC-7786 gateways: one per diamond",
            0x997ce1f0
        );
        r[52] = _row(
            "getForwarder()",
            "ChainlinkAutomationAdapter, ChainlinkCREAdapter",
            Class.Incompatible,
            "Chainlink Automation vs CRE forwarder (Lattice-chosen)",
            0xa0042526
        );
        r[53] = _row(
            "setApprovalForAll(address,bool)",
            "ERC1155, ERC721",
            Class.Incompatible,
            "ERC-721 vs ERC-1155 over separate storage (standard)",
            0xa22cb465
        );
        r[54] = _row(
            "transfer(address,uint256)",
            "ERC20, ERC20Pausable, ERC20Votes, GovernedVault",
            Class.OnePerDiamond,
            "ERC20Pausable, ERC20Votes and GovernedVault each replace ERC20's: one per diamond (D25)",
            0xa9059cbb
        );
        r[55] = _row(
            "cutCount()",
            "GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut",
            Class.Variant,
            "cut-gate variants: cut one",
            0xaa982c45
        );
        r[56] = _row(
            "latestAnswerRaw(bytes32)",
            "ChainlinkAdapter, PythAdapter",
            Class.OnePerDiamond,
            "price adapters: one per diamond",
            0xad0ddbee
        );
        r[57] = _row(
            "withdraw(uint256,address,address)",
            "ERC4626, GovernedVault, VaultCore",
            Class.Override,
            "ERC4626 < VaultCore < GovernedVault checkpoint seam",
            0xb460af94
        );
        r[58] = _row(
            "safeTransferFrom(address,address,uint256,bytes)",
            "ERC721, ERC721Enumerable, ERC721Pausable, ERC721Votes",
            Class.OnePerDiamond,
            "ERC721Enumerable, ERC721Pausable and ERC721Votes each replace ERC721's: one per diamond (D25)",
            0xb88d4fde
        );
        r[59] = _row(
            "redeem(uint256,address,address)",
            "ERC4626, GovernedVault, VaultCore",
            Class.Override,
            "ERC4626 < VaultCore < GovernedVault checkpoint seam",
            0xba087652
        );
        r[60] = _row(
            "delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)",
            "ERC20Votes, ERC721Votes, Votes",
            Class.Incompatible,
            "ERC20Votes' and ERC721Votes' balance-aware delegation each replace Votes' (Override); ERC-20 vs ERC-721 units",
            0xc3cda520
        );
        r[61] = _row(
            "getConfig()",
            "API3QRNGAdapter, ChainlinkVRF, GelatoAutomateAdapter, PythEntropyAdapter",
            Class.Incompatible,
            "four different return types (Lattice-chosen)",
            0xc3f909d4
        );
        r[62] = _row(
            "maxMint(address)",
            "ERC4626, VaultCore",
            Class.Override,
            "VaultCore's deposit-latch-aware cap replaces ERC4626's",
            0xc63d75b6
        );
        r[63] = _row(
            "emergencyRemoveCut((address,uint8,bytes4[])[])",
            "GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut",
            Class.Variant,
            "cut-gate variants: cut one",
            0xc83542a6
        );
        r[64] = _row(
            "isSelectorFrozen(bytes4)",
            "GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut",
            Class.Variant,
            "cut-gate variants: cut one",
            0xc8d8e114
        );
        r[65] = _row(
            "sendMessage(bytes,bytes,bytes[])",
            "AxelarGatewayAdapter, CCIPGatewayAdapter, CrosschainLink, ERC7786OpenBridge, HyperbridgeGatewayAdapter, HyperlaneGatewayAdapter, L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter, LayerZeroGatewayAdapter, WormholeGatewayAdapter, ZetaChainGatewayAdapter",
            Class.OnePerDiamond,
            "ERC-7786 senders: one per diamond",
            0xcdfe7f5c
        );
        r[66] = _row(
            "getTimestamp(bytes32)",
            "GovernedSafeDiamondCut, TimelockController",
            Class.Incompatible,
            "GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6)",
            0xd45c4435
        );
        r[67] = _row(
            "revokeRole(bytes32,address)",
            "AccessControl, AccessControlEnumerable, AccessControlTimed",
            Class.Variant,
            "AccessControl flavours: cut one",
            0xd547741f
        );
        r[68] = _row(
            "supportsAttribute(bytes4)",
            "AxelarGatewayAdapter, CCIPGatewayAdapter, ERC7786OpenBridge, HyperbridgeGatewayAdapter, HyperlaneGatewayAdapter, L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter, LayerZeroGatewayAdapter, WormholeGatewayAdapter, ZetaChainGatewayAdapter",
            Class.OnePerDiamond,
            "ERC-7786 gateways: one per diamond",
            0xdc680a0f
        );
        r[69] = _row(
            "getUserKey(uint256)",
            "ChainlinkVRF, GelatoVRFAdapter",
            Class.OnePerDiamond,
            "VRF providers: one per diamond",
            0xdd1e2651
        );
        r[70] = _row(
            "isApprovedForAll(address,address)",
            "ERC1155, ERC721",
            Class.Incompatible,
            "ERC-721 vs ERC-1155 over separate storage (standard)",
            0xe985e9c5
        );
        r[71] = _row(
            "safeTransferFrom(address,address,uint256,uint256,bytes)",
            "ERC1155, ERC1155Pausable",
            Class.Override,
            "ERC1155Pausable's pause-gated transfer replaces ERC1155's (D25)",
            0xf242432a
        );
        r[72] = _row(
            "burn(address,uint256,uint256)",
            "ERC1155Burnable, ERC1155Pausable, ERC1155Supply",
            Class.OnePerDiamond,
            "plain, pause-gated and supply-tracking ERC-1155 burns: one per diamond (D25)",
            0xf5298aca
        );
        r[73] = _row(
            "token()",
            "BridgeERC20, BridgeERC7802, Governor",
            Class.Incompatible,
            "Governor's voting token vs the bridges' bridged token (one bridge per diamond)",
            0xfc0c546a
        );
    }

    function _row(string memory signature, string memory facets, Class class, string memory note, bytes4 selector)
        private
        pure
        returns (Row memory)
    {
        return Row({signature: signature, facets: facets, class: class, note: note, selector: selector});
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CHECKER
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Matches each shared selector to exactly one row with the same sharers, then requires every row to
    ///      have matched. Returns the first mismatch as a reason.
    function _check(bytes4[] memory selectors, string[] memory sharers, Row[] memory rows)
        internal
        pure
        returns (bool ok, string memory reason)
    {
        bool[] memory matched = new bool[](rows.length);
        for (uint256 i; i < selectors.length; ++i) {
            uint256 j;
            while (j < rows.length && rows[j].selector != selectors[i]) ++j;
            if (j == rows.length) {
                return
                    (false, string.concat("unclassified shared selector ", _hex(selectors[i]), " (", sharers[i], ")"));
            }
            if (keccak256(bytes(rows[j].facets)) != keccak256(bytes(sharers[i]))) {
                return (false, string.concat("sharers changed for ", rows[j].signature, ": ", sharers[i]));
            }
            matched[j] = true;
        }
        for (uint256 j; j < rows.length; ++j) {
            if (!matched[j]) return (false, string.concat("stale row (no longer shared): ", rows[j].signature));
        }
        return (true, "");
    }

    /// @dev Every selector exported by two or more inventory facets, ascending, with its sharers joined by ", "
    ///      in inventory order. Each key packs `selector << 32 | facetIndex`, so one sort groups and orders both.
    function _sharedSelectors() internal returns (bytes4[] memory selectors, string[] memory sharers) {
        (string[] memory names, string[] memory paths) = FacetInventory.inventory();
        uint256[] memory keys = new uint256[](2048);
        uint256 n;
        for (uint256 f; f < names.length; ++f) {
            bytes memory packed = IERC8153(deployCode(paths[f])).exportSelectors();
            for (uint256 o; o < packed.length; o += 4) {
                keys[n++] = (uint256(uint32(_slice4(packed, o))) << 32) | f;
            }
        }
        assembly ("memory-safe") {
            mstore(keys, n)
        }
        _sort(keys);

        selectors = new bytes4[](n);
        sharers = new string[](n);
        uint256 count;
        for (uint256 i; i < n;) {
            uint256 sel = keys[i] >> 32;
            uint256 end = i + 1;
            while (end < n && keys[end] >> 32 == sel) ++end;
            if (end - i > 1) {
                string memory joined = names[keys[i] & 0xffffffff];
                for (uint256 k = i + 1; k < end; ++k) {
                    joined = string.concat(joined, ", ", names[keys[k] & 0xffffffff]);
                }
                selectors[count] = bytes4(uint32(sel));
                sharers[count++] = joined;
            }
            i = end;
        }
        assembly ("memory-safe") {
            mstore(selectors, count)
            mstore(sharers, count)
        }
    }

    /// @dev In-place insertion sort (a few hundred keys; no recursion).
    function _sort(uint256[] memory a) private pure {
        for (uint256 i = 1; i < a.length; ++i) {
            uint256 key = a[i];
            uint256 j = i;
            while (j > 0 && a[j - 1] > key) {
                a[j] = a[j - 1];
                --j;
            }
            a[j] = key;
        }
    }

    function _slice4(bytes memory b, uint256 offset) private pure returns (bytes4 out) {
        assembly ("memory-safe") {
            out := mload(add(add(b, 0x20), offset))
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 MARKDOWN
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Prints the matrix exactly as docs/guides/selector-compatibility.md publishes it.
    function _logMatrix(Row[] memory rows) private pure {
        console.log("| Selector | Signature | Facets | Class | Note |");
        console.log("| --- | --- | --- | --- | --- |");
        for (uint256 i; i < rows.length; ++i) {
            console.log(
                string.concat(
                    "| `",
                    _hex(rows[i].selector),
                    "` | `",
                    rows[i].signature,
                    "` | ",
                    rows[i].facets,
                    " | ",
                    _className(rows[i].class),
                    " | ",
                    rows[i].note,
                    " |"
                )
            );
        }
    }

    function _className(Class c) private pure returns (string memory) {
        if (c == Class.Variant) return "Variant";
        if (c == Class.Override) return "Override";
        if (c == Class.Identical) return "Identical";
        if (c == Class.OnePerDiamond) return "One per diamond";
        return "Incompatible";
    }

    function _hex(bytes4 selector) private pure returns (string memory) {
        bytes16 digits = "0123456789abcdef";
        bytes memory out = new bytes(10);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i; i < 4; ++i) {
            out[2 + 2 * i] = digits[uint8(selector[i]) >> 4];
            out[3 + 2 * i] = digits[uint8(selector[i]) & 0x0f];
        }
        return string(out);
    }
}
