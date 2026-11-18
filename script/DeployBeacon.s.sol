// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { PriceBeacon } from "../src/PriceBeacon.sol";

/// @notice M2 step 1 (Base Sepolia): deploy the PriceBeacon origin contract.
/// Env: PRIVATE_KEY (deployer), INITIAL_PRICE (int, default 2000).
contract DeployBeacon is Script {
    function run() external returns (PriceBeacon beacon) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        int256 initialPrice = vm.envOr("INITIAL_PRICE", int256(2000));

        vm.startBroadcast(pk);
        beacon = new PriceBeacon(initialPrice);
        vm.stopBroadcast();

        console.log("PriceBeacon deployed:", address(beacon));
        console.log("chainId:", block.chainid);
    }
}
