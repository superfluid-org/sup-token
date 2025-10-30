// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";

/* Superfluid Protocol Contracts & Interfaces */
import {
    ISuperToken,
    ISuperfluidPool
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {
    MacroForwarder,
    IUserDefinedMacro
} from "@superfluid-finance/ethereum-contracts/contracts/utils/MacroForwarder.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

import { FluidEPProgramManager } from "src/FluidEPProgramManager.sol";
import { IFluidLocker } from "src/FluidLocker.sol";
import { FluidLockerFactory } from "src/FluidLockerFactory.sol";
import { StakingRewardController, IStakingRewardController } from "src/StakingRewardController.sol";
import { Fontaine } from "src/Fontaine.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IEPProgramManager } from "src/interfaces/IEPProgramManager.sol";
import { FluidLocker } from "src/FluidLocker.sol";

/* Uniswap V3 Interfaces */
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

using ECDSA for bytes32;
using SafeCast for int256;
using SuperTokenV1Library for ISuperToken;

contract ProdForkTestSip8 is Test {
    ISuperToken internal _sup;
    FluidEPProgramManager internal _programManager;
    FluidLockerFactory internal _fluidLockerFactory;
    StakingRewardController internal _stakingRewardController;
    MacroForwarder internal _macroForwarder;
    UpgradeableBeacon internal _lockerBeacon;
    UpgradeableBeacon internal _fontaineBeacon;

    IFluidLocker internal _aliceLocker;
    IFluidLocker internal _existingLocker;

    uint96 internal constant _SIGNER_PKEY = 69_420;
    address internal constant _DAO_MULTISIG = 0xac808840f02c47C05507f48165d2222FF28EF4e1;
    address internal constant _ALICE = address(0x1);
    address internal constant _EXISTING_LOCKER_OWNER = 0xe55f0EDD723d574B147481e7Ec5cC98abce2b70b;
    address internal constant _DEPLOYER = 0x011E5Ee334F9af11c631B362f1E0cbab4E15642a;

    uint256 internal constant _SUBSIDY_AMOUNT = 1_000_000 ether;
    uint256 internal constant _TAX_DISTRIBUTION_FLOW_DURATION = 180 days;

    INonfungiblePositionManager internal _nonfungiblePositionManager;
    IV3SwapRouter internal _swapRouter;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 36000000);

        _sup = ISuperToken(0xa69f80524381275A7fFdb3AE01c54150644c8792);
        _programManager = FluidEPProgramManager(0x1e32cf099992E9D3b17eDdDFFfeb2D07AED95C6a);
        _fluidLockerFactory = FluidLockerFactory(0xA6694cAB43713287F7735dADc940b555db9d39D9);
        _stakingRewardController = StakingRewardController(0xb19Ae25A98d352B36CED60F93db926247535048b);
        _macroForwarder = MacroForwarder(0xFD0268E33111565dE546af2675351A4b1587F89F);
        _lockerBeacon = UpgradeableBeacon(0x664161f0974F5B17FB1fD3FDcE5D1679E829176c);
        _fontaineBeacon = UpgradeableBeacon(0xA26FbA47Da24F7DF11b3E4CF60Dcf7D1691Ae47d);
        _nonfungiblePositionManager = INonfungiblePositionManager(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);
        _swapRouter = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);

        vm.prank(_ALICE);
        _aliceLocker = IFluidLocker(_fluidLockerFactory.createLockerContract());
        _existingLocker = IFluidLocker(0x70a6B51C8CE04a216F4875A6447d24F9A7782C6C);

        _deploySIP8();
    }

    function testStake() public {
        _stake();
    }

    function testUnstake() public {
        _stake();

        uint256 stakingUnlocksAt = FluidLocker(payable(address(_existingLocker))).stakingUnlocksAt();

        vm.warp(stakingUnlocksAt - 1);
        vm.prank(_EXISTING_LOCKER_OWNER);
        vm.expectRevert(IFluidLocker.STAKING_COOLDOWN_NOT_ELAPSED.selector);
        _existingLocker.unstake(10_000 ether);

        vm.warp(stakingUnlocksAt + 1);
        vm.prank(_EXISTING_LOCKER_OWNER);
        _existingLocker.unstake(10_000 ether);

        assertEq(_existingLocker.getStakedBalance(), 0, "incorrect staked balance after op");
        assertEq(
            _stakingRewardController.taxDistributionPool().getUnits(address(_existingLocker)),
            0,
            "incorrect units after op"
        );
        assertEq(
            int256(_stakingRewardController.taxDistributionPool().getMemberFlowRate(address(_existingLocker))),
            int256(0),
            "incorrect flow rate after op"
        );
    }

    function testUnlock_shouldRevert(uint128 unlockPeriod) public {
        unlockPeriod = uint128(bound(unlockPeriod, 0, 365 days));

        vm.startPrank(_EXISTING_LOCKER_OWNER);
        vm.expectRevert(IFluidLocker.TTE_NOT_ACTIVATED.selector);
        _existingLocker.unlock(10_000 ether, unlockPeriod, _EXISTING_LOCKER_OWNER);

        vm.stopPrank();
    }

    function testProvideLiquidity_shouldRevert() public {
        vm.startPrank(_EXISTING_LOCKER_OWNER);
        vm.expectRevert(IFluidLocker.TTE_NOT_ACTIVATED.selector);
        _existingLocker.provideLiquidity{ value: 0.0001 ether }(10_000 ether);
        vm.stopPrank();
    }

    function testWithdrawLiquidity_shouldRevert() public {
        vm.startPrank(_EXISTING_LOCKER_OWNER);
        vm.expectRevert(IFluidLocker.TTE_NOT_ACTIVATED.selector);
        _existingLocker.withdrawLiquidity(1, 1, 1, 1);
        vm.stopPrank();
    }

    // REGRESSION TESTS : Create and Fund Program
    function testCreateAndFundProgram() public {
        /// @dev Define program parameters
        uint256 programId = 1;
        uint256 fundingAmount = 10e24;
        uint32 duration = 90 days;

        /// @dev Create the program
        vm.prank(_DAO_MULTISIG);
        ISuperfluidPool pool = _programManager.createProgram(
            programId, _DAO_MULTISIG, vm.addr(_SIGNER_PKEY), _sup, "PROGRAM 1", "PROGRAM_1"
        );

        /// @dev Grant units to Alice
        _helperGrantUnitsToAlice(programId, 1);

        /// @dev Approve and set flow permissions
        vm.startPrank(_DAO_MULTISIG);
        _macroForwarder.runMacro(
            IUserDefinedMacro(address(_programManager)),
            _programManager.paramsGivePermission(programId, fundingAmount, duration)
        );

        /// @dev Start program funding
        _programManager.startFunding(programId, fundingAmount, duration);
        vm.stopPrank();

        /// @dev Validate flows
        int96 requestedFlowRate = int256(fundingAmount / duration).toInt96();
        (, int96 totalDistributionFlowRate) =
            _sup.estimateFlowDistributionActualFlowRate(address(_programManager), pool, requestedFlowRate);

        assertEq(
            pool.getMemberFlowRate(address(_aliceLocker)),
            totalDistributionFlowRate,
            "program distribution flow rate is incorrect"
        );
    }

    // HELPER FUNCTIONS

    function _stake() internal {
        assertEq(_existingLocker.getStakedBalance(), 0, "incorrect staked balance before op");
        assertEq(
            _stakingRewardController.taxDistributionPool().getUnits(address(_existingLocker)),
            0,
            "incorrect units before op"
        );
        assertGt(_existingLocker.getAvailableBalance(), 10_000 ether, "incorrect available balance before op");

        vm.prank(_EXISTING_LOCKER_OWNER);
        _existingLocker.stake(10_000 ether);

        assertEq(_existingLocker.getStakedBalance(), 10_000 ether, "incorrect staked balance after op");
        assertEq(
            _stakingRewardController.taxDistributionPool().getUnits(address(_existingLocker)),
            10_000,
            "incorrect units after op"
        );

        _helperStartStakerSubsidy();

        int96 expectedFlowRate = int256(_SUBSIDY_AMOUNT / _TAX_DISTRIBUTION_FLOW_DURATION).toInt96();
        assertApproxEqAbs(
            int256(_stakingRewardController.taxDistributionPool().getMemberFlowRate(address(_existingLocker))),
            int256(expectedFlowRate),
            uint256(int256(expectedFlowRate * 10 / 10000)),
            "incorrect flow rate after op"
        );
    }

    function _helperGrantUnitsToAlice(uint256 programId, uint256 units) internal {
        uint256 nonce = _programManager.getNextValidNonce(programId, _ALICE);
        bytes memory validSignature = _helperGenerateSignature(_ALICE, units, programId, nonce);

        vm.prank(_ALICE);
        _programManager.updateUnits(programId, units, nonce, validSignature);
    }

    function _helperGenerateSignature(address _locker, uint256 _unitsToGrant, uint256 _programId, uint256 _nonce)
        internal
        pure
        returns (bytes memory signature)
    {
        bytes32 message = keccak256(abi.encodePacked(_locker, _unitsToGrant, _programId, _nonce));

        bytes32 digest = message.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_SIGNER_PKEY, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _helperStartStakerSubsidy() internal {
        vm.startPrank(_DAO_MULTISIG);
        _sup.transfer(address(_stakingRewardController), 1_000_000 ether);
        _stakingRewardController.refreshTaxDistributionFlow();
        vm.stopPrank();
    }

    function _deploySIP8() internal {
        vm.startPrank(_DEPLOYER);
        // Deploy the new implementations
        address newFluidLockerFactoryLogicAddress = address(
            new FluidLockerFactory(
                address(_lockerBeacon),
                IStakingRewardController(address(_stakingRewardController)),
                false // factory is not paused
            )
        );
        address newFontaineLogicAddress = address(new Fontaine(_sup));
        address newStakingRewardControllerLogicAddress = address(new StakingRewardController(_sup));
        vm.stopPrank();

        vm.startPrank(_DAO_MULTISIG);
        // Upgrade the live proxy contracts with newly deployed implementations
        _fluidLockerFactory.upgradeTo(newFluidLockerFactoryLogicAddress, "");
        _stakingRewardController.upgradeTo(newStakingRewardControllerLogicAddress, "");
        _fontaineBeacon.upgradeTo(newFontaineLogicAddress);

        // Setup the LP distribution pool and set the tax allocation
        _stakingRewardController.setupLPDistributionPool();
        _stakingRewardController.setTaxAllocation(10000, 0);
        vm.stopPrank();

        // Deploy the new FluidLocker implementation
        vm.startPrank(_DEPLOYER);
        address newFluidLockerLogicAddress = address(
            new FluidLocker(
                _sup,
                IEPProgramManager(address(_programManager)),
                IStakingRewardController(address(_stakingRewardController)),
                address(_fontaineBeacon),
                false, // unlock is not available
                _nonfungiblePositionManager,
                IUniswapV3Pool(address(0)),
                _swapRouter,
                _DAO_MULTISIG
            )
        );
        vm.stopPrank();

        // Upgrade the live proxy contracts with newly deployed implementations
        vm.startPrank(_DAO_MULTISIG);
        _lockerBeacon.upgradeTo(newFluidLockerLogicAddress);
        vm.stopPrank();
    }
}
