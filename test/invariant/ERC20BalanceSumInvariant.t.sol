// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                 MOCK TOKEN
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal mintable/burnable ERC-20 for invariant testing.
contract InvMockERC20 is ERC20, Initializable {
    function initialize(string memory name_, string memory symbol_) external initializer {
        ERC20Lib.__ERC20_init(name_, symbol_);
    }

    function mint(address to, uint256 amount) external {
        ERC20Lib._mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        ERC20Lib._burn(from, amount);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Handler that exercises mint, burn, and transfer on a fixed set of 5 actors.
contract ERC20BalanceSumHandler is Test {
    InvMockERC20 public token;

    address[5] public actors;
    address[] internal _touchedActors;
    mapping(address => bool) public hasTouched;

    uint256 constant CAP = 1_000_000e18;

    constructor(InvMockERC20 token_) {
        token = token_;
        actors[0] = address(0xA1);
        actors[1] = address(0xA2);
        actors[2] = address(0xA3);
        actors[3] = address(0xA4);
        actors[4] = address(0xA5);
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function touchedActors() external view returns (address[] memory) {
        return _touchedActors;
    }

    function _touch(address a) internal {
        if (!hasTouched[a]) {
            hasTouched[a] = true;
            _touchedActors.push(a);
        }
    }

    function mint(uint256 actorSeed, uint256 amount) external {
        address to = _actor(actorSeed);
        amount = bound(amount, 1, CAP);
        _touch(to);
        token.mint(to, amount);
    }

    function burn(uint256 actorSeed, uint256 amount) external {
        address from = _actor(actorSeed);
        uint256 bal = token.balanceOf(from);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        token.burn(from, amount);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor((toSeed + 1) % actors.length); // ensure different index possibility
        if (from == to) to = actors[(toSeed + 2) % actors.length];
        uint256 bal = token.balanceOf(from);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        _touch(to);
        vm.prank(from);
        token.transfer(to, amount);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title ERC20BalanceSumInvariant
/// @notice Invariant: sum of all actor balances == totalSupply at all times.
contract ERC20BalanceSumInvariant is Test {
    InvMockERC20 internal token;
    ERC20BalanceSumHandler internal handler;

    function setUp() public {
        token = new InvMockERC20();
        token.initialize("Inv Token", "INV");

        handler = new ERC20BalanceSumHandler(token);
        targetContract(address(handler));
    }

    /// @notice The sum of all actor balances must always equal totalSupply.
    function invariant_BalanceSumEqualsSupply() public view {
        address[] memory touched = handler.touchedActors();
        uint256 sum;
        for (uint256 i; i < touched.length; ++i) {
            sum += token.balanceOf(touched[i]);
        }
        assertEq(sum, token.totalSupply(), "balance sum != totalSupply");
    }
}
