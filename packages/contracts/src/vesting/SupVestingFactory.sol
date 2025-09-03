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

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/* Superfluid Protocol Contracts & Interfaces */
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { IVestingSchedulerV2 } from
    "@superfluid-finance/automation-contracts/scheduler/contracts/interface/IVestingSchedulerV2.sol";

/* SUP Token Vesting Interfaces */
import { ISupVestingFactory } from "../interfaces/vesting/ISupVestingFactory.sol";
import { SupVesting } from "./SupVesting.sol";

using SuperTokenV1Library for ISuperToken;
using SafeCast for int256;

/**
 * @title SUP Token Vesting Factory Contract
 * @author Superfluid
 * @notice Contract deploying new SUP Token Vesting contracts
 */
contract SupVestingFactory is ISupVestingFactory {
    //      ____                          __        __    __        _____ __        __
    //     /  _/___ ___  ____ ___  __  __/ /_____ _/ /_  / /__     / ___// /_____ _/ /____  _____
    //     / // __ `__ \/ __ `__ \/ / / / __/ __ `/ __ \/ / _ \    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   _/ // / / / / / / / / / / /_/ / /_/ /_/ / /_/ / /  __/   ___/ / /_/ /_/ / /_/  __(__  )
    //  /___/_/ /_/ /_/_/ /_/ /_/\__,_/\__/\__,_/_.___/_/\___/   /____/\__/\__,_/\__/\___/____/

    /// @notice Superfluid Vesting Scheduler contract address
    IVestingSchedulerV2 public immutable VESTING_SCHEDULER;

    /// @notice SUP Token contract address
    ISuperToken public immutable SUP;

    /// @notice Minimum cliff period for a vesting contract
    uint256 public constant MIN_CLIFF_PERIOD = 3 days;

    //     _____ __        __
    //    / ___// /_____ _/ /____  _____
    //    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   ___/ / /_/ /_/ / /_/  __(__  )
    //  /____/\__/\__,_/\__/\___/____/

    /// @notice Name of the lockedSUP Token
    string public name;

    /// @notice Symbol of the lockedSUP Token
    string public symbol;

    /// @notice Decimals of the lockedSUP Token
    uint256 public decimals;

    /// @notice Foundation treasury address
    address public treasury;

    /// @notice Foundation admin address
    address public admin;

    /// @notice Mapping of recipient addresses to their corresponding SUP Token Vesting contracts
    mapping(address recipient => address[] supVesting) public supVestings;

    /// @notice List of recipient addresses
    address[] public recipients;

    //     ______                 __                  __
    //    / ____/___  ____  _____/ /________  _______/ /_____  _____
    //   / /   / __ \/ __ \/ ___/ __/ ___/ / / / ___/ __/ __ \/ ___/
    //  / /___/ /_/ / / / (__  ) /_/ /  / /_/ / /__/ /_/ /_/ / /
    //  \____/\____/_/ /_/____/\__/_/   \__,_/\___/\__/\____/_/

    /**
     * @notice SupVestingFactory contract constructor
     * @param vestingScheduler The Superfluid vesting scheduler contract
     * @param token The SUP token contract
     * @param treasuryAddress The foundation treasury address
     * @param adminAddress The foundation admin address
     */
    constructor(
        IVestingSchedulerV2 vestingScheduler,
        ISuperToken token,
        address treasuryAddress,
        address adminAddress
    ) {
        // Persist state variables
        VESTING_SCHEDULER = vestingScheduler;
        SUP = token;
        treasury = treasuryAddress;
        admin = adminAddress;
        name = "Locked SUP Token";
        symbol = "lockedSUP";
        decimals = 18;
    }

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc ISupVestingFactory
    function createSupVestingContract(
        address recipient,
        uint256 recipientVestingIndex,
        uint256 amount,
        uint256 cliffAmount,
        uint32 cliffDate,
        uint32 endDate
    ) external onlyAdmin returns (address newSupVestingContract) {
        if (cliffDate < block.timestamp + MIN_CLIFF_PERIOD) revert FORBIDDEN();
        if (!(cliffAmount < amount)) revert FORBIDDEN();
        if (supVestings[recipient].length != recipientVestingIndex) {
            revert VESTING_DUPLICATED();
        }

        // If it is the first schedule for this recipient, add the recipient to the array
        if (recipientVestingIndex == 0) {
            recipients.push(recipient);
        }

        uint256 vestingDuration = endDate - cliffDate;

        uint256 vestingAmount = amount - cliffAmount;
        int96 flowRate = int256(vestingAmount / vestingDuration).toInt96();

        // Add the remainder to the cliff amount
        cliffAmount += vestingAmount - (uint96(flowRate) * vestingDuration);

        // Deploy the new SUP Token Vesting contract
        newSupVestingContract =
            address(new SupVesting(VESTING_SCHEDULER, SUP, recipient, cliffDate, flowRate, cliffAmount, endDate));

        // Maps the recipient address to the new SUP Token Vesting contract
        supVestings[recipient].push(newSupVestingContract);

        // Transfer the tokens from the treasury to the new vesting contract
        SUP.transferFrom(treasury, newSupVestingContract, amount);

        // Emit the events
        emit Transfer(address(0), recipient, amount);
        emit SupVestingCreated(recipient, newSupVestingContract);
    }

    /// @inheritdoc ISupVestingFactory
    function setTreasury(address newTreasury) external onlyTreasury {
        // Ensure the new treasury address is not the zero address
        if (newTreasury == address(0)) revert FORBIDDEN();
        treasury = newTreasury;
    }

    /// @inheritdoc ISupVestingFactory
    function setAdmin(address newAdmin) external onlyTreasuryOrAdmin {
        // Ensure the new admin address is not the zero address
        if (newAdmin == address(0)) revert FORBIDDEN();
        admin = newAdmin;
    }

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc ISupVestingFactory
    function balanceOf(address vestingReceiver) public view returns (uint256 unvestedBalance) {
        for (uint256 i; i < supVestings[vestingReceiver].length; ++i) {
            // Get the flow buffer amount
            (,, uint256 deposit,) = SUP.getFlowInfo(supVestings[vestingReceiver][i], vestingReceiver);

            unvestedBalance += SUP.balanceOf(supVestings[vestingReceiver][i]) + deposit;
        }
    }

    /// @inheritdoc ISupVestingFactory
    function totalSupply() external view returns (uint256 supply) {
        uint256 length = recipients.length;

        for (uint256 i; i < length; ++i) {
            supply += balanceOf(recipients[i]);
        }
    }

    //      __  ___          ___ _____
    //     /  |/  /___  ____/ (_) __(_)__  __________
    //    / /|_/ / __ \/ __  / / /_/ / _ \/ ___/ ___/
    //   / /  / / /_/ / /_/ / / __/ /  __/ /  (__  )
    //  /_/  /_/\____/\__,_/_/_/ /_/\___/_/  /____/

    /**
     * @notice Modifier to restrict access to treasury or admin only
     */
    modifier onlyTreasuryOrAdmin() {
        if (msg.sender != treasury && msg.sender != admin) revert FORBIDDEN();
        _;
    }

    /**
     * @notice Modifier to restrict access to admin only
     */
    modifier onlyAdmin() {
        if (msg.sender != admin) revert FORBIDDEN();
        _;
    }

    /**
     * @notice Modifier to restrict access to treasury only
     */
    modifier onlyTreasury() {
        if (msg.sender != treasury) revert FORBIDDEN();
        _;
    }
}
