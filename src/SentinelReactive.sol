// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title SentinelReactive
/// @notice The Reactive Smart Contract (deployed on Reactive Lasna). It
///         subscribes to `PriceUpdated` events from a PriceBeacon on Base
///         Sepolia and enforces a user-set price rule: if a posted price
///         breaks the floor (or the ceiling) and the cooldown has passed, it
///         asks the Reactive system contract to deliver a callback to the
///         GuardedVault on Base Sepolia, which rescues itself.
///
///         Track: "Set It and Forget It" — set the rule once, walk away.
contract SentinelReactive is AbstractReactive {
    /// @notice topic0 of `PriceUpdated(int256,uint256)`.
    uint256 internal constant PRICE_UPDATED_TOPIC_0 =
        uint256(keccak256("PriceUpdated(int256,uint256)"));

    uint64 internal constant CALLBACK_GAS_LIMIT = 1000000;

    address public owner;

    /// @notice Origin chain (Base Sepolia) and beacon being watched.
    uint256 public immutable originChainId;
    address public immutable beacon;

    /// @notice Destination chain and vault. Destination equals origin in this
    ///         design (Base Sepolia), but the callback machinery is generic.
    uint256 public immutable destinationChainId;
    address public vault;

    /// @notice The user's rule. A price strictly below `floor` or strictly
    ///         above `ceiling` triggers a rescue. Either bound can be
    ///         disabled by the owner (floor = type(int256).min disables the
    ///         lower bound; ceiling = type(int256).max disables the upper).
    int256 public floor;
    int256 public ceiling;

    /// @notice Minimum seconds between two triggers. Compared against the
    ///         price post's timestamp (origin-chain time carried in the
    ///         event), never against block numbers — per the buildathon
    ///         ground rules for Base Sepolia's 200 ms blocks.
    uint256 public cooldownSeconds;
    uint256 public lastTriggerAt;

    uint256 public triggerCount;
    int256 public lastPrice;

    event RuleUpdated(int256 floor, int256 ceiling, uint256 cooldownSeconds);
    event VaultUpdated(address indexed vault);
    event Triggered(int256 price, uint256 at, uint256 triggerCount);

    error NotOwner();
    error VaultNotSet();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param originChainId_ Chain the beacon lives on (Base Sepolia: 84532).
    /// @param beacon_ PriceBeacon address on the origin chain.
    /// @param destinationChainId_ Chain the vault lives on (Base Sepolia: 84532).
    /// @param floor_ Lower bound; a price below it triggers a rescue.
    /// @param ceiling_ Upper bound; a price above it triggers a rescue.
    /// @param cooldownSeconds_ Minimum seconds between triggers.
    constructor(
        uint256 originChainId_,
        address beacon_,
        uint256 destinationChainId_,
        int256 floor_,
        int256 ceiling_,
        uint256 cooldownSeconds_
    ) payable {
        owner = msg.sender;
        originChainId = originChainId_;
        beacon = beacon_;
        destinationChainId = destinationChainId_;
        floor = floor_;
        ceiling = ceiling_;
        cooldownSeconds = cooldownSeconds_;

        SYSTEM.subscribe(
            originChainId_,
            beacon_,
            PRICE_UPDATED_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice Set the vault to call back. Deploy order per the Reactive docs:
    ///         reactive contract first, then the vault (which needs this
    ///         contract's address to authenticate callbacks), then this setter.
    function setVault(address vault_) external onlyOwner {
        vault = vault_;
        emit VaultUpdated(vault_);
    }

    function setRule(int256 floor_, int256 ceiling_, uint256 cooldownSeconds_) external onlyOwner {
        floor = floor_;
        ceiling = ceiling_;
        cooldownSeconds = cooldownSeconds_;
        emit RuleUpdated(floor_, ceiling_, cooldownSeconds_);
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        if (log_.topic0 != PRICE_UPDATED_TOPIC_0) {
            // Not ours — fall through quietly. Reverting as a filter would
            // still bill us for the gas (see Reactive docs).
            return;
        }

        (int256 price, uint256 postedAt) = abi.decode(log_.data, (int256, uint256));
        lastPrice = price;

        bool breached = price < floor || price > ceiling;
        if (!breached) return;
        if (postedAt < lastTriggerAt + cooldownSeconds) return;
        if (vault == address(0)) revert VaultNotSet();

        lastTriggerAt = postedAt;
        triggerCount += 1;
        emit Triggered(price, postedAt, triggerCount);

        // The payload's first argument MUST be an address placeholder: the
        // network overwrites its first 160 bits with this contract's address
        // so the vault can authenticate the callback sender.
        bytes memory payload = abi.encodeWithSignature(
            "executeRescue(address,int256)",
            address(0),
            price
        );

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId,
                recipient: vault,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
    }

    /// @notice Settles outstanding debt from this contract's own balance so a
    ///         third party can restart a starved sentinel (docs pattern).
    function coverDebt() external {
        _coverDebt();
    }
}
