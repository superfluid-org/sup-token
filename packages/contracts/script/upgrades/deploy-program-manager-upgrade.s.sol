// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title DeployEPProgramManagerUpgrade
 * @notice Deployment script for upgrading the FluidEPProgramManager implementation
 *
 * @dev This script deploys a new FluidEPProgramManager implementation contract with updated immutable parameters.
 *      It includes a safety mechanism to prevent accidental parameter changes.
 *
 *      == Deployment Workflow ==
 *
 *      1. Update the desired parameter values in `AddressRegistry.sol` for the target network
 *
 *      2. For each parameter you intend to change, set the corresponding environment variable to `true`:
 *         - UPDATE_TAX_DISTRIBUTION_POOL=true
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
 *      To deploy an upgrade that changes the tax distribution pool address:
 *      ```
 *      export UPDATE_TAX_DISTRIBUTION_POOL=true
 *      forge script script/upgrades/deploy-program-manager-upgrade.s.sol:DeployProgramManagerUpgrade \
 *          --ffi --rpc-url $BASE_MAINNET_RPC_URL --account SUP_DEPLOYER
 *      ```
 */
import { console2 } from "forge-std/console2.sol";
import { SupDeployer } from "script/SupDeployer.s.sol";
import { FluidEPProgramManager } from "src/FluidEPProgramManager.sol";
import { AddressRegistry } from "script/config/AddressRegistry.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

contract DeployProgramManagerUpgrade is SupDeployer {
    function run() public {
        _showGitRevision();

        uint256 chainId = block.chainid;

        // Get configuration
        AddressRegistry.ProgramManagerDeploymentParameters memory pmParams =
            AddressRegistry.getProgramManagerDeploymentParameters(chainId);

        // Get the current live EPProgramManager Implementation
        FluidEPProgramManager currentPmImplementation = FluidEPProgramManager(pmParams.programManager);

        // Validate the deployment parameters - will revert in case of inexplicit parameter change
        _validateDeploymentParameters(currentPmImplementation, pmParams);

        // Start Deployment
        address deployer = _startBroadcast();

        // Log parameters used for deployment
        _logDeploymentParameters(deployer, pmParams);

        // Deploy the new EPProgramManager Implementation
        address newEPProgramManagerImplementation =
            address(new FluidEPProgramManager(ISuperfluidPool(pmParams.taxDistributionPool)));

        // Log deployment results
        _logDeploymentResults(newEPProgramManagerImplementation);

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
     *      - UPDATE_TAX_DISTRIBUTION_POOL: Skip Tax Distribution Pool address validation
     *
     * @param epmImpl The current FluidEPProgramManager implementation to validate against
     * @param pmParams The deployment parameters containing the new values
     */
    function _validateDeploymentParameters(
        FluidEPProgramManager epmImpl,
        AddressRegistry.ProgramManagerDeploymentParameters memory pmParams
    ) internal view {
        if (_shouldCheckParam("UPDATE_TAX_DISTRIBUTION_POOL")) {
            require(
                address(epmImpl.TAX_DISTRIBUTION_POOL()) == pmParams.taxDistributionPool,
                "TaxDistributionPool is not meant to be updated"
            );
        }
    }

    function _logDeploymentParameters(
        address deployer,
        AddressRegistry.ProgramManagerDeploymentParameters memory pmParams
    ) internal pure {
        console2.log("DEPLOYING NEW `FluidEPProgramManager` IMPLEMENTATION CONTRACT ..........");
        console2.log("");
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SETTINGS *---------------------------------*");
        console2.log("|                                                                                    ");
        console2.log("| DEPLOYER                                : %s", deployer);
        console2.log("| PROGRAM_MANAGER_ADDRESS                 : %s", pmParams.programManager);
        console2.log("| TAX_DISTRIBUTION_POOL_ADDRESS           : %s", pmParams.taxDistributionPool);
        console2.log("|                                                                                    ");
        console2.log("*------------------------------------------------------------------------------------------*");
    }

    function _logDeploymentResults(address newEPProgramManagerImplementation) internal pure {
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SUMMARY *----------------------------------*");
        console2.log("|                                                                                          |");
        console2.log("| FluidEPProgramManager (Logic)   : deployed at %s |", newEPProgramManagerImplementation);
        console2.log("*------------------------------------------------------------------------------------------*");
        console2.log("");
    }
}
