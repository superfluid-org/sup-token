// SPDX-License-Identifier: MIT

//                      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@                        @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@                        @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@                        @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@                        @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@                        @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            @@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            @@@@@@@@@@@@
//                   @@@@@@@@@@@@@            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@            @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

pragma solidity ^0.8.23;

/* Openzeppelin Contracts & Interfaces */
import { Math } from "@openzeppelin-v5/contracts/utils/math/Math.sol";
import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";
import { Initializable } from "@openzeppelin-v5/contracts/proxy/utils/Initializable.sol";
import { BeaconProxy } from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IERC20 } from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "solady/utils/ReentrancyGuard.sol";
import { IWETH9 } from "./token/IWETH9.sol";

/* Superfluid Protocol Contracts & Interfaces */
import {
    ISuperfluidPool,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

/* FLUID Interfaces */
import { IEPProgramManager } from "./interfaces/IEPProgramManager.sol";
import { IFluidLocker } from "./interfaces/IFluidLocker.sol";
import { IStakingRewardController } from "./interfaces/IStakingRewardController.sol";
import { IFontaine } from "./interfaces/IFontaine.sol";

/* Uniswap V3 Interfaces */
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { TransferHelper } from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import { TickMath } from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

using SuperTokenV1Library for ISuperToken;
using SafeCast for int256;

/// @dev Basis points denominator (for percentage calculation)
uint256 constant BP_DENOMINATOR = 10_000;

/// @dev Scaler used for unlock percentage calculation
uint256 constant UNLOCKING_PCT_SCALER = 1e18;

function calculateVestUnlockAmounts(uint256 totalAmountToUnlock, uint128 unlockPeriod)
    pure
    returns (uint256 userUnlockAmount, uint256 taxAmount)
{
    userUnlockAmount = Math.mulDiv(totalAmountToUnlock, getUnlockingPercentage(unlockPeriod), BP_DENOMINATOR);
    taxAmount = totalAmountToUnlock - userUnlockAmount;
}

function getUnlockingPercentage(uint128 unlockPeriod) pure returns (uint256 unlockingPercentageBP) {
    unlockingPercentageBP = (
        2_000 + ((8_000 * Math.sqrt(unlockPeriod * UNLOCKING_PCT_SCALER)) / Math.sqrt(365 days * UNLOCKING_PCT_SCALER))
    );
}

/**
 * @title Locker Contract
 * @author Superfluid
 * @notice Contract responsible for locking and holding FLUID token on behalf of users
 *
 */
contract FluidLocker is Initializable, ReentrancyGuard, IFluidLocker {
    //      ____                          __        __    __        _____ __        __
    //     /  _/___ ___  ____ ___  __  __/ /_____ _/ /_  / /__     / ___// /_____ _/ /____  _____
    //     / // __ `__ \/ __ `__ \/ / / / __/ __ `/ __ \/ / _ \    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   _/ // / / / / / / / / / / /_/ / /_/ /_/ / /_/ / /  __/   ___/ / /_/ /_/ / /_/  __(__  )
    //  /___/_/ /_/ /_/_/ /_/ /_/\__,_/\__/\__,_/_.___/_/\___/   /____/\__/\__,_/\__/\___/____/

    /// @notice FLUID SuperToken interface
    ISuperToken public immutable FLUID;

    /// @notice Superfluid GDA Tax Distribution Pool interface
    ISuperfluidPool public immutable STAKER_DISTRIBUTION_POOL;

    /// @notice Superfluid GDA Provider Distribution Pool interface
    ISuperfluidPool public immutable LP_DISTRIBUTION_POOL;

    /// @notice Distribution Program Manager interface
    IEPProgramManager public immutable EP_PROGRAM_MANAGER;

    /// @notice Staking Reward Controller interface
    IStakingRewardController public immutable STAKING_REWARD_CONTROLLER;

    /// @notice Fontaine Beacon contract address
    UpgradeableBeacon public immutable FONTAINE_BEACON;

    /// @notice Boolean sets to True if unlock is available
    bool public immutable UNLOCK_AVAILABLE;

    /// @notice Staking cooldown period
    uint80 private constant _STAKING_COOLDOWN_PERIOD = 30 days;

    /// @notice LP cooldown period
    uint80 private constant _LP_COOLDOWN_PERIOD = 7 days;

    /// @notice Minimum unlock period allowed (1 week)
    uint128 private constant _MIN_UNLOCK_PERIOD = 7 days;

    /// @notice Maximum unlock period allowed (12 months)
    uint128 private constant _MAX_UNLOCK_PERIOD = 365 days;

    /// @notice Instant unlock penalty percentage (expressed in basis points)
    uint256 private constant _INSTANT_UNLOCK_PENALTY_BP = 8_000;

    /// @notice Scaler used for unlock percentage calculation
    uint256 private constant _PERCENT_TO_BP = 100;

    /// @notice Uniswap V3 Router interface
    IV3SwapRouter public immutable SWAP_ROUTER;

    /// @notice Uniswap V3 Nonfungible Position Manager interface
    INonfungiblePositionManager public immutable NONFUNGIBLE_POSITION_MANAGER;

    /// @notice ETH/SUP Uniswap V3 Pool interface
    IUniswapV3Pool public immutable ETH_SUP_POOL;

    /// @notice Pump percentage (expressed in basis points)
    uint256 public constant BP_PUMP_RATIO = 100; // 1%

    /// @notice Slippage tolerance (expressed in basis points)
    uint256 public constant BP_SLIPPAGE_TOLERANCE = 500; // 5%

    /// @notice Liquidity operation deadline
    uint256 public constant LP_OPERATION_DEADLINE = 1 minutes;

    /// @notice Tax free withdraw delay
    uint256 public constant TAX_FREE_WITHDRAW_DELAY = 180 days;

    /// @notice Minimum SUP unlock amount
    uint256 public constant MIN_UNLOCK_AMOUNT = 10 ether;

    //     _____ __        __
    //    / ___// /_____ _/ /____  _____
    //    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   ___/ / /_/ /_/ / /_/  __(__  )
    //  /____/\__/\__,_/\__/\___/____/

    /// @notice This locker owner address
    address public lockerOwner;

    /// @notice Timestamp at which the staking cooldown period is elapsed
    uint80 public stakingUnlocksAt;

    /// @notice Total unlock count
    uint16 public fontaineCount;

    /// @notice Balance of $FLUID token staked in this locker
    uint256 private _stakedBalance;

    /// @notice Stores the Fontaine contract associated to the given unlock identifier
    mapping(uint256 unlockId => IFontaine fontaine) public fontaines;

    //   _    __ ___      _____ __        __
    //  | |  / /|__ \    / ___// /_____ _/ /____  _____
    //  | | / /__/ /    \__ \/ __/ __ `/ __/ _ \/ ___/
    //  | |/ // __/    ___/ / /_/ /_/ / /_/  __(__  )
    //  |___//____/   /____/\__/\__,_/\__/\___/____/

    uint256 public activePositionCount;

    /// @notice Stores the tax free withdraw timestamp for a given position token identifier
    mapping(uint256 positionTokenId => uint256 taxFreeWithdrawTimestamp) public taxFreeExitTimestamps;

    /// @notice Stores the LP cooldown timestamp for a given position token identifier
    mapping(uint256 positionTokenId => uint256 lpCooldownTimestamp) public lpCooldownTimestamps;

    /// @notice Aggregated liquidity balance provided by this locker
    uint256 private _liquidityBalance;

    //     ______                 __                  __
    //    / ____/___  ____  _____/ /________  _______/ /_____  _____
    //   / /   / __ \/ __ \/ ___/ __/ ___/ / / / ___/ __/ __ \/ ___/
    //  / /___/ /_/ / / / (__  ) /_/ /  / /_/ / /__/ /_/ /_/ / /
    //  \____/\____/_/ /_/____/\__/_/   \__,_/\___/\__/\____/_/

    /**
     * @notice Locker contract constructor
     * @param fluid FLUID SuperToken contract interface
     * @param programManager Ecosystem Partner Program Manager contract interface
     * @param stakingRewardController Staking Reward Controller contract interface
     * @param fontaineBeacon Fontaine Beacon contract address
     * @param isUnlockAvailable True if the unlock is available, false otherwise
     * @param nonfungiblePositionManager Nonfungible Position Manager contract interface
     * @param ethSupPool ETH/SUP Uniswap V3 Pool contract interface
     * @param swapRouter Uniswap V3 Swap Router contract interface
     */
    constructor(
        ISuperToken fluid,
        IEPProgramManager programManager,
        IStakingRewardController stakingRewardController,
        address fontaineBeacon,
        bool isUnlockAvailable,
        INonfungiblePositionManager nonfungiblePositionManager,
        IUniswapV3Pool ethSupPool,
        IV3SwapRouter swapRouter
    ) {
        // Disable initializers to prevent implementation contract initalization
        _disableInitializers();

        // Sets immutable states
        UNLOCK_AVAILABLE = isUnlockAvailable;
        FLUID = fluid;
        EP_PROGRAM_MANAGER = programManager;
        STAKING_REWARD_CONTROLLER = stakingRewardController;
        LP_DISTRIBUTION_POOL = stakingRewardController.lpDistributionPool();
        STAKER_DISTRIBUTION_POOL = stakingRewardController.taxDistributionPool();

        // Sets the Fontaine beacon address
        FONTAINE_BEACON = UpgradeableBeacon(fontaineBeacon);

        SWAP_ROUTER = swapRouter;
        NONFUNGIBLE_POSITION_MANAGER = nonfungiblePositionManager;
        ETH_SUP_POOL = ethSupPool;
    }

    /**
     * @notice Locker contract initializer
     * @param owner this Locker contract owner account
     */
    function initialize(address owner) external initializer {
        // Sets the owner of this locker
        lockerOwner = owner;
    }

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    receive() external payable { }
    fallback() external payable { }

    /// @inheritdoc IFluidLocker
    function claim(uint256 programId, uint256 totalProgramUnits, uint256 nonce, bytes memory stackSignature)
        external
        nonReentrant
    {
        _claim(programId, totalProgramUnits, nonce, stackSignature);
    }

    /// @inheritdoc IFluidLocker
    function claim(
        uint256[] memory programIds,
        uint256[] memory totalProgramUnits,
        uint256 nonce,
        bytes memory stackSignature
    ) external nonReentrant {
        _claimBatch(programIds, totalProgramUnits, nonce, stackSignature);
    }

    /// @inheritdoc IFluidLocker
    function claimAndStake(uint256 programId, uint256 totalProgramUnits, uint256 nonce, bytes memory stackSignature)
        external
        nonReentrant
        onlyLockerOwner
    {
        _claim(programId, totalProgramUnits, nonce, stackSignature);
        _stake(getAvailableBalance());
    }

    /// @inheritdoc IFluidLocker
    function claimAndStake(
        uint256[] memory programIds,
        uint256[] memory totalProgramUnits,
        uint256 nonce,
        bytes memory stackSignature
    ) external nonReentrant onlyLockerOwner {
        _claimBatch(programIds, totalProgramUnits, nonce, stackSignature);
        _stake(getAvailableBalance());
    }

    /// @inheritdoc IFluidLocker
    function stake(uint256 amountToStake) external nonReentrant onlyLockerOwner {
        _stake(amountToStake);
    }

    /// @inheritdoc IFluidLocker
    function unstake(uint256 amountToUnstake) external nonReentrant onlyLockerOwner {
        if (block.timestamp < stakingUnlocksAt) {
            revert STAKING_COOLDOWN_NOT_ELAPSED();
        }

        _unstake(amountToUnstake);
    }

    /// @inheritdoc IFluidLocker
    function lock(uint256 amount) external nonReentrant {
        // Fetch the amount of FLUID Token to be locked from the caller
        FLUID.transferFrom(msg.sender, address(this), amount);

        emit FluidLocked(amount);
    }

    /// @inheritdoc IFluidLocker
    function unlock(uint256 unlockAmount, uint128 unlockPeriod, address recipient)
        external
        nonReentrant
        onlyLockerOwner
        unlockAvailable
    {
        // Enforce unlock period validity
        if (unlockPeriod != 0 && (unlockPeriod < _MIN_UNLOCK_PERIOD || unlockPeriod > _MAX_UNLOCK_PERIOD)) {
            revert INVALID_UNLOCK_PERIOD();
        }

        // Enforce unlock amount validity
        if (unlockAmount < MIN_UNLOCK_AMOUNT) {
            revert INSUFFICIENT_UNLOCK_AMOUNT();
        }

        // Ensure recipient is not the zero-address
        if (recipient == address(0)) {
            revert FORBIDDEN();
        }

        // Ensure that the unlock amount is not greater than the available balance
        if (unlockAmount > getAvailableBalance()) {
            revert INSUFFICIENT_AVAILABLE_BALANCE();
        }

        // Check if there will be a tax distribution event
        if (unlockPeriod < _MAX_UNLOCK_PERIOD) {
            (uint256 stakerAllocation, uint256 providerAllocation) = STAKING_REWARD_CONTROLLER.getTaxAllocation();

            // Ensure that the tax distribution pools have at least one unit distributed (if the tax allocation is greater than 0)
            if (STAKER_DISTRIBUTION_POOL.getTotalUnits() == 0 && stakerAllocation > 0) {
                revert STAKER_DISTRIBUTION_POOL_HAS_NO_UNITS();
            }

            if (LP_DISTRIBUTION_POOL.getTotalUnits() == 0 && providerAllocation > 0) {
                revert LP_DISTRIBUTION_POOL_HAS_NO_UNITS();
            }
        }

        if (unlockPeriod == 0) {
            _instantUnlock(unlockAmount, recipient);
        } else {
            _vestUnlock(unlockAmount, unlockPeriod, recipient);
        }
    }

    /// @inheritdoc IFluidLocker
    function connect(uint256 programId) external nonReentrant onlyLockerOwner {
        // Get the corresponding program pool
        ISuperfluidPool programPool = EP_PROGRAM_MANAGER.getProgramPool(programId);

        if (!FLUID.isMemberConnected(address(programPool), address(this))) {
            // Connect this locker to the Program Pool
            FLUID.connectPool(programPool);
        }
    }

    /// @inheritdoc IFluidLocker
    function disconnect(uint256 programId) external nonReentrant onlyLockerOwner {
        _disconnectFromPool(programId);
    }

    /// @inheritdoc IFluidLocker
    function disconnect(uint256[] memory programIds) external nonReentrant onlyLockerOwner {
        for (uint256 i; i < programIds.length; ++i) {
            _disconnectFromPool(programIds[i]);
        }
    }

    /// @inheritdoc IFluidLocker
    function provideLiquidity(uint256 supAmount) external payable nonReentrant onlyLockerOwner unlockAvailable {
        address weth = NONFUNGIBLE_POSITION_MANAGER.WETH9();

        uint256 ethAmount = msg.value;

        // Wrap ETH into WETH
        IWETH9(weth).deposit{ value: ethAmount }();

        uint256 ethPumpAmount = ethAmount * BP_PUMP_RATIO / BP_DENOMINATOR;

        // Pumponomics (market buy SUP with 1% of the provided paired asset)
        _pump(weth, ethPumpAmount);

        uint256 availableBalance = getAvailableBalance();

        // Check if the locker has enough available balance to provide desired liquidity
        if (availableBalance < supAmount) {
            uint256 shortage = supAmount - availableBalance;

            // If not, check if the locker has enough staked balance to compensate for the shortage
            if (_stakedBalance < shortage) {
                revert INSUFFICIENT_AVAILABLE_BALANCE();
            } else {
                // Forcefully unstake the shortage amount to provide liquidity (discards the cooldown period)
                _unstake(shortage);
            }
        }

        // Get the amount of paired asset tokens in the locker
        uint256 ethLPAmount = ethAmount - ethPumpAmount;

        // Approve the locker to spend the paired asset and the $SUP tokens
        TransferHelper.safeApprove(weth, address(NONFUNGIBLE_POSITION_MANAGER), ethLPAmount);
        TransferHelper.safeApprove(address(FLUID), address(NONFUNGIBLE_POSITION_MANAGER), supAmount);

        // Create a new Uniswap V3 position
        (uint256 positionTokenId,,) = _createPosition(ethLPAmount, supAmount);

        lpCooldownTimestamps[positionTokenId] = uint80(block.timestamp) + _LP_COOLDOWN_PERIOD;

        activePositionCount++;

        // Emit the Liquidity Position Created event
        emit LiquidityPositionCreated(positionTokenId);
    }

    /// @inheritdoc IFluidLocker
    function withdrawLiquidity(
        uint256 tokenId,
        uint128 liquidityToRemove,
        uint256 amount0ToRemove,
        uint256 amount1ToRemove
    ) external nonReentrant onlyLockerOwner unlockAvailable {
        // ensure the locker has a position
        if (!_positionExists(tokenId)) {
            revert LOCKER_HAS_NO_POSITION();
        }

        // Enforce LP cooldown
        if (block.timestamp < lpCooldownTimestamps[tokenId]) {
            revert LP_COOLDOWN_NOT_ELAPSED();
        }

        // Collect the fees
        _collect(tokenId, lockerOwner);

        address weth = NONFUNGIBLE_POSITION_MANAGER.WETH9();

        (,,,,,,, uint128 positionLiquidity,,,,) = NONFUNGIBLE_POSITION_MANAGER.positions(tokenId);

        (, uint256 withdrawnSup) = _decreasePosition(tokenId, liquidityToRemove, amount0ToRemove, amount1ToRemove);

        // Unwrap the withdrawn WETH
        IWETH9(weth).withdraw(IERC20(weth).balanceOf(address(this)));

        // Transfer ETH to the locker owner
        TransferHelper.safeTransferETH(lockerOwner, address(this).balance);

        if (block.timestamp >= taxFreeExitTimestamps[tokenId]) {
            TransferHelper.safeTransfer(address(FLUID), lockerOwner, withdrawnSup);
        }

        // Burn the position and delete position tokenId if all liquidity is removed
        if (liquidityToRemove == positionLiquidity) {
            delete taxFreeExitTimestamps[tokenId];
            activePositionCount--;
            NONFUNGIBLE_POSITION_MANAGER.burn(tokenId);
            emit LiquidityPositionBurned(tokenId);
        }
    }

    /// @inheritdoc IFluidLocker
    function collectFees(uint256 tokenId)
        external
        nonReentrant
        onlyLockerOwner
        unlockAvailable
        returns (uint256 collectedWeth, uint256 collectedSup)
    {
        // ensure the locker has a position
        if (!_positionExists(tokenId)) revert LOCKER_HAS_NO_POSITION();

        if (ETH_SUP_POOL.token0() == address(FLUID)) {
            // Collect the fees
            (collectedSup, collectedWeth) = _collect(tokenId, lockerOwner);
        } else {
            // Collect the fees
            (collectedWeth, collectedSup) = _collect(tokenId, lockerOwner);
        }
    }

    /// @inheritdoc IFluidLocker
    function withdrawDustETH() external onlyLockerOwner {
        // Transfer ETH to the locker owner
        TransferHelper.safeTransferETH(lockerOwner, address(this).balance);
    }

    /// @inheritdoc IFluidLocker
    function disconnectAndClaim(
        uint256[] memory programIdsToDisconnect,
        uint256[] memory programIdsToClaim,
        uint256[] memory totalProgramUnits,
        uint256 nonce,
        bytes memory stackSignature
    ) external nonReentrant onlyLockerOwner {
        for (uint256 i; i < programIdsToDisconnect.length; ++i) {
            _disconnectFromPool(programIdsToDisconnect[i]);
        }

        _claimBatch(programIdsToClaim, totalProgramUnits, nonce, stackSignature);
    }

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc IFluidLocker
    function getFlowRatePerProgram(uint256 programId) public view returns (int96 flowRate) {
        // Get the corresponding program pool
        ISuperfluidPool programPool = EP_PROGRAM_MANAGER.getProgramPool(programId);

        // Get the flow rate
        flowRate = programPool.getMemberFlowRate(address(this));
    }

    /// @inheritdoc IFluidLocker
    function getFlowRatePerProgram(uint256[] memory programIds) external view returns (int96[] memory flowRates) {
        flowRates = new int96[](programIds.length);

        for (uint256 i = 0; i < programIds.length; ++i) {
            flowRates[i] = getFlowRatePerProgram(programIds[i]);
        }
    }

    /// @inheritdoc IFluidLocker
    function getUnitsPerProgram(uint256 programId) public view returns (uint128 units) {
        // Get the corresponding program pool
        ISuperfluidPool programPool = EP_PROGRAM_MANAGER.getProgramPool(programId);

        // Get this locker's unit within the given program identifier
        units = programPool.getUnits(address(this));
    }

    /// @inheritdoc IFluidLocker
    function getUnitsPerProgram(uint256[] memory programIds) external view returns (uint128[] memory units) {
        units = new uint128[](programIds.length);

        for (uint256 i = 0; i < programIds.length; ++i) {
            units[i] = getUnitsPerProgram(programIds[i]);
        }
    }

    /// @inheritdoc IFluidLocker
    function getStakedBalance() external view returns (uint256 sBalance) {
        sBalance = _stakedBalance;
    }

    /// @inheritdoc IFluidLocker
    function getLiquidityBalance() public view returns (uint256 lBalance) {
        lBalance = _liquidityBalance;
    }

    /// @inheritdoc IFluidLocker
    function getAvailableBalance() public view returns (uint256 aBalance) {
        aBalance = FLUID.balanceOf(address(this)) - _stakedBalance;
    }

    /// @inheritdoc IFluidLocker
    function getFontaineBeaconImplementation() public view returns (address fontaineBeaconImpl) {
        fontaineBeaconImpl = FONTAINE_BEACON.implementation();
    }

    /// @inheritdoc IFluidLocker
    function getPositionLiquidity(uint256 tokenId) public view returns (uint128 liquidity) {
        (,,,,,,, liquidity,,,,) = NONFUNGIBLE_POSITION_MANAGER.positions(tokenId);
    }

    //      ____      __                        __   ______                 __  _
    //     /  _/___  / /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //     / // __ \/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   _/ // / / / /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /___/_/ /_/\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    function _connectToPool(uint256 programId) internal {
        // Get the corresponding program pool
        ISuperfluidPool programPool = EP_PROGRAM_MANAGER.getProgramPool(programId);

        if (!FLUID.isMemberConnected(address(programPool), address(this))) {
            // Connect this locker to the Program Pool
            FLUID.connectPool(programPool);
        }
    }

    function _claim(uint256 programId, uint256 totalProgramUnits, uint256 nonce, bytes memory stackSignature)
        internal
    {
        _connectToPool(programId);

        // Request program manager to update this locker's units
        EP_PROGRAM_MANAGER.updateUserUnits(lockerOwner, programId, totalProgramUnits, nonce, stackSignature);

        emit IFluidLocker.FluidStreamClaimed(programId, totalProgramUnits);
    }

    function _claimBatch(
        uint256[] memory programIds,
        uint256[] memory totalProgramUnits,
        uint256 nonce,
        bytes memory stackSignature
    ) internal {
        for (uint256 i = 0; i < programIds.length; ++i) {
            _connectToPool(programIds[i]);
        }

        // Request program manager to update this locker's units
        EP_PROGRAM_MANAGER.batchUpdateUserUnits(lockerOwner, programIds, totalProgramUnits, nonce, stackSignature);

        emit IFluidLocker.FluidStreamsClaimed(programIds, totalProgramUnits);
    }

    function _stake(uint256 amountToStake) internal {
        if (amountToStake > getAvailableBalance()) revert INSUFFICIENT_AVAILABLE_BALANCE();

        if (!FLUID.isMemberConnected(address(STAKER_DISTRIBUTION_POOL), address(this))) {
            // Connect this locker to the Tax Distribution Pool
            FLUID.connectPool(STAKER_DISTRIBUTION_POOL);
        }

        // Update staked balance
        _stakedBalance += amountToStake;

        // Update unlock timestamp
        stakingUnlocksAt = uint80(block.timestamp) + _STAKING_COOLDOWN_PERIOD;

        // Call Staking Reward Controller to update staker's units
        STAKING_REWARD_CONTROLLER.updateStakerUnits(_stakedBalance);

        emit FluidStaked(_stakedBalance, amountToStake);
    }

    function _unstake(uint256 amountToUnstake) internal {
        // Enforce amount to unstake is not greater than the staked balance
        if (amountToUnstake > _stakedBalance) {
            revert INSUFFICIENT_STAKED_BALANCE();
        }

        // Update the staked balance
        _stakedBalance -= amountToUnstake;

        uint256 newStakedBalance = _stakedBalance;

        // Call Staking Reward Controller to update staker's units
        STAKING_REWARD_CONTROLLER.updateStakerUnits(newStakedBalance);

        if (newStakedBalance == 0) {
            // Disconnect this locker from the Tax Distribution Pool
            FLUID.disconnectPool(STAKER_DISTRIBUTION_POOL);
        }

        emit FluidUnstaked(newStakedBalance, amountToUnstake);
    }

    function _disconnectFromPool(uint256 programId) internal {
        // Get the corresponding program pool
        ISuperfluidPool programPool = EP_PROGRAM_MANAGER.getProgramPool(programId);

        // Disconnect this locker from the Program Pool
        FLUID.disconnectPool(programPool);
    }

    function _instantUnlock(uint256 amountToUnlock, address recipient) internal {
        // Calculate instant unlock penalty amount
        uint256 taxAmount = Math.mulDiv(amountToUnlock, _INSTANT_UNLOCK_PENALTY_BP, BP_DENOMINATOR);

        // Transfer the tax amount to the Staking Reward Controller
        FLUID.transfer(address(STAKING_REWARD_CONTROLLER), taxAmount);

        // Update the tax distribution flow
        STAKING_REWARD_CONTROLLER.refreshTaxDistributionFlow();

        // Transfer the amount after tax to the locker owner
        FLUID.transfer(recipient, amountToUnlock - taxAmount);

        emit FluidUnlocked(0, amountToUnlock, recipient, address(0));
    }

    function _vestUnlock(uint256 amountToUnlock, uint128 unlockPeriod, address recipient) internal {
        // Calculate the amount due to the user and the tax amount
        (uint256 userUnlockAmount, uint256 taxAmount) = calculateVestUnlockAmounts(amountToUnlock, unlockPeriod);

        // Use create2 to deploy a Fontaine Beacon Proxy
        // The salt used for deployment is the hashed encoded Locker address and unlock identifier
        address newFontaine = address(
            new BeaconProxy{ salt: keccak256(abi.encode(address(this), fontaineCount)) }(address(FONTAINE_BEACON), "")
        );

        // Persist the fontaine address and increment fontaine counter
        fontaines[fontaineCount] = IFontaine(newFontaine);
        fontaineCount++;

        // Transfer the amount to unlock to the newly created Fontaine
        FLUID.transfer(newFontaine, userUnlockAmount);

        // Transfer the tax amount to the Staking Reward Controller
        FLUID.transfer(address(STAKING_REWARD_CONTROLLER), taxAmount);

        // Initialize the new Fontaine instance (this initiate the unlock process)
        IFontaine(newFontaine).initialize(recipient, int256(userUnlockAmount / unlockPeriod).toInt96(), unlockPeriod);

        // Update the tax distribution flow
        STAKING_REWARD_CONTROLLER.refreshTaxDistributionFlow();

        emit FluidUnlocked(unlockPeriod, amountToUnlock, recipient, newFontaine);
    }

    /**
     * @notice Swaps ETH for SUP tokens using Uniswap V3 (Pumponomics)
     * @param weth WETH address
     * @param ethAmount The amount of ETH to swap
     */
    function _pump(address weth, uint256 ethAmount) internal {
        IERC20(weth).approve(address(SWAP_ROUTER), ethAmount);

        // No need slippage protection here as it is
        // implicitely covered by the `_createPosition` slippage protection
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: weth,
            tokenOut: address(FLUID),
            fee: ETH_SUP_POOL.fee(),
            recipient: address(this),
            amountIn: ethAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        SWAP_ROUTER.exactInputSingle(swapParams);
    }

    /**
     * @notice Creates a new Uniswap V3 position with the specified amounts of tokens
     * @param ethAmount The desired amount of ETH to add as liquidity
     * @param supAmount The desired amount of SUP to add as liquidity
     * @return positionTokenId The token identifier of the newly created position
     * @return depositedEthAmount The actual amount of ETH deposited as liquidity
     * @return depositedSupAmount The actual amount of SUP deposited as liquidity
     */
    function _createPosition(uint256 ethAmount, uint256 supAmount)
        internal
        returns (uint256 positionTokenId, uint256 depositedEthAmount, uint256 depositedSupAmount)
    {
        bool zeroIsSup = ETH_SUP_POOL.token0() == address(FLUID);

        INonfungiblePositionManager.MintParams memory mintParams = _formatMintParams(zeroIsSup, ethAmount, supAmount);

        // Create the UniswapV3 position
        (uint256 tokenId, uint128 liquidity, uint256 depositedAmount0, uint256 depositedAmount1) =
            NONFUNGIBLE_POSITION_MANAGER.mint(mintParams);

        // Set the tax free withdraw timestamp
        taxFreeExitTimestamps[tokenId] = block.timestamp + TAX_FREE_WITHDRAW_DELAY;

        // Update the aggregated liquidity balance
        _liquidityBalance += liquidity;

        if (!FLUID.isMemberConnected(address(LP_DISTRIBUTION_POOL), address(this))) {
            // Connect this locker to the LP Tax Distribution Pool
            FLUID.connectPool(LP_DISTRIBUTION_POOL);
        }

        // Update the liquidity provider units
        STAKING_REWARD_CONTROLLER.updateLiquidityProviderUnits(_liquidityBalance);

        (depositedSupAmount, depositedEthAmount) = _sortOutAmounts(zeroIsSup, depositedAmount0, depositedAmount1);

        positionTokenId = tokenId;
    }

    /**
     * @notice Decreases liquidity from a Uniswap V3 position
     * @param tokenId The ID of the NFT position to decrease liquidity from
     * @param liquidityToRemove The amount of liquidity to remove from the position (only collect fees if set to 0)
     * @param amount0ToRemove The minimum amount Token0 to remove from the position
     * @param amount1ToRemove The minimum amount Token1 to remove from the position
     * @return withdrawnPairedAssetAmount The amount of paired asset received from removing liquidity
     * @return withdrawnSupAmount The amount of $FLUID received from removing liquidity
     */
    function _decreasePosition(
        uint256 tokenId,
        uint128 liquidityToRemove,
        uint256 amount0ToRemove,
        uint256 amount1ToRemove
    ) internal returns (uint256 withdrawnPairedAssetAmount, uint256 withdrawnSupAmount) {
        // (,, address token0,,,,,,,,,) = NONFUNGIBLE_POSITION_MANAGER.positions(tokenId);
        // bool zeroIsSup = token0 == address(FLUID);

        bool zeroIsSup = ETH_SUP_POOL.token0() == address(FLUID);

        (uint256 amount0Min, uint256 amount1Min) = _calculateMinAmounts(amount0ToRemove, amount1ToRemove);

        // construct Decrease Liquidity parameters
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenId,
            liquidity: liquidityToRemove,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            deadline: block.timestamp + LP_OPERATION_DEADLINE
        });

        NONFUNGIBLE_POSITION_MANAGER.decreaseLiquidity(params);

        // Update the aggregated liquidity balance
        _liquidityBalance -= liquidityToRemove;

        // Update the liquidity provider units
        STAKING_REWARD_CONTROLLER.updateLiquidityProviderUnits(_liquidityBalance);

        // Collect the tokens owed
        (uint256 withdrawnAmount0, uint256 withdrawnAmount1) = _collect(tokenId, address(this));

        (withdrawnSupAmount, withdrawnPairedAssetAmount) =
            _sortOutAmounts(zeroIsSup, withdrawnAmount0, withdrawnAmount1);
    }

    /**
     * @notice Collects accumulated fees from a Uniswap V3 position
     * @param tokenId The ID of the NFT position to collect fees from
     * @return amount0 The amount of token0 fees collected
     * @return amount1 The amount of token1 fees collected
     */
    function _collect(uint256 tokenId, address recipient) internal returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: recipient,
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = NONFUNGIBLE_POSITION_MANAGER.collect(collectParams);
    }

    function _formatMintParams(bool zeroIsSup, uint256 pairedAssetAmount, uint256 supAmount)
        internal
        view
        returns (INonfungiblePositionManager.MintParams memory mintParams)
    {
        (uint256 amount0, uint256 amount1) = _sortInAmounts(zeroIsSup, supAmount, pairedAssetAmount);
        (uint256 amount0Min, uint256 amount1Min) = _calculateMinAmounts(amount0, amount1);

        int24 tickSpacing = ETH_SUP_POOL.tickSpacing();

        mintParams = INonfungiblePositionManager.MintParams({
            token0: ETH_SUP_POOL.token0(),
            token1: ETH_SUP_POOL.token1(),
            fee: ETH_SUP_POOL.fee(),
            tickLower: (TickMath.MIN_TICK / tickSpacing) * tickSpacing,
            tickUpper: (TickMath.MAX_TICK / tickSpacing) * tickSpacing,
            amount0Desired: amount0,
            amount1Desired: amount1,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp + LP_OPERATION_DEADLINE
        });
    }

    /**
     * @notice Calculates minimum amounts based on slippage tolerance
     * @param amount0 The ideal amount of token0
     * @param amount1 The ideal amount of token1
     * @return amount0Min The minimum acceptable amount of token0
     * @return amount1Min The minimum acceptable amount of token1
     */
    function _calculateMinAmounts(uint256 amount0, uint256 amount1)
        internal
        pure
        returns (uint256 amount0Min, uint256 amount1Min)
    {
        // Calculate minimum amounts with slippage protection
        unchecked {
            amount0Min = (amount0 * (BP_DENOMINATOR - BP_SLIPPAGE_TOLERANCE)) / BP_DENOMINATOR;
            amount1Min = (amount1 * (BP_DENOMINATOR - BP_SLIPPAGE_TOLERANCE)) / BP_DENOMINATOR;
        }
    }

    /**
     * @notice Checks if the locker has a Uniswap V3 position
     * @param tokenId The token identifier to query
     * @return exists True if the locker owns the given tokenId, false otherwise
     */
    function _positionExists(uint256 tokenId) internal view returns (bool exists) {
        exists = taxFreeExitTimestamps[tokenId] > 0;
    }

    /**
     * @notice Sorts input amounts based on token order in the Uniswap V3 pool
     * @param zeroIsSup Whether SUP is token0 in the pool
     * @param supAmount The amount of SUP tokens
     * @param pairedAssetAmount The amount of paired asset tokens
     * @return amount0 The amount of token0 after sorting
     * @return amount1 The amount of token1 after sorting
     */
    function _sortInAmounts(bool zeroIsSup, uint256 supAmount, uint256 pairedAssetAmount)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (zeroIsSup) {
            amount0 = supAmount;
            amount1 = pairedAssetAmount;
        } else {
            amount0 = pairedAssetAmount;
            amount1 = supAmount;
        }
    }

    /**
     * @notice Sorts output amounts based on token order in the Uniswap V3 pool
     * @param zeroIsSup Whether SUP is token0 in the pool
     * @param amount0 The amount of token0 to sort
     * @param amount1 The amount of token1 to sort
     * @return supAmount The sorted SUP token amount
     * @return pairedAssetAmount The sorted paired asset amount
     */
    function _sortOutAmounts(bool zeroIsSup, uint256 amount0, uint256 amount1)
        internal
        pure
        returns (uint256 supAmount, uint256 pairedAssetAmount)
    {
        if (zeroIsSup) {
            supAmount = amount0;
            pairedAssetAmount = amount1;
        } else {
            supAmount = amount1;
            pairedAssetAmount = amount0;
        }
    }

    //      __  ___          ___ _____
    //     /  |/  /___  ____/ (_) __(_)__  __________
    //    / /|_/ / __ \/ __  / / /_/ / _ \/ ___/ ___/
    //   / /  / / /_/ / /_/ / / __/ /  __/ /  (__  )
    //  /_/  /_/\____/\__,_/_/_/ /_/\___/_/  /____/

    /**
     * @dev Throws if called by any account other than the owner
     */
    modifier onlyLockerOwner() {
        if (msg.sender != lockerOwner) revert NOT_LOCKER_OWNER();
        _;
    }

    /**
     * @dev Throws if called operation is not available
     */
    modifier unlockAvailable() {
        if (!UNLOCK_AVAILABLE) revert TTE_NOT_ACTIVATED();
        _;
    }
}
