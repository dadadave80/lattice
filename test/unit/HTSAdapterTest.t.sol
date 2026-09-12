// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {HTSAdapterTestBase} from "@lattice-test/base/HTSAdapterTestBase.sol";
import {MockHederaTokenService} from "@lattice-test/mocks/hedera/MockHederaTokenService.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {HederaResponseCodes} from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import {IHederaTokenService} from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
import {IHTSAdapter} from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import {HTSAdapter} from "@lattice/tokens/hedera/HTSAdapter.sol";
import {HTS_KEY_SUPPLY, HTS_MANAGER_ROLE, HTS_OPERATOR_ROLE} from "@lattice/tokens/hedera/HTSAdapterLib.sol";

/// @title HTSAdapterTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Exercises the Hedera Token Service facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployHTSAdapter} script (see {HTSAdapterTestBase}) against a `vm.etch`ed {MockHederaTokenService}
///         at `0x167` — no fork, no RPC. Every call routes through the diamond's `delegatecall` dispatch, which
///         is the frame HTS keys on, so the `delegatableContractId` supply-key requirement is proved end to end
///         alongside the full response-code → typed-error mapping. Role gating is enforced by the cut-in
///         `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`.
/// @dev Branching trees: [`HTSAdapterAssociateToken.tree`](HTSAdapterAssociateToken.tree) and
///      [`HTSAdapterMintToken.tree`](HTSAdapterMintToken.tree).
contract HTSAdapterTest is HTSAdapterTestBase {
    /// @dev The Hedera Token Service system contract (HIP-206) — pinned here independently of the module.
    address constant HTS = 0x0000000000000000000000000000000000000167;
    /// @dev `type(IHTSAdapter).interfaceId`, pinned so a drifting interface fails loudly.
    bytes4 constant IHTS_ADAPTER_ID = 0x37ae8968;

    string constant FT_NAME = "Lattice HTS Fungible";
    string constant FT_SYMBOL = "LHF";
    string constant NFT_NAME = "Lattice HTS Collection";
    string constant NFT_SYMBOL = "LHC";
    string constant MEMO = "lattice hts adapter test";
    int64 constant INITIAL_SUPPLY = 1_000;
    uint256 constant CREATION_FEE = 1 ether;

    MockHederaTokenService hts;

    address admin = makeAddr("admin");
    address manager = makeAddr("manager"); // HTS_MANAGER_ROLE only
    address operator = makeAddr("operator"); // HTS_OPERATOR_ROLE only
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address notAToken = makeAddr("notAToken");

    function setUp() public {
        vm.etch(HTS, address(new MockHederaTokenService()).code);
        hts = MockHederaTokenService(payable(HTS));

        diamond = _deployHTSAdapter(admin);
        htsAdapter = HTSAdapter(diamond);

        // Single-role holders prove each gate independently: neither may pass the other's.
        vm.startPrank(admin);
        IAccessControl(diamond).grantRole(HTS_MANAGER_ROLE, manager);
        IAccessControl(diamond).grantRole(HTS_OPERATOR_ROLE, operator);
        vm.stopPrank();

        vm.deal(admin, 100 ether);
        vm.deal(address(this), 100 ether);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Creates a fungible token through the diamond: it becomes treasury, auto-renew account and holder
    ///      of the admin + supply keys, with `INITIAL_SUPPLY` units sitting in the treasury.
    function _createFungibleToken() internal returns (address token) {
        vm.prank(admin);
        token =
            htsAdapter.createFungibleToken{value: CREATION_FEE}(FT_NAME, FT_SYMBOL, MEMO, 8, INITIAL_SUPPLY, int64(0));
    }

    /// @dev Creates a non-fungible token through the diamond (an empty collection until a mint).
    function _createNonFungibleToken() internal returns (address token) {
        vm.prank(admin);
        token = htsAdapter.createNonFungibleToken{value: CREATION_FEE}(NFT_NAME, NFT_SYMBOL, MEMO, int64(0));
    }

    /// @dev Creates a token on the ledger OUTSIDE the diamond: the test contract is the treasury and
    ///      `supplyKey` (zero for none) is the `delegatableContractId` holder — so the diamond is neither
    ///      associated with it nor, unless `supplyKey` is the diamond, able to mint it.
    function _foreignToken(address supplyKey) internal returns (address token) {
        IHederaTokenService.HederaToken memory t;
        t.treasury = address(this);
        if (supplyKey != address(0)) {
            t.tokenKeys = new IHederaTokenService.TokenKey[](1);
            t.tokenKeys[0].keyType = HTS_KEY_SUPPLY;
            t.tokenKeys[0].key.delegatableContractId = supplyKey;
        }
        (, token) = IHederaTokenService(HTS).createFungibleToken{value: CREATION_FEE}(t, int64(0), int32(0));
    }

    /// @dev Associates `account` with `token` on the ledger — the counterparty-side transaction the diamond
    ///      never signs, so the receiver-must-be-associated network rule can be satisfied.
    function _associate(address account, address token) internal {
        hts.associateToken(account, token);
    }

    /// @dev Forces `code` as the next `transferToken` response and asserts the adapter maps it to
    ///      `expectedError`. `transferToken` is the vehicle because every mapping runs the shared `_check`.
    function _assertTransferCodeMapsTo(address token, int64 code, bytes memory expectedError) internal {
        hts.force(IHederaTokenService.transferToken.selector, code);
        vm.prank(admin);
        vm.expectRevert(expectedError);
        htsAdapter.transferToken(token, alice, 1);
    }

    /// @dev Gives `alice` a spendable balance and associates `bob`, so only the allowance is under test.
    function _seedAllowanceScenario(uint256 allowance) internal returns (address token) {
        token = _createFungibleToken();
        _associate(alice, token);
        _associate(bob, token);
        vm.prank(admin);
        htsAdapter.transferToken(token, alice, 100);
        if (allowance != 0) hts.seedAllowance(token, alice, diamond, allowance);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The IHTSAdapter flag is readable through the cut-in `ERC165Facet`. Load-bearing: the read path
    ///         recomputes the keccak at runtime, so a wrong `ERC165_MAP_IHTSADAPTER_SLOT` fails here.
    function test_SupportsInterface_IHTSAdapter() public view {
        assertEq(type(IHTSAdapter).interfaceId, IHTS_ADAPTER_ID, "IHTSAdapter interfaceId drifted");
        assertTrue(ERC165Facet(diamond).supportsInterface(IHTS_ADAPTER_ID), "IHTSAdapter flag missing");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ASSOCIATE TOKEN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Happy path: the diamond associates itself and emits {HTSTokenAssociated}.
    function test_AssociateToken_AssociatesTheDiamond() public {
        address token = _foreignToken(address(0));
        assertFalse(htsAdapter.isAssociated(token), "diamond starts unassociated");

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, diamond);
        emit IHTSAdapter.HTSTokenAssociated(token);
        htsAdapter.associateToken(token);

        assertTrue(htsAdapter.isAssociated(token), "diamond must be associated");
    }

    /// @notice HTS 194: the treasury of a token the diamond created is already associated.
    function test_AssociateToken_RevertsWhenAlreadyAssociated() public {
        address token = _createFungibleToken();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSTokenAlreadyAssociated.selector, token, diamond));
        htsAdapter.associateToken(token);
    }

    /// @notice HTS 167: the address is not an HTS token.
    function test_AssociateToken_RevertsWhenNotAToken() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSNotAToken.selector, notAToken));
        htsAdapter.associateToken(notAToken);
    }

    /// @notice Association is `HTS_MANAGER_ROLE`: an operator-only holder does not pass the manager gate.
    function test_AssociateToken_RevertsForOperatorWithoutManagerRole() public {
        address token = _foreignToken(address(0));
        vm.prank(operator);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, operator, HTS_MANAGER_ROLE)
        );
        htsAdapter.associateToken(token);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              DISSOCIATE TOKEN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Happy path: a zero-balance association is dropped and {HTSTokenDissociated} is emitted.
    function test_DissociateToken_DissociatesTheDiamond() public {
        address token = _foreignToken(address(0));
        vm.prank(admin);
        htsAdapter.associateToken(token);

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, diamond);
        emit IHTSAdapter.HTSTokenDissociated(token);
        htsAdapter.dissociateToken(token);

        assertFalse(htsAdapter.isAssociated(token), "diamond must be dissociated");
    }

    /// @notice HTS 195: the treasury still holds the created supply, so dissociation is refused.
    function test_DissociateToken_RevertsOnNonZeroBalance() public {
        address token = _createFungibleToken();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSNonZeroBalance.selector, token, diamond));
        htsAdapter.dissociateToken(token);
    }

    /// @notice HTS 184: there is nothing to dissociate.
    function test_DissociateToken_RevertsWhenNotAssociated() public {
        address token = _foreignToken(address(0));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSTokenNotAssociated.selector, token, diamond));
        htsAdapter.dissociateToken(token);
    }

    /// @notice Dissociation is `HTS_MANAGER_ROLE`.
    function test_DissociateToken_RevertsForNonManager() public {
        address token = _createFungibleToken();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, HTS_MANAGER_ROLE)
        );
        htsAdapter.dissociateToken(token);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             FUNGIBLE TOKEN LIFE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Creation puts the diamond in BOTH load-bearing seats: treasury of the initial supply and holder
    ///         of the supply key as a `delegatableContractId` key — the only form a facet frame activates (the
    ///         ledger records `address(0)` for a plain `contractId` key, so this assertion is the proof).
    function test_CreateFungibleToken_DiamondIsTreasuryAndSupplyKeyHolder() public {
        address token = _createFungibleToken();

        assertTrue(hts.tokenExists(token), "token must exist on the ledger");
        assertEq(hts.balanceOf(token, diamond), INITIAL_SUPPLY, "diamond must be the treasury");
        assertEq(hts.supplyKeyHolder(token), diamond, "supply key must be delegatableContractId(diamond)");
        assertTrue(htsAdapter.isAssociated(token), "the treasury is auto-associated");
        assertTrue(htsAdapter.isHTSToken(token), "created token must be an HTS token");
        assertEq(htsAdapter.htsTokenType(token), 0, "fungible token type");
    }

    /// @notice Creation is `HTS_MANAGER_ROLE`.
    function test_CreateFungibleToken_RevertsForNonManager() public {
        vm.deal(alice, CREATION_FEE);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, HTS_MANAGER_ROLE)
        );
        htsAdapter.createFungibleToken{value: CREATION_FEE}(FT_NAME, FT_SYMBOL, MEMO, 8, INITIAL_SUPPLY, int64(0));
    }

    /// @notice Local guards: a negative supply parameter, and an initial supply above a finite cap.
    function test_CreateFungibleToken_RevertsOnInvalidSupplyParameters() public {
        vm.startPrank(admin);

        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector); // negative initial supply
        htsAdapter.createFungibleToken{value: CREATION_FEE}(FT_NAME, FT_SYMBOL, MEMO, 8, -1, int64(0));

        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector); // negative max supply
        htsAdapter.createFungibleToken{value: CREATION_FEE}(FT_NAME, FT_SYMBOL, MEMO, 8, INITIAL_SUPPLY, -1);

        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector); // initial supply above a finite max supply
        htsAdapter.createFungibleToken{value: CREATION_FEE}(FT_NAME, FT_SYMBOL, MEMO, 8, 10, 5);

        vm.stopPrank();
    }

    /// @notice Happy path: burning reduces the treasury balance and the total supply.
    function test_BurnToken_BurnsFungibleSupplyFromTreasury() public {
        address token = _createFungibleToken();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, diamond);
        emit IHTSAdapter.HTSTokenBurned(token, 200, INITIAL_SUPPLY - 200);
        int64 newTotalSupply = htsAdapter.burnToken(token, 200, new int64[](0));

        assertEq(newTotalSupply, INITIAL_SUPPLY - 200, "burned supply");
        assertEq(hts.balanceOf(token, diamond), INITIAL_SUPPLY - 200, "treasury balance after the burn");
    }

    /// @notice Local guard: a negative burn amount never reaches the system contract.
    function test_BurnToken_RevertsOnNegativeAmount() public {
        address token = _createFungibleToken();
        vm.prank(admin);
        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector);
        htsAdapter.burnToken(token, -1, new int64[](0));
    }

    /// @notice Burning is `HTS_OPERATOR_ROLE`.
    function test_BurnToken_RevertsForNonOperator() public {
        address token = _createFungibleToken();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, HTS_OPERATOR_ROLE)
        );
        htsAdapter.burnToken(token, 1, new int64[](0));
    }

    /// @notice Happy path: the diamond moves its own balance to an associated receiver.
    function test_TransferToken_MovesTreasuryBalanceToReceiver() public {
        address token = _createFungibleToken();
        _associate(alice, token);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true, diamond);
        emit IHTSAdapter.HTSTokenTransferred(token, diamond, alice, 100);
        htsAdapter.transferToken(token, alice, 100);

        assertEq(hts.balanceOf(token, alice), 100, "receiver balance");
        assertEq(hts.balanceOf(token, diamond), INITIAL_SUPPLY - 100, "treasury balance");
    }

    /// @notice HTS 184: the receiver has not associated itself with the token.
    function test_TransferToken_RevertsWhenReceiverNotAssociated() public {
        address token = _createFungibleToken();
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSTokenNotAssociated.selector, token, diamond));
        htsAdapter.transferToken(token, alice, 100);
    }

    /// @notice Local guard: a zero or negative transfer amount never reaches the system contract.
    function test_TransferToken_RevertsOnNonPositiveAmount() public {
        address token = _createFungibleToken();
        _associate(alice, token);

        vm.startPrank(admin);
        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector);
        htsAdapter.transferToken(token, alice, 0);

        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector);
        htsAdapter.transferToken(token, alice, -1);
        vm.stopPrank();
    }

    /// @notice Transfers are `HTS_OPERATOR_ROLE`.
    function test_TransferToken_RevertsForNonOperator() public {
        address token = _createFungibleToken();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, HTS_OPERATOR_ROLE)
        );
        htsAdapter.transferToken(token, alice, 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           NON-FUNGIBLE TOKEN LIFE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Creation seats the diamond as treasury and `delegatableContractId` supply-key holder; the
    ///         collection starts empty and reports the non-fungible type.
    function test_CreateNonFungibleToken_DiamondIsTreasuryAndSupplyKeyHolder() public {
        address token = _createNonFungibleToken();

        assertTrue(hts.tokenExists(token), "token must exist on the ledger");
        assertEq(hts.supplyKeyHolder(token), diamond, "supply key must be delegatableContractId(diamond)");
        assertEq(hts.balanceOf(token, diamond), 0, "a fresh collection holds no serials");
        assertTrue(htsAdapter.isAssociated(token), "the treasury is auto-associated");
        assertEq(htsAdapter.htsTokenType(token), 1, "non-fungible token type");
    }

    /// @notice Local guard: a negative max supply never reaches the system contract.
    function test_CreateNonFungibleToken_RevertsOnNegativeMaxSupply() public {
        vm.prank(admin);
        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector);
        htsAdapter.createNonFungibleToken{value: CREATION_FEE}(NFT_NAME, NFT_SYMBOL, MEMO, -1);
    }

    /// @notice Happy path: a minted serial moves from the treasury to an associated receiver.
    function test_TransferNFT_MovesSerialToReceiver() public {
        address token = _createNonFungibleToken();
        _associate(alice, token);

        bytes[] memory metadata = new bytes[](1);
        metadata[0] = "ipfs://serial-1";
        vm.prank(admin);
        (, int64[] memory serials) = htsAdapter.mintToken(token, 0, metadata);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true, diamond);
        emit IHTSAdapter.HTSTokenTransferred(token, diamond, alice, 1);
        htsAdapter.transferNFT(token, alice, serials[0]);

        assertEq(hts.nftOwner(token, serials[0]), alice, "serial owner after the transfer");
        assertEq(hts.balanceOf(token, diamond), 0, "the treasury no longer holds the serial");
    }

    /// @notice Happy path: burning by serial clears the owner record and reduces the supply.
    function test_BurnToken_BurnsNonFungibleSerial() public {
        address token = _createNonFungibleToken();

        bytes[] memory metadata = new bytes[](2);
        metadata[0] = "ipfs://serial-1";
        metadata[1] = "ipfs://serial-2";
        vm.prank(admin);
        (, int64[] memory serials) = htsAdapter.mintToken(token, 0, metadata);

        int64[] memory burned = new int64[](1);
        burned[0] = serials[0];

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, diamond);
        emit IHTSAdapter.HTSTokenBurned(token, 1, 1);
        int64 newTotalSupply = htsAdapter.burnToken(token, 0, burned);

        assertEq(newTotalSupply, 1, "one serial left");
        assertEq(hts.nftOwner(token, serials[0]), address(0), "the burned serial has no owner");
        assertEq(hts.nftOwner(token, serials[1]), diamond, "the surviving serial stays in the treasury");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 MINT TOKEN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Happy path (fungible): `amount` units are minted to the treasury.
    function test_MintToken_MintsFungibleSupplyToTreasury() public {
        address token = _createFungibleToken();

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, diamond);
        emit IHTSAdapter.HTSTokenMinted(token, 500, INITIAL_SUPPLY + 500);
        (int64 newTotalSupply, int64[] memory serials) = htsAdapter.mintToken(token, 500, new bytes[](0));

        assertEq(newTotalSupply, INITIAL_SUPPLY + 500, "new total supply");
        assertEq(serials.length, 0, "a fungible mint returns no serials");
        assertEq(hts.balanceOf(token, diamond), INITIAL_SUPPLY + 500, "treasury balance after the mint");
    }

    /// @notice Happy path (non-fungible): one serial per metadata entry, returned in mint order.
    function test_MintToken_MintsNonFungibleSerialsFromMetadata() public {
        address token = _createNonFungibleToken();

        bytes[] memory metadata = new bytes[](2);
        metadata[0] = "ipfs://serial-1";
        metadata[1] = "ipfs://serial-2";

        vm.prank(admin);
        vm.expectEmit(true, false, false, true, diamond);
        emit IHTSAdapter.HTSTokenMinted(token, 2, 2);
        (int64 newTotalSupply, int64[] memory serials) = htsAdapter.mintToken(token, 0, metadata);

        assertEq(newTotalSupply, 2, "new total supply");
        assertEq(serials.length, 2, "one serial per metadata entry");
        assertEq(serials[0], 1, "first serial");
        assertEq(serials[1], 2, "second serial");
        assertEq(hts.nftOwner(token, serials[1]), diamond, "serials are minted to the treasury");
    }

    /// @notice Local guard: a negative mint amount never reaches the system contract.
    function test_MintToken_RevertsOnNegativeAmount() public {
        address token = _createFungibleToken();
        vm.prank(admin);
        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector);
        htsAdapter.mintToken(token, -1, new bytes[](0));
    }

    /// @notice HTS 167: the address is not an HTS token.
    function test_MintToken_RevertsWhenNotAToken() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSNotAToken.selector, notAToken));
        htsAdapter.mintToken(notAToken, 1, new bytes[](0));
    }

    /// @notice HTS 180: a token created without a supply key can never be minted.
    function test_MintToken_RevertsWithoutSupplyKey() public {
        address token = _foreignToken(address(0));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSTokenNoSupplyKey.selector, token));
        htsAdapter.mintToken(token, 1, new bytes[](0));
    }

    /// @notice HTS 326: the supply key belongs to somebody else, so no key activates for the diamond's frame.
    function test_MintToken_RevertsWhenSupplyKeyIsNotTheDiamond() public {
        address token = _foreignToken(address(this));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSKeyNotActive.selector, token));
        htsAdapter.mintToken(token, 1, new bytes[](0));
    }

    /// @notice HTS 236: the mint would push a finite token past its cap.
    function test_MintToken_RevertsWhenMaxSupplyReached() public {
        address token = _createFungibleToken();
        hts.force(IHederaTokenService.mintToken.selector, HederaResponseCodes.TOKEN_MAX_SUPPLY_REACHED);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSMaxSupplyReached.selector, token));
        htsAdapter.mintToken(token, 1, new bytes[](0));
    }

    /// @notice Minting is `HTS_OPERATOR_ROLE`: a manager-only holder does not pass the operator gate.
    function test_MintToken_RevertsForManagerWithoutOperatorRole() public {
        address token = _createFungibleToken();
        vm.prank(manager);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, manager, HTS_OPERATOR_ROLE)
        );
        htsAdapter.mintToken(token, 1, new bytes[](0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          TRANSFER FROM (ALLOWANCE)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Happy path: the diamond spends the allowance `alice` granted it.
    function test_TransferTokenFrom_SpendsAllowanceGrantedToTheDiamond() public {
        address token = _seedAllowanceScenario(50);

        vm.prank(admin);
        vm.expectEmit(true, true, true, true, diamond);
        emit IHTSAdapter.HTSTokenTransferred(token, alice, bob, 40);
        htsAdapter.transferTokenFrom(token, alice, bob, 40);

        assertEq(hts.balanceOf(token, alice), 60, "owner balance after the pull");
        assertEq(hts.balanceOf(token, bob), 40, "receiver balance after the pull");
        assertEq(hts.allowances(token, alice, diamond), 10, "the allowance is consumed");
    }

    /// @notice HTS 292: no allowance was ever granted to the diamond.
    function test_TransferTokenFrom_RevertsWithoutAllowance() public {
        address token = _seedAllowanceScenario(0);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSAllowanceExceeded.selector, token, alice));
        htsAdapter.transferTokenFrom(token, alice, bob, 40);
    }

    /// @notice HTS 293: the allowance exists but is smaller than the requested amount.
    function test_TransferTokenFrom_RevertsWhenAmountExceedsAllowance() public {
        address token = _seedAllowanceScenario(10);
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSAllowanceExceeded.selector, token, alice));
        htsAdapter.transferTokenFrom(token, alice, bob, 40);
    }

    /// @notice Local guard: a zero or negative pull amount never reaches the system contract.
    function test_TransferTokenFrom_RevertsOnNonPositiveAmount() public {
        address token = _seedAllowanceScenario(50);

        vm.startPrank(admin);
        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector);
        htsAdapter.transferTokenFrom(token, alice, bob, 0);

        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector);
        htsAdapter.transferTokenFrom(token, alice, bob, -1);
        vm.stopPrank();
    }

    /// @notice Allowance pulls are `HTS_OPERATOR_ROLE`.
    function test_TransferTokenFrom_RevertsForNonOperator() public {
        address token = _seedAllowanceScenario(50);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, HTS_OPERATOR_ROLE)
        );
        htsAdapter.transferTokenFrom(token, alice, bob, 40);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      RESPONSE CODE → TYPED ERROR MAPPING
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice HTS 184 → {HTSTokenNotAssociated}.
    function test_ErrorMapping_TokenNotAssociated() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token,
            HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT,
            abi.encodeWithSelector(IHTSAdapter.HTSTokenNotAssociated.selector, token, diamond)
        );
    }

    /// @notice HTS 194 → {HTSTokenAlreadyAssociated}.
    function test_ErrorMapping_TokenAlreadyAssociated() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token,
            HederaResponseCodes.TOKEN_ALREADY_ASSOCIATED_TO_ACCOUNT,
            abi.encodeWithSelector(IHTSAdapter.HTSTokenAlreadyAssociated.selector, token, diamond)
        );
    }

    /// @notice HTS 178 and HTS 28 → {HTSInsufficientBalance}.
    function test_ErrorMapping_InsufficientBalance() public {
        address token = _createFungibleToken();
        bytes memory expected = abi.encodeWithSelector(IHTSAdapter.HTSInsufficientBalance.selector, token, diamond);
        _assertTransferCodeMapsTo(token, HederaResponseCodes.INSUFFICIENT_TOKEN_BALANCE, expected);
        _assertTransferCodeMapsTo(token, HederaResponseCodes.INSUFFICIENT_ACCOUNT_BALANCE, expected);
    }

    /// @notice HTS 195 → {HTSNonZeroBalance}.
    function test_ErrorMapping_NonZeroBalance() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token,
            HederaResponseCodes.TRANSACTION_REQUIRES_ZERO_TOKEN_BALANCES,
            abi.encodeWithSelector(IHTSAdapter.HTSNonZeroBalance.selector, token, diamond)
        );
    }

    /// @notice HTS 7 and HTS 326 → {HTSKeyNotActive} (for a diamond: a `contractId` key that never activates).
    function test_ErrorMapping_KeyNotActive() public {
        address token = _createFungibleToken();
        bytes memory expected = abi.encodeWithSelector(IHTSAdapter.HTSKeyNotActive.selector, token);
        _assertTransferCodeMapsTo(token, HederaResponseCodes.INVALID_SIGNATURE, expected);
        _assertTransferCodeMapsTo(token, HederaResponseCodes.INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE, expected);
    }

    /// @notice HTS 180 → {HTSTokenNoSupplyKey}.
    function test_ErrorMapping_TokenNoSupplyKey() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token,
            HederaResponseCodes.TOKEN_HAS_NO_SUPPLY_KEY,
            abi.encodeWithSelector(IHTSAdapter.HTSTokenNoSupplyKey.selector, token)
        );
    }

    /// @notice HTS 236 → {HTSMaxSupplyReached}.
    function test_ErrorMapping_MaxSupplyReached() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token,
            HederaResponseCodes.TOKEN_MAX_SUPPLY_REACHED,
            abi.encodeWithSelector(IHTSAdapter.HTSMaxSupplyReached.selector, token)
        );
    }

    /// @notice HTS 265 → {HTSTokenPaused}.
    function test_ErrorMapping_TokenPaused() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token,
            HederaResponseCodes.TOKEN_IS_PAUSED,
            abi.encodeWithSelector(IHTSAdapter.HTSTokenPaused.selector, token)
        );
    }

    /// @notice HTS 165 → {HTSAccountFrozen}.
    function test_ErrorMapping_AccountFrozen() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token,
            HederaResponseCodes.ACCOUNT_FROZEN_FOR_TOKEN,
            abi.encodeWithSelector(IHTSAdapter.HTSAccountFrozen.selector, token, diamond)
        );
    }

    /// @notice HTS 176 → {HTSKycNotGranted}.
    function test_ErrorMapping_KycNotGranted() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token,
            HederaResponseCodes.ACCOUNT_KYC_NOT_GRANTED_FOR_TOKEN,
            abi.encodeWithSelector(IHTSAdapter.HTSKycNotGranted.selector, token, diamond)
        );
    }

    /// @notice HTS 292 and HTS 293 → {HTSAllowanceExceeded}.
    function test_ErrorMapping_AllowanceExceeded() public {
        address token = _createFungibleToken();
        bytes memory expected = abi.encodeWithSelector(IHTSAdapter.HTSAllowanceExceeded.selector, token, diamond);
        _assertTransferCodeMapsTo(token, HederaResponseCodes.SPENDER_DOES_NOT_HAVE_ALLOWANCE, expected);
        _assertTransferCodeMapsTo(token, HederaResponseCodes.AMOUNT_EXCEEDS_ALLOWANCE, expected);
    }

    /// @notice HTS 30 → {HTSInsufficientGas}.
    function test_ErrorMapping_InsufficientGas() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token, HederaResponseCodes.INSUFFICIENT_GAS, abi.encodeWithSelector(IHTSAdapter.HTSInsufficientGas.selector)
        );
    }

    /// @notice HTS 167 → {HTSNotAToken}.
    function test_ErrorMapping_NotAToken() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token,
            HederaResponseCodes.INVALID_TOKEN_ID,
            abi.encodeWithSelector(IHTSAdapter.HTSNotAToken.selector, token)
        );
    }

    /// @notice HTS 182, HTS 183 and HTS 225 → {HTSInvalidAmount}.
    function test_ErrorMapping_InvalidAmount() public {
        address token = _createFungibleToken();
        bytes memory expected = abi.encodeWithSelector(IHTSAdapter.HTSInvalidAmount.selector);
        _assertTransferCodeMapsTo(token, HederaResponseCodes.INVALID_TOKEN_MINT_AMOUNT, expected);
        _assertTransferCodeMapsTo(token, HederaResponseCodes.INVALID_TOKEN_BURN_AMOUNT, expected);
        _assertTransferCodeMapsTo(token, HederaResponseCodes.INVALID_TOKEN_NFT_SERIAL_NUMBER, expected);
    }

    /// @notice Catch-all: a code the adapter deliberately does not map surfaces as {HTSCallFailed} carrying the
    ///         HTS selector and the raw response code.
    function test_ErrorMapping_UnmappedCodeFallsBackToHTSCallFailed() public {
        address token = _createFungibleToken();
        _assertTransferCodeMapsTo(
            token,
            HederaResponseCodes.TOKEN_WAS_DELETED,
            abi.encodeWithSelector(
                IHTSAdapter.HTSCallFailed.selector,
                IHederaTokenService.transferToken.selector,
                HederaResponseCodes.TOKEN_WAS_DELETED
            )
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                    READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice `isHTSToken` answers false for an address the ledger does not know.
    function test_IsHTSToken_FalseForNonToken() public view {
        assertFalse(htsAdapter.isHTSToken(notAToken), "an unknown address is not an HTS token");
    }

    /// @notice HTS 167 → {HTSNotAToken} on the type getter.
    function test_HtsTokenType_RevertsForNonToken() public {
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSNotAToken.selector, notAToken));
        htsAdapter.htsTokenType(notAToken);
    }

    /// @notice The created-token set enumerates every create, in creation order.
    function test_CreatedTokens_EnumeratesEveryCreate() public {
        assertEq(htsAdapter.createdTokens().length, 0, "no tokens before the first create");

        address fungible = _createFungibleToken();
        address nonFungible = _createNonFungibleToken();

        address[] memory tokens = htsAdapter.createdTokens();
        assertEq(tokens.length, 2, "both creates enumerated");
        assertEq(tokens[0], fungible, "first create");
        assertEq(tokens[1], nonFungible, "second create");
    }
}
