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
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { ERC1967Utils } from "@openzeppelin-v5/contracts/proxy/ERC1967/ERC1967Utils.sol";
import { SafeCast } from "@openzeppelin-v5/contracts/utils/math/SafeCast.sol";

/* Superfluid Protocol Contracts & Interfaces */
import {
    ISuperfluidPool,
    ISuperToken,
    PoolConfig
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

/* FLUID Interfaces */
import { IStakingRewardController } from "./interfaces/IStakingRewardController.sol";

using SuperTokenV1Library for ISuperToken;
using SafeCast for int256;
using SafeCast for int128;

/**
 * @title Staking Reward Controller Contract
 * @author Superfluid
 * @notice Contract responsible for administrating the GDA pool that distribute the unlocking tax to stakers
 *
 */
contract StakingRewardController is Initializable, OwnableUpgradeable, IStakingRewardController {
    //      ____                          __        __    __        _____ __        __
    //     /  _/___ ___  ____ ___  __  __/ /_____ _/ /_  / /__     / ___// /_____ _/ /____  _____
    //     / // __ `__ \/ __ `__ \/ / / / __/ __ `/ __ \/ / _ \    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   _/ // / / / / / / / / / / /_/ / /_/ /_/ / /_/ / /  __/   ___/ / /_/ /_/ / /_/  __(__  )
    //  /___/_/ /_/ /_/_/ /_/ /_/\__,_/\__/\__,_/_.___/_/\___/   /____/\__/\__,_/\__/\___/____/

    /// @notice $FLUID SuperToken interface
    ISuperToken public immutable FLUID;

    /// @notice Value used to convert staked amount into GDA pool units
    uint128 private constant _STAKING_UNIT_DOWNSCALER = 1e18;

    /// @notice Value used to convert the provided liquidity amount into GDA pool units
    uint128 private constant _LIQUIDITY_UNIT_DOWNSCALER = 1e16;

    /// @notice Basis points denominator used for percentage calculations
    uint128 private constant _BP_DENOMINATOR = 10_000;

    /// @notice Duration of the tax distribution flow
    uint256 private constant _TAX_DISTRIBUTION_FLOW_DURATION = 180 days;

    //     _____ __        __
    //    / ___// /_____ _/ /____  _____
    //    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   ___/ / /_/ /_/ / /_/  __(__  )
    //  /____/\__/\__,_/\__/\___/____/

    /// @notice Stores the approval status of a given locker contract address
    mapping(address locker => bool isApproved) private _approvedLockers;

    /// @notice Superfluid pool interface
    ISuperfluidPool public taxDistributionPool;

    /// @notice Locker Factory contract address
    address public lockerFactory;

    //   _    __ ___      _____ __        __
    //  | |  / /|__ \    / ___// /_____ _/ /____  _____
    //  | | / /__/ /    \__ \/ __/ __ `/ __/ _ \/ ___/
    //  | |/ // __/    ___/ / /_/ /_/ / /_/  __(__  )
    //  |___//____/   /____/\__/\__,_/\__/\___/____/

    /// @notice Tax Allocation
    TaxAllocation public taxAllocation;

    /// @notice Superfluid pool interface
    ISuperfluidPool public lpDistributionPool;

    //     ______                 __                  __
    //    / ____/___  ____  _____/ /________  _______/ /_____  _____
    //   / /   / __ \/ __ \/ ___/ __/ ___/ / / / ___/ __/ __ \/ ___/
    //  / /___/ /_/ / / / (__  ) /_/ /  / /_/ / /__/ /_/ /_/ / /
    //  \____/\____/_/ /_/____/\__/_/   \__,_/\___/\__/\____/_/

    /**
     * @notice Staking Reward Controller contract constructor
     * @param fluid FLUID SuperToken contract interface
     */
    constructor(ISuperToken fluid) {
        // Disable initializers to prevent implementation contract initalization
        _disableInitializers();

        // Set immutable state
        FLUID = fluid;
    }

    /**
     * @notice Staking Reward Controller contract initializer
     * @param owner Staking Reward Controller contract owner address
     */
    function initialize(address owner) external initializer {
        // Sets the owner
        __Ownable_init(owner);

        // Configure Superfluid GDA Pool
        PoolConfig memory poolConfig =
            PoolConfig({ transferabilityForUnitsOwner: false, distributionFromAnyAddress: true });

        // Create Staker Superfluid GDA Pool
        taxDistributionPool = FLUID.createPool(address(this), poolConfig);
    }

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc IStakingRewardController
    function updateStakerUnits(uint256 lockerStakedBalance) external onlyApprovedLocker {
        taxDistributionPool.updateMemberUnits(msg.sender, uint128(lockerStakedBalance) / _STAKING_UNIT_DOWNSCALER);

        emit UpdatedStakersUnits(msg.sender, uint128(lockerStakedBalance) / _STAKING_UNIT_DOWNSCALER);
    }

    /// @inheritdoc IStakingRewardController
    function updateLiquidityProviderUnits(uint256 lockerLiquidityBalance) external onlyApprovedLocker {
        lpDistributionPool.updateMemberUnits(msg.sender, uint128(lockerLiquidityBalance) / _LIQUIDITY_UNIT_DOWNSCALER);

        emit UpdatedLiquidityProviderUnits(msg.sender, uint128(lockerLiquidityBalance) / _LIQUIDITY_UNIT_DOWNSCALER);
    }

    /// @inheritdoc IStakingRewardController
    function setLockerFactory(address lockerFactoryAddress) external onlyOwner {
        // Enforce non-zero-address
        if (lockerFactoryAddress == address(0)) {
            revert IStakingRewardController.INVALID_PARAMETER();
        }

        lockerFactory = lockerFactoryAddress;

        emit LockerFactoryAddressUpdated(lockerFactoryAddress);
    }

    /// @inheritdoc IStakingRewardController
    function approveLocker(address lockerAddress) external onlyLockerFactory {
        _approvedLockers[lockerAddress] = true;

        emit LockerApproved(lockerAddress);
    }

    /// @inheritdoc IStakingRewardController
    function upgradeTo(address newImplementation, bytes calldata data) external onlyOwner {
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }

    /// @inheritdoc IStakingRewardController
    function setTaxAllocation(uint128 stakerAllocationBP, uint128 liquidityProviderAllocationBP) external onlyOwner {
        // Ensure the sum of the allocations is 100%
        if (stakerAllocationBP + liquidityProviderAllocationBP != _BP_DENOMINATOR) {
            revert INVALID_PARAMETER();
        }

        // Set the tax allocation
        taxAllocation = TaxAllocation({
            stakerAllocationBP: stakerAllocationBP,
            liquidityProviderAllocationBP: liquidityProviderAllocationBP
        });

        emit TaxAllocationUpdated(stakerAllocationBP, liquidityProviderAllocationBP);
    }

    /// @inheritdoc IStakingRewardController
    function setupLPDistributionPool() external onlyOwner {
        if (address(lpDistributionPool) != address(0)) {
            revert LP_DISTRIBUTION_POOL_ALREADY_SET();
        }

        // Superfluid GDA Pool configuration
        PoolConfig memory poolConfig =
            PoolConfig({ transferabilityForUnitsOwner: false, distributionFromAnyAddress: true });

        // Create LP Superfluid GDA Pool
        lpDistributionPool = FLUID.createPool(address(this), poolConfig);
    }

    /// @inheritdoc IStakingRewardController
    function refreshTaxDistributionFlow() external {
        // Recalculate the global tax flow rate on a 6 months sliding window
        int96 taxFlowRate = int256(FLUID.balanceOf(address(this)) / _TAX_DISTRIBUTION_FLOW_DURATION).toInt96();

        // Apply Staker and LP tax allocations
        int96 liquidityProviderFlowRate = (taxFlowRate * int128(taxAllocation.liquidityProviderAllocationBP).toInt96())
            / int128(_BP_DENOMINATOR).toInt96();
        int96 stakerFlowRate = taxFlowRate - liquidityProviderFlowRate;

        // Distribute the tax flow to the staker and liquidity provider pools
        FLUID.distributeFlow(address(this), taxDistributionPool, stakerFlowRate);
        FLUID.distributeFlow(address(this), lpDistributionPool, liquidityProviderFlowRate);

        emit TaxDistributionFlowUpdated(liquidityProviderFlowRate, stakerFlowRate);
    }

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc IStakingRewardController
    function getTaxAllocation()
        external
        view
        returns (uint128 stakerAllocationBP, uint128 liquidityProviderAllocationBP)
    {
        stakerAllocationBP = taxAllocation.stakerAllocationBP;
        liquidityProviderAllocationBP = taxAllocation.liquidityProviderAllocationBP;
    }

    //      __  ___          ___ _____
    //     /  |/  /___  ____/ (_) __(_)__  __________
    //    / /|_/ / __ \/ __  / / /_/ / _ \/ ___/ ___/
    //   / /  / / /_/ / /_/ / / __/ /  __/ /  (__  )
    //  /_/  /_/\____/\__,_/_/_/ /_/\___/_/  /____/

    /**
     * @dev Throws if called by any account other than the Locker Factory contract
     */
    modifier onlyLockerFactory() {
        if (msg.sender != lockerFactory) revert NOT_LOCKER_FACTORY();
        _;
    }

    /**
     * @dev Throws if called by any account other than an approved locker contract
     */
    modifier onlyApprovedLocker() {
        if (!_approvedLockers[msg.sender]) revert NOT_APPROVED_LOCKER();
        _;
    }
}
