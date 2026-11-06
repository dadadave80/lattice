// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title MockStargateBusToken
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice ERC20 oddities fixture: modes 1=no return, 2=false pull, 3=taxed pull, 4=false approval, 5=false transfer.
contract MockStargateBusToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint8 public mode;

    function setMode(uint8 value) external {
        mode = value;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (mode == 4) return false;
        allowance[msg.sender][spender] = amount;
        if (mode == 1) {
            assembly ("memory-safe") { return(0, 0) }
        }
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (mode == 5) return false;
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        if (mode == 1) {
            assembly ("memory-safe") { return(0, 0) }
        }
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (mode == 2) return false;
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += mode == 3 ? amount - 1 : amount;
        if (mode == 1) {
            assembly ("memory-safe") { return(0, 0) }
        }
        return true;
    }
}
