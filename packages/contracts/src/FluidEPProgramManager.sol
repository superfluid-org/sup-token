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
    ISuperfluid,
    ISuperToken,
    ISuperfluidPool,
    PoolConfig,
    PoolERC20Metadata,
    IConstantFlowAgreementV1,
    BatchOperation
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { IUserDefinedMacro } from "@superfluid-finance/ethereum-contracts/contracts/utils/MacroForwarder.sol";

/* FLUID Contracts & Interfaces */
import { EPProgramManager, IEPProgramManager } from "./EPProgramManager.sol";
import { IFluidLockerFactory } from "./interfaces/IFluidLockerFactory.sol";

using SuperTokenV1Library for ISuperToken;
using SafeCast for int256;

/**
 * @title Superfluid Ecosystem Partner Program Manager Contract
 * @author Superfluid
 * @notice Contract responsible for administrating the GDA pool that distribute FLUID to lockers
 *
 */
contract FluidEPProgramManager is Initializable, OwnableUpgradeable, EPProgramManager, IUserDefinedMacro {
    //      ______                 __
    //     / ____/   _____  ____  / /______
    //    / __/ | | / / _ \/ __ \/ __/ ___/
    //   / /___ | |/ /  __/ / / / /_(__  )
    //  /_____/ |___/\___/_/ /_/\__/____/

    /// @notice Event emitted when a reward program is cancelled
    event ProgramCancelled(uint256 indexed programId, uint256 indexed returnedDeposit);

    /// @notice Event emitted when a reward program is funded
    event ProgramFunded(
        uint256 indexed programId,
        uint256 indexed fundingAmount,
        uint256 indexed subsidyAmount,
        uint256 earlyEndDate,
        uint256 endDate
    );

    /// @notice Event emitted when a reward program is stopped
    event ProgramStopped(
        uint256 indexed programId, uint256 indexed fundingCompensationAmount, uint256 indexed subsidyCompensationAmount
    );

    //      ____        __        __
    //     / __ \____ _/ /_____ _/ /___  ______  ___  _____
    //    / / / / __ `/ __/ __ `/ __/ / / / __ \/ _ \/ ___/
    //   / /_/ / /_/ / /_/ /_/ / /_/ /_/ / /_/ /  __(__  )
    //  /_____/\__,_/\__/\__,_/\__/\__, / .___/\___/____/
    //                            /____/_/

    /**
     * @notice Fluid Program related details Data Type
     * @param fundingFlowRate flow rate between this contract and the program pool
     * @param subsidyFlowRate flow rate between the Staking Reward Controller contract and the tax distribution pool
     * @param fundingStartDate timestamp at which the program is funded
     * @param duration program duration
     */
    struct FluidProgramDetails {
        int96 fundingFlowRate;
        int96 subsidyFlowRate;
        uint32 fundingStartDate;
        uint32 duration;
    }

    //     ______           __                     ______
    //    / ____/_  _______/ /_____  ____ ___     / ____/_____________  __________
    //   / /   / / / / ___/ __/ __ \/ __ `__ \   / __/ / ___/ ___/ __ \/ ___/ ___/
    //  / /___/ /_/ (__  ) /_/ /_/ / / / / / /  / /___/ /  / /  / /_/ / /  (__  )
    //  \____/\__,_/____/\__/\____/_/ /_/ /_/  /_____/_/  /_/   \____/_/  /____/

    /// @notice Error thrown when attempting to add units to a non-existant locker
    /// @dev Error Selector : 0x2d2cd50c
    error LOCKER_NOT_FOUND();

    /// @notice Error thrown when attempting to stop a program's funding earlier than expected
    /// @dev Error Selector : 0xc582137f
    error TOO_EARLY_TO_END_PROGRAM();

    /// @notice Error thrown when attempting to start funding a program with a pool that has no units
    /// @dev Error Selector : 0x93005752
    error POOL_HAS_NO_UNITS();

    //      ____                          __        __    __        _____ __        __
    //     /  _/___ ___  ____ ___  __  __/ /_____ _/ /_  / /__     / ___// /_____ _/ /____  _____
    //     / // __ `__ \/ __ `__ \/ / / / __/ __ `/ __ \/ / _ \    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   _/ // / / / / / / / / / / /_/ / /_/ /_/ / /_/ / /  __/   ___/ / /_/ /_/ / /_/  __(__  )
    //  /___/_/ /_/ /_/_/ /_/ /_/\__,_/\__/\__,_/_.___/_/\___/   /____/\__/\__,_/\__/\___/____/

    /// @notice Staking Reward Controller contract interface
    ISuperfluidPool public immutable TAX_DISTRIBUTION_POOL;

    /// @notice Constant used to calculate the earliest date a program can be stopped
    uint256 public constant EARLY_PROGRAM_END = 3 days;

    /// @notice Basis points denominator (for percentage calculation)
    uint96 private constant _BP_DENOMINATOR = 10_000;

    //     _____ __        __
    //    / ___// /_____ _/ /____  _____
    //    \__ \/ __/ __ `/ __/ _ \/ ___/
    //   ___/ / /_/ /_/ / /_/  __(__  )
    //  /____/\__/\__,_/\__/\___/____/

    /// @notice Stores the program details of a given program
    mapping(uint256 programId => FluidProgramDetails programDetails) private _fluidProgramDetails;

    /// @notice Staking subsidy funding rate
    uint96 public subsidyFundingRate;

    /// @notice Fluid Locker Factory interface
    IFluidLockerFactory public fluidLockerFactory;

    /// @notice Fluid treasury account address
    address public fluidTreasury;

    //     ______                 __                  __
    //    / ____/___  ____  _____/ /________  _______/ /_____  _____
    //   / /   / __ \/ __ \/ ___/ __/ ___/ / / / ___/ __/ __ \/ ___/
    //  / /___/ /_/ / / / (__  ) /_/ /  / /_/ / /__/ /_/ /_/ / /
    //  \____/\____/_/ /_/____/\__/_/   \__,_/\___/\__/\____/_/

    /**
     * @notice Superfluid Ecosystem Partner Program Manager constructor
     * @param taxDistributionPool Tax Distribution Pool GDA contract interface
     */
    constructor(ISuperfluidPool taxDistributionPool) {
        // Disable initializers to prevent implementation contract initalization
        _disableInitializers();

        TAX_DISTRIBUTION_POOL = taxDistributionPool;
    }

    /**
     * @notice Superfluid Ecosystem Partner Program Manager initializer
     * @param owner contract owner address
     * @param treasury fluid treasury address
     */
    function initialize(address owner, address treasury) external initializer {
        // Initialize Ownable
        __Ownable_init(owner);

        // Sets the treasury address
        fluidTreasury = treasury;
    }

    //      ______     __                        __   ______                 __  _
    //     / ____/  __/ /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //    / __/ | |/_/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   / /____>  </ /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /_____/_/|_|\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /// @inheritdoc IEPProgramManager
    /// @dev Only the contract owner can perform this operation
    function createProgram(
        uint256 programId,
        address programAdmin,
        address signer,
        ISuperToken token,
        string memory poolName,
        string memory poolSymbol
    ) external override onlyOwner returns (ISuperfluidPool distributionPool) {
        // Input validation
        if (programId == 0) revert INVALID_PARAMETER();
        if (programAdmin == address(0)) revert INVALID_PARAMETER();
        if (signer == address(0)) revert INVALID_PARAMETER();
        if (address(token) == address(0)) revert INVALID_PARAMETER();
        if (address(programs[programId].distributionPool) != address(0)) {
            revert PROGRAM_ALREADY_CREATED();
        }

        // Configure Superfluid GDA Pool
        PoolConfig memory poolConfig =
            PoolConfig({ transferabilityForUnitsOwner: false, distributionFromAnyAddress: true });

        PoolERC20Metadata memory poolERC20Metadata =
            PoolERC20Metadata({ name: poolName, symbol: poolSymbol, decimals: 0 });

        // Create Superfluid GDA Pool
        distributionPool = token.createPoolWithCustomERC20Metadata(address(this), poolConfig, poolERC20Metadata);

        // Persist program details
        programs[programId] = EPProgram({
            programAdmin: programAdmin,
            stackSigner: signer,
            token: token,
            distributionPool: distributionPool
        });

        emit IEPProgramManager.ProgramCreated(
            programId, programAdmin, signer, address(token), address(distributionPool)
        );
    }

    /**
     * @notice Stop flows from this contract to the distribution pool and to the staking reserve.
     *         Return the undistributed funds to the treasury
     *  @dev Only the contract owner can perform this operation
     * @param programId program identifier to cancel
     */
    function cancelProgram(uint256 programId) external onlyOwner {
        EPProgram memory program = programs[programId];
        FluidProgramDetails memory programDetails = _fluidProgramDetails[programId];

        // Ensure program exists or has not already been terminated
        if (programDetails.fundingStartDate == 0) revert IEPProgramManager.INVALID_PARAMETER();

        // Delete the program details
        delete _fluidProgramDetails[programId];

        // Stop the stream to the program pool
        program.token.distributeFlow(address(this), program.distributionPool, 0);

        if (programDetails.subsidyFlowRate > 0) {
            // Decrease the subsidy flow to the tax distribution pool
            _updateSubsidyFlowRate(program.token, -programDetails.subsidyFlowRate);
        }

        // Update the funding flow rate from the treasury
        _updateFundingFlowRateFromTreasury(
            program.token, -(programDetails.fundingFlowRate + programDetails.subsidyFlowRate)
        );

        // Return the initial deposit to the treasury
        uint256 buffer =
            program.token.getBufferAmountByFlowRate(programDetails.fundingFlowRate + programDetails.subsidyFlowRate);
        uint256 initialDeposit =
            buffer + uint96(programDetails.fundingFlowRate + programDetails.subsidyFlowRate) * EARLY_PROGRAM_END;

        program.token.transfer(fluidTreasury, initialDeposit);

        emit ProgramCancelled(programId, initialDeposit);
    }

    /**
     * @notice Programatically calculate and initiate distribution to the GDA pools and staking reserve
     * @dev Only the contract owner can perform this operation
     * @param programId program identifier to start funding
     * @param totalAmount total amount to be distributed (including staking subsidy)
     * @param programDuration program duration
     */
    function startFunding(uint256 programId, uint256 totalAmount, uint32 programDuration) external onlyOwner {
        EPProgram memory program = programs[programId];

        // Ensure program exists
        if (address(program.distributionPool) == address(0)) revert IEPProgramManager.PROGRAM_NOT_FOUND();

        // Check if program pool has units
        if (program.distributionPool.getTotalUnits() == 0) revert POOL_HAS_NO_UNITS();

        // Calculate the funding and subsidy amount
        uint256 subsidyAmount = (totalAmount * subsidyFundingRate) / _BP_DENOMINATOR;
        uint256 fundingAmount = totalAmount - subsidyAmount;

        // Calculate the funding and subsidy flow rates
        int96 subsidyFlowRate = int256(subsidyAmount / programDuration).toInt96();
        int96 fundingFlowRate = int256(fundingAmount / programDuration).toInt96();

        // Persist program details
        _fluidProgramDetails[programId] = FluidProgramDetails({
            fundingFlowRate: fundingFlowRate,
            subsidyFlowRate: subsidyFlowRate,
            fundingStartDate: uint32(block.timestamp),
            duration: programDuration
        });

        // Calculate the initial deposit to cover the CFA buffer and the early end compensation
        uint256 buffer = program.token.getBufferAmountByFlowRate(fundingFlowRate + subsidyFlowRate);
        uint256 initialDeposit = buffer + uint96(fundingFlowRate + subsidyFlowRate) * EARLY_PROGRAM_END;

        // Fetch funds from FLUID Treasury (requires prior approval from the Treasury)
        program.token.transferFrom(fluidTreasury, address(this), initialDeposit);

        // Update the funding flow rate from the treasury
        _updateFundingFlowRateFromTreasury(program.token, fundingFlowRate + subsidyFlowRate);

        // Distribute flow to Program GDA pool
        program.token.distributeFlow(address(this), program.distributionPool, fundingFlowRate);

        if (subsidyFlowRate > 0) {
            // Create or update the subsidy flow to the Staking Reward Controller
            _updateSubsidyFlowRate(program.token, subsidyFlowRate);
        }

        emit ProgramFunded(
            programId,
            fundingAmount,
            subsidyAmount,
            block.timestamp + programDuration - EARLY_PROGRAM_END,
            block.timestamp + programDuration
        );
    }

    /**
     * @notice Stop flows from this contract to the distribution pool and to the staking reserve
     *         Send the undistributed funds to the program pool and tax distribution pool
     * @param programId program identifier to stop funding
     */
    function stopFunding(uint256 programId) external {
        EPProgram memory program = programs[programId];
        FluidProgramDetails memory programDetails = _fluidProgramDetails[programId];

        // Ensure program exists or has not already been terminated
        if (programDetails.fundingStartDate == 0) revert IEPProgramManager.INVALID_PARAMETER();

        uint256 endDate = programDetails.fundingStartDate + programDetails.duration;

        // Ensure time window is valid to stop the funding
        if (block.timestamp < endDate - EARLY_PROGRAM_END) {
            revert TOO_EARLY_TO_END_PROGRAM();
        }

        // Delete the program details
        delete _fluidProgramDetails[programId];

        uint256 earlyEndCompensation;
        uint256 subsidyEarlyEndCompensation;

        // if the program is stopped during its early end period, calculate the flow compensations
        if (block.timestamp < endDate) {
            earlyEndCompensation = (endDate - block.timestamp) * uint96(programDetails.fundingFlowRate);
            subsidyEarlyEndCompensation = (endDate - block.timestamp) * uint96(programDetails.subsidyFlowRate);
        }

        // Stops the distribution flow to the program pool
        program.token.distributeFlow(address(this), program.distributionPool, 0);

        if (programDetails.subsidyFlowRate > 0) {
            // Delete or update the subsidy flow to the Staking Reward Controller
            _updateSubsidyFlowRate(program.token, -programDetails.subsidyFlowRate);
        }

        // Update the funding flow rate from the treasury
        _updateFundingFlowRateFromTreasury(
            program.token, -(programDetails.fundingFlowRate + programDetails.subsidyFlowRate)
        );

        if (earlyEndCompensation > 0) {
            // Distribute the early end compensation to the program pool
            program.token.distribute(address(this), program.distributionPool, earlyEndCompensation);
        }

        if (subsidyEarlyEndCompensation > 0) {
            // Distribute the early end compensation to the stakers pool
            program.token.distribute(address(this), TAX_DISTRIBUTION_POOL, subsidyEarlyEndCompensation);
        }

        emit ProgramStopped(programId, earlyEndCompensation, subsidyEarlyEndCompensation);
    }

    /**
     * @notice Update GDA Pool units of the locker associated to the given user
     * @dev Only the program admin can perform this operation
     * @param programId The ID of the program to update units for
     * @param stackPoints The amount of stack points to set for the user's locker
     * @param user The address of the user whose locker will be updated
     */
    function manualPoolUpdate(uint256 programId, uint256 stackPoints, address user)
        external
        onlyProgramAdmin(programId)
    {
        EPProgram memory program = programs[programId];

        // Get the locker address belonging to the given user
        address locker = fluidLockerFactory.getLockerAddress(user);

        // Ensure the locker exists
        if (locker == address(0)) revert LOCKER_NOT_FOUND();

        // Update the locker's units in the program GDA pool
        program.distributionPool.updateMemberUnits(locker, uint128(stackPoints));
    }

    /**
     * @notice Update GDA Pool units of the locker associated to the given user
     * @dev Only the program admin can perform this operation
     * @param programId The ID of the program to update units for
     * @param stackPoints The amounts of stack points to set for the user's locker
     * @param users The addresses of the users whose lockers will be updated
     */
    function manualPoolUpdate(uint256 programId, uint256[] memory stackPoints, address[] memory users)
        external
        onlyProgramAdmin(programId)
    {
        // Input validation
        if (users.length == 0) revert INVALID_PARAMETER();
        if (users.length != stackPoints.length) revert INVALID_PARAMETER();

        EPProgram memory program = programs[programId];

        for (uint256 i; i < users.length; ++i) {
            // Get the locker address belonging to the given user
            address locker = fluidLockerFactory.getLockerAddress(users[i]);

            // Ensure the locker exists
            if (locker == address(0)) revert LOCKER_NOT_FOUND();

            // Update the locker's units in the program GDA pool
            program.distributionPool.updateMemberUnits(locker, uint128(stackPoints[i]));
        }
    }

    /**
     * @notice Update the Locker Factory contract address
     * @dev Only the contract owner can perform this operation
     * @param lockerFactoryAddress Locker Factory contract address to be set
     */
    function setLockerFactory(address lockerFactoryAddress) external onlyOwner {
        // Input validation
        if (lockerFactoryAddress == address(0)) revert INVALID_PARAMETER();
        fluidLockerFactory = IFluidLockerFactory(lockerFactoryAddress);
    }

    /**
     * @notice Update the Treasury address
     * @dev Only the contract owner can perform this operation
     * @param treasuryAddress Treasury address to be set
     */
    function setTreasury(address treasuryAddress) external onlyOwner {
        // Input validation
        if (treasuryAddress == address(0)) revert INVALID_PARAMETER();
        fluidTreasury = treasuryAddress;
    }

    /**
     * @notice Update the Staking Subsidy Rate
     * @dev Only the contract owner can perform this operation
     * @param subsidyRate Subsidy rate to be set (expressed in basis points)
     */
    function setSubsidyRate(uint96 subsidyRate) external onlyOwner {
        // Input validation
        if (subsidyRate > _BP_DENOMINATOR) revert INVALID_PARAMETER();
        subsidyFundingRate = subsidyRate;
    }

    /**
     * @notice Withdraw all funds from this contract to the treasury
     * @dev Only the contract owner can perform this operation
     * @param token token contract address
     */
    function emergencyWithdraw(ISuperToken token) external onlyOwner {
        token.transfer(fluidTreasury, token.balanceOf(address(this)));
    }

    /**
     * @notice Upgrade this proxy logic
     * @dev Only the owner address can perform this operation
     * @param newImplementation new logic contract address
     * @param data calldata for potential initializer
     */
    function upgradeTo(address newImplementation, bytes calldata data) external onlyOwner {
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }

    // IUserDefinedMacro

    /**
     * @notice Returns the batch operations to be executed by the treasury using the MacroForwarder
     * @inheritdoc IUserDefinedMacro
     */
    function buildBatchOperations(ISuperfluid host, bytes memory params, address /*msgSender*/ )
        external
        view
        override
        returns (ISuperfluid.Operation[] memory operations)
    {
        // parse params
        (ISuperToken token, uint256 depositAllowance, int96 flowRateAllowance) =
            abi.decode(params, (ISuperToken, uint256, int96));
        // construct batch operations
        operations = new ISuperfluid.Operation[](2);

        // approval for transfer
        operations[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC20_APPROVE, // type
            target: address(token),
            data: abi.encode(address(this), depositAllowance)
        });

        // flowrateAllowance for flow
        {
            IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(
                address(host.getAgreementClass(keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")))
            );
            uint8 permissions = 1 | 1 << 1 | 1 << 2; // create/update/delete
            bytes memory callData = abi.encodeCall(
                cfa.increaseFlowRateAllowanceWithPermissions,
                (token, address(this), permissions, flowRateAllowance, new bytes(0))
            );
            operations[1] = ISuperfluid.Operation({
                operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT, // type
                target: address(cfa),
                data: abi.encode(callData, new bytes(0))
            });
        }
    }

    /// @inheritdoc IUserDefinedMacro
    function postCheck(ISuperfluid host, bytes memory params, address msgSender) external view { }

    /// @notice convenience view function for encoding the params argument to be provided to MacroForwarder.runMacro()
    function paramsGivePermission(uint256 programId, uint256 amount, uint32 duration)
        external
        view
        returns (bytes memory)
    {
        (uint256 depositAllowance, int96 flowRateAllowance) = calculateAllowances(programId, amount, duration);

        // getRequiredPermissions(token, amount);
        return abi.encode(programs[programId].token, depositAllowance, flowRateAllowance);
    }

    //   _    ___                 ______                 __  _
    //  | |  / (_)__ _      __   / ____/_  ______  _____/ /_(_)___  ____  _____
    //  | | / / / _ \ | /| / /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //  | |/ / /  __/ |/ |/ /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  |___/_/\___/|__/|__/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Returns the given `programId` program details
     * @param programId program identifier to query
     * @return details the program details associated to the given `programId`
     */
    function getProgramDetails(uint256 programId) external view returns (FluidProgramDetails memory details) {
        details = _fluidProgramDetails[programId];
    }

    /**
     * @notice Calculate the required deposit and flow rate allowances for a program
     * @param programId The ID of the program to calculate allowances for
     * @param plannedFundingAmount The total amount planned to be distributed over the program duration
     * @param plannedProgramDuration Program Planned Duration (in seconds)
     * @return depositAllowance The required deposit allowance to cover buffer and early end compensation
     * @return flowRateAllowance The required ACL flow rate allowance to be granted
     */
    function calculateAllowances(uint256 programId, uint256 plannedFundingAmount, uint32 plannedProgramDuration)
        public
        view
        returns (uint256 depositAllowance, int96 flowRateAllowance)
    {
        EPProgram memory program = programs[programId];

        flowRateAllowance = int256(plannedFundingAmount / plannedProgramDuration).toInt96();

        uint256 buffer = program.token.getBufferAmountByFlowRate(flowRateAllowance);
        depositAllowance = buffer + uint96(flowRateAllowance) * EARLY_PROGRAM_END;
    }

    //      ____      __                        __   ______                 __  _
    //     /  _/___  / /____  _________  ____ _/ /  / ____/_  ______  _____/ /_(_)___  ____  _____
    //     / // __ \/ __/ _ \/ ___/ __ \/ __ `/ /  / /_  / / / / __ \/ ___/ __/ / __ \/ __ \/ ___/
    //   _/ // / / / /_/  __/ /  / / / / /_/ / /  / __/ / /_/ / / / / /__/ /_/ / /_/ / / / (__  )
    //  /___/_/ /_/\__/\___/_/  /_/ /_/\__,_/_/  /_/    \__,_/_/ /_/\___/\__/_/\____/_/ /_/____/

    /**
     * @notice Update GDA Pool units of the locker associated to the given user
     * @param program The program associated with the update
     * @param stackPoints Amount of stack points
     * @param user The user address to receive the units
     */
    function _poolUpdate(EPProgram memory program, uint256 stackPoints, address user) internal override {
        // Get the locker address belonging to the given user
        address locker = fluidLockerFactory.getLockerAddress(user);

        // Ensure the locker exists
        if (locker == address(0)) revert LOCKER_NOT_FOUND();

        // Update the locker's units in the program GDA pool
        // NOTE : when the locker owner has a linked SF wallet, the signed total is expected to
        // already cover both addresses' points (the backend aggregates them off-chain)
        program.distributionPool.updateMemberUnits(locker, uint128(stackPoints));
    }

    /**
     * @notice Update the funding flow rate from the treasury to this contract
     * @param token The SuperToken used for the flow
     * @param fundingFlowRateDelta The delta to apply to the current flow rate
     * @return newFundingFlowRate The new flow rate after applying the delta
     */
    function _updateFundingFlowRateFromTreasury(ISuperToken token, int96 fundingFlowRateDelta)
        internal
        returns (int96 newFundingFlowRate)
    {
        // Fetch current flow between the treasury and this contract
        int96 currentGlobalFundingFlowRate = token.getFlowRate(fluidTreasury, address(this));

        // Calculate the new funding flow rate
        newFundingFlowRate = currentGlobalFundingFlowRate + fundingFlowRateDelta;

        // Update the CFA flow rate from the treasury to this contract
        if (newFundingFlowRate >= 0) {
            token.flowFrom(fluidTreasury, address(this), newFundingFlowRate);
        } else {
            // This case should never happen unless the treasury screws up
            token.flowFrom(fluidTreasury, address(this), 0);
        }
    }

    /**
     * @notice Update the subsidy flow rate from this contract to the tax distribution pool
     * @param token The SuperToken used for the flow
     * @param subsidyFlowRateDelta The delta to apply to the current flow rate
     * @return newSubsidyFlowRate The new flow rate after applying the delta
     */
    function _updateSubsidyFlowRate(ISuperToken token, int96 subsidyFlowRateDelta)
        internal
        returns (int96 newSubsidyFlowRate)
    {
        // Fetch current flow between this contract and the tax distribution pool
        int96 currentSubsidyFlowRate = token.getFlowDistributionFlowRate(address(this), TAX_DISTRIBUTION_POOL);

        // Calculate the new subsidy flow rate
        newSubsidyFlowRate = currentSubsidyFlowRate + subsidyFlowRateDelta;

        // Update the distribution flow rate to the tax distribution pool
        if (newSubsidyFlowRate >= 0) {
            token.distributeFlow(address(this), TAX_DISTRIBUTION_POOL, newSubsidyFlowRate);
        } else {
            // This case should never happen
            token.distributeFlow(address(this), TAX_DISTRIBUTION_POOL, 0);
        }
    }
}
