// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { console2 } from "forge-std/console2.sol";
import { SupDeployer } from "script/SupDeployer.s.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { FluidLocker } from "src/FluidLocker.sol";
import { AddressRegistry } from "script/config/AddressRegistry.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { IStakingRewardController } from "src/interfaces/IStakingRewardController.sol";
import { IEPProgramManager } from "src/interfaces/IEPProgramManager.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

// forge script script/upgrades/deploy-locker-upgrade.s.sol:DeployLockerUpgrade --ffi --via-ir --rpc-url $BASE_MAINNET_RPC_URL --account SUP_DEPLOYER
contract DeployLockerUpgrade is SupDeployer {
    function run() public {
        _showGitRevision();

        uint256 chainId = block.chainid;

        // Get configuration
        AddressRegistry.LockerDeploymentParameters memory lockerParams =
            AddressRegistry.getLockerDeploymentParameters(chainId);

        // Get the current live Locker Implementation
        UpgradeableBeacon lockerBeacon = UpgradeableBeacon(lockerParams.lockerBeacon);
        FluidLocker currentLockerImplementation = FluidLocker(payable(lockerBeacon.implementation()));

        // Validate the deployment parameters;
        _validateDeploymentParameters(currentLockerImplementation, lockerParams);

        // Start Deployment :
        address deployer = _startBroadcast();

        _logDeploymentParameters(deployer, lockerParams);

        address newFluidLockerImplementation = address(
            new FluidLocker(
                ISuperToken(lockerParams.sup),
                IEPProgramManager(lockerParams.programManager),
                IStakingRewardController(lockerParams.stakingRewardController),
                lockerParams.fontaineBeacon,
                lockerParams.isUnlockAvailable,
                INonfungiblePositionManager(lockerParams.uniswapNonFungiblePositionManager),
                IUniswapV3Pool(lockerParams.uniswapSupEthxPool),
                IV3SwapRouter(lockerParams.uniswapSwapRouter),
                lockerParams.daoTreasury
            )
        );

        _logDeploymentResults(newFluidLockerImplementation);

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
     *      - UPDATE_PROGRAM_MANAGER: Skip EP Program Manager address validation
     *      - UPDATE_STAKING_REWARD_CONTROLLER: Skip Staking Reward Controller address validation
     *      - UPDATE_FONTAINE_BEACON: Skip Fontaine Beacon address validation
     *      - UPDATE_UNLOCK_AVAILABLE: Skip unlock availability flag validation
     *      - UPDATE_NONFUNGIBLE_POSITION_MANAGER: Skip Uniswap NFT Position Manager address validation
     *      - UPDATE_ETH_SUP_POOL: Skip ETH/SUP Uniswap V3 Pool address validation
     *      - UPDATE_SWAP_ROUTER: Skip Uniswap V3 Swap Router address validation
     *      - UPDATE_DAO_TREASURY: Skip DAO Treasury address validation
     *
     * @param lockerImpl The current FluidLocker implementation to validate against
     * @param lockerParams The address lockerParams containing the new deployment parameters
     */
    function _validateDeploymentParameters(
        FluidLocker lockerImpl,
        AddressRegistry.LockerDeploymentParameters memory lockerParams
    ) internal view {
        if (_shouldCheckParam("UPDATE_SUP")) {
            require(address(lockerImpl.FLUID()) == lockerParams.sup, "SUP is not meant to be updated");
        }

        if (_shouldCheckParam("UPDATE_PROGRAM_MANAGER")) {
            require(
                address(lockerImpl.EP_PROGRAM_MANAGER()) == lockerParams.programManager,
                "ProgramManager is not meant to be updated"
            );
        }

        if (_shouldCheckParam("UPDATE_STAKING_REWARD_CONTROLLER")) {
            require(
                address(lockerImpl.STAKING_REWARD_CONTROLLER()) == lockerParams.stakingRewardController,
                "StakingRewardController is not meant to be updated"
            );
        }

        if (_shouldCheckParam("UPDATE_FONTAINE_BEACON")) {
            require(
                address(lockerImpl.FONTAINE_BEACON()) == lockerParams.fontaineBeacon,
                "FontaineBeacon is not meant to be updated"
            );
        }

        if (_shouldCheckParam("UPDATE_UNLOCK_AVAILABLE")) {
            require(
                lockerImpl.UNLOCK_AVAILABLE() == lockerParams.isUnlockAvailable,
                "UnlockAvailable is not meant to be updated"
            );
        }

        if (_shouldCheckParam("UPDATE_NONFUNGIBLE_POSITION_MANAGER")) {
            require(
                address(lockerImpl.NONFUNGIBLE_POSITION_MANAGER()) == lockerParams.uniswapNonFungiblePositionManager,
                "NonfungiblePositionManager is not meant to be updated"
            );
        }

        if (_shouldCheckParam("UPDATE_ETH_SUP_POOL")) {
            require(
                address(lockerImpl.ETH_SUP_POOL()) == lockerParams.uniswapSupEthxPool,
                "EthSupPool is not meant to be updated"
            );
        }

        if (_shouldCheckParam("UPDATE_SWAP_ROUTER")) {
            require(
                address(lockerImpl.SWAP_ROUTER()) == lockerParams.uniswapSwapRouter,
                "SwapRouter is not meant to be updated"
            );
        }

        if (_shouldCheckParam("UPDATE_DAO_TREASURY")) {
            require(lockerImpl.DAO_TREASURY() == lockerParams.daoTreasury, "DaoTreasury is not meant to be updated");
        }
    }

    function _logDeploymentParameters(address deployer, AddressRegistry.LockerDeploymentParameters memory lockerParams)
        internal
        pure
    {
        console2.log("DEPLOYING NEW `FluidLocker` IMPLEMENTATION CONTRACT ..........");
        console2.log("");
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SETTINGS *---------------------------------*");
        console2.log("|                                                                                    ");
        console2.log("| DEPLOYER                                : %s", deployer);
        console2.log("| SUP_ADDRESS                             : %s", lockerParams.sup);
        console2.log("| PROGRAM_MANAGER_ADDRESS                 : %s", lockerParams.programManager);
        console2.log("| STAKING_REWARD_CONTROLLER_ADDRESS       : %s", lockerParams.stakingRewardController);
        console2.log("| FONTAINE_BEACON_ADDRESS                 : %s", lockerParams.fontaineBeacon);
        console2.log("| IS_UNLOCK_AVAILABLE                     : %s", lockerParams.isUnlockAvailable);
        console2.log("| DAO_TREASURY_ADDRESS                    : %s", lockerParams.daoTreasury);
        console2.log("| NONFUNGIBLE_POSITION_MANAGER_ADDRESS    : %s", lockerParams.uniswapNonFungiblePositionManager);
        console2.log("| ETH_SUP_POOL_ADDRESS                    : %s", lockerParams.uniswapSupEthxPool);
        console2.log("| SWAP_ROUTER_ADDRESS                     : %s", lockerParams.uniswapSwapRouter);
        console2.log("|                                                                                    ");
        console2.log("*------------------------------------------------------------------------------------------*");
    }

    function _logDeploymentResults(address newFluidLockerImplementation) internal pure {
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SUMMARY *----------------------------------*");
        console2.log("|                                                                                          |");
        console2.log("| FluidLocker (Logic)             : deployed at %s |", newFluidLockerImplementation);
        console2.log("*------------------------------------------------------------------------------------------*");
        console2.log("");
    }
}
