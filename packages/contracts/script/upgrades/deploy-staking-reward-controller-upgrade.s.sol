// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title DeployStakingRewardControllerUpgrade
 * @notice Deployment script for upgrading the StakingRewardController implementation
 *
 * @dev This script deploys a new StakingRewardController implementation contract with updated immutable parameters.
 *      It includes a safety mechanism to prevent accidental parameter changes.
 *
 *      == Deployment Workflow ==
 *
 *      1. Update the desired parameter values in `AddressRegistry.sol` for the target network
 *
 *      2. For each parameter you intend to change, set the corresponding environment variable to `true`:
 *         - UPDATE_SUP=true
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
 *      To deploy an upgrade that changes the SUP token address:
 *      ```
 *      export UPDATE_SUP=true
 *      forge script script/upgrades/deploy-staking-reward-controller-upgrade.s.sol:DeployStakingRewardControllerUpgrade \
 *          --ffi --rpc-url $BASE_MAINNET_RPC_URL --account SUP_DEPLOYER
 *      ```
 */
import { console2 } from "forge-std/console2.sol";
import { SupDeployer } from "script/SupDeployer.s.sol";
import { StakingRewardController } from "src/StakingRewardController.sol";
import { AddressRegistry } from "script/config/AddressRegistry.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract DeployStakingRewardControllerUpgrade is SupDeployer {
    function run() public {
        _showGitRevision();

        uint256 chainId = block.chainid;

        // Get configuration
        AddressRegistry.StakingRewardControllerDeploymentParameters memory srcParams =
            AddressRegistry.getStakingRewardControllerDeploymentParameters(chainId);

        // Get the current live StakingRewardController Implementation
        StakingRewardController currentSrcImplementation = StakingRewardController(srcParams.stakingRewardController);

        // Validate the deployment parameters - will revert in case of inexplicit parameter change
        _validateDeploymentParameters(currentSrcImplementation, srcParams);

        // Start Deployment
        address deployer = _startBroadcast();

        // Log parameters used for deployment
        _logDeploymentParameters(deployer, srcParams);

        // Deploy the new StakingRewardController Implementation
        address newStakingRewardControllerImplementation =
            address(new StakingRewardController(ISuperToken(srcParams.sup)));

        // Log deployment results
        _logDeploymentResults(newStakingRewardControllerImplementation);

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
     *      - UPDATE_SUP: Skip SUP token address validation
     *
     * @param srcImpl The current StakingRewardController implementation to validate against
     * @param srcParams The deployment parameters containing the new values
     */
    function _validateDeploymentParameters(
        StakingRewardController srcImpl,
        AddressRegistry.StakingRewardControllerDeploymentParameters memory srcParams
    ) internal view {
        if (_shouldCheckParam("UPDATE_SUP")) {
            require(address(srcImpl.FLUID()) == srcParams.sup, "SUP is not meant to be updated");
        }
    }

    function _logDeploymentParameters(
        address deployer,
        AddressRegistry.StakingRewardControllerDeploymentParameters memory srcParams
    ) internal pure {
        console2.log("DEPLOYING NEW `StakingRewardController` IMPLEMENTATION CONTRACT ..........");
        console2.log("");
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SETTINGS *---------------------------------*");
        console2.log("|                                                                                    ");
        console2.log("| DEPLOYER                                : %s", deployer);
        console2.log("| STAKING_REWARD_CONTROLLER_ADDRESS       : %s", srcParams.stakingRewardController);
        console2.log("| SUP_ADDRESS                             : %s", srcParams.sup);
        console2.log("|                                                                                    ");
        console2.log("*------------------------------------------------------------------------------------------*");
    }

    function _logDeploymentResults(address newStakingRewardControllerImplementation) internal pure {
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SUMMARY *----------------------------------*");
        console2.log("|                                                                                          |");
        console2.log(
            "| StakingRewardController (Logic) : deployed at %s |", newStakingRewardControllerImplementation
        );
        console2.log("*------------------------------------------------------------------------------------------*");
        console2.log("");
    }
}
