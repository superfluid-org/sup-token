// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { console2 } from "forge-std/Test.sol";
import { SFTest } from "../SFTest.t.sol";
import { SupVestingFactory } from "src/vesting/SupVestingFactory.sol";
import { ISupVesting, SupVesting } from "src/vesting/SupVesting.sol";
import { ISuperToken, SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { VestingSchedulerV2 } from "@superfluid-finance/automation-contracts/scheduler/contracts/VestingSchedulerV2.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";

import { IVestingSchedulerV2 } from
    "@superfluid-finance/automation-contracts/scheduler/contracts/interface/IVestingSchedulerV2.sol";

using SuperTokenV1Library for SuperToken;
using SafeCast for int256;

contract SupVestingTestInit is SFTest {
    SupVestingFactory public supVestingFactory;
    VestingSchedulerV2 public vestingScheduler;

    function setUp() public virtual override {
        super.setUp();

        vestingScheduler = new VestingSchedulerV2(_sf.host);
        supVestingFactory = new SupVestingFactory(
            IVestingSchedulerV2(address(vestingScheduler)), ISuperToken(_fluidSuperToken), FLUID_TREASURY, ADMIN
        );
    }
}

contract SupVestingTest is SupVestingTestInit {
    SupVesting public supVesting;

    uint256 public constant VESTING_AMOUNT = 115340 ether;
    uint256 public constant CLIFF_AMOUNT = 38446666666666717280000;

    uint32 public constant VESTING_DURATION = 730 days;
    uint32 public constant CLIFF_PERIOD = 365 days;

    uint32 public cliffDate;
    int96 public flowRate;

    function setUp() public virtual override {
        super.setUp();

        // Move time forward to avoid vesting scheduler errors (time based input validation constraints)
        vm.warp(block.timestamp + 420 days);

        vm.prank(FLUID_TREASURY);
        _fluidSuperToken.approve(address(supVestingFactory), VESTING_AMOUNT);

        cliffDate = uint32(block.timestamp + CLIFF_PERIOD);
        flowRate = int256((VESTING_AMOUNT - CLIFF_AMOUNT) / uint256(VESTING_DURATION)).toInt96();

        uint256 aliceVestingIndex = 0;

        vm.prank(ADMIN);
        supVestingFactory.createSupVestingContract(
            ALICE, aliceVestingIndex, VESTING_AMOUNT, CLIFF_AMOUNT, cliffDate, uint32(cliffDate + VESTING_DURATION)
        );

        supVesting = SupVesting(address(supVestingFactory.supVestings(ALICE, aliceVestingIndex)));
    }

    function testVesting() public {
        // Move time to after vesting can be started
        vm.warp(cliffDate);

        // Execute the vesting start
        vestingScheduler.executeCliffAndFlow(_fluidSuperToken, address(supVesting), ALICE);

        assertEq(_fluidSuperToken.balanceOf(ALICE), CLIFF_AMOUNT, "Alice should have received the cliff amount");
        assertEq(_fluidSuperToken.getFlowRate(address(supVesting), ALICE), flowRate, "Flow rate mismatch");

        IVestingSchedulerV2.VestingSchedule memory aliceVS =
            vestingScheduler.getVestingSchedule(address(_fluidSuperToken), address(supVesting), ALICE);

        // Move time to after vesting can be concluded (before the stream gets critical / buffer starts being consumed)
        vm.warp(aliceVS.endDate - 5 hours);

        vestingScheduler.executeEndVesting(_fluidSuperToken, address(supVesting), ALICE);

        assertEq(_fluidSuperToken.balanceOf(ALICE), VESTING_AMOUNT, "Alice should have the full amount");
        assertEq(_fluidSuperToken.balanceOf(address(supVesting)), 0, "SupVesting contract should be empty");
    }

    function testVestingFuzz(uint256 _amount, uint32 _cliffDate, uint32 _endDate) public {
        address recipient = vm.addr(69_420);
        _amount = bound(_amount, 1 ether, 1_000_000 ether);
        _endDate = uint32(bound(_endDate, block.timestamp + 365 days, block.timestamp + (365 days * 10)));
        _cliffDate = uint32(bound(_cliffDate, block.timestamp + 3 days, _endDate - 7 days));

        vm.prank(FLUID_TREASURY);
        _fluidSuperToken.approve(address(supVestingFactory), _amount);

        vm.prank(ADMIN);
        address recipientSupVesting =
            supVestingFactory.createSupVestingContract(recipient, 0, _amount, _amount / 3, _cliffDate, _endDate);

        (uint256 expectedCliff, int96 expectedFlowRate) =
            _helperCalculateExpectedCliffAndFlow(_amount, _endDate - _cliffDate);

        // Move time to after vesting can be started
        vm.warp(_cliffDate);

        // Execute the vesting start
        vestingScheduler.executeCliffAndFlow(_fluidSuperToken, recipientSupVesting, recipient);

        assertEq(
            _fluidSuperToken.balanceOf(recipient), expectedCliff, "Recipient should have received the cliff amount"
        );
        assertEq(_fluidSuperToken.getFlowRate(recipientSupVesting, recipient), expectedFlowRate, "Flow rate mismatch");

        // Move time to after vesting can be concluded (before stream gets critical)
        vm.warp(_endDate - 5 hours);

        vestingScheduler.executeEndVesting(_fluidSuperToken, recipientSupVesting, recipient);

        assertEq(_fluidSuperToken.balanceOf(recipient), _amount, "Recipient should have the full amount");
        assertEq(_fluidSuperToken.balanceOf(recipientSupVesting), 0, "SupVesting contract should be empty");
    }

    function testEmergencyWithdrawBeforeVestingStart(address nonAdmin) public {
        vm.assume(nonAdmin != address(ADMIN));

        vm.prank(nonAdmin);
        vm.expectRevert(ISupVesting.FORBIDDEN.selector);
        supVesting.emergencyWithdraw();

        uint256 treasuryBalanceBefore = _fluidSuperToken.balanceOf(FLUID_TREASURY);
        uint256 aliceVestingBalanceBefore = _fluidSuperToken.balanceOf(address(supVesting));

        vm.prank(ADMIN);
        supVesting.emergencyWithdraw();

        assertEq(
            _fluidSuperToken.balanceOf(FLUID_TREASURY),
            treasuryBalanceBefore + aliceVestingBalanceBefore,
            "Balance should be updated"
        );

        assertEq(_fluidSuperToken.balanceOf(address(supVesting)), 0, "Balance should be 0");
    }

    function testEmergencyWithdrawAfterVestingStart(address nonAdmin) public {
        vm.assume(nonAdmin != address(ADMIN));

        vm.prank(nonAdmin);
        vm.expectRevert(ISupVesting.FORBIDDEN.selector);
        supVesting.emergencyWithdraw();

        // Move time to after vesting can be started
        vm.warp(cliffDate + 1 minutes);

        // Execute the vesting start
        vestingScheduler.executeCliffAndFlow(_fluidSuperToken, address(supVesting), ALICE);

        int96 vestingFlowRate = _fluidSuperToken.getFlowRate(address(supVesting), ALICE);

        console2.log("vestingFlowRate", vestingFlowRate);

        assertEq(vestingFlowRate, flowRate, "Flow rate mismatch");

        vm.warp(block.timestamp + 5 days);

        uint256 treasuryBalanceBefore = _fluidSuperToken.balanceOf(FLUID_TREASURY);
        uint256 aliceVestingBalanceBefore = _fluidSuperToken.balanceOf(address(supVesting));

        vm.prank(ADMIN);
        supVesting.emergencyWithdraw();

        assertEq(_fluidSuperToken.getFlowRate(address(supVesting), ALICE), 0, "Flow should be deleted");

        assertApproxEqAbs(
            _fluidSuperToken.balanceOf(FLUID_TREASURY),
            treasuryBalanceBefore + aliceVestingBalanceBefore,
            (_fluidSuperToken.balanceOf(FLUID_TREASURY) * 10) / 10_000, // 0.1% tolerance
            "Balance should be updated"
        );

        assertEq(_fluidSuperToken.balanceOf(address(supVesting)), 0, "Balance should be 0");
    }

    function testEmergencyWithdrawStreamManuallyClosedByRecipient() public {
        // Move time to after vesting can be started
        vm.warp(cliffDate + 1 minutes);

        // Execute the vesting start
        vestingScheduler.executeCliffAndFlow(_fluidSuperToken, address(supVesting), ALICE);

        int96 vestingFlowRate = _fluidSuperToken.getFlowRate(address(supVesting), ALICE);

        assertEq(vestingFlowRate, flowRate, "Flow rate mismatch");

        vm.warp(block.timestamp + 5 days);

        uint256 treasuryBalanceBefore = _fluidSuperToken.balanceOf(FLUID_TREASURY);
        uint256 aliceVestingBalanceBefore = _fluidSuperToken.balanceOf(address(supVesting));

        vm.startPrank(ALICE);
        _fluidSuperToken.deleteFlow(address(supVesting), ALICE);
        vm.stopPrank();

        vm.prank(ADMIN);
        supVesting.emergencyWithdraw();

        assertEq(_fluidSuperToken.getFlowRate(address(supVesting), ALICE), 0, "Flow should be deleted");

        assertApproxEqAbs(
            _fluidSuperToken.balanceOf(FLUID_TREASURY),
            treasuryBalanceBefore + aliceVestingBalanceBefore,
            (_fluidSuperToken.balanceOf(FLUID_TREASURY) * 10) / 10_000, // 0.1% tolerance
            "Balance should be updated"
        );

        assertEq(_fluidSuperToken.balanceOf(address(supVesting)), 0, "Balance should be 0");
    }

    function testEmergencyWithdrawStreamManuallyClosedByRecipientAndVestingEnded() public {
        IVestingSchedulerV2.VestingSchedule memory aliceVS =
            vestingScheduler.getVestingSchedule(address(_fluidSuperToken), address(supVesting), ALICE);

        // Move time to after vesting can be started
        vm.warp(cliffDate + 1 minutes);

        // Execute the vesting start
        vestingScheduler.executeCliffAndFlow(_fluidSuperToken, address(supVesting), ALICE);

        int96 vestingFlowRate = _fluidSuperToken.getFlowRate(address(supVesting), ALICE);

        assertEq(vestingFlowRate, flowRate, "Flow rate mismatch");

        vm.warp(block.timestamp + 5 days);

        uint256 treasuryBalanceBefore = _fluidSuperToken.balanceOf(FLUID_TREASURY);
        uint256 aliceVestingBalanceBefore = _fluidSuperToken.balanceOf(address(supVesting));

        vm.startPrank(ALICE);
        _fluidSuperToken.deleteFlow(address(supVesting), ALICE);
        vm.stopPrank();

        // Move time to after vesting can be concluded (before the stream gets critical / buffer starts being consumed)
        vm.warp(aliceVS.endDate - 5 hours);

        vestingScheduler.executeEndVesting(_fluidSuperToken, address(supVesting), ALICE);

        vm.prank(ADMIN);
        supVesting.emergencyWithdraw();

        assertEq(_fluidSuperToken.getFlowRate(address(supVesting), ALICE), 0, "Flow should be deleted");

        assertApproxEqAbs(
            _fluidSuperToken.balanceOf(FLUID_TREASURY),
            treasuryBalanceBefore + aliceVestingBalanceBefore,
            (_fluidSuperToken.balanceOf(FLUID_TREASURY) * 10) / 10_000, // 0.1% tolerance
            "Balance should be updated"
        );

        assertEq(_fluidSuperToken.balanceOf(address(supVesting)), 0, "Balance should be 0");
    }
}

/// @notice This test is meant to be updated with all the real data for each insider
contract SupVestingTestRealData is SupVestingTestInit {
    uint32 public constant TWO_YEARS_IN_SECONDS = 63158400;

    uint256 public constant CURRENT_DATE = 1740783600; // March 1st 2025 (CET)
    uint32 public constant CLIFF_DATE = 1772319600; // March 1st 2026 (CET)
    uint32 public constant END_DATE = CLIFF_DATE + TWO_YEARS_IN_SECONDS; // March 1st 2028 00:00:00 (CET)

    uint256 public constant TOTAL_MAX_VESTING_AMOUNT = 250_000_000 ether;

    uint256[7] public amounts;

    function setUp() public virtual override {
        super.setUp();

        amounts = [100_000 ether, 50_000 ether, 25_000 ether, 17_500 ether, 14_000 ether, 12_710 ether, 9_850 ether];

        vm.prank(FLUID_TREASURY);
        _fluidSuperToken.approve(address(supVestingFactory), TOTAL_MAX_VESTING_AMOUNT);
    }

    function testVestings(uint256 creationDate) public {
        creationDate = bound(creationDate, CURRENT_DATE, CLIFF_DATE - 3 days);
        vm.warp(creationDate);
        _helperCreateVestings();

        vm.warp(CLIFF_DATE);
        _helperExecuteCliffAndFlow();

        vm.warp(END_DATE - 24 hours);
        _helperExecuteEndVestings();
    }

    function _helperCreateVestings() internal {
        vm.startPrank(ADMIN);

        for (uint256 i = 0; i < amounts.length; i++) {
            supVestingFactory.createSupVestingContract(
                vm.addr(i + 69_420), 0, amounts[i], amounts[i] / 3, CLIFF_DATE, END_DATE
            );
        }

        vm.stopPrank();
    }

    function _helperExecuteCliffAndFlow() internal {
        vm.startPrank(ADMIN);

        uint256 vestingDuration = END_DATE - CLIFF_DATE;

        for (uint256 i = 0; i < amounts.length; i++) {
            address recipient = vm.addr(i + 69_420);
            address sv = address(supVestingFactory.supVestings(recipient, 0));

            vestingScheduler.executeCliffAndFlow(_fluidSuperToken, sv, recipient);

            (uint256 expectedCliffAmount, int96 expectedFlowRate) =
                _helperCalculateExpectedCliffAndFlow(amounts[i], vestingDuration);

            assertEq(
                _fluidSuperToken.balanceOf(recipient),
                expectedCliffAmount,
                "recipient should have received the exact cliff amount"
            );
            assertEq(_fluidSuperToken.getFlowRate(sv, recipient), expectedFlowRate, "Recipient Flow rate mismatch");
        }

        vm.stopPrank();
    }

    function _helperExecuteEndVestings() internal {
        vm.startPrank(ADMIN);

        for (uint256 i = 0; i < amounts.length; i++) {
            address recipient = vm.addr(i + 69_420);
            address sv = address(supVestingFactory.supVestings(recipient, 0));

            console2.log("amounts[i]", amounts[i]);
            vestingScheduler.executeEndVesting(_fluidSuperToken, sv, recipient);

            assertEq(
                _fluidSuperToken.balanceOf(recipient), amounts[i], "Recipient should have received the full amount"
            );
            assertEq(_fluidSuperToken.balanceOf(sv), 0, "SupVesting contract should be empty");
            assertEq(_fluidSuperToken.getFlowRate(sv, recipient), 0, "Recipient Flow rate should be 0");
        }

        vm.stopPrank();
    }
}

function _helperCalculateExpectedCliffAndFlow(uint256 amount, uint256 vestingDuration)
    pure
    returns (uint256 expectedCliffAmount, int96 expectedFlowRate)
{
    expectedCliffAmount = amount / 3;
    expectedFlowRate = int256((amount - expectedCliffAmount) / vestingDuration).toInt96();
    expectedCliffAmount += (amount - expectedCliffAmount) - (uint96(expectedFlowRate) * vestingDuration);
}
