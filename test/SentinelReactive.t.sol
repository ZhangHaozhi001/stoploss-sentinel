// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { PriceBeacon } from "../src/PriceBeacon.sol";
import { SentinelReactive } from "../src/SentinelReactive.sol";
import { MockSystemContract } from "./mocks/MockSystemContract.sol";

/// @notice Unit tests for the sentinel. The mock system contract is etched
///         onto the real system address, so the sentinel's constructor
///         subscription, its `react` authentication and its callback requests
///         all run against the double exactly as they would on Lasna.
contract SentinelReactiveTest is Test {
    event Triggered(int256 price, uint256 at, uint256 triggerCount);
    event RuleUpdated(int256 floor, int256 ceiling, uint256 cooldownSeconds);
    event VaultUpdated(address indexed vault);
    event Paused();
    event Unpaused();

    address payable internal constant SYSTEM_ADDR = payable(0x8888888888888888888888888888888888888888);
    uint256 internal constant PRICE_TOPIC = uint256(keccak256("PriceUpdated(int256,uint256)"));

    uint256 internal constant ORIGIN = 84532;
    int256 internal constant FLOOR = 90;
    int256 internal constant CEILING = 110;
    uint256 internal constant COOLDOWN = 3600;

    MockSystemContract internal system;
    PriceBeacon internal beacon;
    SentinelReactive internal sentinel;
    address internal vaultAddr = makeAddr("vault");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        MockSystemContract impl = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(impl).code);
        system = MockSystemContract(SYSTEM_ADDR);

        beacon = new PriceBeacon(100);
        sentinel = new SentinelReactive(ORIGIN, address(beacon), ORIGIN, FLOOR, CEILING, COOLDOWN);
        sentinel.setVault(vaultAddr);
    }

    // ---- helpers -----------------------------------------------------------

    function _log(int256 price, uint256 postedAt) internal view returns (IReactive.LogRecord memory) {
        return _logWithTopic(PRICE_TOPIC, price, postedAt);
    }

    function _logWithTopic(uint256 topic0, int256 price, uint256 postedAt)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return IReactive.LogRecord({
            chainId: ORIGIN,
            contractAddress: address(beacon),
            topic0: topic0,
            topic1: 0,
            topic2: 0,
            topic3: 0,
            data: abi.encode(price, postedAt),
            blockNumber: 0,
            opCode: 0,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    function _react(int256 price, uint256 postedAt) internal {
        vm.prank(SYSTEM_ADDR);
        sentinel.react(_log(price, postedAt));
    }

    function _decodePayload(bytes memory payload) internal pure returns (bytes4 selector, address placeholder, int256 price) {
        require(payload.length == 68, "payload must be selector + 2 words");
        selector = bytes4(
            (uint32(uint8(payload[0])) << 24) | (uint32(uint8(payload[1])) << 16)
                | (uint32(uint8(payload[2])) << 8) | uint32(uint8(payload[3]))
        );
        bytes memory args = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            args[i] = payload[i + 4];
        }
        (placeholder, price) = abi.decode(args, (address, int256));
    }

    // ---- construction / subscription --------------------------------------

    function test_ConstructorSubscribesToBeacon() public view {
        assertEq(system.subscribeCount(), 1);
        assertEq(system.lastSubChainId(), ORIGIN);
        assertEq(system.lastSubContract(), address(beacon));
        assertEq(system.lastSubTopic0(), PRICE_TOPIC);
        assertEq(system.lastSubscriber(), address(sentinel));
    }

    function test_ConstructorState() public view {
        assertEq(sentinel.owner(), address(this));
        assertEq(sentinel.originChainId(), ORIGIN);
        assertEq(sentinel.beacon(), address(beacon));
        assertEq(sentinel.destinationChainId(), ORIGIN);
        assertEq(sentinel.vault(), vaultAddr);
        assertEq(sentinel.floor(), FLOOR);
        assertEq(sentinel.ceiling(), CEILING);
        assertEq(sentinel.cooldownSeconds(), COOLDOWN);
        assertFalse(sentinel.paused());
    }

    // ---- react: filtering ---------------------------------------------------

    function test_ReactIgnoresForeignTopic() public {
        vm.prank(SYSTEM_ADDR);
        sentinel.react(_logWithTopic(uint256(keccak256("SomethingElse()")), 1, 10_000));
        assertEq(system.callbackCount(), 0);
        assertEq(sentinel.lastPrice(), 0);
        assertEq(sentinel.triggerCount(), 0);
    }

    function test_ReactOnlySystem() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, stranger, SYSTEM_ADDR)
        );
        sentinel.react(_log(1, 10_000));
    }

    function test_ReactNoBreachNoCallback() public {
        _react(100, 10_000);
        assertEq(system.callbackCount(), 0);
        assertEq(sentinel.lastPrice(), 100);
        assertEq(sentinel.triggerCount(), 0);
    }

    function test_ReactBoundaryPricesDoNotTrigger() public {
        // Bounds are strict: exactly at the floor/ceiling is not a breach.
        _react(FLOOR, 10_000);
        _react(CEILING, 10_100);
        assertEq(system.callbackCount(), 0);
        assertEq(sentinel.triggerCount(), 0);
    }

    // ---- react: triggering --------------------------------------------------

    function test_ReactFloorBreachRequestsCallback() public {
        vm.expectEmit(false, false, false, true, address(sentinel));
        emit Triggered(89, 10_000, 1);
        _react(89, 10_000);

        assertEq(system.callbackCount(), 1);
        assertEq(system.lastCallbackChainId(), ORIGIN);
        assertEq(system.lastCallbackRecipient(), vaultAddr);
        assertEq(system.lastCallbackGasLimit(), 1_000_000);

        // Payload layout: selector, address(0) placeholder, trigger price.
        (bytes4 selector, address placeholder, int256 price) = _decodePayload(system.lastCallbackPayload());
        assertEq(selector, bytes4(keccak256("executeRescue(address,int256)")));
        assertEq(placeholder, address(0));
        assertEq(price, 89);

        assertEq(sentinel.triggerCount(), 1);
        assertEq(sentinel.lastTriggerAt(), 10_000);
        assertEq(sentinel.lastPrice(), 89);
    }

    function test_ReactCeilingBreachRequestsCallback() public {
        _react(111, 10_000);
        assertEq(system.callbackCount(), 1);
        (, , int256 price) = _decodePayload(system.lastCallbackPayload());
        assertEq(price, 111);
        assertEq(sentinel.triggerCount(), 1);
    }

    function test_ReactCooldownSuppressesSecondBreach() public {
        _react(89, 10_000);
        assertEq(system.callbackCount(), 1);

        // One second before the cooldown expires: suppressed.
        _react(80, 10_000 + COOLDOWN - 1);
        assertEq(system.callbackCount(), 1);
        assertEq(sentinel.triggerCount(), 1);

        // Exactly at expiry: triggers again (comparison is strict `<`).
        _react(80, 10_000 + COOLDOWN);
        assertEq(system.callbackCount(), 2);
        assertEq(sentinel.triggerCount(), 2);
        assertEq(sentinel.lastTriggerAt(), 10_000 + COOLDOWN);
    }

    function test_ReactRevertsWhenVaultNotSet() public {
        SentinelReactive unset = new SentinelReactive(ORIGIN, address(beacon), ORIGIN, FLOOR, CEILING, COOLDOWN);
        vm.prank(SYSTEM_ADDR);
        vm.expectRevert(SentinelReactive.VaultNotSet.selector);
        unset.react(_log(1, 10_000));
    }

    function test_ReactDisabledBoundsNeverTrigger() public {
        sentinel.setRule(type(int256).min, type(int256).max, 0);
        _react(0, 10_000);
        _react(int256(2 ** 200), 10_100);
        assertEq(system.callbackCount(), 0);
    }

    // ---- owner setters --------------------------------------------------------

    function test_SetRuleOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(SentinelReactive.NotOwner.selector);
        sentinel.setRule(1, 2, 3);
    }

    function test_SetRuleUpdatesAndEmits() public {
        vm.expectEmit(false, false, false, true, address(sentinel));
        emit RuleUpdated(50, 150, 60);
        sentinel.setRule(50, 150, 60);
        assertEq(sentinel.floor(), 50);
        assertEq(sentinel.ceiling(), 150);
        assertEq(sentinel.cooldownSeconds(), 60);
    }

    function test_SetVaultOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(SentinelReactive.NotOwner.selector);
        sentinel.setVault(stranger);
    }

    function test_SetVaultUpdatesAndEmits() public {
        address newVault = makeAddr("newVault");
        vm.expectEmit(true, false, false, false, address(sentinel));
        emit VaultUpdated(newVault);
        sentinel.setVault(newVault);
        assertEq(sentinel.vault(), newVault);
    }

    // ---- pause / unpause ------------------------------------------------------

    function test_PauseUnsubscribesAndBlocksReact() public {
        vm.expectEmit(false, false, false, true, address(sentinel));
        emit Paused();
        sentinel.pause();

        assertTrue(sentinel.paused());
        assertEq(system.unsubscribeCount(), 1);

        // Even if a log is delivered anyway, a paused sentinel stays silent.
        _react(1, 10_000);
        assertEq(system.callbackCount(), 0);
        assertEq(sentinel.triggerCount(), 0);
    }

    function test_PauseTwiceReverts() public {
        sentinel.pause();
        vm.expectRevert(SentinelReactive.AlreadyPaused.selector);
        sentinel.pause();
    }

    function test_UnpauseResubscribesAndResumes() public {
        sentinel.pause();
        vm.expectEmit(false, false, false, true, address(sentinel));
        emit Unpaused();
        sentinel.unpause();

        assertFalse(sentinel.paused());
        assertEq(system.subscribeCount(), 2); // constructor + unpause

        _react(1, 10_000);
        assertEq(system.callbackCount(), 1);
    }

    function test_UnpauseWhenNotPausedReverts() public {
        vm.expectRevert(SentinelReactive.NotPaused.selector);
        sentinel.unpause();
    }

    function test_PauseOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(SentinelReactive.NotOwner.selector);
        sentinel.pause();
    }

    // ---- debt -----------------------------------------------------------------

    function test_CoverDebtPaysSystem() public {
        system.setDebt(address(sentinel), 0.5 ether);
        vm.deal(address(sentinel), 1 ether);
        sentinel.coverDebt();
        assertEq(SYSTEM_ADDR.balance, 0.5 ether);
        assertEq(address(sentinel).balance, 0.5 ether);
    }
}
