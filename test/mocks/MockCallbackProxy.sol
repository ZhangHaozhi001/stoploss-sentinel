// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title MockCallbackProxy
/// @notice Stands in for a destination chain's callback proxy in vault tests.
///         The vault only needs two things from its service provider: the
///         caller's address (checked by `onlyServiceProvider`) and `debt()`
///         for `coverDebt`. This double provides both, with a settable debt.
contract MockCallbackProxy {
    mapping(address => uint256) public debts;

    function debt(address contract_) external view returns (uint256) {
        return debts[contract_];
    }

    function setDebt(address contract_, uint256 amount_) external {
        debts[contract_] = amount_;
    }

    receive() external payable {}
}
