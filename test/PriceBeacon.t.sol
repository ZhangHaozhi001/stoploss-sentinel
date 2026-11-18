// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { PriceBeacon } from "../src/PriceBeacon.sol";

contract PriceBeaconTest is Test {
    event PriceUpdated(int256 price, uint256 updatedAt);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    PriceBeacon internal beacon;
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        vm.warp(12_345);
        beacon = new PriceBeacon(100);
    }

    function test_ConstructorSetsPriceAndTimestamp() public view {
        assertEq(beacon.price(), 100);
        assertEq(beacon.updatedAt(), 12_345);
        assertEq(beacon.owner(), address(this));
    }

    function test_PostPriceUpdatesAndEmits() public {
        vm.warp(20_000);
        vm.expectEmit(false, false, false, true, address(beacon));
        emit PriceUpdated(95, 20_000);
        beacon.postPrice(95);
        assertEq(beacon.price(), 95);
        assertEq(beacon.updatedAt(), 20_000);
    }

    function test_PostPriceEmitsEvenWhenUnchanged() public {
        // Demos rely on re-posting the same value to re-trigger the loop.
        vm.expectEmit(false, false, false, true, address(beacon));
        emit PriceUpdated(100, 12_345);
        beacon.postPrice(100);
    }

    function test_PostPriceOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(PriceBeacon.NotOwner.selector);
        beacon.postPrice(1);
    }

    function test_TransferOwnership() public {
        vm.expectEmit(true, true, false, false, address(beacon));
        emit OwnershipTransferred(address(this), stranger);
        beacon.transferOwnership(stranger);
        assertEq(beacon.owner(), stranger);

        // Old owner can no longer post; new owner can.
        vm.expectRevert(PriceBeacon.NotOwner.selector);
        beacon.postPrice(1);
        vm.prank(stranger);
        beacon.postPrice(42);
        assertEq(beacon.price(), 42);
    }

    function test_TransferOwnershipOnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(PriceBeacon.NotOwner.selector);
        beacon.transferOwnership(stranger);
    }

    function test_TransferOwnershipZeroReverts() public {
        vm.expectRevert(PriceBeacon.ZeroAddress.selector);
        beacon.transferOwnership(address(0));
    }
}
