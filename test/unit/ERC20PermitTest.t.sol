// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC20PermitTestBase} from "@lattice-test/base/ERC20PermitTestBase.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Permit} from "@lattice/interfaces/tokens/IERC20Permit.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";

/// @title ERC20PermitTest
/// @notice Exercises the {ERC20Permit} facet (ERC-2612) through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployERC20Permit} script (base ERC-20 + the additive permit facet, EIP-712 domain + nonce storage
///         seeded by {ERC20PermitInit}). Every `permit`/`nonces`/`DOMAIN_SEPARATOR` call routes through the
///         diamond's `delegatecall` dispatch, not a flattened inheritance mock; `mint` comes from the test-only
///         {TokenTestFacet} (`helper`) and `supportsInterface` from the cut-in `ERC165Facet`.
contract ERC20PermitTest is ERC20PermitTestBase {
    IERC20Permit internal permitToken;

    uint256 ownerKey = 0xA11CE;
    address owner;
    address spender = address(0x2);
    address alice = address(0x3);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    event Approval(address indexed owner_, address indexed spender_, uint256 value);

    function setUp() public override {
        owner = vm.addr(ownerKey);
        diamond = _deployERC20Permit("Permit Token", "PRMT");
        token = ERC20(diamond);
        permitToken = IERC20Permit(diamond);
        helper = TokenTestFacet(diamond);

        helper.mint(owner, INITIAL_SUPPLY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          HELPER: build permit digest
    //////////////////////////////////////////////////////////////////////////*//

    function _permitHash(address owner_, address spender_, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH(), owner_, spender_, value, nonce, deadline));
        return keccak256(abi.encodePacked("\x19\x01", permitToken.DOMAIN_SEPARATOR(), structHash));
    }

    function PERMIT_TYPEHASH() internal pure returns (bytes32) {
        return keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    }

    function _sign(bytes32 digest, uint256 key) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        (v, r, s) = vm.sign(key, digest);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          VALID PERMIT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ValidPermitGrantsAllowance() public {
        uint256 value = 500e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = permitToken.nonces(owner);

        bytes32 digest = _permitHash(owner, spender, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, ownerKey);

        permitToken.permit(owner, spender, value, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), value);
    }

    function test_ValidPermitEmitsApprovalEvent() public {
        uint256 value = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = permitToken.nonces(owner);

        bytes32 digest = _permitHash(owner, spender, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, ownerKey);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(owner, spender, value);
        permitToken.permit(owner, spender, value, deadline, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          EXPIRED SIGNATURE
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExpiredSignatureReverts() public {
        uint256 value = 100e18;
        uint256 deadline = block.timestamp - 1; // already expired
        uint256 nonce = permitToken.nonces(owner);

        bytes32 digest = _permitHash(owner, spender, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, ownerKey);

        vm.expectRevert(abi.encodeWithSelector(IERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        permitToken.permit(owner, spender, value, deadline, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          WRONG SIGNER
    //////////////////////////////////////////////////////////////////////////*//

    function test_WrongSignerReverts() public {
        uint256 wrongKey = 0xBAD;
        address wrongSigner = vm.addr(wrongKey);

        uint256 value = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = permitToken.nonces(owner);

        bytes32 digest = _permitHash(owner, spender, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, wrongKey);

        vm.expectRevert(abi.encodeWithSelector(IERC20Permit.ERC2612InvalidSigner.selector, wrongSigner, owner));
        permitToken.permit(owner, spender, value, deadline, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          NONCE CONSUMPTION
    //////////////////////////////////////////////////////////////////////////*//

    function test_NonceIsConsumedAfterPermit() public {
        uint256 nonceBefore = permitToken.nonces(owner);
        uint256 value = 100e18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _permitHash(owner, spender, value, nonceBefore, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, ownerKey);

        permitToken.permit(owner, spender, value, deadline, v, r, s);

        assertEq(permitToken.nonces(owner), nonceBefore + 1);
    }

    function test_ReplayWithSameSignatureReverts() public {
        uint256 value = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = permitToken.nonces(owner);

        bytes32 digest = _permitHash(owner, spender, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, ownerKey);

        // First use succeeds (increments nonce to 1)
        permitToken.permit(owner, spender, value, deadline, v, r, s);

        // For the replay the permit function will compute a new digest with nonce=1,
        // so ecrecover returns a different (stale) signer. Compute that digest to derive
        // the recovered address deterministically.
        bytes32 staleDigest = _permitHash(owner, spender, value, nonce + 1, deadline);
        address staleSigner = ecrecover(staleDigest, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(IERC20Permit.ERC2612InvalidSigner.selector, staleSigner, owner));
        permitToken.permit(owner, spender, value, deadline, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          DOMAIN SEPARATOR
    //////////////////////////////////////////////////////////////////////////*//

    function test_DomainSeparatorIsNonZero() public view {
        assertNotEq(permitToken.DOMAIN_SEPARATOR(), bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIERC20Permit() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20Permit).interfaceId));
    }

    function test_SupportsIERC20() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20).interfaceId));
    }
}
