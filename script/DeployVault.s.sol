// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { GuardedVault } from "../src/GuardedVault.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";

/// @notice M2 step 3 (Base Sepolia): deploy the test ERC-20 and the
/// GuardedVault destination contract, seed the vault with tokens, and fund
/// it with native ETH (callbacks are billed to the recipient contract; the
/// callback proxy draws from this balance via AbstractPayer.pay).
/// Env: PRIVATE_KEY, SENTINEL (SentinelReactive address on Lasna),
///      MINT_AMOUNT (uint wei, default 1000 ether),
///      DEPOSIT_AMOUNT (uint wei, default 100 ether),
///      VAULT_FUND_ETH (uint wei, default 0.05 ether).
contract DeployVault is Script {
    /// @notice Base Sepolia callback proxy (official, see NOTES.md).
    address internal constant CALLBACK_PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    function run() external returns (GuardedVault vault, MockERC20 token) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address sentinel = vm.envAddress("SENTINEL");
        uint256 mintAmount = vm.envOr("MINT_AMOUNT", uint256(1000 ether));
        uint256 depositAmount = vm.envOr("DEPOSIT_AMOUNT", uint256(100 ether));
        uint256 vaultFund = vm.envOr("VAULT_FUND_ETH", uint256(0.05 ether));

        vm.startBroadcast(pk);
        token = new MockERC20();
        // The deployer is both owner and safe address for the testnet demo:
        // a rescue sweeps the tokens back to the wallet that controls them.
        vault = new GuardedVault(CALLBACK_PROXY, sentinel, address(token), deployer);

        token.mint(deployer, mintAmount);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);

        // Fund the vault so the callback proxy can collect callback fees.
        (bool ok,) = address(vault).call{ value: vaultFund }("");
        require(ok, "vault ETH funding failed");
        vm.stopBroadcast();

        console.log("MockERC20 deployed:", address(token));
        console.log("GuardedVault deployed:", address(vault));
        console.log("vault token balance:", vault.balance());
        console.log("vault ETH balance (wei):", address(vault).balance);
    }
}
