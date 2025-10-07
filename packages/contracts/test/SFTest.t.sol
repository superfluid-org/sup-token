// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IERC20 } from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import { SuperfluidFrameworkDeployer } from
    "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import { ERC1820RegistryCompiled } from
    "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken, ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts//interfaces/tokens/ISETH.sol";

import { FluidEPProgramManager } from "../src/FluidEPProgramManager.sol";
import { FluidLocker } from "../src/FluidLocker.sol";
import { FluidLockerFactory } from "../src/FluidLockerFactory.sol";
import { Fontaine } from "../src/Fontaine.sol";
import { StakingRewardController } from "../src/StakingRewardController.sol";

import { _deployAll, DeploySettings, DeployedContracts } from "../script/Deploy.s.sol";

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

using SuperTokenV1Library for SuperToken;
using SuperTokenV1Library for ISuperToken;
using ECDSA for bytes32;
using SafeCast for int256;

contract SFTest is Test {
    uint256 public constant INITIAL_BALANCE = 10000 ether;
    uint256 public constant FLUID_SUPPLY = 1_000_000_000 ether;
    uint256 public constant PROGRAM_DURATION = 90 days;
    uint24 public constant POOL_FEE = 3000;
    int24 internal constant _MIN_TICK = -887272;
    int24 internal constant _MAX_TICK = -_MIN_TICK;

    // Units downscaler defined in StakingRewardController.sol
    uint128 internal constant _STAKING_UNIT_DOWNSCALER = 1e18;

    // Initial Pool Price : 20000 SUP/ETH
    uint160 public constant INITIAL_SQRT_PRICEX96_SUP_PER_WETH = 11204554194957228397824552468480;

    // Initial Pool Price : 0.00005 ETH/SUP
    uint160 public constant INITIAL_SQRT_PRICEX96_WETH_PER_SUP = 560227709747861407246843904;

    SuperfluidFrameworkDeployer.Framework internal _sf;
    SuperfluidFrameworkDeployer internal _deployer;

    bool public constant FACTORY_IS_PAUSED = false;
    bool public constant LOCKER_CAN_UNLOCK = true;

    address public constant ADMIN = address(0x420);
    address public constant ALICE = address(0x1);
    address public constant BOB = address(0x2);
    address public constant CAROL = address(0x3);
    address public constant FLUID_TREASURY = address(0x4);
    address[] internal TEST_ACCOUNTS = [ADMIN, FLUID_TREASURY, ALICE, BOB, CAROL];

    TestToken internal _fluidUnderlying;
    SuperToken internal _fluidSuperToken;
    ISuperToken internal _fluid;
    ISETH internal _ethx;

    FluidEPProgramManager internal _programManager;
    FluidLocker internal _fluidLockerLogic;
    Fontaine internal _fontaineLogic;
    FluidLockerFactory internal _fluidLockerFactory;
    StakingRewardController internal _stakingRewardController;
    UpgradeableBeacon internal _lockerBeacon;
    UpgradeableBeacon internal _fontaineBeacon;

    // Uniswap V3 Configuration
    INonfungiblePositionManager internal _nonfungiblePositionManager;
    IV3SwapRouter internal _swapRouter;
    IUniswapV3Factory internal _poolFactory;
    IUniswapV3Pool internal _pool;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("BASE_MAINNET_RPC_URL"), 36486000);

        _ethx = ISETH(0x46fd5cfB4c12D87acD3a13e92BAa53240C661D93);

        // Superfluid Protocol Deployment Start
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        _deployer = new SuperfluidFrameworkDeployer();
        _deployer.deployTestFramework();
        _sf = _deployer.getFramework();

        (_fluidUnderlying, _fluidSuperToken) =
            _deployer.deployWrapperSuperToken("Superfluid Token", "SUP", 18, type(uint256).max, address(0));

        // Superfluid Protocol Deployment End

        // Mint tokens for test accounts
        for (uint256 i; i < TEST_ACCOUNTS.length; ++i) {
            vm.startPrank(TEST_ACCOUNTS[i]);
            vm.deal(TEST_ACCOUNTS[i], INITIAL_BALANCE * 2);
            _ethx.upgradeByETH{ value: INITIAL_BALANCE }();
            vm.stopPrank();
        }

        vm.startPrank(FLUID_TREASURY);
        _fluidUnderlying.mint(FLUID_TREASURY, FLUID_SUPPLY);
        _fluidUnderlying.approve(address(_fluidSuperToken), FLUID_SUPPLY);
        _fluidSuperToken.upgrade(FLUID_SUPPLY);
        vm.stopPrank();

        // Uniswap V3 Pool & Interfaces configuration
        _nonfungiblePositionManager = INonfungiblePositionManager(0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1);
        _swapRouter = IV3SwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);
        _poolFactory = IUniswapV3Factory(0x33128a8fC17869897dcE68Ed026d694621f6FDfD);

        // Deploy the pool
        _pool = IUniswapV3Pool(_poolFactory.createPool(address(_ethx), address(_fluidSuperToken), POOL_FEE));

        // Initialize the pool
        uint160 sqrtPriceX96 =
            _pool.token0() == address(_ethx) ? INITIAL_SQRT_PRICEX96_SUP_PER_WETH : INITIAL_SQRT_PRICEX96_WETH_PER_SUP;
        _pool.initialize(sqrtPriceX96);

        // Provide liquidity to the pool (from the treasury)
        vm.startPrank(FLUID_TREASURY);
        uint256 ethxAmountToDeposit = 1000 ether;
        uint256 supAmountToDeposit = 20_000_000 ether;

        _ethx.approve(address(_nonfungiblePositionManager), ethxAmountToDeposit);
        _fluidSuperToken.approve(address(_nonfungiblePositionManager), supAmountToDeposit);

        uint256 amount0 = _pool.token0() == address(_ethx) ? ethxAmountToDeposit : supAmountToDeposit;
        uint256 amount1 = _pool.token1() == address(_ethx) ? ethxAmountToDeposit : supAmountToDeposit;

        vm.label(address(_ethx), "ETHx");
        vm.label(address(_fluidSuperToken), "SUP");

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: _pool.token0(),
            token1: _pool.token1(),
            fee: POOL_FEE,
            tickLower: (_MIN_TICK / _pool.tickSpacing()) * _pool.tickSpacing(),
            tickUpper: (_MAX_TICK / _pool.tickSpacing()) * _pool.tickSpacing(),
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        // Create the UniswapV3 position
        _nonfungiblePositionManager.mint(mintParams);
        vm.stopPrank();

        // FLUID Contracts Deployment Start
        DeploySettings memory settings = DeploySettings({
            fluid: _fluidSuperToken,
            governor: ADMIN,
            deployer: ADMIN,
            treasury: FLUID_TREASURY,
            factoryPauseStatus: FACTORY_IS_PAUSED,
            unlockStatus: LOCKER_CAN_UNLOCK,
            swapRouter: _swapRouter,
            nonfungiblePositionManager: _nonfungiblePositionManager,
            ethSupPool: _pool
        });

        vm.startPrank(ADMIN);

        DeployedContracts memory deployedContracts = _deployAll(settings);

        _programManager = FluidEPProgramManager(deployedContracts.programManagerProxyAddress);
        _stakingRewardController = StakingRewardController(deployedContracts.stakingRewardControllerProxyAddress);
        _fluidLockerFactory = FluidLockerFactory(deployedContracts.lockerFactoryProxyAddress);
        _fluidLockerLogic = FluidLocker(payable(deployedContracts.lockerLogicAddress));
        _fontaineLogic = Fontaine(deployedContracts.fontaineLogicAddress);
        _fluid = ISuperToken(address(_fluidSuperToken));
        _lockerBeacon = UpgradeableBeacon(deployedContracts.lockerBeaconAddress);
        _fontaineBeacon = UpgradeableBeacon(deployedContracts.fontaineBeaconAddress);

        vm.stopPrank();

        // FLUID Contracts Deployment End
    }

    //      __  __     __                   ______                 __  _
    //     / / / /__  / /___  ___  _____   / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / /_/ / _ \/ / __ \/ _ \/ ___/  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / __  /  __/ / /_/ /  __/ /     / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_/ /_/\___/_/ .___/\___/_/     /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/
    //              /_/

    function _helperCreateProgram(uint256 pId, address admin, address signer)
        internal
        virtual
        returns (ISuperfluidPool pool)
    {
        vm.prank(ADMIN);
        pool = _programManager.createProgram(
            pId, admin, signer, _fluidSuperToken, "FLUID Ecosystem Partner Test Program", "FLUID_Test_EPP"
        );
    }

    function _helperCreatePrograms(uint256[] memory pIds, address admin, address signer)
        internal
        returns (ISuperfluidPool[] memory pools)
    {
        vm.startPrank(ADMIN);
        pools = new ISuperfluidPool[](pIds.length);

        for (uint256 i; i < pIds.length; ++i) {
            pools[i] = _programManager.createProgram(
                pIds[i], admin, signer, _fluidSuperToken, "FLUID Ecosystem Partner Test Program", "FLUID_Test_EPP"
            );
        }

        vm.stopPrank();
    }

    function _helperGenerateSignature(
        uint256 _signerPkey,
        address _locker,
        uint256 _unitsToGrant,
        uint256 _programId,
        uint256 _nonce
    ) internal pure returns (bytes memory signature) {
        bytes32 message = keccak256(abi.encodePacked(_locker, _unitsToGrant, _programId, _nonce));

        bytes32 digest = message.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPkey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _helperGenerateBatchSignature(
        uint256 _signerPkey,
        address _locker,
        uint256[] memory _unitsToGrant,
        uint256[] memory _programIds,
        uint256 _nonce
    ) internal pure returns (bytes memory signature) {
        bytes32 message = keccak256(abi.encodePacked(_locker, _unitsToGrant, _programIds, _nonce));

        bytes32 digest = message.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPkey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _helperDistributeToProgramPool(uint256 programId, uint256 amount, uint256 period)
        internal
        returns (int96 actualDistributionFlowRate)
    {
        ISuperfluidPool pool = _programManager.getProgramPool(programId);

        int96 distributionFlowRate = int256(amount / period).toInt96();

        (actualDistributionFlowRate,) =
            _fluid.estimateFlowDistributionActualFlowRate(FLUID_TREASURY, pool, distributionFlowRate);

        vm.startPrank(FLUID_TREASURY);
        _fluid.distributeFlow(FLUID_TREASURY, pool, distributionFlowRate);
        vm.stopPrank();
    }

    function _helperDistributeToProgramPool(
        uint256[] memory programIds,
        uint256[] memory amounts,
        uint256[] memory periods
    ) internal returns (int96[] memory actualDistributionFlowRates) {
        actualDistributionFlowRates = new int96[](programIds.length);

        for (uint256 i; i < programIds.length; ++i) {
            ISuperfluidPool pool = _programManager.getProgramPool(programIds[i]);

            int96 distributionFlowRate = int256(amounts[i] / periods[i]).toInt96();

            (actualDistributionFlowRates[i],) =
                _fluid.estimateFlowDistributionActualFlowRate(FLUID_TREASURY, pool, distributionFlowRate);

            vm.startPrank(FLUID_TREASURY);
            _fluid.distributeFlow(FLUID_TREASURY, pool, distributionFlowRate);
            vm.stopPrank();
        }
    }

    function _helperFundLocker(address locker, uint256 amount) internal {
        vm.prank(FLUID_TREASURY);
        _fluidSuperToken.transfer(locker, amount);
    }

    function _helperCreatePosition(address locker, uint256 wethAmount, uint256 supAmount)
        internal
        returns (uint256 positionTokenId)
    {
        _helperFundLocker(locker, supAmount);
        vm.startPrank(FluidLocker(payable(locker)).lockerOwner());
        FluidLocker(payable(locker)).provideLiquidity{ value: wethAmount }(supAmount);
        vm.stopPrank();

        positionTokenId = _nonfungiblePositionManager.tokenOfOwnerByIndex(
            locker, FluidLocker(payable(locker)).activePositionCount() - 1
        );
    }

    function _helperLockerProvideLiquidity(address locker) internal {
        _helperCreatePosition(locker, 1 ether, 20000e18);
    }

    function _helperWithdrawLiquidity(
        address locker,
        uint256 tokenId,
        uint128 liquidityToRemove,
        uint256 wethAmountToRemove,
        uint256 supAmountToRemove
    ) internal {
        vm.startPrank(FluidLocker(payable(locker)).lockerOwner());
        FluidLocker(payable(locker)).withdrawLiquidity(
            tokenId, liquidityToRemove, wethAmountToRemove, supAmountToRemove
        );
        vm.stopPrank();
    }

    function _helperLockerWithdrawLiquidity(address locker) internal {
        uint256 tokenId = _nonfungiblePositionManager.tokenOfOwnerByIndex(
            locker, FluidLocker(payable(locker)).activePositionCount() - 1
        );

        (,,,,,,, uint128 positionLiquidity,,,,) = _nonfungiblePositionManager.positions(tokenId);

        _helperWithdrawLiquidity(locker, tokenId, positionLiquidity, 1 ether, 20000e18);
    }

    function _helperLockerStake(address locker) internal {
        _helperFundLocker(locker, 10_000e18);
        vm.prank(FluidLocker(payable(locker)).lockerOwner());
        FluidLocker(payable(locker)).stake(10_000e18);
    }

    function _helperLockerUnstake(address locker) internal {
        vm.prank(FluidLocker(payable(locker)).lockerOwner());
        FluidLocker(payable(locker)).unstake(10_000e18);
    }
}
