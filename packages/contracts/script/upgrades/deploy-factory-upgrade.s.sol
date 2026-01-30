// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title DeployLockerFactoryUpgrade
 * @notice Deployment script for upgrading the FluidLockerFactory implementation
 *
 * @dev This script deploys a new FluidLockerFactory implementation contract with updated immutable parameters.
 *      It includes a safety mechanism to prevent accidental parameter changes.
 *
 *      == Deployment Workflow ==
 *
 *      1. Update the desired parameter values in `AddressRegistry.sol` for the target network
 *
 *      2. For each parameter you intend to change, set the corresponding environment variable to `true`:
 *         - UPDATE_LOCKER_BEACON=true
 *         - UPDATE_STAKING_REWARD_CONTROLLER=true
 *         - UPDATE_IS_PAUSED=true
 *
 *      3. Run the deployment script (see command below)
 *
 *      == Safety Mechanism ==
 *
 *      The script compares each parameter in `AddressRegistry` against the current live implementation.
 *      If a parameter differs and the corresponding env var is NOT set, the script reverts.
 *      This ensures that parameter changes are always intentional and explicitly acknowledged.
 *
 *      == Example ==
 *
 *      To deploy an upgrade that only changes the pause status:
 *      ```
 *      export UPDATE_IS_PAUSED=true
 *      forge script script/upgrades/deploy-factory-upgrade.s.sol:DeployFactoryUpgrade \
 *          --ffi --rpc-url $BASE_MAINNET_RPC_URL --account SUP_DEPLOYER
 *      ```
 */
import { console2 } from "forge-std/console2.sol";
import { SupDeployer } from "script/SupDeployer.s.sol";
import { FluidLockerFactory } from "src/FluidLockerFactory.sol";
import { AddressRegistry } from "script/config/AddressRegistry.sol";
import { IStakingRewardController } from "src/interfaces/IStakingRewardController.sol";

contract DeployFactoryUpgrade is SupDeployer {
    function run() public {
        _showGitRevision();

        uint256 chainId = block.chainid;

        // Get configuration
        AddressRegistry.FactoryDeploymentParameters memory factoryParams =
            AddressRegistry.getFactoryDeploymentParameters(chainId);

        // Get the current live Factory Implementation
        FluidLockerFactory currentFactoryImplementation = FluidLockerFactory(factoryParams.lockerFactory);

        // Validate the deployment parameters - will revert in case of inexplicit parameter change
        _validateDeploymentParameters(currentFactoryImplementation, factoryParams);

        // Start Deployment
        address deployer = _startBroadcast();

        // Log parameters used for deployment
        _logDeploymentParameters(deployer, factoryParams);

        // Deploy the new Factory Implementation
        address newFluidLockerFactoryImplementation = address(
            new FluidLockerFactory(
                factoryParams.lockerBeacon,
                IStakingRewardController(factoryParams.stakingRewardController),
                factoryParams.isPaused
            )
        );

        // Log deployment results
        _logDeploymentResults(newFluidLockerFactoryImplementation);

        _stopBroadcast();
    }

    /**
     * @notice Returns whether or not a parameter should be checked against current implementation
     * @dev if the `paramName` evaluates to true, the check is not necessary
     * @param paramName the env var corresponding to a parameter change
     * @return shouldCheck true if the param should be check (i.e. no update) false otherwise
     */
    function _shouldCheckParam(string memory paramName) internal view returns (bool shouldCheck) {
        shouldCheck = !vm.envOr(paramName, false);
    }

    /**
     * @notice Validates that the new deployment parameters match the current implementation
     * @dev Each parameter check can be bypassed by setting the corresponding env var to true.
     *      This is useful when intentionally updating a specific immutable parameter.
     *
     *      Env vars to bypass checks:
     *      - UPDATE_LOCKER_BEACON: Skip Locker Beacon address validation
     *      - UPDATE_STAKING_REWARD_CONTROLLER: Skip Staking Reward Controller address validation
     *      - UPDATE_IS_PAUSED: Skip pause status validation
     *
     * @param factoryImpl The current FluidLockerFactory implementation to validate against
     * @param factoryParams The deployment parameters containing the new values
     */
    function _validateDeploymentParameters(
        FluidLockerFactory factoryImpl,
        AddressRegistry.FactoryDeploymentParameters memory factoryParams
    ) internal view {
        if (_shouldCheckParam("UPDATE_LOCKER_BEACON")) {
            require(
                address(factoryImpl.LOCKER_BEACON()) == factoryParams.lockerBeacon,
                "LockerBeacon is not meant to be updated"
            );
        }

        if (_shouldCheckParam("UPDATE_STAKING_REWARD_CONTROLLER")) {
            require(
                address(factoryImpl.STAKING_REWARD_CONTROLLER()) == factoryParams.stakingRewardController,
                "StakingRewardController is not meant to be updated"
            );
        }

        if (_shouldCheckParam("UPDATE_IS_PAUSED")) {
            require(factoryImpl.IS_PAUSED() == factoryParams.isPaused, "IsPaused is not meant to be updated");
        }
    }

    function _logDeploymentParameters(
        address deployer,
        AddressRegistry.FactoryDeploymentParameters memory factoryParams
    ) internal pure {
        console2.log("DEPLOYING NEW `FluidLockerFactory` IMPLEMENTATION CONTRACT ..........");
        console2.log("");
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SETTINGS *---------------------------------*");
        console2.log("|                                                                                    ");
        console2.log("| DEPLOYER                                : %s", deployer);
        console2.log("| FACTORY_PROXY_ADDRESS                   : %s", factoryParams.lockerFactory);
        console2.log("| LOCKER_BEACON_ADDRESS                   : %s", factoryParams.lockerBeacon);
        console2.log("| STAKING_REWARD_CONTROLLER_ADDRESS       : %s", factoryParams.stakingRewardController);
        console2.log("| IS_PAUSED                               : %s", factoryParams.isPaused);
        console2.log("|                                                                                    ");
        console2.log("*------------------------------------------------------------------------------------------*");
    }

    function _logDeploymentResults(address newFluidLockerFactoryImplementation) internal pure {
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SUMMARY *----------------------------------*");
        console2.log("|                                                                                          |");
        console2.log("| FluidLockerFactory (Logic)      : deployed at %s |", newFluidLockerFactoryImplementation);
        console2.log("*------------------------------------------------------------------------------------------*");
        console2.log("");
    }
}
