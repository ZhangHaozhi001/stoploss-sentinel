// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { PriceBeacon } from "../src/PriceBeacon.sol";
import { SentinelReactive } from "../src/SentinelReactive.sol";
import { GuardedVault } from "../src/GuardedVault.sol";
import { MockSystemContract } from "./mocks/MockSystemContract.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockCallbackProxy } from "./mocks/MockCallbackProxy.sol";

/// @notice Local end-to-end rehearsal of the three-leg loop that M2 will run
///         on testnet: beacon post (origin) -> sentinel `react` (reactive)
///         -> vault callback (destination). The middle leg is played by the
///         etched mock system contract; the last leg is delivered exactly as
///         the network delivers it — the recorded payload with its first
///         argument's placeholder overwritten by the sentinel's address,
///         called by the callback proxy.
contract FullLoopTest is Test {
    address payable internal constant SYSTEM_ADDR = payable(0x8888888888888888888888888888888888888888);
    uint256 internal constant PRICE_TOPIC = uint256(keccak256("PriceUpdated(int256,uint256)"));
    uint256 internal constant ORIGIN = 84532;
    int256 internal constant FLOOR = 90;
    int256 internal constant CEILING = 110;

    MockSystemContract internal system;
    MockERC20 internal token;
    MockCallbackProxy internal proxy;
    PriceBeacon internal beacon;
    SentinelReactive internal sentinel;
    GuardedVault internal vault;
    address internal safe = makeAddr("safe");

    function setUp() public {
        MockSystemContract impl = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(impl).code);
        system = MockSystemContract(SYSTEM_ADDR);

        beacon = new PriceBeacon(100);
        sentinel = new SentinelReactive(ORIGIN, address(beacon), ORIGIN, FLOOR, CEILING, 3600);
        token = new MockERC20();
        proxy = new MockCallbackProxy();
        vault = new GuardedVault(address(proxy), address(sentinel), address(token), safe);
        sentinel.setVault(address(vault));

        token.mint(address(this), 500);
        token.approve(address(vault), 500);
        vault.deposit(500);
    }

    function _deliverLog(int256 price, uint256 postedAt) internal {
        IReactive.LogRecord memory log_ = IReactive.LogRecord({
            chainId: ORIGIN,
            contractAddress: address(beacon),
            topic0: PRICE_TOPIC,
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
        vm.prank(SYSTEM_ADDR);
        sentinel.react(log_);
    }

    /// @notice Plays the network's part: take the payload the sentinel asked
    ///         to have delivered, inject the sentinel's address in place of
    ///         the address(0) placeholder, and deliver it from the proxy.
    function _deliverCallback() internal {
        bytes memory payload = system.lastCallbackPayload();
        bytes20 sender = bytes20(address(sentinel));
        for (uint256 i = 0; i < 20; i++) {
            payload[16 + i] = sender[i]; // first word: bytes 4..36, address in 16..36
        }
        vm.prank(address(proxy));
        (bool ok, bytes memory err) = address(vault).call(payload);
        if (!ok) {
            assembly {
                revert(add(err, 32), mload(err))
            }
        }
    }

    function test_FullLoopRescue() public {
        // Leg 1+2, no breach: a normal price post changes nothing.
        beacon.postPrice(100);
        _deliverLog(100, 10_000);
        assertEq(system.callbackCount(), 0);
        assertEq(vault.balance(), 500);
        assertFalse(vault.frozen());

        // Leg 1+2, breach: the sentinel requests exactly one callback,
        // addressed to the vault on the origin/destination chain.
        beacon.postPrice(80);
        _deliverLog(80, 10_100);
        assertEq(system.callbackCount(), 1);
        assertEq(system.lastCallbackChainId(), ORIGIN);
        assertEq(system.lastCallbackRecipient(), address(vault));

        // Leg 3: the delivered callback sweeps the vault to the safe address.
        _deliverCallback();
        assertTrue(vault.frozen());
        assertEq(vault.rescueCount(), 1);
        assertEq(vault.lastTriggerPrice(), 80);
        assertEq(vault.balance(), 0);
        assertEq(token.balanceOf(safe), 500);
    }

    function test_FullLoopTakeProfit() public {
        beacon.postPrice(150);
        _deliverLog(150, 10_000);
        assertEq(system.callbackCount(), 1);

        _deliverCallback();
        assertTrue(vault.frozen());
        assertEq(vault.lastTriggerPrice(), 150);
        assertEq(token.balanceOf(safe), 500);
    }
}
