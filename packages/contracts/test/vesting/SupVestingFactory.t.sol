// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Test.sol";
import { SFTest } from "../SFTest.t.sol";
import { ISupVestingFactory, SupVestingFactory } from "src/vesting/SupVestingFactory.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { VestingSchedulerV2 } from "@superfluid-finance/automation-contracts/scheduler/contracts/VestingSchedulerV2.sol";
import { IVestingSchedulerV2 } from
    "@superfluid-finance/automation-contracts/scheduler/contracts/interface/IVestingSchedulerV2.sol";
import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";

using SafeCast for int256;

contract SupVestingFactoryTest is SFTest {
    SupVestingFactory public supVestingFactory;
    VestingSchedulerV2 public vestingScheduler;

    // 2 years vesting
    uint32 public constant VESTING_DURATION = 730 days;

    // 1 year cliff
    uint32 public constant CLIFF_PERIOD = 365 days;

    function setUp() public virtual override {
        super.setUp();

        vestingScheduler = new VestingSchedulerV2(_sf.host);
        supVestingFactory = new SupVestingFactory(
            IVestingSchedulerV2(address(vestingScheduler)), ISuperToken(_fluidSuperToken), FLUID_TREASURY, ADMIN
        );

        // Move time forward to avoid vesting scheduler errors (time based input validation constraints)
        vm.warp(block.timestamp + 420 days);
    }

    function testCreateSupVestingContract(
        address nonAdmin,
        uint256 recipientNbVesting,
        address recipient,
        uint256 amount,
        uint256 cliffAmount
    ) public {
        vm.assume(nonAdmin != address(ADMIN));
        vm.assume(recipient != address(0));
        amount = bound(amount, 1 ether, 1_000_000 ether);
        cliffAmount = bound(cliffAmount, 1, amount - 0.1 ether);

        recipientNbVesting = bound(recipientNbVesting, 1, 3);

        uint32 cliffDate = uint32(block.timestamp + CLIFF_PERIOD);

        vm.prank(FLUID_TREASURY);
        _fluidSuperToken.approve(address(supVestingFactory), amount * recipientNbVesting);

        vm.prank(nonAdmin);
        vm.expectRevert(ISupVestingFactory.FORBIDDEN.selector);
        supVestingFactory.createSupVestingContract(
            recipient, 0, amount, cliffAmount, cliffDate, uint32(block.timestamp + CLIFF_PERIOD + VESTING_DURATION)
        );

        uint256 supplyBefore = supVestingFactory.totalSupply();

        for (uint256 i = 0; i < recipientNbVesting; ++i) {
            vm.prank(ADMIN);
            supVestingFactory.createSupVestingContract(
                recipient, i, amount, cliffAmount, cliffDate, uint32(block.timestamp + CLIFF_PERIOD + VESTING_DURATION)
            );

            address newSupVestingContract = supVestingFactory.supVestings(recipient, i);

            assertNotEq(newSupVestingContract, address(0), "New sup vesting contract should be created");
            assertEq(supVestingFactory.balanceOf(recipient), amount * (i + 1), "Balance should be updated");
            assertEq(supVestingFactory.totalSupply(), supplyBefore + amount * (i + 1), "Total supply should be updated");

            // if (i > 0) {
            //     vm.prank(ADMIN);
            //     vm.expectRevert(ISupVestingFactory.RECIPIENT_ALREADY_HAS_VESTING_CONTRACT.selector);
            //     supVestingFactory.createSupVestingContract(
            //         recipient, amount, cliffAmount, cliffDate, uint32(block.timestamp + CLIFF_PERIOD + VESTING_DURATION)
            //     );
            // }
        }
    }

    function testCreateSupVestingContract_invalidIndex(
        uint256 recipientNbVesting,
        uint256 randomIndex,
        address recipient,
        uint256 amount,
        uint256 cliffAmount
    ) public {
        amount = bound(amount, 1 ether, 1_000_000 ether);
        cliffAmount = bound(cliffAmount, 1, amount - 0.1 ether);
        recipientNbVesting = bound(recipientNbVesting, 2, 10);
        randomIndex = bound(randomIndex, 1, 1000);

        uint32 cliffDate = uint32(block.timestamp + CLIFF_PERIOD);

        vm.prank(FLUID_TREASURY);
        _fluidSuperToken.approve(address(supVestingFactory), amount * recipientNbVesting);

        vm.startPrank(ADMIN);
        for (uint256 i = 0; i < recipientNbVesting; ++i) {
            vm.expectRevert(ISupVestingFactory.VESTING_DUPLICATED.selector);
            supVestingFactory.createSupVestingContract(
                recipient,
                i + randomIndex,
                amount,
                cliffAmount,
                cliffDate,
                uint32(block.timestamp + CLIFF_PERIOD + VESTING_DURATION)
            );

            supVestingFactory.createSupVestingContract(
                recipient, i, amount, cliffAmount, cliffDate, uint32(block.timestamp + CLIFF_PERIOD + VESTING_DURATION)
            );
        }
        vm.stopPrank();
    }

    function testSetTreasury(address newTreasury, address nonTreasury) public {
        vm.assume(nonTreasury != address(FLUID_TREASURY));
        vm.assume(newTreasury != address(FLUID_TREASURY));
        vm.assume(newTreasury != address(0));

        vm.prank(nonTreasury);
        vm.expectRevert(ISupVestingFactory.FORBIDDEN.selector);
        supVestingFactory.setTreasury(newTreasury);

        vm.startPrank(FLUID_TREASURY);
        vm.expectRevert(ISupVestingFactory.FORBIDDEN.selector);
        supVestingFactory.setTreasury(address(0));

        supVestingFactory.setTreasury(newTreasury);
        vm.stopPrank();

        assertEq(supVestingFactory.treasury(), newTreasury, "Treasury should be updated to the new treasury");
    }

    function testSetAdmin(address newAdmin, address nonAdmin) public {
        address currentAdmin = supVestingFactory.admin();
        vm.assume(nonAdmin != currentAdmin);
        vm.assume(nonAdmin != supVestingFactory.treasury());
        vm.assume(newAdmin != currentAdmin);
        vm.assume(newAdmin != address(0));

        vm.prank(nonAdmin);
        vm.expectRevert(ISupVestingFactory.FORBIDDEN.selector);
        supVestingFactory.setAdmin(newAdmin);

        vm.startPrank(currentAdmin);
        vm.expectRevert(ISupVestingFactory.FORBIDDEN.selector);
        supVestingFactory.setAdmin(address(0));

        supVestingFactory.setAdmin(newAdmin);
        vm.stopPrank();

        assertEq(supVestingFactory.admin(), newAdmin, "Admin should be updated to the new admin");
    }
}
