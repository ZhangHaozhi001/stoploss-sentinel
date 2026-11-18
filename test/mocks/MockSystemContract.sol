// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";

/// @title MockSystemContract
/// @notice Test double for the Reactive system contract. Its code is etched
///         onto the real system-contract address (0x8888...8888) with
///         `vm.etch`, so contracts under test talk to it exactly as they
///         would talk to the network. It records subscriptions and callback
///         requests instead of delivering anything, and exposes a settable
///         per-contract debt for `coverDebt` tests.
contract MockSystemContract {
    uint256 public subscribeCount;
    uint256 public unsubscribeCount;
    uint256 public callbackCount;

    // Last subscription arguments (all subscriptions in this project use the
    // same criteria, so last-write-wins is enough).
    uint256 public lastSubChainId;
    address public lastSubContract;
    uint256 public lastSubTopic0;
    address public lastSubscriber;

    // Last callback request, verbatim.
    uint256 public lastCallbackChainId;
    address public lastCallbackRecipient;
    uint64 public lastCallbackGasLimit;
    bytes public lastCallbackPayload;

    mapping(address => uint256) public debts;

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 /* topic1_ */,
        uint256 /* topic2_ */,
        uint256 /* topic3_ */
    ) external {
        subscribeCount += 1;
        lastSubChainId = chainId_;
        lastSubContract = contract_;
        lastSubTopic0 = topic0_;
        lastSubscriber = msg.sender;
    }

    function unsubscribe(
        uint256 /* chainId_ */,
        address /* contract_ */,
        uint256 /* topic0_ */,
        uint256 /* topic1_ */,
        uint256 /* topic2_ */,
        uint256 /* topic3_ */
    ) external {
        unsubscribeCount += 1;
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        callbackCount += 1;
        lastCallbackChainId = config_.chainId;
        lastCallbackRecipient = config_.recipient;
        lastCallbackGasLimit = config_.gasLimit;
        lastCallbackPayload = config_.payload;
    }

    function requestCallback(ISystemContract.CallbackVersion /* version_ */, bytes memory /* config_ */)
        external
    {
        // The V_1_0 convenience wrapper is what this project uses; the generic
        // entry point is unused and intentionally a no-op here.
    }

    function debt(address contract_) external view returns (uint256) {
        return debts[contract_];
    }

    function setDebt(address contract_, uint256 amount_) external {
        debts[contract_] = amount_;
    }

    receive() external payable {}
}
