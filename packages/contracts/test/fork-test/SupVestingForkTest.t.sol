// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";

import {
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { IVestingSchedulerV2 } from
    "@superfluid-finance/automation-contracts/scheduler/contracts/interface/IVestingSchedulerV2.sol";

import { SupVestingFactory } from "src/vesting/SupVestingFactory.sol";
import { ISupVesting } from "src/vesting/SupVesting.sol";

using SafeCast for int256;

struct VestingTestData {
    address recipient;
    uint256 vestingIndex;
    uint256 vestingAmount;
}

contract SupVestingForkTest is Test {
    ISuperToken internal _sup;
    SupVestingFactory internal _supVestingFactory;
    IVestingSchedulerV2 internal _vestingScheduler;
    address internal _admin;
    address internal _treasury;

    address internal constant _ALICE = address(0x1);
    uint32 internal constant _CLIFF_DATE = 1771459200;
    uint32 internal constant _END_DATE = 1834531200;

    // NOTE: To be updated if the input data changes
    uint256 internal constant _TOTAL_SUPPLY = 317709052 ether + 56597041 ether;

    function setUp() public {
        _sup = ISuperToken(0xa69f80524381275A7fFdb3AE01c54150644c8792);
        _supVestingFactory = SupVestingFactory(0x3DF8A6558073e973f4c3979138Cca836C993E285);

        _vestingScheduler = _supVestingFactory.VESTING_SCHEDULER();
        console.log("vestingScheduler", address(_vestingScheduler));

        _admin = _supVestingFactory.admin();
        console.log("admin", _admin);

        _treasury = _supVestingFactory.treasury();
        console.log("treasury", _treasury);
    }

    function _getFlowRateAndCliffAmount(uint256 vestingAmount) internal pure returns (int96 flowRate, uint256 cliffAmount) {
        uint256 vestingDuration = _END_DATE - _CLIFF_DATE;
        cliffAmount = vestingAmount / 3;

        uint256 remainderAmount = vestingAmount - cliffAmount;
        flowRate = int256(remainderAmount / vestingDuration).toInt96();

        // Add the remainder to the cliff amount
        cliffAmount += remainderAmount - (uint96(flowRate) * vestingDuration);
    }

    // NOTE: To be updated if the input data changes
    function _getTestData() internal pure returns (VestingTestData[] memory) {
        VestingTestData[] memory testData = new VestingTestData[](1);
        
        // Entry 2 (from row 3) - Type 1, 0x395605F350C448C3e5102213022C3E976140ed25, 1,662,234
        testData[0] = VestingTestData({
            recipient: 0x395605F350C448C3e5102213022C3E976140ed25,
            vestingIndex: 0, // Type 1 = vestingIndex 0
            vestingAmount: 1662234 ether
        });
        
        return testData;
    }

    function testVerifyTotalSupply() public view {
        uint256 totalSupply = _supVestingFactory.totalSupply();
        console.log("totalSupply", totalSupply);

        assertEq(totalSupply, _TOTAL_SUPPLY, "total supply mismatch");
    }

    function testVerifySchedulesCreatedByScript() public {
        console.log("verify schedules created by script");
        address newAdmin = makeAddr("newAdmin");

        // hand over admin
        vm.startPrank(_admin);
        _supVestingFactory.setAdmin(newAdmin);
        vm.stopPrank();

        assertEq(_supVestingFactory.admin(), _treasury, "admin should be new admin");
        
        // Define an array of test data with randomly selected entries from schedules.csv
        VestingTestData[] memory testData = _getTestData();
        
        // Loop through each test data entry and verify the vesting schedule
        for (uint i = 0; i < testData.length; i++) {
            console.log("Verifying recipient", testData[i].recipient);

            uint256 recipientBalanceBefore = _sup.balanceOf(testData[i].recipient);
            
            ISupVesting recipientContract = ISupVesting(_supVestingFactory.supVestings(
                testData[i].recipient, 
                testData[i].vestingIndex
            ));
            
            console.log("Contract address", address(recipientContract));
            
            address vestingContractAddr = address(recipientContract);
            address recipient = testData[i].recipient;
            uint256 vestingAmount = testData[i].vestingAmount;
            (int96 expectedFlowRate, uint256 expectedCliffAmount) = _getFlowRateAndCliffAmount(vestingAmount);
            uint32 cliffDate = _CLIFF_DATE;
            uint32 endDate = _END_DATE;

            IVestingSchedulerV2.VestingSchedule memory vestingSchedule = _vestingScheduler.getVestingSchedule(
                address(_sup), vestingContractAddr, recipient
            );
            console.log("vestingSchedule cliffAndFlowDate", vestingSchedule.cliffAndFlowDate);
            console.log("vestingSchedule endDate", vestingSchedule.endDate);
            console.log("vestingSchedule flowRate", vestingSchedule.flowRate);
            console.log("vestingSchedule cliffAmount", vestingSchedule.cliffAmount);
            console.log("vestingSchedule remainderAmount", vestingSchedule.remainderAmount);
            
            // Skip further tests if the contract doesn't exist
            if (address(recipientContract) == address(0)) {
                console.log("Contract not found for recipient", recipient);
                continue;
            }

            // verify
            assertEq(vestingSchedule.cliffAndFlowDate, cliffDate, "cliff date mismatch");
            assertEq(vestingSchedule.endDate, endDate, "end date mismatch");
            assertEq(vestingSchedule.flowRate, expectedFlowRate, "flow rate mismatch");
            assertEq(vestingSchedule.cliffAmount, expectedCliffAmount, "cliff amount mismatch");
            assertEq(vestingSchedule.remainderAmount, 0, "remainder amount not zero");
            assertEq(vestingSchedule.claimValidityDate, 0, "claim validity date is not zero");

            // fast forward to after cliff date
            vm.warp(cliffDate + 1);

            // execute the cliff and flow (permissionless, done by automation in prod)
            assertEq(_vestingScheduler.executeCliffAndFlow(_sup, vestingContractAddr, recipient), true, "executeCliffAndFlow should return true");

            // proceed with emergency withdraw for 50% of the vesting schedules
            bool doEmergencyWithdraw = i % 2 == 0;

            if (doEmergencyWithdraw) { // emergency withdraw
                console.log("emergency withdraw");

                // verify that the previous admin doesn't have privileges anymore
                vm.startPrank(_admin);
                vm.expectRevert(ISupVesting.FORBIDDEN.selector);
                ISupVesting(vestingContractAddr).emergencyWithdraw();
                vm.stopPrank();

                // but treasury can still emergency withdraw
                uint256 vestingContractBalanceBefore = _sup.balanceOf(vestingContractAddr);
                uint256 treasuryBalanceBefore = _sup.balanceOf(_treasury);
                vm.startPrank(_treasury);
                ISupVesting(vestingContractAddr).emergencyWithdraw();
                vm.stopPrank();
                uint256 vestingContractBalanceAfter = _sup.balanceOf(vestingContractAddr);
                assertEq(vestingContractBalanceAfter, 0, "vesting contract balance should be 0 after emergency withdraw");
                uint256 treasuryBalanceAfter = _sup.balanceOf(_treasury);
                // ensure that the treasury received the remaining amount (Ge because the redeemed flow deposit is missing in vestingContractBalanceBefore)
                assertGe(treasuryBalanceAfter, treasuryBalanceBefore + vestingContractBalanceBefore, "treasury balance should be increased by remaining amount");
            } else {
                console.log("end vesting");
                // fast forward to the end date minus 1 day, and execute end vesting
                vm.warp(endDate - 1 days);
                
                assertEq(_vestingScheduler.executeEndVesting(_sup, vestingContractAddr, recipient), true, "executeEndVesting should return true");

                // verify that the vesting contract balance is 0
                assertEq(_sup.balanceOf(vestingContractAddr), 0, "vesting contract balance should be 0 after end vesting");

                // verify that the recipient has the full amount
                assertEq(_sup.balanceOf(recipient), recipientBalanceBefore + vestingAmount, "recipient balance should be the full amount");
            }

            // Reset state for next test
            vm.warp(block.timestamp - 1); // Go back in time before cliff date
        }
    }
}
