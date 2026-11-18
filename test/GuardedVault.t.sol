// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { GuardedVault } from "../src/GuardedVault.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockCallbackProxy } from "./mocks/MockCallbackProxy.sol";

/// @notice Unit tests for the vault. Callbacks are simulated the way the
///         network delivers them: the caller is the chain's callback proxy
///         and the first payload argument is the sentinel's address.
contract GuardedVaultTest is Test {
    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);
    event Rescued(int256 triggerPrice, uint256 amount, address indexed safeAddress);
    event Reset();
    event SafeAddressUpdated(address indexed safeAddress);

    MockERC20 internal token;
    MockCallbackProxy internal proxy;
    GuardedVault internal vault;
    address internal sentinelAddr = makeAddr("sentinel");
    address internal safe = makeAddr("safe");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        token = new MockERC20();
        proxy = new MockCallbackProxy();
        vault = new GuardedVault(address(proxy), sentinelAddr, address(token), safe);
        token.mint(address(this), 1_000);
        token.approve(address(vault), 1_000);
    }

    function _rescue(int256 price) internal {
        vm.prank(address(proxy));
        vault.executeRescue(sentinelAddr, price);
    }

    // ---- deposits / withdrawals ----------------------------------------------

    function test_DepositAndWithdraw() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit Deposited(address(this), 400);
        vault.deposit(400);
        assertEq(vault.balance(), 400);
        assertEq(token.balanceOf(address(this)), 600);

        vm.expectEmit(true, false, false, true, address(vault));
        emit Withdrawn(address(this), 150);
        vault.withdraw(150);
        assertEq(vault.balance(), 250);
        assertEq(token.balanceOf(address(this)), 750);
    }

    function test_DepositTransferFailureReverts() public {
        token.setFailTransfers(true);
        vm.expectRevert(GuardedVault.TokenTransferFailed.selector);
        vault.deposit(10);
    }

    function test_DepositOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(GuardedVault.NotOwner.selector);
        vault.deposit(10);
    }

    function test_WithdrawOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(GuardedVault.NotOwner.selector);
        vault.withdraw(10);
    }

    // ---- rescue callback --------------------------------------------------------

    function test_ExecuteRescueSweepsFreezesAndEmits() public {
        vault.deposit(400);

        vm.expectEmit(false, false, true, true, address(vault));
        emit Rescued(85, 400, safe);
        _rescue(85);

        assertTrue(vault.frozen());
        assertEq(vault.rescueCount(), 1);
        assertEq(vault.lastTriggerPrice(), 85);
        assertEq(vault.balance(), 0);
        assertEq(token.balanceOf(safe), 400);
    }

    function test_ExecuteRescueZeroBalanceStillFreezes() public {
        vm.expectEmit(false, false, true, true, address(vault));
        emit Rescued(200, 0, safe);
        _rescue(200);
        assertTrue(vault.frozen());
        assertEq(vault.rescueCount(), 1);
        assertEq(token.balanceOf(safe), 0);
    }

    function test_ExecuteRescueRejectsNonProxyCaller() public {
        // The spoofing case: an EOA passing the real sentinel address must
        // not be able to force a rescue — the caller must be the proxy.
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, stranger, address(proxy))
        );
        vault.executeRescue(sentinelAddr, 1);
        assertFalse(vault.frozen());
    }

    function test_ExecuteRescueRejectsWrongSender() public {
        vm.prank(address(proxy));
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractCallback.CallbackNotAuthorized.selector, stranger, sentinelAddr
            )
        );
        vault.executeRescue(stranger, 1);
        assertFalse(vault.frozen());
    }

    function test_FrozenVaultRejectsDepositAndWithdraw() public {
        vault.deposit(100);
        _rescue(85);

        vm.expectRevert(GuardedVault.Frozen.selector);
        vault.deposit(10);
        vm.expectRevert(GuardedVault.Frozen.selector);
        vault.withdraw(10);
    }

    // ---- reset / safe address ---------------------------------------------------

    function test_ResetUnfreezesForReuse() public {
        vault.deposit(100);
        _rescue(85);

        vm.expectEmit(false, false, false, true, address(vault));
        emit Reset();
        vault.reset();
        assertFalse(vault.frozen());

        vault.deposit(50);
        assertEq(vault.balance(), 50);
    }

    function test_ResetWhenNotFrozenReverts() public {
        vm.expectRevert(GuardedVault.NotFrozen.selector);
        vault.reset();
    }

    function test_ResetOnlyOwner() public {
        vault.deposit(100);
        _rescue(85);
        vm.prank(stranger);
        vm.expectRevert(GuardedVault.NotOwner.selector);
        vault.reset();
    }

    function test_SetSafeAddressRedirectsRescue() public {
        address newSafe = makeAddr("newSafe");
        vm.expectEmit(true, false, false, false, address(vault));
        emit SafeAddressUpdated(newSafe);
        vault.setSafeAddress(newSafe);
        assertEq(vault.safeAddress(), newSafe);

        vault.deposit(100);
        _rescue(85);
        assertEq(token.balanceOf(newSafe), 100);
        assertEq(token.balanceOf(safe), 0);
    }

    function test_SetSafeAddressOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(GuardedVault.NotOwner.selector);
        vault.setSafeAddress(stranger);
    }

    function test_SetSafeAddressZeroReverts() public {
        vm.expectRevert(GuardedVault.ZeroAddress.selector);
        vault.setSafeAddress(address(0));
    }

    function test_ConstructorZeroSafeAddressReverts() public {
        vm.expectRevert(GuardedVault.ZeroAddress.selector);
        new GuardedVault(address(proxy), sentinelAddr, address(token), address(0));
    }

    // ---- debt ---------------------------------------------------------------------

    function test_CoverDebtPaysProxy() public {
        proxy.setDebt(address(vault), 0.25 ether);
        vm.deal(address(vault), 1 ether);
        vault.coverDebt();
        assertEq(address(proxy).balance, 0.25 ether);
        assertEq(address(vault).balance, 0.75 ether);
    }
}
