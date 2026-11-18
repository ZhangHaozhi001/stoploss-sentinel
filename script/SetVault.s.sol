// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { SentinelReactive } from "../src/SentinelReactive.sol";

/// @notice M2 step 4 (Reactive Lasna): point the sentinel at the vault.
/// Env: PRIVATE_KEY, SENTINEL, VAULT.
contract SetVault is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        SentinelReactive sentinel = SentinelReactive(payable(vm.envAddress("SENTINEL")));
        address vault = vm.envAddress("VAULT");

        vm.startBroadcast(pk);
        sentinel.setVault(vault);
        vm.stopBroadcast();

        console.log("sentinel.vault set to:", sentinel.vault());
    }
}
