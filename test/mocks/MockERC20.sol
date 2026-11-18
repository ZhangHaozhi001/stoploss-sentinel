// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title MockERC20
/// @notice Minimal ERC-20 for vault tests: mintable, with a switch to force
///         `transfer`/`transferFrom` to return false so failure paths in the
///         vault can be exercised.
contract MockERC20 {
    string public constant name = "Mock Token";
    string public constant symbol = "MOCK";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    bool public failTransfers;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function mint(address to_, uint256 amount_) external {
        totalSupply += amount_;
        balanceOf[to_] += amount_;
        emit Transfer(address(0), to_, amount_);
    }

    function setFailTransfers(bool fail_) external {
        failTransfers = fail_;
    }

    function approve(address spender_, uint256 amount_) external returns (bool) {
        allowance[msg.sender][spender_] = amount_;
        emit Approval(msg.sender, spender_, amount_);
        return true;
    }

    function transfer(address to_, uint256 amount_) external returns (bool) {
        if (failTransfers) return false;
        if (balanceOf[msg.sender] < amount_) return false;
        balanceOf[msg.sender] -= amount_;
        balanceOf[to_] += amount_;
        emit Transfer(msg.sender, to_, amount_);
        return true;
    }

    function transferFrom(address from_, address to_, uint256 amount_) external returns (bool) {
        if (failTransfers) return false;
        if (balanceOf[from_] < amount_) return false;
        if (allowance[from_][msg.sender] < amount_) return false;
        allowance[from_][msg.sender] -= amount_;
        balanceOf[from_] -= amount_;
        balanceOf[to_] += amount_;
        emit Transfer(from_, to_, amount_);
        return true;
    }
}
