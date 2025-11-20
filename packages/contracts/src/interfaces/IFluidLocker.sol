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

/**
 * @title Locker Contract Interface
 * @author Superfluid
 * @notice Contract responsible for locking and holding FLUID token on behalf of users
 *
 */
interface IFluidLocker {
    //      ______                 __
    //     / ____/   _____  ____  / /______
    //    / __/ | | / / _ \/ __ \/ __/ ___/
    //   / /___ | |/ /  __/ / / / /_(__  )
    //  /_____/ |___/\___/_/ /_/\__/____/

    /// @notice Event emitted when locker owner claims units
    event FluidStreamClaimed(uint256 indexed programId, uint256 indexed totalProgramUnits);

    /// @notice Event emitted when locker owner batch claims units
    event FluidStreamsClaimed(uint256[] indexed programId, uint256[] indexed totalProgramUnits);

    /// @notice Event emitted when new $FLUID are locked into the locker
    event FluidLocked(uint256 indexed amount);

    /// @notice Event emitted when $FLUID are unlocked from the locker
    event FluidUnlocked(
        uint128 indexed unlockPeriod, uint256 indexed availableBalance, address recipient, address indexed fontaine
    );

    /// @notice Event emitted when $FLUID are staked
    event FluidStaked(uint256 indexed newTotalStakedBalance, uint256 indexed addedAmount);

    /// @notice Event emitted when $FLUID are unstaked
    event FluidUnstaked(uint256 indexed newTotalStakedBalance, uint256 indexed removedAmount);

    /// @notice Event emitted when a liquidity position is created
    event LiquidityPositionCreated(uint256 indexed tokenId);

    /// @notice Event emitted when a liquidity position is burned
    event LiquidityPositionBurned(uint256 indexed tokenId);

    //     ______           __                     ______
    //    / ____/_  _______/ /_____  ____ ___     / ____/_____________  __________
    //   / /   / / / / ___/ __/ __ \/ __ `__ \   / __/ / ___/ ___/ __ \/ ___/ ___/
    //  / /___/ /_/ (__  ) /_/ /_/ / / / / / /  / /___/ /  / /  / /_/ / /  (__  )
    //  \____/\__,_/____/\__/\____/_/ /_/ /_/  /_____/_/  /_/   \____/_/  /____/

    /// @notice Error thrown when the caller is not the owner
    error NOT_LOCKER_OWNER();

    /// @notice Error thrown when attempting to perform a forbidden operation
    error FORBIDDEN();

    /// @notice Error thrown when attempting to unlock FLUID from a locker with an invalid unlock period
    error INVALID_UNLOCK_PERIOD();

    /// @notice Error thrown when attempting to unlock FLUID from a locker that does not have available $FLUID
    error NO_FLUID_TO_UNLOCK();

    /// @notice Error thrown when attempting to unstake from locker that does not have staked $FLUID
    error NO_FLUID_TO_UNSTAKE();

    /// @notice Error thrown when attempting to stake or to LP from locker that does not have enough available $FLUID
    error INSUFFICIENT_AVAILABLE_BALANCE();

    /// @notice Error thrown when attempting to unstake from locker that does not have enough staked $FLUID
    error INSUFFICIENT_STAKED_BALANCE();

    /// @notice Error thrown when attempting to unstake while the staking cooldown is not yet elapsed
    error STAKING_COOLDOWN_NOT_ELAPSED();

    /// @notice Error thrown when attempting to withdraw liquidity while the cooldown is not yet elapsed
    error LP_COOLDOWN_NOT_ELAPSED();

    /// @notice Error thrown when attempting to unlock or stake while this operation is not yet available
    error TTE_NOT_ACTIVATED();

    /// @notice Error thrown when attempting to unlock while the Staker Distribution Pool did not distribute units
    error STAKER_DISTRIBUTION_POOL_HAS_NO_UNITS();

    /// @notice Error thrown when attempting to unlock while the Provider Distribution Pool did not distribute units
    error LP_DISTRIBUTION_POOL_HAS_NO_UNITS();

    /// @notice Error thrown when attempting to provide liquidity with an amount greater than the available balance
    error INSUFFICIENT_BALANCE();

    /// @notice Error thrown when attempting to collect fees or withdrawing liquidity while the locker has no position
    error LOCKER_HAS_NO_POSITION();

    /// @notice Error thrown when attempting to provide liquidity to a Uniswap Pool that is not approved
    error LIQUIDITY_POOL_NOT_APPROVED();

    /// @notice Error thrown when attempting to provide liquidity with an amount of ETH sent different than the paired asset amount
    error INSUFFICIENT_ETH_SENT();

    /// @notice Error thrown when attempting to unlock an amount of SUP less than the minimum unlock amount
    error INSUFFICIENT_UNLOCK_AMOUNT();

    /// @notice Error thrown when attempting to unlock an amount of SUP with an invalid unlocking fee
    error INVALID_UNLOCKING_FEE();

    /// @notice Error thrown when attempting to transfer the unlocking fee to the DAO Treasury fails
    error FAILED_TO_TRANSFER_UNLOCKING_FEE();

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Update this locker units within the given program identifier's GDA pool
     * @param programId program identifier corresponding to the unit update
     * @param totalProgramUnits new total amount of units
     * @param nonce nonce associated to the signature provided by Stack
     * @param stackSignature stack signature containing necessary info to update units
     */
    function claim(uint256 programId, uint256 totalProgramUnits, uint256 nonce, bytes memory stackSignature) external;

    /**
     * @notice Batch update this locker units within the given programs identifier's GDA pools
     * @param programIds array of program identifiers corresponding to the unit update
     * @param totalProgramUnits array new total amount of units
     * @param nonce Single nonce used for all updates in the batch
     * @param stackSignature Single signature containing necessary info to update all units in the batch
     */
    function claim(
        uint256[] memory programIds,
        uint256[] memory totalProgramUnits,
        uint256 nonce,
        bytes memory stackSignature
    ) external;

    /**
     * @notice Update this locker units within the given program identifier's GDA pool and stake all available SUP Tokens
     * @param programId program identifier corresponding to the unit update
     * @param totalProgramUnits new total amount of units
     * @param nonce nonce associated to the signature provided by Stack
     * @param stackSignature stack signature containing necessary info to update units
     */
    function claimAndStake(uint256 programId, uint256 totalProgramUnits, uint256 nonce, bytes memory stackSignature)
        external;

    /**
     * @notice Batch update this locker units within the given programs identifier's GDA pools and stake all available SUP Tokens
     * @param programIds array of program identifiers corresponding to the unit update
     * @param totalProgramUnits array new total amount of units
     * @param nonce Single nonce used for all updates in the batch
     * @param stackSignature Single signature containing necessary info to update all units in the batch
     */
    function claimAndStake(
        uint256[] memory programIds,
        uint256[] memory totalProgramUnits,
        uint256 nonce,
        bytes memory stackSignature
    ) external;

    /**
     * @notice Stake all the available FLUID Token of this locker
     * @dev Only this Locker owner can call this function
     * @param amountToStake amount of FLUID Token to stake
     */
    function stake(uint256 amountToStake) external;

    /**
     * @notice Unstake all the staked FLUID Token of this locker
     * @dev Only this Locker owner can call this function
     * @param amountToUnstake amount of FLUID Token to unstake
     */
    function unstake(uint256 amountToUnstake) external;

    /**
     * @notice Lock a given `amount` of FLUID Token in this Locker
     * @dev Requires preliminary token approval
     * @param amount amount of FLUID Token to lock
     */
    function lock(uint256 amount) external;

    /**
     * @notice Unlock the available FLUID Token from this locker and transfer the unlocking fee to the DAO Treasury
     * @dev Only this Locker owner can call this function
     * @param unlockAmount the amount of FLUID Token to unlock
     * @param unlockPeriod the desired unlocking period (instant unlock if sets to 0)
     * @param recipient account to receive the unlocked FLUID tokens
     */
    function unlock(uint256 unlockAmount, uint128 unlockPeriod, address recipient) external payable;

    /**
     * @notice Provides liquidity to a liquidity pool by creating or increasing a position
     * @param supAmount The amount of SUP tokens to provide as liquidity
     * @return positionTokenId The NFT token identifier of the position created
     */
    function provideLiquidity(uint256 supAmount) external payable returns (uint256 positionTokenId);

    /**
     * @notice Withdraws liquidity from a liquidity pool
     * @param tokenId The token identifier of the position to withdraw liquidity from
     * @param liquidityToRemove The amount of liquidity to remove from the position
     * @param amount0ToRemove The amount of token0 to remove from the position
     * @param amount1ToRemove The amount of token1 to remove from the position
     */
    function withdrawLiquidity(
        uint256 tokenId,
        uint128 liquidityToRemove,
        uint256 amount0ToRemove,
        uint256 amount1ToRemove
    ) external;

    /**
     * @notice Collects accumulated fees from a Uniswap V3 position
     * @dev SUP and ETHx fees generated from the position are collected and transferred directly to the locker owner
     * @param tokenId The token identifier of the position to collect fees from
     * @return collectedEthx The amount of ETHx tokens collected
     * @return collectedSup The amount of SUP tokens collected
     */
    function collectFees(uint256 tokenId) external returns (uint256 collectedEthx, uint256 collectedSup);

    /**
     * @notice Helper function which connects the Locker to a program pool
     * @dev Only this Locker owner can call this function
     * @param programId program identifier corresponding to the pool to connect to
     */
    function connect(uint256 programId) external;

    /**
     * @notice Withdraws dust ETH from the locker
     * @dev ETH (dust amount) may be left in the locker during the liquidity provision process.
     * This happens when the pool reserves changes between transaction broadcast and transaction execution.
     * @dev Only this Locker owner can call this function
     */
    function withdrawDustETH() external;

    /**
     * @notice Helper function to help the Locker disconnect from a program pool
     * @notice Helper function which disconnects the Locker from a program pool
     * @dev Only this Locker owner can call this function
     * @param programId program identifier corresponding to the pool to connect to
     */
    function disconnect(uint256 programId) external;

    /**
     * @notice Helper function which disconnects the Locker from multiple program pools
     * @dev Only this Locker owner can call this function
     * @param programIds array of program identifiers corresponding to the pools to disconnect from
     */
    function disconnect(uint256[] memory programIds) external;

    /**
     * @notice Helper function which combines batched disconnectFromPool and claim into one call.
     * @dev Only this Locker owner can call this function
     * @param programIdsToDisconnect array of program identifiers corresponding to the pools to disconnect from
     * @param programIdsToClaim array of program identifiers corresponding to the pools to claim units from
     * @param totalProgramUnits array of total program units to claim
     * @param nonce Single nonce used for all updates in the batch
     * @param stackSignature Single signature containing necessary info to update all units in the batch
     */
    function disconnectAndClaim(
        uint256[] memory programIdsToDisconnect,
        uint256[] memory programIdsToClaim,
        uint256[] memory totalProgramUnits,
        uint256 nonce,
        bytes memory stackSignature
    ) external;

    /**
     * @notice Helper function which combines batched disconnectFromPool, claim and stake into one call.
     * @dev Only this Locker owner can call this function
     * @param programIdsToDisconnect array of program identifiers corresponding to the pools to disconnect from
     * @param programIdsToClaim array of program identifiers corresponding to the pools to claim units from
     * @param totalProgramUnits array of total program units to claim
     * @param nonce Single nonce used for all updates in the batch
     * @param stackSignature Single signature containing necessary info to update all units in the batch
     */
    function disconnectAndClaimAndStake(
        uint256[] memory programIdsToDisconnect,
        uint256[] memory programIdsToClaim,
        uint256[] memory totalProgramUnits,
        uint256 nonce,
        bytes memory stackSignature
    ) external;

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Returns the flowrate received by this Locker for the given program identifier
     * @param programId program identifier to query
     * @return flowRate the flowrate received by this Locker for the given program identifier
     */
    function getFlowRatePerProgram(uint256 programId) external view returns (int96 flowRate);

    /**
     * @notice Returns the flowrates received by this Locker for the given program identifiers
     * @param programIds array of program identifiers to query
     * @return flowRates array of flowrate received by this Locker for the given program identifiers
     */
    function getFlowRatePerProgram(uint256[] memory programIds) external view returns (int96[] memory flowRates);

    /**
     * @notice Returns the amount of GDA units owned by this Locker for the given program identifier
     * @param programId program identifier to query
     * @return units the amount of GDA units owned by this Locker for the given program identifier
     */
    function getUnitsPerProgram(uint256 programId) external view returns (uint128 units);

    /**
     * @notice Returns the amounts of GDA units owned by this Locker for the given program identifiers
     * @param programIds array of program identifiers to query
     * @return units array of GDA units amount owned by this Locker for the given program identifiers
     */
    function getUnitsPerProgram(uint256[] memory programIds) external view returns (uint128[] memory units);

    /**
     * @notice Returns this Lockers' staked FLUID Token balance
     * @return sBalance amount of FLUID Token staked in this Locker
     */
    function getStakedBalance() external view returns (uint256 sBalance);

    /**
     * @notice Returns this Lockers' Uniswap V3 Liquidity balance in the SUP/ETH pool
     * @return lBalance Uniswap V3 Liquidity balance in the SUP/ETH pool
     */
    function getLiquidityBalance() external view returns (uint256 lBalance);

    /**
     * @notice Returns this Lockers' available FLUID Token balance
     * @dev Available balance is the total balance minus the staked balance
     * @return aBalance amount of FLUID Token available in this Locker
     */
    function getAvailableBalance() external view returns (uint256 aBalance);

    /**
     * @notice Returns the fontaine beacon implementation contract address
     * @return fontaineBeaconImpl The fontaine beacon implementation contract address
     */
    function getFontaineBeaconImplementation() external view returns (address fontaineBeaconImpl);

    /**
     * @notice Returns the liquidity of the position for the given token identifier
     * @param tokenId The token identifier of the position to query
     * @return liquidity the liquidity of the position for the given token identifier
     */
    function getPositionLiquidity(uint256 tokenId) external view returns (uint128 liquidity);
}
