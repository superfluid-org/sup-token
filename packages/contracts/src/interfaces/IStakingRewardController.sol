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

/* Superfluid Protocol Contracts & Interfaces */
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

/**
 * @title Staking Reward Controller Contract Interface
 * @author Superfluid
 * @notice Contract responsible for administrating the GDA pool that distribute the unlocking tax to stakers
 *
 */
interface IStakingRewardController {
    //      ______                 __
    //     / ____/   _____  ____  / /______
    //    / __/ | | / / _ \/ __ \/ __/ ___/
    //   / /___ | |/ /  __/ / / / /_(__  )
    //  /_____/ |___/\___/_/ /_/\__/____/

    /// @notice Event emitted when locker updates their units from staking or unstaking
    event UpdatedStakersUnits(address indexed staker, uint128 indexed totalStakerUnits);

    /// @notice Event emitted when locker updates their units from providing or withdrawingliquidity
    event UpdatedLiquidityProviderUnits(address indexed liquidityProvider, uint128 indexed totalLiquidityProviderUnits);

    /// @notice Event emitted when the subsidy flowrate is updated
    event SubsidyFlowRateUpdated(int96 indexed newSubsidyFlowRate);

    /// @notice Event emitted when the Locker Factory address is updated
    event LockerFactoryAddressUpdated(address indexed newLockerFactoryAddress);

    /// @notice Event emitted when the Locker Factory address is updated
    event ProgramManagerAddressUpdated(address indexed newProgramManagerAddress);

    /// @notice Event emitted when a Locker is approved
    event LockerApproved(address indexed approvedLocker);

    /// @notice Event emitted when the tax allocation is updated
    event TaxAllocationUpdated(uint128 stakerAllocationBP, uint128 liquidityProviderAllocationBP);

    /// @notice Event emitted when the tax distribution flow is updated
    event TaxDistributionFlowUpdated(int96 liquidityProviderFlowRate, int96 stakerFlowRate);

    //      ____        __        __
    //     / __ \____ _/ /_____ _/ /___  ______  ___  _____
    //    / / / / __ `/ __/ __ `/ __/ / / / __ \/ _ \/ ___/
    //   / /_/ / /_/ / /_/ /_/ / /_/ /_/ / /_/ /  __(__  )
    //  /_____/\__,_/\__/\__,_/\__/\__, / .___/\___/____/
    //                            /____/_/

    /**
     * @notice Tax Allocation Data Type
     * @param stakerAllocationBP staker allocation (expressed in basis points)
     * @param liquidityProviderAllocationBP liquidity provider allocation (expressed in basis points)
     */
    struct TaxAllocation {
        uint128 stakerAllocationBP;
        uint128 liquidityProviderAllocationBP;
    }

    //     ______           __                     ______
    //    / ____/_  _______/ /_____  ____ ___     / ____/_____________  __________
    //   / /   / / / / ___/ __/ __ \/ __ `__ \   / __/ / ___/ ___/ __ \/ ___/ ___/
    //  / /___/ /_/ (__  ) /_/ /_/ / / / / / /  / /___/ /  / /  / /_/ / /  (__  )
    //  \____/\__,_/____/\__/\____/_/ /_/ /_/  /_____/_/  /_/   \____/_/  /____/

    /// @notice Error thrown when the caller is not an approved Locker
    error NOT_APPROVED_LOCKER();

    /// @notice Error thrown when the caller is not the Locker Factory contract
    error NOT_LOCKER_FACTORY();

    /// @notice Error thrown when the caller is not the Program Manager contract
    error NOT_PROGRAM_MANAGER();

    /// @notice Error thrown when passing an invalid parameter
    error INVALID_PARAMETER();

    /// @notice Error thrown when the provider distribution pool is already set
    error LP_DISTRIBUTION_POOL_ALREADY_SET();

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Update the caller's (staker) units within the GDA Penalty Pool
     * @dev Only approved lockers can perform this operation
     * @param lockerStakedBalance locker's new staked balance amount
     */
    function updateStakerUnits(uint256 lockerStakedBalance) external;

    /**
     * @notice Update the caller's (liquidity provider) units within the GDA Penalty Pool
     * @dev Only approved lockers can perform this operation
     * @param lockerLiquidityBalance locker's new liquidity balance amount
     */
    function updateLiquidityProviderUnits(uint256 lockerLiquidityBalance) external;

    /**
     * @notice Update the Locker Factory contract address
     * @dev Only the contract owner can perform this operation
     * @param lockerFactoryAddress Locker Factory contract address to be set
     */
    function setLockerFactory(address lockerFactoryAddress) external;

    /**
     * @notice Approve a Locker to interact with the Staking Reward Controller contract
     * @dev Only the Locker Factory contract can perform this operation
     * @param lockerAddress Locker contract address to be approved
     */
    function approveLocker(address lockerAddress) external;

    /**
     * @notice Upgrade this proxy logic
     * @dev Only the contract owner can perform this operation
     * @param newImplementation new logic contract address
     * @param data calldata for potential initializer
     */
    function upgradeTo(address newImplementation, bytes calldata data) external;

    /**
     * @notice Set the tax allocation
     * @dev Only the contract owner can perform this operation
     * @param stakerAllocationBP staker allocation percentage (expressed in basis points)
     * @param liquidityProviderAllocationBP liquidity provider allocation percentage (expressed in basis points)
     */
    function setTaxAllocation(uint128 stakerAllocationBP, uint128 liquidityProviderAllocationBP) external;

    /**
     * @notice Setup the provider distribution pool
     * @dev Only the contract owner can perform this operation
     */
    function setupLPDistributionPool() external;

    /**
     * @notice Recalculate and redistribute the tax distribution flow to the staker and liquidity provider pools
     * @dev The taxes are distributed over a 6 months sliding window
     * @dev Every new call to this function will reevaluate the flow rates so that the distribution can last 6 months
     * @dev Since the StakingRewardController is the pool admin, adjustment flow rate will also be distributed via these flow distributions
     * @dev This function is can be called by anyone
     */
    function refreshTaxDistributionFlow() external;

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Get the tax allocation
     * @return stakerAllocationBP staker allocation percentage (expressed in basis points)
     * @return liquidityProviderAllocationBP liquidity provider allocation percentage (expressed in basis points)
     */
    function getTaxAllocation()
        external
        view
        returns (uint128 stakerAllocationBP, uint128 liquidityProviderAllocationBP);

    /**
     * @notice Get the tax distribution pool
     * @return taxDistributionPool tax distribution pool
     */
    function taxDistributionPool() external view returns (ISuperfluidPool taxDistributionPool);

    /**
     * @notice Get the provider distribution pool
     * @return lpDistributionPool provider distribution pool
     */
    function lpDistributionPool() external view returns (ISuperfluidPool lpDistributionPool);
}
