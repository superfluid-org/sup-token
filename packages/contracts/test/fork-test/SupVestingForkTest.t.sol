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
    uint32 internal constant _CLIFF_DATE = 1771074000;
    uint32 internal constant _END_DATE = 1834146000;

    // NOTE: To be updated if the input data changes
    uint256 internal constant _TOTAL_SUPPLY = 317709052 ether;

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
        VestingTestData[] memory testData = new VestingTestData[](7);
        
        // Entry 1 (from row 2) - Type 1, 0xfd2A175CFAa14344a0e896179765f6d83F7c1977, 411,061
        testData[0] = VestingTestData({
            recipient: 0xfd2A175CFAa14344a0e896179765f6d83F7c1977,
            vestingIndex: 0, // Type 1 = vestingIndex 0
            vestingAmount: 411061 ether
        });
        
        // Entry 2 (from row 3) - Type 2, 0xfd2A175CFAa14344a0e896179765f6d83F7c1977, 1,783,088
        testData[1] = VestingTestData({
            recipient: 0xfd2A175CFAa14344a0e896179765f6d83F7c1977,
            vestingIndex: 1, // Type 2 = vestingIndex 1
            vestingAmount: 1783088 ether
        });
        
        // Entry 3 (from row 12) - Type 3, 0x24F2C443642649869acBa5c1A9CEA27b04Ba004E, 365,691
        testData[2] = VestingTestData({
            recipient: 0x24F2C443642649869acBa5c1A9CEA27b04Ba004E,
            vestingIndex: 2, // Type 3 = vestingIndex 2
            vestingAmount: 365691 ether
        });
        
        // Entry 4 (from row 26) - Type 1, 0x97A8131e4d571431E937d8712Ab67Ac83EE02c2D, 5,265,957
        testData[3] = VestingTestData({
            recipient: 0x97A8131e4d571431E937d8712Ab67Ac83EE02c2D,
            vestingIndex: 0, // Type 1 = vestingIndex 0
            vestingAmount: 5265957 ether
        });
        
        // Entry 5 (from row 29) - Type 2, 0x16e5AD2F9697Caf4B0F0deB25FF1121a01cBD2c7, 5,920,179
        testData[4] = VestingTestData({
            recipient: 0x16e5AD2F9697Caf4B0F0deB25FF1121a01cBD2c7,
            vestingIndex: 1, // Type 2 = vestingIndex 1
            vestingAmount: 5920179 ether
        });
        
        // Entry 6 (from row 37) - Type 1, 0xA6c49067919D92d5DB655AF190111D480Ee1B9A4, 81,183,511
        testData[5] = VestingTestData({
            recipient: 0xA6c49067919D92d5DB655AF190111D480Ee1B9A4,
            vestingIndex: 0, // Type 1 = vestingIndex 0
            vestingAmount: 81183511 ether
        });
        
        // Entry 7 (from row 59) - Type 1, 0x84A1C94DE422cd1a8dC6D8cb819f57403fB93D58, 31,382,979
        testData[6] = VestingTestData({
            recipient: 0x84A1C94DE422cd1a8dC6D8cb819f57403fB93D58,
            vestingIndex: 0, // Type 1 = vestingIndex 0
            vestingAmount: 31382979 ether
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

        // hand over admin to the treasury
        vm.startPrank(_admin);
        _supVestingFactory.setAdmin(_treasury);
        vm.stopPrank();

        assertEq(_supVestingFactory.admin(), _treasury, "admin should be treasury");
        
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
