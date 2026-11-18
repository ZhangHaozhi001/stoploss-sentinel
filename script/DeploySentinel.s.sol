// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { SentinelReactive } from "../src/SentinelReactive.sol";

/// @notice M2 step 2 (Reactive Lasna): deploy the SentinelReactive RSC.
/// The constructor subscribes to the beacon's PriceUpdated events on Base
/// Sepolia, and the contract is funded with lREACT at deployment (it pays
/// for its own reactive transactions).
/// Env: PRIVATE_KEY, BEACON (address on Base Sepolia),
///      FLOOR (int, default 1500), CEILING (int, default int256 max = disabled),
///      COOLDOWN_SECONDS (uint, default 300),
///      SENTINEL_FUND_LREACT (uint wei, default 5 ether).
contract DeploySentinel is Script {
    uint256 internal constant BASE_SEPOLIA = 84532;

    function run() external returns (SentinelReactive sentinel) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address beacon = vm.envAddress("BEACON");
        int256 floor_ = vm.envOr("FLOOR", int256(1500));
        int256 ceiling = vm.envOr("CEILING", type(int256).max);
        uint256 cooldown = vm.envOr("COOLDOWN_SECONDS", uint256(300));
        uint256 fund = vm.envOr("SENTINEL_FUND_LREACT", uint256(5 ether));

        vm.startBroadcast(pk);
        sentinel = new SentinelReactive{ value: fund }(
            BASE_SEPOLIA, beacon, BASE_SEPOLIA, floor_, ceiling, cooldown
        );
        vm.stopBroadcast();

        console.log("SentinelReactive deployed:", address(sentinel));
        console.log("chainId:", block.chainid);
        console.log("funded with lREACT (wei):", fund);
    }
}
