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
 * @title SUP Token Vesting Factory Contract Interface
 * @author Superfluid
 * @notice Contract deploying new SUP Token Vesting contracts
 */
interface ISupVestingFactory {
    //      ______                 __
    //     / ____/   _____  ____  / /______
    //    / __/ | | / / _ \/ __ \/ __/ ___/
    //   / /___ | |/ /  __/ / / / /_(__  )
    //  /_____/ |___/\___/_/ /_/\__/____/

    /// @notice Event emitted when a new SUP token vesting contract is created
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Event emitted when a new SUP token vesting contract is created
    event SupVestingCreated(address indexed recipient, address indexed newSupVestingContract);

    //     ______           __                     ______
    //    / ____/_  _______/ /_____  ____ ___     / ____/_____________  __________
    //   / /   / / / / ___/ __/ __ \/ __ `__ \   / __/ / ___/ ___/ __ \/ ___/ ___/
    //  / /___/ /_/ (__  ) /_/ /_/ / / / / / /  / /___/ /  / /  / /_/ / /  (__  )
    //  \____/\__,_/____/\__/\____/_/ /_/ /_/  /_____/_/  /_/   \____/_/  /____/

    /// @notice Error thrown when the caller is not the foundation treasury
    error FORBIDDEN();

    /// @notice Error thrown when a recipient already has a vesting contract at the given vesting index
    error VESTING_DUPLICATED();

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Creates a SUP token vesting contract for a recipient
     * @param recipient The address that will receive the vested tokens
     * @param recipientVestingIndex The expected count of pre-existing schedules for the given `recipient` (0 if none exists)
     * @param amount The total amount of SUP tokens to be vested
     * @param cliffAmount The amount of SUP tokens that will be transferred at cliff date
     * @param cliffDate The timestamp when the cliff period ends and the flow can start
     * @param endDate The timestamp when the vesting schedule ends
     * @return newSupVestingContract The address of the newly created vesting contract
     */
    function createSupVestingContract(
        address recipient,
        uint256 recipientVestingIndex,
        uint256 amount,
        uint256 cliffAmount,
        uint32 cliffDate,
        uint32 endDate
    ) external returns (address newSupVestingContract);

    /**
     * @notice Updates the treasury address
     * @param newTreasury The new treasury address to set
     * @dev The treasury is meant to be a multisig
     * @dev Can only be called by the treasury itself
     */
    function setTreasury(address newTreasury) external;

    /**
     * @notice Updates the admin address
     * @param newAdmin The new admin address to set
     * @dev The admin is originally meant to be an operational EOA then be updated to a multisig
     * @dev Can only be called by either the admin or the treasury
     */
    function setAdmin(address newAdmin) external;

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Gets the unvested token balance of a given vesting receiver
     * @param vestingReceiver The address of the vesting receiver to query
     * @return unvestedBalance The sum of the vesting contract's token balance and the pending flow deposits
     */
    function balanceOf(address vestingReceiver) external view returns (uint256 unvestedBalance);

    /**
     * @notice Gets the total supply of LockedSUP tokens (unvested SUP Tokens)
     * @return supply The total supply of LockedSUP tokens
     */
    function totalSupply() external view returns (uint256 supply);

    /**
     * @notice Gets the admin address
     * @return admin The current admin address
     */
    function admin() external view returns (address admin);

    /**
     * @notice Gets the treasury address
     * @return treasury The current treasury address
     */
    function treasury() external view returns (address treasury);
}
