// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { SFTest } from "./SFTest.t.sol";

import {
    ISuperToken,
    ISuperfluidPool
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

import { StakingRewardController, IStakingRewardController } from "../src/StakingRewardController.sol";

using SuperTokenV1Library for ISuperToken;

contract StakingRewardControllerTest is SFTest {
    function setUp() public override {
        super.setUp();
    }

    function testUpdateStakerUnits(address caller, uint256 stakingAmount) external {
        vm.assume(caller != address(0));
        vm.assume(caller != address(_stakingRewardController.taxDistributionPool()));
        vm.assume(caller != address(_stakingRewardController.lpDistributionPool()));
        stakingAmount = bound(stakingAmount, 1e18, 10_000_000e18);

        vm.prank(caller);
        vm.expectRevert(IStakingRewardController.NOT_APPROVED_LOCKER.selector);
        _stakingRewardController.updateStakerUnits(stakingAmount);

        vm.expectRevert(IStakingRewardController.NOT_LOCKER_FACTORY.selector);
        _stakingRewardController.approveLocker(caller);

        vm.prank(address(_fluidLockerFactory));
        _stakingRewardController.approveLocker(caller);

        vm.prank(caller);
        _stakingRewardController.updateStakerUnits(stakingAmount);

        assertEq(
            _stakingRewardController.taxDistributionPool().getUnits(caller),
            stakingAmount / _STAKING_UNIT_DOWNSCALER,
            "incorrect amount of units"
        );
    }

    function testSetLockerFactory(address newLockerFactory) external {
        vm.assume(newLockerFactory != address(0));
        vm.assume(newLockerFactory != _stakingRewardController.lockerFactory());

        vm.prank(ADMIN);
        _stakingRewardController.setLockerFactory(newLockerFactory);

        assertEq(_stakingRewardController.lockerFactory(), newLockerFactory);

        vm.prank(ADMIN);
        vm.expectRevert(IStakingRewardController.INVALID_PARAMETER.selector);
        _stakingRewardController.setLockerFactory(address(0));
    }
}

contract StakingRewardControllerLayoutTest is StakingRewardController {
    constructor() StakingRewardController(ISuperToken(address(0))) { }

    function testStorageLayout() external pure {
        uint256 slot;
        uint256 offset;

        // StakingRewardController storage

        // private state : _approvedLockers
        // slot = 0 - offset = 0

        assembly {
            slot := taxDistributionPool.slot
            offset := taxDistributionPool.offset
        }
        require(slot == 1 && offset == 0, "taxDistributionPool changed location");

        assembly {
            slot := lockerFactory.slot
            offset := lockerFactory.offset
        }
        require(slot == 2 && offset == 0, "lockerFactory changed location");
    }
}
