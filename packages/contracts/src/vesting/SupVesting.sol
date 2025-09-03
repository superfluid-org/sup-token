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
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { IVestingSchedulerV2 } from
    "@superfluid-finance/automation-contracts/scheduler/contracts/interface/IVestingSchedulerV2.sol";

/* SUP Token Vesting Interfaces */
import { ISupVestingFactory } from "../interfaces/vesting/ISupVestingFactory.sol";
import { ISupVesting } from "../interfaces/vesting/ISupVesting.sol";

using SuperTokenV1Library for ISuperToken;

/**
 * @title SUP Token Vesting Contract
 * @author Superfluid
 * @notice Contract holding unvested SUP tokens and acting as sender for the vesting scheduler
 */
contract SupVesting is ISupVesting {
    //      ____                          __        __    __        _____ __        __
    //     /  _/___ ___  ____ ___  __  __/ /_____ _/ /_  / /__     / ___// /_____ _/ /____  _____
    //     / // __ `__ \/ __ `__ \/ / / / __/ __ `/ __ \/ / _ \    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   _/ // / / / / / / / / / / /_/ / /_/ /_/ / /_/ / /  __/   ___/ / /_/ /_/ / /_/  __(__  )
    //  /___/_/ /_/ /_/_/ /_/ /_/\__,_/\__/\__,_/_.___/_/\___/   /____/\__/\__,_/\__/\___/____/

    /// @notice SUP Vesting Factory contract address
    ISupVestingFactory public immutable FACTORY;

    /// @notice Vesting Recipient address
    address public immutable RECIPIENT;

    /// @notice Superfluid Vesting Scheduler contract address
    IVestingSchedulerV2 public immutable VESTING_SCHEDULER;

    /// @notice SUP Token contract address
    ISuperToken public immutable SUP;

    //     ______                 __                  __
    //    / ____/___  ____  _____/ /________  _______/ /_____  _____
    //   / /   / __ \/ __ \/ ___/ __/ ___/ / / / ___/ __/ __ \/ ___/
    //  / /___/ /_/ / / / (__  ) /_/ /  / /_/ / /__/ /_/ /_/ / /
    //  \____/\____/_/ /_/____/\__/_/   \__,_/\___/\__/\____/_/

    /**
     * @notice SupVesting contract constructor
     * @param vestingScheduler The Superfluid vesting scheduler contract
     * @param sup The SUP token contract
     * @param recipient The recipient of the vested tokens
     * @param cliffDate The timestamp when the cliff period ends and the flow can start
     * @param flowRate The rate at which tokens are streamed after the cliff period
     * @param cliffAmount The amount of tokens released at the cliff date
     * @param endDate The timestamp when the vesting schedule ends
     */
    constructor(
        IVestingSchedulerV2 vestingScheduler,
        ISuperToken sup,
        address recipient,
        uint32 cliffDate,
        int96 flowRate,
        uint256 cliffAmount,
        uint32 endDate
    ) {
        // Persist the admin, recipient, and vesting scheduler addresses
        RECIPIENT = recipient;
        VESTING_SCHEDULER = vestingScheduler;
        SUP = sup;
        FACTORY = ISupVestingFactory(msg.sender);

        // Grant flow and token allowances
        sup.setMaxFlowPermissions(address(vestingScheduler));
        sup.approve(address(vestingScheduler), type(uint256).max);

        // Create the vesting schedule for this recipient
        vestingScheduler.createVestingSchedule(
            sup,
            recipient,
            uint32(block.timestamp),
            cliffDate,
            flowRate,
            cliffAmount,
            endDate,
            0 /* claimValidityDate */
        );
    }

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc ISupVesting
    function emergencyWithdraw() external onlyAdmin {
        // Close the flow between this contract and the recipient
        SUP.flow(RECIPIENT, 0);

        IVestingSchedulerV2.VestingSchedule memory vs =
            VESTING_SCHEDULER.getVestingSchedule(address(SUP), address(this), RECIPIENT);
        if (vs.endDate != 0) {
            // Delete the vesting schedule if it is not already deleted
            VESTING_SCHEDULER.deleteVestingSchedule(SUP, RECIPIENT, bytes(""));
        }
        // Fetch the remaining balance of the vesting contract
        uint256 remainingBalance = SUP.balanceOf(address(this));

        // Transfer the remaining SUP tokens to the treasury
        SUP.transfer(FACTORY.treasury(), remainingBalance);

        // Emit the `VestingDeleted` event
        emit VestingDeleted(remainingBalance);
    }

    //      __  ___          ___ _____
    //     /  |/  /___  ____/ (_) __(_)__  __________
    //    / /|_/ / __ \/ __  / / /_/ / _ \/ ___/ ___/
    //   / /  / / /_/ / /_/ / / __/ /  __/ /  (__  )
    //  /_/  /_/\____/\__,_/_/_/ /_/\___/_/  /____/

    /**
     * @notice Modifier to restrict access to admin only
     */
    modifier onlyAdmin() {
        if (msg.sender != FACTORY.admin()) revert FORBIDDEN();
        _;
    }
}
