// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title DeployFontaineUpgrade
 * @notice Deployment script for upgrading the Fontaine implementation
 *
 * @dev This script deploys a new Fontaine implementation contract with updated immutable parameters.
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
 *      forge script script/upgrades/deploy-fontaine-upgrade.s.sol:DeployFontaineUpgrade \
 *          --ffi --rpc-url $BASE_MAINNET_RPC_URL --account SUP_DEPLOYER
 *      ```
 */
import { console2 } from "forge-std/console2.sol";
import { SupDeployer } from "script/SupDeployer.s.sol";
import { Fontaine } from "src/Fontaine.sol";
import { AddressRegistry } from "script/config/AddressRegistry.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

contract DeployFontaineUpgrade is SupDeployer {
    function run() public {
        _showGitRevision();

        uint256 chainId = block.chainid;

        // Get configuration
        AddressRegistry.FontaineDeploymentParameters memory fontaineParams =
            AddressRegistry.getFontaineDeploymentParameters(chainId);

        // Get the current live Fontaine Implementation from the beacon
        UpgradeableBeacon fontaineBeacon = UpgradeableBeacon(fontaineParams.fontaineBeacon);
        Fontaine currentFontaineImplementation = Fontaine(fontaineBeacon.implementation());

        // Validate the deployment parameters - will revert in case of inexplicit parameter change
        _validateDeploymentParameters(currentFontaineImplementation, fontaineParams);

        // Start Deployment
        address deployer = _startBroadcast();

        // Log parameters used for deployment
        _logDeploymentParameters(deployer, fontaineParams);

        // Deploy the new Fontaine Implementation
        address newFontaineImplementation = address(new Fontaine(ISuperToken(fontaineParams.sup)));

        // Log deployment results
        _logDeploymentResults(newFontaineImplementation);

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
     * @param fontaineImpl The current Fontaine implementation to validate against
     * @param fontaineParams The deployment parameters containing the new values
     */
    function _validateDeploymentParameters(
        Fontaine fontaineImpl,
        AddressRegistry.FontaineDeploymentParameters memory fontaineParams
    ) internal view {
        if (_shouldCheckParam("UPDATE_SUP")) {
            require(address(fontaineImpl.FLUID()) == fontaineParams.sup, "SUP is not meant to be updated");
        }
    }

    function _logDeploymentParameters(
        address deployer,
        AddressRegistry.FontaineDeploymentParameters memory fontaineParams
    ) internal pure {
        console2.log("DEPLOYING NEW `Fontaine` IMPLEMENTATION CONTRACT ..........");
        console2.log("");
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SETTINGS *---------------------------------*");
        console2.log("|                                                                                    ");
        console2.log("| DEPLOYER                                : %s", deployer);
        console2.log("| FONTAINE_BEACON_ADDRESS                 : %s", fontaineParams.fontaineBeacon);
        console2.log("| SUP_ADDRESS                             : %s", fontaineParams.sup);
        console2.log("|                                                                                    ");
        console2.log("*------------------------------------------------------------------------------------------*");
    }

    function _logDeploymentResults(address newFontaineImplementation) internal pure {
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SUMMARY *----------------------------------*");
        console2.log("|                                                                                          |");
        console2.log("| Fontaine (Logic)                : deployed at %s |", newFontaineImplementation);
        console2.log("*------------------------------------------------------------------------------------------*");
        console2.log("");
    }
}
