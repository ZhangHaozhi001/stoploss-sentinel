// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { PriceBeacon } from "../src/PriceBeacon.sol";

/// @notice M2 step 5 (Base Sepolia): post a price to the beacon. Used twice
/// per loop run — once with a normal price (no trigger expected) and once
/// with a breach price (below FLOOR) to fire the reactive loop.
/// Env: PRIVATE_KEY, BEACON, PRICE (int).
contract PostPrice is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        PriceBeacon beacon = PriceBeacon(vm.envAddress("BEACON"));
        int256 price = vm.envInt("PRICE");

        vm.startBroadcast(pk);
        beacon.postPrice(price);
        vm.stopBroadcast();

        console.log("posted price:", price);
        console.log("beacon:", address(beacon));
    }
}
