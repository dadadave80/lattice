// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {PermitTokenInit} from "@lattice-test/composability/ComposedTokenInit.sol";
import {TokenBlueprintHelper} from "@lattice-test/helpers/TokenBlueprintHelper.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Permit} from "@lattice/interfaces/tokens/IERC20Permit.sol";

/// @dev ERC-5267 surface served by the standalone EIP712 facet (the component ERC20Permit needs).
interface IEip712 {
    function eip712Domain()
        external
        view
        returns (bytes1, string memory name, string memory version, uint256, address, bytes32, uint256[] memory);
}

/// @title ERC20PermitComposition
/// @notice Proves the "facet needs another facet → cut it as a component, don't inherit it" pattern. A real diamond
///         is assembled from base ERC20 + {ERC20Permit} (ERC-2612) + the standalone {EIP712} facet (ERC-5267). The
///         cut itself is the guard: it succeeds ONLY because ERC20Permit no longer re-exports `eip712Domain()` — if
///         ERC20Permit were `is EIP712` again, cut[3] (EIP712) would revert `CannotAddFunctionToDiamondThatAlreadyExists`.
///         Then permit/nonces (from ERC20Permit) and eip712Domain (from the EIP712 facet) all work over one storage.
contract ERC20PermitComposition is TokenBlueprintHelper {
    address token; // the assembled permit-token diamond
    uint256 ownerKey = 0xA11CE;
    address owner;
    address spender = address(0x2);

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        owner = vm.addr(ownerKey);
        (FacetCut[] memory cuts, PermitTokenInit init) = _permitTokenBlueprint();
        Diamond diamond = new Diamond();
        // Cut succeeds only because ERC20Permit + EIP712 own disjoint selectors (no shared eip712Domain).
        diamond.initialize(cuts, address(init), abi.encodeCall(PermitTokenInit.init, ()));
        token = address(diamond);
    }

    function test_PermitDispatchesAndGrantsAllowance() public {
        uint256 value = 500e18;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = IERC20Permit(token).nonces(owner);

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", IERC20Permit(token).DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        IERC20Permit(token).permit(owner, spender, value, deadline, v, r, s);

        assertEq(IERC20(token).allowance(owner, spender), value, "permit granted allowance via real dispatch");
        assertEq(IERC20Permit(token).nonces(owner), nonce + 1, "nonce consumed (ERC20Permit owns nonces)");
    }

    function test_Eip712DomainServedByTheComponentFacet() public view {
        // eip712Domain() resolves to the SEPARATE EIP712 facet, reading the same domain ERC20Permit's digest used.
        (, string memory name, string memory version,,,,) = IEip712(token).eip712Domain();
        assertEq(name, "Permit", "eip712Domain name from the EIP712 component facet");
        assertEq(version, "1", "eip712Domain version from the EIP712 component facet");
        assertTrue(IERC20Permit(token).DOMAIN_SEPARATOR() != bytes32(0), "domain separator wired");
    }
}
