// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { console2 } from "forge-std/Test.sol";

import { SFTest } from "./SFTest.t.sol";

import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";
import { Math } from "@openzeppelin-v5/contracts/utils/math/Math.sol";

import {
    ISuperToken,
    ISuperfluidPool
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

import { FluidLocker, IFluidLocker, getUnlockingPercentage, calculateVestUnlockAmounts } from "../src/FluidLocker.sol";
import { IFontaine } from "../src/interfaces/IFontaine.sol";
import { IEPProgramManager } from "../src/interfaces/IEPProgramManager.sol";
import { IStakingRewardController } from "../src/interfaces/IStakingRewardController.sol";
import { Fontaine } from "../src/Fontaine.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { LiquidityAmounts } from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

using SuperTokenV1Library for ISuperToken;
using SafeCast for int256;

abstract contract FluidLockerBaseTest is SFTest {
    uint256 public constant PROGRAM_0 = 1;
    uint256 public constant PROGRAM_1 = 2;
    uint256 public constant PROGRAM_2 = 3;
    uint256 public constant signerPkey = 0x69;

    uint256 internal constant _BP_DENOMINATOR = 10_000;
    uint256 internal constant _INSTANT_UNLOCK_PENALTY_BP = 8000;
    uint256 internal constant _SCALER = 1e18;
    uint128 internal constant _MIN_UNLOCK_PERIOD = 7 days;
    uint128 internal constant _MAX_UNLOCK_PERIOD = 365 days;
    uint256 internal constant _TAX_DISTRIBUTION_FLOW_DURATION = 180 days;
    uint80 internal constant _STAKING_COOLDOWN_PERIOD = 7 days;
    uint80 internal constant _LP_COOLDOWN_PERIOD = 7 days;

    ISuperfluidPool[] public programPools;

    IFluidLocker public aliceLocker;
    IFluidLocker public bobLocker;
    IFluidLocker public carolLocker;

    function setUp() public virtual override {
        super.setUp();

        uint256[] memory pIds = new uint256[](3);
        pIds[0] = PROGRAM_0;
        pIds[1] = PROGRAM_1;
        pIds[2] = PROGRAM_2;

        programPools = _helperCreatePrograms(pIds, ADMIN, vm.addr(signerPkey));

        vm.prank(ALICE);
        aliceLocker = IFluidLocker(_fluidLockerFactory.createLockerContract());

        vm.prank(BOB);
        bobLocker = IFluidLocker(_fluidLockerFactory.createLockerContract());

        vm.prank(CAROL);
        carolLocker = IFluidLocker(_fluidLockerFactory.createLockerContract());
    }

    //      __  __     __                   ______                 __  _
    //     / / / /__  / /___  ___  _____   / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / /_/ / _ \/ / __ \/ _ \/ ___/  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / __  /  __/ / /_/ /  __/ /     / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_/ /_/\___/_/ .___/\___/_/     /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/
    //              /_/

    function _helperGetAmountsForLiquidity(IUniswapV3Pool pool, uint128 liquidity)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        uint160 sqrtRatioLowerX96 = TickMath.getSqrtRatioAtTick(_MIN_TICK);
        uint160 sqrtRatioHigherX96 = TickMath.getSqrtRatioAtTick(_MAX_TICK);

        (amount0, amount1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioLowerX96, sqrtRatioHigherX96, liquidity);
    }

    function _helperBuySUP(address buyer, uint256 wethAmount) internal {
        deal(address(_weth), buyer, wethAmount);

        vm.startPrank(buyer);
        _weth.approve(address(_swapRouter), wethAmount);

        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(_weth),
            tokenOut: address(_fluidSuperToken),
            fee: POOL_FEE,
            recipient: buyer,
            amountIn: wethAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        _swapRouter.exactInputSingle(swapParams);
        vm.stopPrank();
    }

    function _helperSellSUP(address seller, uint256 supAmount) internal {
        vm.prank(FLUID_TREASURY);
        _fluidSuperToken.transfer(seller, supAmount);

        vm.startPrank(seller);
        _fluidSuperToken.approve(address(_swapRouter), supAmount);

        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(_fluidSuperToken),
            tokenOut: address(_weth),
            fee: POOL_FEE,
            recipient: seller,
            amountIn: supAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        _swapRouter.exactInputSingle(swapParams);
        vm.stopPrank();
    }

    function _helperCalculateTaxDisitrutionInstantUnlock(uint256 amountToUnlock)
        internal
        view
        returns (uint256 amountToUser, int96 flowRateToStaker, int96 flowRateToLP)
    {
        (, uint256 lpAllocation) = _stakingRewardController.getTaxAllocation();

        uint256 totalPenaltyAmount = Math.mulDiv(amountToUnlock, _INSTANT_UNLOCK_PENALTY_BP, _BP_DENOMINATOR);
        amountToUser = amountToUnlock - totalPenaltyAmount;

        int96 totalPenaltyFlowRate = int256(totalPenaltyAmount / _TAX_DISTRIBUTION_FLOW_DURATION).toInt96();

        flowRateToLP = (totalPenaltyFlowRate * int256(lpAllocation).toInt96()) / int256(_BP_DENOMINATOR).toInt96();

        flowRateToStaker = totalPenaltyFlowRate - flowRateToLP;
    }

    function _helperCalculateFlowRatesVestUnlock(uint256 amountToUnlock, uint128 unlockPeriod)
        internal
        view
        returns (int96 stakerFlowRate, int96 providerFlowRate, int96 unlockFlowRate)
    {
        (uint256 userUnlockAmount, uint256 taxAmount) = calculateVestUnlockAmounts(amountToUnlock, unlockPeriod);

        unlockFlowRate = int256(userUnlockAmount / unlockPeriod).toInt96();

        int96 taxFlowRate = int256(taxAmount / _TAX_DISTRIBUTION_FLOW_DURATION).toInt96();

        // Calculate the tax allocation split between provider and staker
        (, uint256 providerAllocation) = _stakingRewardController.getTaxAllocation();

        providerFlowRate = (taxFlowRate * int256(providerAllocation).toInt96()) / int256(_BP_DENOMINATOR).toInt96();
        stakerFlowRate = taxFlowRate - providerFlowRate;
    }
}

contract FluidLockerTest is FluidLockerBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    function testInitialize(address owner) external virtual {
        vm.expectRevert();
        FluidLocker(payable(address(aliceLocker))).initialize(owner);
    }

    function testClaim(uint256 units) external virtual {
        units = bound(units, 1, 1_000_000);

        uint256 nonce = _programManager.getNextValidNonce(PROGRAM_0, ALICE);
        bytes memory signature = _helperGenerateSignature(signerPkey, ALICE, units, PROGRAM_0, nonce);

        vm.prank(ALICE);
        aliceLocker.claim(PROGRAM_0, units, nonce, signature);

        assertEq(programPools[0].getUnits(address(aliceLocker)), units, "units not updated");
        assertEq(aliceLocker.getUnitsPerProgram(PROGRAM_0), units, "getUnitsPerProgram invalid");

        int96 distributionFlowrate = _helperDistributeToProgramPool(PROGRAM_0, 1_000_000e18, _MAX_UNLOCK_PERIOD);

        assertEq(aliceLocker.getFlowRatePerProgram(PROGRAM_0), distributionFlowrate, "getFlowRatePerProgram invalid");
    }

    function testClaimBatch(uint256 units) external virtual {
        units = bound(units, 1, 1_000_000);

        uint256[] memory programIds = new uint256[](3);
        uint256[] memory newUnits = new uint256[](3);

        uint256 nonce;
        bytes memory signature;

        uint256[] memory distributionAmounts = new uint256[](3);
        uint256[] memory distributionPeriods = new uint256[](3);

        for (uint8 i = 0; i < 3; ++i) {
            programIds[i] = i + 1;
            newUnits[i] = units;
            nonce = _programManager.getNextValidNonce(programIds[i], ALICE) > nonce
                ? _programManager.getNextValidNonce(programIds[i], ALICE)
                : nonce;
            distributionAmounts[i] = 1_000_000e18;
            distributionPeriods[i] = _MAX_UNLOCK_PERIOD;
        }

        signature = _helperGenerateBatchSignature(signerPkey, ALICE, newUnits, programIds, nonce);

        vm.prank(ALICE);
        aliceLocker.claim(programIds, newUnits, nonce, signature);

        int96[] memory distributionFlowrates =
            _helperDistributeToProgramPool(programIds, distributionAmounts, distributionPeriods);

        uint128[] memory unitsPerProgram = aliceLocker.getUnitsPerProgram(programIds);
        int96[] memory flowratePerProgram = aliceLocker.getFlowRatePerProgram(programIds);

        for (uint8 i = 0; i < 3; ++i) {
            assertEq(newUnits[i], programPools[i].getUnits(address(aliceLocker)), "incorrect units amounts");
            assertEq(newUnits[i], unitsPerProgram[i], "getUnitsPerProgram invalid");
            assertEq(distributionFlowrates[i], flowratePerProgram[i], "getFlowRatePerProgram invalid");
        }
    }

    function testConnectToPool(uint256 units) external virtual {
        units = bound(units, 1, 1_000_000);

        uint256 nonce = _programManager.getNextValidNonce(PROGRAM_0, ALICE);
        bytes memory signature = _helperGenerateSignature(signerPkey, ALICE, units, PROGRAM_0, nonce);

        vm.prank(BOB);
        _programManager.updateUserUnits(ALICE, PROGRAM_0, units, nonce, signature);

        assertEq(programPools[0].getUnits(address(aliceLocker)), units, "units not updated");
        assertEq(aliceLocker.getUnitsPerProgram(PROGRAM_0), units, "getUnitsPerProgram invalid");

        int96 distributionFlowrate = _helperDistributeToProgramPool(PROGRAM_0, 1_000_000e18, _MAX_UNLOCK_PERIOD);

        assertEq(aliceLocker.getFlowRatePerProgram(PROGRAM_0), distributionFlowrate, "getFlowRatePerProgram invalid");

        vm.warp(block.timestamp + 5 days);
        assertEq(_fluid.balanceOf(address(aliceLocker)), 0, "invalid disconnect balance");

        vm.prank(BOB);
        vm.expectRevert(IFluidLocker.NOT_LOCKER_OWNER.selector);
        aliceLocker.connect(PROGRAM_0);

        vm.prank(ALICE);
        aliceLocker.connect(PROGRAM_0);

        assertEq(
            _fluid.balanceOf(address(aliceLocker)),
            uint256(uint96(distributionFlowrate) * 5 days),
            "invalid connected balance"
        );
    }

    function testDisconnectFromPool(uint256 units) external virtual {
        units = bound(units, 1, 1_000_000);

        uint256 nonce = _programManager.getNextValidNonce(PROGRAM_0, ALICE);
        bytes memory signature = _helperGenerateSignature(signerPkey, ALICE, units, PROGRAM_0, nonce);

        vm.prank(ALICE);
        aliceLocker.claim(PROGRAM_0, units, nonce, signature);

        assertEq(
            _fluid.isMemberConnected(address(programPools[0]), address(aliceLocker)),
            true,
            "Locker should be connected to pool"
        );

        vm.prank(BOB);
        vm.expectRevert(IFluidLocker.NOT_LOCKER_OWNER.selector);
        aliceLocker.disconnect(PROGRAM_0);

        vm.prank(ALICE);
        aliceLocker.disconnect(PROGRAM_0);

        assertEq(
            _fluid.isMemberConnected(address(programPools[0]), address(aliceLocker)),
            false,
            "Locker should be disconnected from pool"
        );
    }

    function testDisconnectFromPools(uint256 units) external virtual {
        units = bound(units, 1, 1_000_000);

        uint256 nonce0 = _programManager.getNextValidNonce(PROGRAM_0, ALICE);
        bytes memory signature0 = _helperGenerateSignature(signerPkey, ALICE, units, PROGRAM_0, nonce0);
        uint256 nonce1 = _programManager.getNextValidNonce(PROGRAM_1, ALICE);
        bytes memory signature1 = _helperGenerateSignature(signerPkey, ALICE, units, PROGRAM_1, nonce1);

        vm.prank(ALICE);
        aliceLocker.claim(PROGRAM_0, units, nonce0, signature0);
        aliceLocker.claim(PROGRAM_1, units, nonce1, signature1);

        assertEq(
            _fluid.isMemberConnected(address(programPools[0]), address(aliceLocker)),
            true,
            "Locker should be connected to pool"
        );

        assertEq(
            _fluid.isMemberConnected(address(programPools[1]), address(aliceLocker)),
            true,
            "Locker should be connected to pool"
        );

        uint256[] memory programIds = new uint256[](2);
        programIds[0] = PROGRAM_0;
        programIds[1] = PROGRAM_1;

        vm.prank(BOB);
        vm.expectRevert(IFluidLocker.NOT_LOCKER_OWNER.selector);
        aliceLocker.disconnect(programIds);

        vm.prank(ALICE);
        aliceLocker.disconnect(programIds);

        assertEq(
            _fluid.isMemberConnected(address(programPools[0]), address(aliceLocker)),
            false,
            "Locker should be disconnected from pool"
        );

        assertEq(
            _fluid.isMemberConnected(address(programPools[1]), address(aliceLocker)),
            false,
            "Locker should be disconnected from pool"
        );
    }

    function testDisconnectAndClaim(uint256 units) external virtual {
        units = bound(units, 1, 1_000_000);

        uint256 nonce0 = _programManager.getNextValidNonce(PROGRAM_0, ALICE);
        bytes memory signature0 = _helperGenerateSignature(signerPkey, ALICE, units, PROGRAM_0, nonce0);
        uint256 nonce1 = _programManager.getNextValidNonce(PROGRAM_1, ALICE);
        bytes memory signature1 = _helperGenerateSignature(signerPkey, ALICE, units, PROGRAM_1, nonce1);
        uint256 nonce2 = _programManager.getNextValidNonce(PROGRAM_2, ALICE);
        bytes memory signature2 = _helperGenerateSignature(signerPkey, ALICE, units, PROGRAM_2, nonce2);

        vm.prank(ALICE);
        aliceLocker.claim(PROGRAM_0, units, nonce0, signature0);
        aliceLocker.claim(PROGRAM_1, units, nonce1, signature1);

        assertEq(
            _fluid.isMemberConnected(address(programPools[0]), address(aliceLocker)),
            true,
            "Locker should be connected to pool"
        );

        assertEq(
            _fluid.isMemberConnected(address(programPools[1]), address(aliceLocker)),
            true,
            "Locker should be connected to pool"
        );

        assertEq(
            _fluid.isMemberConnected(address(programPools[2]), address(aliceLocker)),
            false,
            "Locker should be not be connected to pool"
        );

        uint256[] memory programIdsToDisconnect = new uint256[](2);
        programIdsToDisconnect[0] = PROGRAM_0;
        programIdsToDisconnect[1] = PROGRAM_1;

        uint256[] memory programIdsToClaim = new uint256[](1);
        programIdsToClaim[0] = PROGRAM_2;

        uint256[] memory totalProgramUnits = new uint256[](1);
        totalProgramUnits[0] = units;

        vm.prank(BOB);
        vm.expectRevert(IFluidLocker.NOT_LOCKER_OWNER.selector);
        aliceLocker.disconnectAndClaim(programIdsToDisconnect, programIdsToClaim, totalProgramUnits, nonce2, signature2);

        vm.prank(ALICE);
        aliceLocker.disconnectAndClaim(programIdsToDisconnect, programIdsToClaim, totalProgramUnits, nonce2, signature2);

        assertEq(
            _fluid.isMemberConnected(address(programPools[0]), address(aliceLocker)),
            false,
            "Locker should be disconnected from pool"
        );

        assertEq(
            _fluid.isMemberConnected(address(programPools[1]), address(aliceLocker)),
            false,
            "Locker should be disconnected from pool"
        );

        assertEq(
            _fluid.isMemberConnected(address(programPools[2]), address(aliceLocker)),
            true,
            "Locker should be connected to pool"
        );
    }

    function testLock(uint256 amount) external virtual {
        amount = bound(amount, 1, 1e24);
        assertEq(_fluidSuperToken.balanceOf(address(aliceLocker)), 0, "incorrect balance before operation");

        vm.startPrank(FLUID_TREASURY);
        _fluidSuperToken.approve(address(aliceLocker), amount);
        aliceLocker.lock(amount);
        vm.stopPrank();

        assertEq(_fluidSuperToken.balanceOf(address(aliceLocker)), amount, "incorrect balance after operation");
    }

    function testInstantUnlock(uint256 fundingAmount, uint256 unlockAmount, uint256 invalidUnlockAmount)
        external
        virtual
    {
        fundingAmount = bound(fundingAmount, 1 ether, 1_000_000e18);
        unlockAmount = bound(unlockAmount, 1, fundingAmount);
        vm.assume(invalidUnlockAmount > fundingAmount);

        _helperFundLocker(address(aliceLocker), fundingAmount);

        if (unlockAmount < FluidLocker(payable(address(aliceLocker))).MIN_UNLOCK_AMOUNT()) {
            vm.prank(ALICE);
            vm.expectRevert(IFluidLocker.INSUFFICIENT_UNLOCK_AMOUNT.selector);
            aliceLocker.unlock(unlockAmount, 0, ALICE);
        } else {
            vm.prank(ALICE);
            vm.expectRevert(IFluidLocker.STAKER_DISTRIBUTION_POOL_HAS_NO_UNITS.selector);
            aliceLocker.unlock(unlockAmount, 0, ALICE);

            _helperLockerStake(address(bobLocker));

            vm.prank(ALICE);
            vm.expectRevert(IFluidLocker.LP_DISTRIBUTION_POOL_HAS_NO_UNITS.selector);
            aliceLocker.unlock(unlockAmount, 0, ALICE);

            _helperLockerProvideLiquidity(address(carolLocker));

            uint256 aliceBalanceBefore = _fluidSuperToken.balanceOf(address(ALICE));
            uint256 lockerBalanceBefore = _fluidSuperToken.balanceOf(address(aliceLocker));

            vm.prank(BOB);
            vm.expectRevert(IFluidLocker.NOT_LOCKER_OWNER.selector);
            aliceLocker.unlock(unlockAmount, 0, ALICE);

            vm.startPrank(ALICE);
            vm.expectRevert(IFluidLocker.FORBIDDEN.selector);
            aliceLocker.unlock(unlockAmount, 0, address(0));

            vm.expectRevert(IFluidLocker.INSUFFICIENT_AVAILABLE_BALANCE.selector);
            aliceLocker.unlock(invalidUnlockAmount, 0, ALICE);

            aliceLocker.unlock(unlockAmount, 0, ALICE);
            vm.stopPrank();

            (uint256 amountToUser, int96 flowRateToStaker, int96 flowRateToLP) =
                _helperCalculateTaxDisitrutionInstantUnlock(unlockAmount);

            (, int96 actualLPFlowRate) = _fluid.estimateFlowDistributionActualFlowRate(
                address(_stakingRewardController), _stakingRewardController.lpDistributionPool(), flowRateToLP
            );

            (, int96 actualStakerFlowRate) = _fluid.estimateFlowDistributionActualFlowRate(
                address(_stakingRewardController), _stakingRewardController.taxDistributionPool(), flowRateToStaker
            );

            assertEq(
                _fluidSuperToken.balanceOf(address(ALICE)),
                aliceBalanceBefore + amountToUser,
                "incorrect ALICE balance after instant unlock"
            );

            assertEq(
                _fluidSuperToken.balanceOf(address(aliceLocker)),
                lockerBalanceBefore - unlockAmount,
                "incorrect Locker balance after instant unlock"
            );

            assertEq(
                _stakingRewardController.taxDistributionPool().getMemberFlowRate(address(bobLocker)),
                actualStakerFlowRate,
                "incorrect Bob Locker (staker) flow rate after instant unlock"
            );

            assertEq(
                _stakingRewardController.lpDistributionPool().getMemberFlowRate(address(carolLocker)),
                actualLPFlowRate,
                "incorrect Carol Locker (provider) flow rate after instant unlock"
            );
        }
    }

    function testVestUnlock(uint128 unlockPeriod, uint256 unlockAmount) external {
        unlockPeriod = uint128(bound(unlockPeriod, _MIN_UNLOCK_PERIOD, _MAX_UNLOCK_PERIOD));
        unlockAmount = bound(unlockAmount, 10e18, 100_000_000e18);
        _helperFundLocker(address(aliceLocker), unlockAmount);

        assertEq(_fluidSuperToken.balanceOf(address(aliceLocker)), unlockAmount, "incorrect Locker bal before op");
        assertEq(FluidLocker(payable(address(aliceLocker))).fontaineCount(), 0, "incorrect fontaine count");
        assertEq(
            address(FluidLocker(payable(address(aliceLocker))).fontaines(0)),
            address(IFontaine(address(0))),
            "incorrect fontaine address"
        );

        (int96 stakerFlowRate, int96 providerFlowRate, int96 unlockFlowRate) =
            _helperCalculateFlowRatesVestUnlock(unlockAmount, unlockPeriod);

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.STAKER_DISTRIBUTION_POOL_HAS_NO_UNITS.selector);
        aliceLocker.unlock(unlockAmount, unlockPeriod, ALICE);

        _helperLockerStake(address(bobLocker));

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.LP_DISTRIBUTION_POOL_HAS_NO_UNITS.selector);
        aliceLocker.unlock(unlockAmount, unlockPeriod, ALICE);

        _helperLockerProvideLiquidity(address(carolLocker));

        vm.prank(ALICE);
        aliceLocker.unlock(unlockAmount, unlockPeriod, ALICE);

        IFontaine newFontaine = FluidLocker(payable(address(aliceLocker))).fontaines(0);

        (, int96 actualStakerFlowRate) = _fluid.estimateFlowDistributionActualFlowRate(
            address(_stakingRewardController), _stakingRewardController.taxDistributionPool(), stakerFlowRate
        );
        (, int96 actualProviderFlowRate) = _fluid.estimateFlowDistributionActualFlowRate(
            address(_stakingRewardController), _stakingRewardController.lpDistributionPool(), providerFlowRate
        );

        assertEq(_fluidSuperToken.balanceOf(address(aliceLocker)), 0, "incorrect bal after op");
        assertApproxEqAbs(
            uint96(ISuperToken(_fluidSuperToken).getFlowRate(address(newFontaine), ALICE)),
            uint96(unlockFlowRate),
            uint96(unlockFlowRate * 10 / 10000),
            "incorrect unlock flowrate"
        );

        assertApproxEqAbs(
            uint96(_stakingRewardController.taxDistributionPool().getMemberFlowRate(address(bobLocker))),
            uint96(actualStakerFlowRate),
            uint96(actualStakerFlowRate * 10 / 10000),
            "incorrect staker flowrate"
        );

        assertApproxEqAbs(
            uint96(_stakingRewardController.lpDistributionPool().getMemberFlowRate(address(carolLocker))),
            uint96(actualProviderFlowRate),
            uint96(actualProviderFlowRate * 10 / 10000),
            "incorrect provider flowrate"
        );
    }

    function testInvalidUnlockPeriod(uint128 unlockPeriod) external virtual {
        uint256 funding = 10_000e18;
        _helperFundLocker(address(aliceLocker), funding);

        unlockPeriod = uint128(bound(unlockPeriod, 0 + 1, _MIN_UNLOCK_PERIOD - 1));
        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.INVALID_UNLOCK_PERIOD.selector);
        aliceLocker.unlock(funding, unlockPeriod, ALICE);

        unlockPeriod = uint128(bound(unlockPeriod, _MAX_UNLOCK_PERIOD + 1, 100_000 days));
        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.INVALID_UNLOCK_PERIOD.selector);
        aliceLocker.unlock(funding, unlockPeriod, ALICE);
    }

    function testStake(uint256 amountToStake1, uint256 amountToStake2) external virtual {
        amountToStake1 = bound(amountToStake1, 1, 100_000_000 ether);
        amountToStake2 = bound(amountToStake2, 1, 100_000_000 ether);
        _helperFundLocker(address(aliceLocker), amountToStake1);
        assertEq(_fluidSuperToken.balanceOf(address(aliceLocker)), amountToStake1, "incorrect Locker bal before op");
        assertEq(aliceLocker.getAvailableBalance(), amountToStake1, "incorrect available bal before op");
        assertEq(aliceLocker.getStakedBalance(), 0, "incorrect staked bal before op");

        vm.prank(ALICE);
        aliceLocker.stake(amountToStake1);

        assertEq(aliceLocker.getAvailableBalance(), 0, "incorrect available bal after op");
        assertEq(aliceLocker.getStakedBalance(), amountToStake1, "incorrect staked bal after op");
        assertEq(
            _stakingRewardController.taxDistributionPool().getUnits(address(aliceLocker)),
            amountToStake1 / _STAKING_UNIT_DOWNSCALER,
            "incorrect units"
        );

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.INSUFFICIENT_AVAILABLE_BALANCE.selector);
        aliceLocker.stake(amountToStake2);
    }

    function testUnstake(uint256 amountToStake, uint256 amountToUnstake, uint256 invalidAmountToUnstake)
        external
        virtual
    {
        amountToStake = bound(amountToStake, 1, 100_000_000 ether);
        vm.assume(amountToUnstake <= amountToStake);
        vm.assume(invalidAmountToUnstake > amountToStake);

        _helperFundLocker(address(aliceLocker), amountToStake);

        vm.startPrank(ALICE);
        aliceLocker.stake(amountToStake);

        assertEq(aliceLocker.getAvailableBalance(), 0, "incorrect available bal before op");
        assertEq(aliceLocker.getStakedBalance(), amountToStake, "incorrect staked bal before op");
        assertEq(
            _stakingRewardController.taxDistributionPool().getUnits(address(aliceLocker)),
            amountToStake / _STAKING_UNIT_DOWNSCALER,
            "incorrect units before op"
        );

        vm.expectRevert(IFluidLocker.STAKING_COOLDOWN_NOT_ELAPSED.selector);
        aliceLocker.unstake(amountToUnstake);

        vm.warp(uint256(FluidLocker(payable(address(aliceLocker))).stakingUnlocksAt()) + 1);
        aliceLocker.unstake(amountToUnstake);

        assertEq(aliceLocker.getAvailableBalance(), amountToUnstake, "incorrect available bal after op");
        assertEq(aliceLocker.getStakedBalance(), amountToStake - amountToUnstake, "incorrect staked bal after op");
        assertEq(
            _stakingRewardController.taxDistributionPool().getUnits(address(aliceLocker)),
            (amountToStake - amountToUnstake) / _STAKING_UNIT_DOWNSCALER,
            "incorrect units after op"
        );

        vm.expectRevert(IFluidLocker.INSUFFICIENT_STAKED_BALANCE.selector);
        aliceLocker.unstake(invalidAmountToUnstake);

        vm.stopPrank();
    }

    function testGetFontaineBeaconImplementation() external view virtual {
        assertEq(_fluidLockerLogic.getFontaineBeaconImplementation(), address(_fontaineLogic));
    }

    // Note: golden (characteristic) test
    function testGetUnlockingPercentage(uint128 unlockPeriod) public pure {
        unlockPeriod = uint128(bound(unlockPeriod, _MIN_UNLOCK_PERIOD, _MAX_UNLOCK_PERIOD));

        uint256 unlockPercentage = getUnlockingPercentage(unlockPeriod);
        assertGe(unlockPercentage, 3107, "shouldnt be any smaller");
        assertLe(unlockPercentage, 10_000, "shouldnt be any larger");

        // Test different periods
        assertEq(getUnlockingPercentage(7 days), 3107, "should be 3107");
        assertEq(getUnlockingPercentage(30 days), 4293, "should be 4293");
        assertEq(getUnlockingPercentage(90 days), 5972, "should be 5972");
        assertEq(getUnlockingPercentage(180 days), 7617, "should be 7617");
        assertEq(getUnlockingPercentage(365 days), 10_000, "should be 10000");
    }

    // Note: property based testing
    // Property: monotonicity of getUnlockingPercentage / "Punitive high-time preference law"
    function testGetUnlockingPercentageStrictMonotonicity(uint128 t1, uint128 t2) public pure {
        t1 = uint128(bound(t1, _MIN_UNLOCK_PERIOD, _MAX_UNLOCK_PERIOD));
        t2 = uint128(bound(t2, _MIN_UNLOCK_PERIOD, _MAX_UNLOCK_PERIOD));

        // Ensure `t1` is always lower than `t2`
        if (t1 > t2) (t1, t2) = (t2, t1);
        console2.log("using t1 t2", t1, t2);

        (uint256 p1, uint256 p2) = (getUnlockingPercentage(t1), getUnlockingPercentage(t2));
        assertLe(p1, p2, "monotonicity violated");
    }

    // Property : lower time-preference shall result in higher taxed amount and lower unlock amount
    function testCalculateVestUnlockFlowRates(uint128 t1, uint128 t2) public pure {
        uint256 amount = 1 ether;
        uint256 minDistance = 80 minutes;

        t1 = uint128(bound(t1, _MIN_UNLOCK_PERIOD, _MAX_UNLOCK_PERIOD - minDistance));
        t2 = uint128(bound(t2, t1 + minDistance, _MAX_UNLOCK_PERIOD));

        (uint256 userUnlockAmount1, uint256 taxAmount1) = calculateVestUnlockAmounts(amount, t1);
        (uint256 userUnlockAmount2, uint256 taxAmount2) = calculateVestUnlockAmounts(amount, t2);

        assertGe(userUnlockAmount2, userUnlockAmount1, "unlock amount monotonicity violated");
        assertGe(taxAmount1, taxAmount2, "tax amount monotonicity violated");
    }
}

// Note : this test the transition phase from non-unlockable to unlockable FluidLocker contract instances
contract FluidLockerTTETest is FluidLockerBaseTest {
    address internal _nonUnlockableLockerLogic;
    address internal _unlockableLockerLogic;

    function setUp() public override {
        super.setUp();

        // Deploy the non-unlockable Fluid Locker Implementation contract
        _nonUnlockableLockerLogic = address(
            new FluidLocker(
                _fluid,
                IEPProgramManager(address(_programManager)),
                IStakingRewardController(address(_stakingRewardController)),
                address(_fontaineLogic),
                !LOCKER_CAN_UNLOCK,
                _nonfungiblePositionManager,
                _pool,
                _swapRouter
            )
        );

        _unlockableLockerLogic = address(_fluidLockerLogic);
        UpgradeableBeacon beacon = _fluidLockerFactory.LOCKER_BEACON();

        vm.prank(ADMIN);
        beacon.upgradeTo(_nonUnlockableLockerLogic);
    }

    function testClaim(uint256 units) external {
        units = bound(units, 1, 1_000_000);

        uint256 nonce = _programManager.getNextValidNonce(PROGRAM_0, ALICE);
        bytes memory signature = _helperGenerateSignature(signerPkey, ALICE, units, PROGRAM_0, nonce);

        vm.prank(ALICE);
        aliceLocker.claim(PROGRAM_0, units, nonce, signature);

        assertEq(programPools[0].getUnits(address(aliceLocker)), units, "units not updated");
        assertEq(aliceLocker.getUnitsPerProgram(PROGRAM_0), units, "getUnitsPerProgram invalid");

        int96 distributionFlowrate = _helperDistributeToProgramPool(PROGRAM_0, 1_000_000e18, _MAX_UNLOCK_PERIOD);

        assertEq(aliceLocker.getFlowRatePerProgram(PROGRAM_0), distributionFlowrate, "getFlowRatePerProgram invalid");
    }

    function testClaimBatch(uint256 units) external {
        units = bound(units, 1, 1_000_000);

        uint256[] memory programIds = new uint256[](3);
        uint256[] memory newUnits = new uint256[](3);

        uint256 nonce;
        bytes memory signature;

        uint256[] memory distributionAmounts = new uint256[](3);
        uint256[] memory distributionPeriods = new uint256[](3);

        for (uint8 i = 0; i < 3; ++i) {
            programIds[i] = i + 1;
            newUnits[i] = units;
            nonce = _programManager.getNextValidNonce(programIds[i], ALICE) > nonce
                ? _programManager.getNextValidNonce(programIds[i], ALICE)
                : nonce;
            distributionAmounts[i] = 1_000_000e18;
            distributionPeriods[i] = _MAX_UNLOCK_PERIOD;
        }
        signature = _helperGenerateBatchSignature(signerPkey, ALICE, newUnits, programIds, nonce);

        vm.prank(ALICE);
        aliceLocker.claim(programIds, newUnits, nonce, signature);

        int96[] memory distributionFlowrates =
            _helperDistributeToProgramPool(programIds, distributionAmounts, distributionPeriods);

        uint128[] memory unitsPerProgram = aliceLocker.getUnitsPerProgram(programIds);
        int96[] memory flowratePerProgram = aliceLocker.getFlowRatePerProgram(programIds);

        for (uint8 i = 0; i < 3; ++i) {
            assertEq(newUnits[i], programPools[i].getUnits(address(aliceLocker)), "incorrect units amounts");
            assertEq(newUnits[i], unitsPerProgram[i], "getUnitsPerProgram invalid");
            assertEq(distributionFlowrates[i], flowratePerProgram[i], "getFlowRatePerProgram invalid");
        }
    }

    function testLock(uint256 amount) external {
        amount = bound(amount, 1, 1e24);
        assertEq(_fluidSuperToken.balanceOf(address(aliceLocker)), 0, "incorrect balance before operation");

        vm.startPrank(FLUID_TREASURY);
        _fluidSuperToken.approve(address(aliceLocker), amount);
        aliceLocker.lock(amount);
        vm.stopPrank();

        assertEq(_fluidSuperToken.balanceOf(address(aliceLocker)), amount, "incorrect balance after operation");
    }

    function testInstantUnlock(uint256 fundingAmount, uint256 unlockAmount, uint256 invalidUnlockAmount)
        external
        virtual
    {
        fundingAmount = bound(fundingAmount, 1 ether, 1_000_000e18);
        unlockAmount = bound(unlockAmount, 1, fundingAmount);
        vm.assume(invalidUnlockAmount > fundingAmount);

        uint128 instantUnlockPeriod = 0;

        _helperFundLocker(address(aliceLocker), fundingAmount);

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.TTE_NOT_ACTIVATED.selector);
        aliceLocker.unlock(unlockAmount, instantUnlockPeriod, ALICE);
        _helperUpgradeLocker();

        if (unlockAmount < FluidLocker(payable(address(aliceLocker))).MIN_UNLOCK_AMOUNT()) {
            vm.prank(ALICE);
            vm.expectRevert(IFluidLocker.INSUFFICIENT_UNLOCK_AMOUNT.selector);
            aliceLocker.unlock(unlockAmount, 0, ALICE);
        } else {
            vm.prank(ALICE);
            vm.expectRevert(IFluidLocker.STAKER_DISTRIBUTION_POOL_HAS_NO_UNITS.selector);
            aliceLocker.unlock(unlockAmount, instantUnlockPeriod, ALICE);

            _helperLockerStake(address(bobLocker));

            vm.prank(ALICE);
            vm.expectRevert(IFluidLocker.LP_DISTRIBUTION_POOL_HAS_NO_UNITS.selector);
            aliceLocker.unlock(unlockAmount, instantUnlockPeriod, ALICE);

            _helperLockerProvideLiquidity(address(carolLocker));

            uint256 aliceBalanceBefore = _fluidSuperToken.balanceOf(address(ALICE));
            uint256 lockerBalanceBefore = _fluidSuperToken.balanceOf(address(aliceLocker));

            vm.prank(BOB);
            vm.expectRevert(IFluidLocker.NOT_LOCKER_OWNER.selector);
            aliceLocker.unlock(unlockAmount, instantUnlockPeriod, ALICE);

            vm.startPrank(ALICE);
            vm.expectRevert(IFluidLocker.FORBIDDEN.selector);
            aliceLocker.unlock(unlockAmount, instantUnlockPeriod, address(0));

            vm.expectRevert(IFluidLocker.INSUFFICIENT_AVAILABLE_BALANCE.selector);
            aliceLocker.unlock(invalidUnlockAmount, instantUnlockPeriod, ALICE);

            aliceLocker.unlock(unlockAmount, instantUnlockPeriod, ALICE);
            vm.stopPrank();

            (uint256 amountToUser, int96 flowRateToStaker, int96 flowRateToLP) =
                _helperCalculateTaxDisitrutionInstantUnlock(unlockAmount);

            (, int96 actualLPFlowRate) = _fluid.estimateFlowDistributionActualFlowRate(
                address(_stakingRewardController), _stakingRewardController.lpDistributionPool(), flowRateToLP
            );

            (, int96 actualStakerFlowRate) = _fluid.estimateFlowDistributionActualFlowRate(
                address(_stakingRewardController), _stakingRewardController.taxDistributionPool(), flowRateToStaker
            );

            assertEq(
                _fluidSuperToken.balanceOf(address(ALICE)),
                aliceBalanceBefore + amountToUser,
                "incorrect ALICE balance after instant unlock"
            );

            assertEq(
                _fluidSuperToken.balanceOf(address(aliceLocker)),
                lockerBalanceBefore - unlockAmount,
                "incorrect Locker balance after instant unlock"
            );

            assertEq(
                _stakingRewardController.taxDistributionPool().getMemberFlowRate(address(bobLocker)),
                actualStakerFlowRate,
                "incorrect Bob Locker (staker) flow rate after instant unlock"
            );

            assertEq(
                _stakingRewardController.lpDistributionPool().getMemberFlowRate(address(carolLocker)),
                actualLPFlowRate,
                "incorrect Carol Locker (provider) flow rate after instant unlock"
            );
        }
    }

    function testVestUnlock(uint128 unlockPeriod, uint256 unlockAmount) external {
        unlockPeriod = uint128(bound(unlockPeriod, _MIN_UNLOCK_PERIOD, _MAX_UNLOCK_PERIOD));
        unlockAmount = bound(unlockAmount, 10e18, 100_000_000e18);
        _helperFundLocker(address(aliceLocker), unlockAmount);

        assertEq(_fluidSuperToken.balanceOf(address(aliceLocker)), unlockAmount, "incorrect Locker bal before op");
        assertEq(FluidLocker(payable(address(aliceLocker))).fontaineCount(), 0, "incorrect fontaine count");
        assertEq(
            address(FluidLocker(payable(address(aliceLocker))).fontaines(0)),
            address(IFontaine(address(0))),
            "incorrect fontaine address"
        );

        (int96 stakerFlowRate, int96 providerFlowRate, int96 unlockFlowRate) =
            _helperCalculateFlowRatesVestUnlock(unlockAmount, unlockPeriod);

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.TTE_NOT_ACTIVATED.selector);
        aliceLocker.unlock(unlockAmount, unlockPeriod, ALICE);

        _helperUpgradeLocker();

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.STAKER_DISTRIBUTION_POOL_HAS_NO_UNITS.selector);
        aliceLocker.unlock(unlockAmount, unlockPeriod, ALICE);

        _helperLockerStake(address(bobLocker));

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.LP_DISTRIBUTION_POOL_HAS_NO_UNITS.selector);
        aliceLocker.unlock(unlockAmount, unlockPeriod, ALICE);

        _helperLockerProvideLiquidity(address(carolLocker));

        vm.prank(ALICE);
        aliceLocker.unlock(unlockAmount, unlockPeriod, ALICE);

        IFontaine newFontaine = FluidLocker(payable(address(aliceLocker))).fontaines(0);

        (, int96 actualStakerFlowRate) = _fluid.estimateFlowDistributionActualFlowRate(
            address(_stakingRewardController), _stakingRewardController.taxDistributionPool(), stakerFlowRate
        );
        (, int96 actualProviderFlowRate) = _fluid.estimateFlowDistributionActualFlowRate(
            address(_stakingRewardController), _stakingRewardController.lpDistributionPool(), providerFlowRate
        );

        assertEq(_fluidSuperToken.balanceOf(address(aliceLocker)), 0, "incorrect bal after op");
        assertApproxEqAbs(
            uint96(ISuperToken(_fluidSuperToken).getFlowRate(address(newFontaine), ALICE)),
            uint96(unlockFlowRate),
            uint96(unlockFlowRate * 10 / 10000),
            "incorrect unlock flowrate"
        );
        assertApproxEqAbs(
            uint96(_stakingRewardController.taxDistributionPool().getMemberFlowRate(address(bobLocker))),
            uint96(actualStakerFlowRate),
            uint96(actualStakerFlowRate * 10 / 10000),
            "incorrect staker flowrate"
        );
        assertApproxEqAbs(
            uint96(_stakingRewardController.lpDistributionPool().getMemberFlowRate(address(carolLocker))),
            uint96(actualProviderFlowRate),
            uint96(actualProviderFlowRate * 10 / 10000),
            "incorrect provider flowrate"
        );
    }

    function testStake(uint256 amountToStake1, uint256 amountToStake2) external virtual {
        amountToStake1 = bound(amountToStake1, 1, 100_000_000 ether);
        amountToStake2 = bound(amountToStake2, 1, 100_000_000 ether);
        _helperFundLocker(address(aliceLocker), amountToStake1);
        assertEq(_fluidSuperToken.balanceOf(address(aliceLocker)), amountToStake1, "incorrect Locker bal before op");
        assertEq(aliceLocker.getAvailableBalance(), amountToStake1, "incorrect available bal before op");
        assertEq(aliceLocker.getStakedBalance(), 0, "incorrect staked bal before op");

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.TTE_NOT_ACTIVATED.selector);
        aliceLocker.stake(amountToStake1);

        _helperUpgradeLocker();

        vm.prank(ALICE);
        aliceLocker.stake(amountToStake1);

        assertEq(aliceLocker.getAvailableBalance(), 0, "incorrect available bal after op");
        assertEq(aliceLocker.getStakedBalance(), amountToStake1, "incorrect staked bal after op");
        assertEq(
            _stakingRewardController.taxDistributionPool().getUnits(address(aliceLocker)),
            amountToStake1 / _STAKING_UNIT_DOWNSCALER,
            "incorrect units"
        );

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.INSUFFICIENT_AVAILABLE_BALANCE.selector);
        aliceLocker.stake(amountToStake2);
    }

    function testUnstake(uint256 amountToStake, uint256 amountToUnstake, uint256 invalidAmountToUnstake)
        external
        virtual
    {
        amountToStake = bound(amountToStake, 1, 100_000_000 ether);
        vm.assume(amountToUnstake <= amountToStake);
        vm.assume(invalidAmountToUnstake > amountToStake);

        _helperFundLocker(address(aliceLocker), amountToStake);

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.TTE_NOT_ACTIVATED.selector);
        aliceLocker.unstake(amountToUnstake);

        _helperUpgradeLocker();

        vm.startPrank(ALICE);
        aliceLocker.stake(amountToStake);

        assertEq(aliceLocker.getAvailableBalance(), 0, "incorrect available bal before op");
        assertEq(aliceLocker.getStakedBalance(), amountToStake, "incorrect staked bal before op");
        assertEq(
            _stakingRewardController.taxDistributionPool().getUnits(address(aliceLocker)),
            amountToStake / _STAKING_UNIT_DOWNSCALER,
            "incorrect units before op"
        );

        vm.expectRevert(IFluidLocker.STAKING_COOLDOWN_NOT_ELAPSED.selector);
        aliceLocker.unstake(amountToUnstake);

        vm.warp(uint256(FluidLocker(payable(address(aliceLocker))).stakingUnlocksAt()) + 1);
        aliceLocker.unstake(amountToUnstake);

        assertEq(aliceLocker.getAvailableBalance(), amountToUnstake, "incorrect available bal after op");
        assertEq(aliceLocker.getStakedBalance(), amountToStake - amountToUnstake, "incorrect staked bal after op");
        assertEq(
            _stakingRewardController.taxDistributionPool().getUnits(address(aliceLocker)),
            (amountToStake - amountToUnstake) / _STAKING_UNIT_DOWNSCALER,
            "incorrect units after op"
        );

        vm.expectRevert(IFluidLocker.INSUFFICIENT_STAKED_BALANCE.selector);
        aliceLocker.unstake(invalidAmountToUnstake);

        vm.stopPrank();
    }

    // Note: golden (characteristic) test
    function testGetUnlockingPercentage(uint128 unlockPeriod) public pure {
        unlockPeriod = uint128(bound(unlockPeriod, _MIN_UNLOCK_PERIOD, _MAX_UNLOCK_PERIOD));

        uint256 unlockPercentage = getUnlockingPercentage(unlockPeriod);
        assertGe(unlockPercentage, 3107, "shouldnt be any smaller");
        assertLe(unlockPercentage, 10_000, "shouldnt be any larger");

        // Test different periods
        assertEq(getUnlockingPercentage(7 days), 3107, "should be 3107");
        assertEq(getUnlockingPercentage(30 days), 4293, "should be 4293");
        assertEq(getUnlockingPercentage(90 days), 5972, "should be 5972");
        assertEq(getUnlockingPercentage(180 days), 7617, "should be 7617");
        assertEq(getUnlockingPercentage(365 days), 10_000, "should be 10000");
    }

    // Note: property based testing
    // Property: monotonicity of getUnlockingPercentage / "Punitive high-time preference law"
    function testGetUnlockingPercentageStrictMonotonicity(uint128 t1, uint128 t2) public pure {
        t1 = uint128(bound(t1, _MIN_UNLOCK_PERIOD, _MAX_UNLOCK_PERIOD));
        t2 = uint128(bound(t2, _MIN_UNLOCK_PERIOD, _MAX_UNLOCK_PERIOD));

        // Ensure `t1` is always lower than `t2`
        if (t1 > t2) (t1, t2) = (t2, t1);
        console2.log("using t1 t2", t1, t2);

        (uint256 p1, uint256 p2) = (getUnlockingPercentage(t1), getUnlockingPercentage(t2));
        assertLe(p1, p2, "monotonicity violated");
    }

    /// Note: golden (characteristic) test
    function testCalculateVestUnlockFlowRatesCharacteristic() public pure {
        uint256 amount = 1 ether;

        // Test different periods
        (uint256 unlockAmount, uint256 taxAmount) = calculateVestUnlockAmounts(amount, 7 days);
        assertEq(unlockAmount, 310700000000000000, "(7 days) unlock amount should be 310700000000000000");
        assertEq(taxAmount, 689300000000000000, "(7 days) tax amount should be 689300000000000000");
        assertEq(unlockAmount + taxAmount, amount, "(7 days) unlock amount + tax amount should be equal to amount");

        (unlockAmount, taxAmount) = calculateVestUnlockAmounts(amount, 30 days);
        assertEq(unlockAmount, 429300000000000000, "(30 days) unlock amount should be 429300000000000000");
        assertEq(taxAmount, 570700000000000000, "(30 days) tax amount should be 570700000000000000");
        assertEq(unlockAmount + taxAmount, amount, "(30 days) unlock amount + tax amount should be equal to amount");

        (unlockAmount, taxAmount) = calculateVestUnlockAmounts(amount, 90 days);
        assertEq(unlockAmount, 597200000000000000, "(90 days) unlock amount should be 597200000000000000");
        assertEq(taxAmount, 402800000000000000, "(90 days) tax amount should be 402800000000000000");
        assertEq(unlockAmount + taxAmount, amount, "(90 days) unlock amount + tax amount should be equal to amount");

        (unlockAmount, taxAmount) = calculateVestUnlockAmounts(amount, 180 days);
        assertEq(unlockAmount, 761700000000000000, "(180 days) unlock amount should be 761700000000000000");
        assertEq(taxAmount, 238300000000000000, "(180 days) tax amount should be 238300000000000000");
        assertEq(unlockAmount + taxAmount, amount, "(180 days) unlock amount + tax amount should be equal to amount");

        (unlockAmount, taxAmount) = calculateVestUnlockAmounts(amount, 365 days);
        assertEq(unlockAmount, 1000000000000000000, "(365 days) unlock amount should be 1000000000000000000");
        assertEq(taxAmount, 0, "(365 days) tax amount should be 0");
        assertEq(unlockAmount + taxAmount, amount, "(365 days) unlock amount + tax amount should be equal to amount");
    }

    // Property : lower time-preference shall result in higher taxed amount and lower unlock amount
    function testCalculateVestUnlockFlowRates(uint128 t1, uint128 t2) public pure {
        uint256 amount = 1 ether;
        uint256 minDistance = 80 minutes;

        t1 = uint128(bound(t1, _MIN_UNLOCK_PERIOD, _MAX_UNLOCK_PERIOD - minDistance));
        t2 = uint128(bound(t2, t1 + minDistance, _MAX_UNLOCK_PERIOD));

        console2.log("using t1 t2", t1, t2);

        (uint256 userUnlockAmount1, uint256 taxAmount1) = calculateVestUnlockAmounts(amount, t1);
        (uint256 userUnlockAmount2, uint256 taxAmount2) = calculateVestUnlockAmounts(amount, t2);
        assertGe(userUnlockAmount2, userUnlockAmount1, "unlock amount monotonicity violated");
        assertGe(taxAmount1, taxAmount2, "tax amount monotonicity violated");
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    //      ________      _     ____               __                _    _____      ______          __
    //     / ____/ /_  __(_)___/ / /   ____  _____/ /_____  _____   | |  / /__ \    /_  __/__  _____/ /______
    //    / /_  / / / / / / __  / /   / __ \/ ___/ //_/ _ \/ ___/   | | / /__/ /     / / / _ \/ ___/ __/ ___/
    //   / __/ / / /_/ / / /_/ / /___/ /_/ / /__/ ,< /  __/ /       | |/ // __/     / / /  __(__  ) /_(__  )
    //  /_/   /_/\__,_/_/\__,_/_____/\____/\___/_/|_|\___/_/        |___//____/    /_/  \___/____/\__/____/

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // 1 eth contribution :
    // -> 0.01 eth to pump -> expected min sup = 0.01 * 20000 = 200 sup
    // -> 0.99 eth to lp -> expected supLPAmount = 0.99 * 20000 = 19800 sup
    function testV2ProvideLiquidity_createPosition(uint256 ethAmount) external {
        ethAmount = bound(ethAmount, 0.001 ether, 1000 ether);
        _helperUpgradeLocker();

        uint256 supAmountToLP = ethAmount * 20_000 * 9900 / 10_000;

        _helperFundLocker(address(aliceLocker), supAmountToLP);

        vm.startPrank(ALICE);
        aliceLocker.provideLiquidity{ value: ethAmount }(supAmountToLP);
        vm.stopPrank();

        uint256 positionCount = FluidLocker(payable(address(aliceLocker))).activePositionCount();
        assertEq(positionCount, 1, "position count should be 1");
        assertGt(
            _nonfungiblePositionManager.tokenOfOwnerByIndex(address(aliceLocker), positionCount - 1),
            0,
            "tokenId should not be 0"
        );
        assertEq(_weth.balanceOf(address(aliceLocker)), 0, "weth locker balance should be 0");
    }

    function testV2CollectFees() external {
        _helperUpgradeLocker();
        uint256 positionTokenId = _helperCreatePosition(address(aliceLocker), 1 ether, 20_000e18);

        uint256 aliceWethBalanceBefore = _weth.balanceOf(address(ALICE));
        uint256 aliceSupBalanceBefore = _fluidSuperToken.balanceOf(address(ALICE));

        _helperBuySUP(makeAddr("buyer"), 10 ether);
        _helperSellSUP(makeAddr("seller"), 200_000e18);

        vm.prank(ALICE);
        aliceLocker.collectFees(positionTokenId);

        uint256 aliceWethBalanceAfter = _weth.balanceOf(address(ALICE));
        uint256 aliceSupBalanceAfter = _fluidSuperToken.balanceOf(address(ALICE));

        assertGt(aliceWethBalanceAfter, aliceWethBalanceBefore, "alice weth balance should increase");
        assertGt(aliceSupBalanceAfter, aliceSupBalanceBefore, "alice sup balance should increase");
    }

    function testV2withdrawLiquidity_removeAllLiquidity_beforeTaxFreeWithdrawDelay(uint256 ethAmountToDeposit)
        external
    {
        ethAmountToDeposit = bound(ethAmountToDeposit, 0.001 ether, 1000 ether);
        _helperUpgradeLocker();

        uint256 supAmountToLP = ethAmountToDeposit * 20_000 * 9900 / 10_000;
        uint256 positionTokenId = _helperCreatePosition(address(aliceLocker), ethAmountToDeposit, supAmountToLP);

        _helperSellSUP(makeAddr("seller"), 200_000e18);

        (,,,,,,, uint128 positionLiquidity,,,,) = _nonfungiblePositionManager.positions(positionTokenId);
        (uint256 amount0ToRemove, uint256 amount1ToRemove) = _helperGetAmountsForLiquidity(_pool, positionLiquidity);

        uint256 expectedEthReceived = _pool.token0() == address(_weth) ? amount0ToRemove : amount1ToRemove;
        uint256 expectedSupBackInLocker =
            _pool.token0() == address(_fluidSuperToken) ? amount0ToRemove : amount1ToRemove;

        uint256 ethBalanceBefore = ALICE.balance;
        uint256 supInLockerBefore = _fluidSuperToken.balanceOf(address(aliceLocker));

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.LP_COOLDOWN_NOT_ELAPSED.selector);
        aliceLocker.withdrawLiquidity(positionTokenId, positionLiquidity, amount0ToRemove, amount1ToRemove);

        vm.warp(uint256(FluidLocker(payable(address(aliceLocker))).lpCooldownTimestamps(positionTokenId)));
        vm.prank(ALICE);
        aliceLocker.withdrawLiquidity(positionTokenId, positionLiquidity, amount0ToRemove, amount1ToRemove);

        uint256 ethBalanceAfter = ALICE.balance;
        uint256 supInLockerAfter = _fluidSuperToken.balanceOf(address(aliceLocker));

        assertApproxEqAbs(
            ethBalanceAfter,
            ethBalanceBefore + expectedEthReceived,
            ethBalanceAfter * 10 / 10_000, // 0.1% tolerance
            "Alice ETH balance should increase"
        );
        assertApproxEqAbs(
            supInLockerAfter,
            supInLockerBefore + expectedSupBackInLocker,
            supInLockerAfter * 10 / 10_000, // 0.1% tolerance
            "SUP balance in locker should increase"
        );

        assertEq(FluidLocker(payable(address(aliceLocker))).activePositionCount(), 0, "position count should be 0");
        assertEq(
            FluidLocker(payable(address(aliceLocker))).taxFreeExitTimestamps(positionTokenId),
            0,
            "position exit timestamp should be 0"
        );
    }

    function testV2withdrawLiquidity_removePartialLiquidity(uint256 ethAmountToDeposit, uint256 liquidityPercentage)
        external
    {
        ethAmountToDeposit = bound(ethAmountToDeposit, 0.001 ether, 1000 ether);
        _helperUpgradeLocker();

        uint256 supAmountToLP = ethAmountToDeposit * 20_000 * 9900 / 10_000;
        uint256 positionTokenId = _helperCreatePosition(address(aliceLocker), ethAmountToDeposit, supAmountToLP);

        uint256 initialTaxFreeExitTimestamp =
            FluidLocker(payable(address(aliceLocker))).taxFreeExitTimestamps(positionTokenId);

        _helperBuySUP(makeAddr("buyer"), 10 ether);
        _helperSellSUP(makeAddr("seller"), 200_000e18);

        (,,,,,,, uint128 positionLiquidity,,,,) = _nonfungiblePositionManager.positions(positionTokenId);

        // Randomized partial liquidity removal : 1% to 99% of the liquidity
        liquidityPercentage = uint256(bound(liquidityPercentage, 100, 9900));

        uint128 liquidityToRemove = uint128((positionLiquidity * liquidityPercentage) / _BP_DENOMINATOR);

        (uint256 amount0ToRemove, uint256 amount1ToRemove) = _helperGetAmountsForLiquidity(_pool, liquidityToRemove);

        uint256 expectedWethReceived = _pool.token0() == address(_weth) ? amount0ToRemove : amount1ToRemove;
        uint256 expectedSupBackInLocker =
            _pool.token0() == address(_fluidSuperToken) ? amount0ToRemove : amount1ToRemove;

        uint256 ethBalanceBefore = ALICE.balance;
        uint256 supInLockerBefore = _fluidSuperToken.balanceOf(address(aliceLocker));

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.LP_COOLDOWN_NOT_ELAPSED.selector);
        aliceLocker.withdrawLiquidity(positionTokenId, liquidityToRemove, amount0ToRemove, amount1ToRemove);

        vm.warp(uint256(FluidLocker(payable(address(aliceLocker))).lpCooldownTimestamps(positionTokenId)));
        vm.prank(ALICE);
        aliceLocker.withdrawLiquidity(positionTokenId, liquidityToRemove, amount0ToRemove, amount1ToRemove);

        uint256 ethBalanceAfter = ALICE.balance;
        uint256 supInLockerAfter = _fluidSuperToken.balanceOf(address(aliceLocker));

        // Eq because of the fees are accounted in WETH
        assertApproxEqAbs(
            ethBalanceAfter,
            ethBalanceBefore + expectedWethReceived,
            ethBalanceAfter * 10 / 1000,
            "WETH balance should increase"
        );

        // Eq because the fees are collected in the locker owner address
        assertApproxEqAbs(
            supInLockerAfter,
            supInLockerBefore + expectedSupBackInLocker,
            supInLockerAfter * 10 / 10_000, // 0.1% tolerance
            "SUP balance in locker should increase"
        );
        assertEq(
            FluidLocker(payable(address(aliceLocker))).activePositionCount(), 1, "position count should still be 1"
        );
        assertEq(
            FluidLocker(payable(address(aliceLocker))).taxFreeExitTimestamps(positionTokenId),
            initialTaxFreeExitTimestamp,
            "position exit timestamp should remain the same"
        );
    }

    function testV2withdrawLiquidity_removeAllLiquidity_afterTaxFreeWithdrawDelay(uint256 ethAmountToDeposit)
        external
    {
        ethAmountToDeposit = bound(ethAmountToDeposit, 0.001 ether, 1000 ether);
        _helperUpgradeLocker();

        uint256 supAmountToLP = ethAmountToDeposit * 20_000 * 9900 / 10_000;
        uint256 positionTokenId = _helperCreatePosition(address(aliceLocker), ethAmountToDeposit, supAmountToLP);

        _helperSellSUP(makeAddr("seller"), 200_000e18);

        (,,,,,,, uint128 positionLiquidity,,,,) = _nonfungiblePositionManager.positions(positionTokenId);
        (uint256 amount0ToRemove, uint256 amount1ToRemove) = _helperGetAmountsForLiquidity(_pool, positionLiquidity);

        uint256 expectedEthReceived = _pool.token0() == address(_weth) ? amount0ToRemove : amount1ToRemove;
        uint256 expectedSupBack = _pool.token0() == address(_fluidSuperToken) ? amount0ToRemove : amount1ToRemove;

        uint256 ethBalanceBefore = ALICE.balance;
        uint256 supInLockerBefore = _fluidSuperToken.balanceOf(address(aliceLocker));
        uint256 supInAliceBefore = _fluidSuperToken.balanceOf(address(ALICE));

        vm.warp(block.timestamp + FluidLocker(payable(address(aliceLocker))).TAX_FREE_WITHDRAW_DELAY());

        vm.prank(ALICE);
        aliceLocker.withdrawLiquidity(positionTokenId, positionLiquidity, amount0ToRemove, amount1ToRemove);

        uint256 ethBalanceAfter = ALICE.balance;
        uint256 supInLockerAfter = _fluidSuperToken.balanceOf(address(aliceLocker));
        uint256 supInAliceAfter = _fluidSuperToken.balanceOf(address(ALICE));

        assertApproxEqAbs(
            ethBalanceAfter,
            ethBalanceBefore + expectedEthReceived,
            ethBalanceAfter * 10 / 10_000, // 0.1% tolerance
            "Alice ETH balance should increase"
        );
        assertApproxEqAbs(
            supInAliceAfter,
            supInAliceBefore + expectedSupBack,
            supInAliceAfter * 10 / 10_000, // 0.1% tolerance
            "SUP balance in Alice wallet should increase"
        );

        assertEq(supInLockerAfter, supInLockerBefore, "SUP balance in locker should not change");
        assertEq(FluidLocker(payable(address(aliceLocker))).activePositionCount(), 0, "position count should be 0");
    }

    function testV2withdrawLiquidity_removeAllLiquidity_withFeeInPosition(uint256 ethAmountToDeposit) external {
        ethAmountToDeposit = bound(ethAmountToDeposit, 0.001 ether, 1000 ether);
        _helperUpgradeLocker();

        uint256 supAmountToLP = ethAmountToDeposit * 20_000 * 9900 / 10_000;
        uint256 positionTokenId = _helperCreatePosition(address(aliceLocker), ethAmountToDeposit, supAmountToLP);

        _helperBuySUP(makeAddr("buyer"), 10 ether);
        _helperSellSUP(makeAddr("seller"), 200_000e18);

        (,,,,,,, uint128 positionLiquidity,,,,) = _nonfungiblePositionManager.positions(positionTokenId);
        (uint256 amount0ToRemove, uint256 amount1ToRemove) = _helperGetAmountsForLiquidity(_pool, positionLiquidity);

        uint256 expectedEthReceived = _pool.token0() == address(_weth) ? amount0ToRemove : amount1ToRemove;
        uint256 expectedSupBack = _pool.token0() == address(_fluidSuperToken) ? amount0ToRemove : amount1ToRemove;

        uint256 ethBalanceBefore = ALICE.balance;
        uint256 supInLockerBefore = _fluidSuperToken.balanceOf(address(aliceLocker));
        uint256 supInAliceBefore = _fluidSuperToken.balanceOf(address(ALICE));

        vm.warp(block.timestamp + FluidLocker(payable(address(aliceLocker))).TAX_FREE_WITHDRAW_DELAY());

        vm.prank(ALICE);
        aliceLocker.withdrawLiquidity(positionTokenId, positionLiquidity, amount0ToRemove, amount1ToRemove);

        uint256 ethBalanceAfter = ALICE.balance;
        uint256 supInLockerAfter = _fluidSuperToken.balanceOf(address(aliceLocker));
        uint256 supInAliceAfter = _fluidSuperToken.balanceOf(address(ALICE));

        assertApproxEqAbs(
            ethBalanceAfter,
            ethBalanceBefore + expectedEthReceived,
            ethBalanceAfter * 10 / 10_000, // 0.1% tolerance
            "Alice ETH balance should increase"
        );
        assertApproxEqAbs(
            supInAliceAfter,
            supInAliceBefore + expectedSupBack,
            supInAliceAfter * 10 / 10_000, // 0.1% tolerance
            "SUP balance in Alice wallet should increase"
        );

        assertEq(supInLockerAfter, supInLockerBefore, "SUP balance in locker should not change");
        assertEq(FluidLocker(payable(address(aliceLocker))).activePositionCount(), 0, "position count should be 0");
    }

    function testV2withdrawLiquidity_removePartialLiquidity_beforeAndAfterTaxFreeWithdrawDelay(
        uint256 ethAmountToDeposit,
        uint256 liquidityPercentage
    ) external {
        ethAmountToDeposit = bound(ethAmountToDeposit, 0.001 ether, 1000 ether);
        _helperUpgradeLocker();

        uint256 supAmountToLP = ethAmountToDeposit * 20_000 * 9900 / 10_000;
        uint256 positionTokenId = _helperCreatePosition(address(aliceLocker), ethAmountToDeposit, supAmountToLP);

        _helperBuySUP(makeAddr("buyer"), 10 ether);
        _helperSellSUP(makeAddr("seller"), 200_000e18);

        (,,,,,,, uint128 positionLiquidity,,,,) = _nonfungiblePositionManager.positions(positionTokenId);

        // Randomized partial liquidity removal : 1% to 99% of the liquidity
        liquidityPercentage = uint256(bound(liquidityPercentage, 100, 9900));

        uint128 liquidityToRemove = uint128((positionLiquidity * liquidityPercentage) / _BP_DENOMINATOR);

        (uint256 amount0ToRemove, uint256 amount1ToRemove) = _helperGetAmountsForLiquidity(_pool, liquidityToRemove);

        uint256 expectedEthReceived = _pool.token0() == address(_weth) ? amount0ToRemove : amount1ToRemove;
        uint256 expectedSupBack = _pool.token0() == address(_fluidSuperToken) ? amount0ToRemove : amount1ToRemove;

        uint256 ethBalanceBefore = ALICE.balance;
        uint256 supInLockerBefore = _fluidSuperToken.balanceOf(address(aliceLocker));

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.LP_COOLDOWN_NOT_ELAPSED.selector);
        aliceLocker.withdrawLiquidity(positionTokenId, liquidityToRemove, amount0ToRemove, amount1ToRemove);

        vm.warp(uint256(FluidLocker(payable(address(aliceLocker))).lpCooldownTimestamps(positionTokenId)));
        vm.prank(ALICE);
        aliceLocker.withdrawLiquidity(positionTokenId, liquidityToRemove, amount0ToRemove, amount1ToRemove);

        uint256 ethBalanceAfter = ALICE.balance;
        uint256 supInLockerAfter = _fluidSuperToken.balanceOf(address(aliceLocker));

        // Eq because the fees are collected in the locker owner address
        assertApproxEqAbs(
            ethBalanceAfter,
            ethBalanceBefore + expectedEthReceived,
            ethBalanceAfter * 10 / 1000,
            "WETH balance should increase"
        );

        // Eq because the fees are collected in the locker owner address
        assertApproxEqAbs(
            supInLockerAfter,
            supInLockerBefore + expectedSupBack,
            supInLockerAfter * 10 / 10_000, // 0.1% tolerance
            "SUP balance in locker should increase"
        );

        (,,,,,,, positionLiquidity,,,,) = _nonfungiblePositionManager.positions(positionTokenId);

        (amount0ToRemove, amount1ToRemove) = _helperGetAmountsForLiquidity(_pool, positionLiquidity);

        expectedEthReceived = _pool.token0() == address(_weth) ? amount0ToRemove : amount1ToRemove;
        expectedSupBack = _pool.token0() == address(_fluidSuperToken) ? amount0ToRemove : amount1ToRemove;

        ethBalanceBefore = ALICE.balance;
        supInLockerBefore = _fluidSuperToken.balanceOf(address(aliceLocker));
        uint256 supInAliceBefore = _fluidSuperToken.balanceOf(address(ALICE));

        vm.warp(block.timestamp + FluidLocker(payable(address(aliceLocker))).TAX_FREE_WITHDRAW_DELAY());

        vm.prank(ALICE);
        aliceLocker.withdrawLiquidity(positionTokenId, positionLiquidity, amount0ToRemove, amount1ToRemove);

        ethBalanceAfter = ALICE.balance;
        supInLockerAfter = _fluidSuperToken.balanceOf(address(aliceLocker));
        uint256 supInAliceAfter = _fluidSuperToken.balanceOf(address(ALICE));

        assertApproxEqAbs(
            ethBalanceAfter,
            ethBalanceBefore + expectedEthReceived,
            ethBalanceAfter * 10 / 10_000,
            "ETH balance should increase after tax free withdraw"
        );
        assertEq(supInLockerAfter, supInLockerBefore, "SUP balance in locker should not change after tax free withdraw");
        assertApproxEqAbs(
            supInAliceAfter,
            supInAliceBefore + expectedSupBack,
            supInAliceAfter * 10 / 10_000,
            "SUP balance in Alice wallet should increase after tax free withdraw"
        );
        assertEq(FluidLocker(payable(address(aliceLocker))).activePositionCount(), 0, "position count should be 0");
    }

    function testV2withdrawLiquidity_lockerHasNoPosition(uint256 inexistantPositionTokenId) external {
        _helperUpgradeLocker();

        uint128 positionLiquidity = 1e18;
        (uint256 amount0ToRemove, uint256 amount1ToRemove) = _helperGetAmountsForLiquidity(_pool, positionLiquidity);

        vm.prank(ALICE);
        vm.expectRevert(IFluidLocker.LOCKER_HAS_NO_POSITION.selector);
        aliceLocker.withdrawLiquidity(inexistantPositionTokenId, positionLiquidity, amount0ToRemove, amount1ToRemove);
    }

    function testV2withdrawDustETH(address _nonLockerOwner, uint256 ethAmount) external {
        vm.assume(_nonLockerOwner != ALICE);
        ethAmount = uint256(bound(ethAmount, 1, 1_000_000_000 ether));

        _helperUpgradeLocker();

        vm.deal(address(aliceLocker), ethAmount);

        vm.prank(_nonLockerOwner);
        vm.expectRevert(IFluidLocker.NOT_LOCKER_OWNER.selector);
        aliceLocker.withdrawDustETH();

        uint256 ethBalanceBefore = ALICE.balance;
        vm.prank(ALICE);
        aliceLocker.withdrawDustETH();
        uint256 ethBalanceAfter = ALICE.balance;

        assertEq(ethBalanceAfter, ethBalanceBefore + ethAmount, "ETH balance in ALICE walletshould increase");
    }

    function testV2provideLiquidityWhileStaking() external virtual {
        uint256 fundingAmount = 100e18;

        _helperUpgradeLocker();

        // Set up Alice's Locker to be functional
        _helperFundLocker(address(aliceLocker), fundingAmount);

        vm.startPrank(ALICE);

        //Stake all avaialble tokens
        aliceLocker.stake(fundingAmount);

        //Provide liquidity using the staked tokens (should revert)
        vm.expectRevert(IFluidLocker.INSUFFICIENT_AVAILABLE_BALANCE.selector);
        aliceLocker.provideLiquidity{ value: fundingAmount / (2 * 9900) }(100e18);

        vm.warp(block.timestamp + _STAKING_COOLDOWN_PERIOD + 1);

        // Unstake all staked tokens
        aliceLocker.unstake(aliceLocker.getStakedBalance());

        // Provide liquidity using the freshly unstaked tokens
        aliceLocker.provideLiquidity{ value: fundingAmount / (2 * 9900) }(100e18);
        vm.stopPrank();
    }

    function _helperUpgradeLocker() internal {
        UpgradeableBeacon beacon = _fluidLockerFactory.LOCKER_BEACON();

        vm.prank(ADMIN);
        beacon.upgradeTo(_unlockableLockerLogic);
    }
}

contract FluidLockerLayoutTest is FluidLocker {
    constructor()
        FluidLocker(
            ISuperToken(address(0)),
            IEPProgramManager(address(0)),
            IStakingRewardController(address(0)),
            address(0),
            true,
            INonfungiblePositionManager(address(0)),
            IUniswapV3Pool(address(0)),
            IV3SwapRouter(address(0))
        )
    { }

    // function testStorageLayout() external pure {
    //     uint256 slot;
    //     uint256 offset;

    //     // FluidLocker storage

    //     assembly {
    //         slot := lockerOwner.slot
    //         offset := lockerOwner.offset
    //     }
    //     require(slot == 0 && offset == 0, "lockerOwner changed location");

    //     assembly {
    //         slot := stakingUnlocksAt.slot
    //         offset := stakingUnlocksAt.offset
    //     }
    //     require(slot == 0 && offset == 20, "stakingUnlocksAt changed location");

    //     assembly {
    //         slot := fontaineCount.slot
    //         offset := fontaineCount.offset
    //     }
    //     require(slot == 0 && offset == 30, "fontaineCount changed location");

    //     // private state : _stakedBalance
    //     // slot = 1 - offset = 0

    //     assembly {
    //         slot := fontaines.slot
    //         offset := fontaines.offset
    //     }
    //     require(slot == 2 && offset == 0, "fontaines changed location");
    // }
}
