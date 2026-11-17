// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @title GuardedVault
/// @notice Destination-chain vault (Base Sepolia). Holds a test ERC-20 for
///         its owner. When the SentinelReactive contract on Lasna reports a
///         price breach, Reactive delivers a callback here; the vault then
///         sweeps its full balance to the owner's pre-set safe address and
///         freezes itself. The callback entry point is authenticated twice:
///         AbstractPayer checks the caller is the chain's callback proxy,
///         and `onlyCallbackSender` checks the injected sender is the
///         sentinel contract.
contract GuardedVault is AbstractCallback {
    address public owner;
    IERC20 public immutable token;
    address public safeAddress;

    bool public frozen;
    uint256 public rescueCount;
    int256 public lastTriggerPrice;

    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event Rescued(int256 triggerPrice, uint256 amount, address indexed safeAddress);
    event Reset();
    event SafeAddressUpdated(address indexed safeAddress);

    error NotOwner();
    error Frozen();
    error NotFrozen();
    error TokenTransferFailed();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param callbackProxy_ Base Sepolia callback proxy
    ///        (0x476F44b11F5C942c58f4c8E3d0300E5710743585).
    /// @param sentinel_ Address of SentinelReactive on Lasna — the only
    ///        reactive contract allowed to trigger a rescue.
    /// @param token_ The ERC-20 this vault guards (test token on Base Sepolia).
    /// @param safeAddress_ Where funds are swept on a rescue.
    constructor(
        address callbackProxy_,
        address sentinel_,
        address token_,
        address safeAddress_
    ) AbstractCallback(IPayable(payable(callbackProxy_)), sentinel_) {
        owner = msg.sender;
        token = IERC20(token_);
        safeAddress = safeAddress_;
    }

    /// @notice Pull tokens into the vault (approve first).
    function deposit(uint256 amount_) external onlyOwner {
        if (frozen) revert Frozen();
        if (!token.transferFrom(msg.sender, address(this), amount_)) revert TokenTransferFailed();
        emit Deposited(msg.sender, amount_);
    }

    function withdraw(uint256 amount_) external onlyOwner {
        if (frozen) revert Frozen();
        if (!token.transfer(msg.sender, amount_)) revert TokenTransferFailed();
        emit Withdrawn(msg.sender, amount_);
    }

    /// @notice Callback entry point. `sentinel_` is injected by the network
    ///         (it replaces the address(0) placeholder in the payload) and is
    ///         checked against the expected reactive contract by
    ///         `onlyCallbackSender`; AbstractPayer additionally requires the
    ///         caller to be the callback proxy.
    function executeRescue(address sentinel_, int256 triggerPrice_)
        external
        onlyCallbackSender(sentinel_)
    {
        frozen = true;
        rescueCount += 1;
        lastTriggerPrice = triggerPrice_;

        uint256 balance = token.balanceOf(address(this));
        if (balance > 0) {
            if (!token.transfer(safeAddress, balance)) revert TokenTransferFailed();
        }
        emit Rescued(triggerPrice_, balance, safeAddress);
    }

    /// @notice After a rescue, the owner can unfreeze and reuse the vault.
    function reset() external onlyOwner {
        if (!frozen) revert NotFrozen();
        frozen = false;
        emit Reset();
    }

    function setSafeAddress(address safeAddress_) external onlyOwner {
        safeAddress = safeAddress_;
        emit SafeAddressUpdated(safeAddress_);
    }

    function balance() external view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
