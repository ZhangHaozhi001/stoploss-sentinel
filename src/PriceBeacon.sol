// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title PriceBeacon
/// @notice Origin-chain price poster (Base Sepolia). Stands in for an oracle
///         feed: the owner posts a price and every post emits `PriceUpdated`,
///         which is the event the reactive contract subscribes to. Using our
///         own beacon keeps the demo loop deterministic — a price breach can
///         be triggered on demand to produce the full origin -> reactive ->
///         callback transaction chain that the judges score on Execution.
contract PriceBeacon {
    address public owner;
    int256 public price;
    uint256 public updatedAt;

    event PriceUpdated(int256 price, uint256 updatedAt);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(int256 initialPrice_) {
        owner = msg.sender;
        price = initialPrice_;
        updatedAt = block.timestamp;
        emit PriceUpdated(initialPrice_, block.timestamp);
    }

    /// @notice Post a new price. Emits `PriceUpdated` on every call, even if
    ///         the value is unchanged, so demos can re-trigger the loop.
    function postPrice(int256 price_) external onlyOwner {
        price = price_;
        updatedAt = block.timestamp;
        emit PriceUpdated(price_, block.timestamp);
    }

    function transferOwnership(address newOwner_) external onlyOwner {
        emit OwnershipTransferred(owner, newOwner_);
        owner = newOwner_;
    }
}
