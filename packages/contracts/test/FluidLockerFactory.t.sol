// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { SFTest } from "./SFTest.t.sol";

import {
    ISuperToken,
    ISuperfluidPool
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { IFluidLockerFactory } from "../src/FluidLockerFactory.sol";

using SuperTokenV1Library for ISuperToken;

contract FluidLockerFactoryTest is SFTest {
    uint256 public constant LOCKER_CREATION_FEE = 0.00025 ether;

    function setUp() public override {
        super.setUp();

        vm.prank(ADMIN);
        _fluidLockerFactory.setLockerCreationFee(LOCKER_CREATION_FEE);
    }

    function testCreateLockerContract(uint256 _invalidFee) external {
        vm.assume(_invalidFee != LOCKER_CREATION_FEE);

        vm.deal(CAROL, type(uint256).max);

        vm.startPrank(CAROL);

        vm.expectRevert(IFluidLockerFactory.INVALID_FEE.selector);
        _fluidLockerFactory.createLockerContract{ value: _invalidFee }();

        assertEq(_fluidLockerFactory.getLockerAddress(CAROL), address(0), "locker should not exists");

        address userLockerAddress = _fluidLockerFactory.createLockerContract{ value: LOCKER_CREATION_FEE }();

        assertEq(_fluidLockerFactory.getLockerAddress(CAROL), userLockerAddress, "locker should exists");
        assertEq(address(_fluidLockerFactory).balance, LOCKER_CREATION_FEE, "incorrect balance");

        vm.expectRevert();
        _fluidLockerFactory.createLockerContract{ value: LOCKER_CREATION_FEE }();

        vm.stopPrank();
    }

    function testCreateLockerContractOnBehalf(address _user, address _onBehalfOf, uint256 _invalidFee) external {
        vm.assume(_user != _onBehalfOf);
        vm.assume(_user != address(0));
        vm.assume(_onBehalfOf != address(0));
        vm.assume(_invalidFee != LOCKER_CREATION_FEE);

        vm.deal(_user, type(uint256).max);

        vm.startPrank(_user);

        vm.expectRevert(IFluidLockerFactory.INVALID_FEE.selector);
        _fluidLockerFactory.createLockerContract{ value: _invalidFee }(_onBehalfOf);

        assertEq(_fluidLockerFactory.getLockerAddress(_onBehalfOf), address(0), "locker should not exists");

        address createdLockerAddress =
            _fluidLockerFactory.createLockerContract{ value: LOCKER_CREATION_FEE }(_onBehalfOf);

        assertEq(_fluidLockerFactory.getLockerAddress(_onBehalfOf), createdLockerAddress, "locker should exists");
        assertEq(address(_fluidLockerFactory).balance, LOCKER_CREATION_FEE, "incorrect balance");

        vm.expectRevert();
        _fluidLockerFactory.createLockerContract{ value: LOCKER_CREATION_FEE }(_onBehalfOf);

        vm.stopPrank();
    }

    function testSetGovernor(address _newGovernor) external {
        address currentGovernor = _fluidLockerFactory.governor();
        vm.assume(_newGovernor != currentGovernor);
        vm.assume(_newGovernor != address(0));

        vm.prank(_newGovernor);
        vm.expectRevert(IFluidLockerFactory.NOT_GOVERNOR.selector);
        _fluidLockerFactory.setGovernor(_newGovernor);

        vm.prank(currentGovernor);
        _fluidLockerFactory.setGovernor(_newGovernor);

        assertEq(_fluidLockerFactory.governor(), _newGovernor, "governor not updated");
    }

    function testWithdrawETH(address _user) external {
        vm.assume(_user != address(0));
        vm.assume(_user != ADMIN);

        vm.deal(_user, type(uint256).max);

        vm.startPrank(_user);

        _fluidLockerFactory.createLockerContract{ value: LOCKER_CREATION_FEE }();

        assertEq(address(_fluidLockerFactory).balance, LOCKER_CREATION_FEE, "incorrect balance");

        vm.expectRevert(IFluidLockerFactory.NOT_GOVERNOR.selector);
        _fluidLockerFactory.withdrawETH();

        vm.stopPrank();

        uint256 adminBalanceBefore = address(ADMIN).balance;

        vm.prank(ADMIN);
        _fluidLockerFactory.withdrawETH();

        uint256 adminBalanceAfter = address(ADMIN).balance;

        assertEq(adminBalanceAfter, adminBalanceBefore + LOCKER_CREATION_FEE, "incorrect balance");
        assertEq(address(_fluidLockerFactory).balance, 0, "incorrect balance");
    }

    function testGetUserLocker(address user, address nonUser) external {
        vm.assume(user != nonUser);

        vm.deal(user, LOCKER_CREATION_FEE);

        vm.prank(user);
        address userLockerAddress = _fluidLockerFactory.createLockerContract{ value: LOCKER_CREATION_FEE }();

        (bool isCreated, address lockerAddressResult) = _fluidLockerFactory.getUserLocker(user);

        assertEq(lockerAddressResult, userLockerAddress, "incorrect address");
        assertEq(isCreated, true, "locker should be created");

        (isCreated, lockerAddressResult) = _fluidLockerFactory.getUserLocker(nonUser);
        assertEq(lockerAddressResult, address(0), "should be the zero-address");
        assertEq(isCreated, false, "locker should not be created");
    }

    function testGetLockerBeaconImplementation() external view {
        assertEq(_fluidLockerFactory.getLockerBeaconImplementation(), address(_fluidLockerLogic));
    }
}
