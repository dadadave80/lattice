// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Permit} from "@lattice/interfaces/tokens/IERC20Permit.sol";
import {ERC20Permit} from "@lattice/tokens/ERC20/ERC20Permit.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20PermitLib} from "@lattice/tokens/ERC20/libraries/ERC20PermitLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockERC20PermitContract
contract MockERC20PermitContract is ERC20Permit {
    function initialize(string memory name_, string memory symbol_, address mintTo, uint256 mintAmount) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        EIP712Lib.__EIP712_init(name_, "1");
        NoncesLib.__Nonces_init();
        ERC20PermitLib.__ERC20Permit_init();
        if (mintTo != address(0) && mintAmount > 0) {
            ERC20Lib._mint(mintTo, mintAmount);
        }
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC20PermitTester
contract ERC20PermitTester is Test {
    MockERC20PermitContract token;

    uint256 ownerKey = 0xA11CE;
    address owner;
    address spender = address(0x2);
    address alice = address(0x3);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    event Approval(address indexed owner_, address indexed spender_, uint256 value);

    function setUp() public {
        owner = vm.addr(ownerKey);
        token = new MockERC20PermitContract();
        token.initialize("Permit Token", "PRMT", owner, INITIAL_SUPPLY);
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
        return keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
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
        uint256 nonce = token.nonces(owner);

        bytes32 digest = _permitHash(owner, spender, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, ownerKey);

        token.permit(owner, spender, value, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), value);
    }

    function test_ValidPermitEmitsApprovalEvent() public {
        uint256 value = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        bytes32 digest = _permitHash(owner, spender, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, ownerKey);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(owner, spender, value);
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          EXPIRED SIGNATURE
    //////////////////////////////////////////////////////////////////////////*//

    function test_ExpiredSignatureReverts() public {
        uint256 value = 100e18;
        uint256 deadline = block.timestamp - 1; // already expired
        uint256 nonce = token.nonces(owner);

        bytes32 digest = _permitHash(owner, spender, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, ownerKey);

        vm.expectRevert(abi.encodeWithSelector(IERC20Permit.ERC2612ExpiredSignature.selector, deadline));
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          WRONG SIGNER
    //////////////////////////////////////////////////////////////////////////*//

    function test_WrongSignerReverts() public {
        uint256 wrongKey = 0xBAD;
        address wrongSigner = vm.addr(wrongKey);

        uint256 value = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        bytes32 digest = _permitHash(owner, spender, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, wrongKey);

        vm.expectRevert(abi.encodeWithSelector(IERC20Permit.ERC2612InvalidSigner.selector, wrongSigner, owner));
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          NONCE CONSUMPTION
    //////////////////////////////////////////////////////////////////////////*//

    function test_NonceIsConsumedAfterPermit() public {
        uint256 nonceBefore = token.nonces(owner);
        uint256 value = 100e18;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 digest = _permitHash(owner, spender, value, nonceBefore, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, ownerKey);

        token.permit(owner, spender, value, deadline, v, r, s);

        assertEq(token.nonces(owner), nonceBefore + 1);
    }

    function test_ReplayWithSameSignatureReverts() public {
        uint256 value = 100e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = token.nonces(owner);

        bytes32 digest = _permitHash(owner, spender, value, nonce, deadline);
        (uint8 v, bytes32 r, bytes32 s) = _sign(digest, ownerKey);

        // First use succeeds (increments nonce to 1)
        token.permit(owner, spender, value, deadline, v, r, s);

        // For the replay the permit function will compute a new digest with nonce=1,
        // so ecrecover returns a different (stale) signer. Compute that digest to derive
        // the recovered address deterministically.
        bytes32 staleDigest = _permitHash(owner, spender, value, nonce + 1, deadline);
        address staleSigner = ecrecover(staleDigest, v, r, s);

        vm.expectRevert(abi.encodeWithSelector(IERC20Permit.ERC2612InvalidSigner.selector, staleSigner, owner));
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          DOMAIN SEPARATOR
    //////////////////////////////////////////////////////////////////////////*//

    function test_DomainSeparatorIsNonZero() public view {
        assertNotEq(token.DOMAIN_SEPARATOR(), bytes32(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIERC20Permit() public view {
        assertTrue(token.supportsInterface(type(IERC20Permit).interfaceId));
    }

    function test_SupportsIERC20() public view {
        assertTrue(token.supportsInterface(type(IERC20).interfaceId));
    }
}
