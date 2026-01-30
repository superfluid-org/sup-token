// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console2 } from "forge-std/Script.sol";

import { IStakingRewardController } from "src/interfaces/IStakingRewardController.sol";
import { IEPProgramManager } from "src/interfaces/IEPProgramManager.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {
    ISuperfluidPool,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

import { FluidLocker } from "src/FluidLocker.sol";
import { FluidLockerFactory } from "src/FluidLockerFactory.sol";
import { Fontaine } from "src/Fontaine.sol";
import { StakingRewardController } from "src/StakingRewardController.sol";

/*
Base Sepolia Deployment Command : 
PART_I :

LOCKER_BEACON_ADDRESS=0xf2880c6D68080393C1784f978417a96ab4f37c38 \
STAKING_REWARD_CONTROLLER_ADDRESS=0x9FC0Bb109F3e733Bd84B30F8D89685b0304fC018 \
SUP_ADDRESS=0xFd62b398DD8a233ad37156690631fb9515059d6A \
PAUSE_FACTORY_LOCKER_CREATION=false \
forge script script/upgrades/deploy-sip8.s.sol:DeploySIP8_PART_I --ffi --rpc-url $BASE_SEPOLIA_RPC_URL --account TESTNET_DEPLOYER -vvv --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY


PART_II :

PROGRAM_MANAGER_ADDRESS=0x71a1975A1009e48E0BF2f621B6835db5Ea1f7706 \
STAKING_REWARD_CONTROLLER_ADDRESS=0x9FC0Bb109F3e733Bd84B30F8D89685b0304fC018 \
SUP_ADDRESS=0xFd62b398DD8a233ad37156690631fb9515059d6A \
FONTAINE_BEACON_ADDRESS=0xeBfA246A0BAd08A2A3ffB137ed75601AA41867dE \
UNLOCK_STATUS=false \
NONFUNGIBLE_POSITION_MANAGER_ADDRESS=0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2 \
ETH_SUP_POOL_ADDRESS=0xCa2054E3E5A940473DD6dCC4a67ECdfdFa8c0b72 \
SWAP_ROUTER_ADDRESS=0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4 \
DAO_TREASURY_ADDRESS=0xe7143e87661418DEA122941e01Fdb3f9Acfd02aB \
forge script script/upgrades/deploy-sip8.s.sol:DeploySIP8_PART_II --ffi --rpc-url $BASE_SEPOLIA_RPC_URL --account TESTNET_DEPLOYER -vvv --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY


Base Mainnet Deployment Command : 

PART_I :

LOCKER_BEACON_ADDRESS=0x664161f0974F5B17FB1fD3FDcE5D1679E829176c \
STAKING_REWARD_CONTROLLER_ADDRESS=0xb19Ae25A98d352B36CED60F93db926247535048b \
SUP_ADDRESS=0xa69f80524381275A7fFdb3AE01c54150644c8792 \
PAUSE_FACTORY_LOCKER_CREATION=false \
forge script script/upgrades/deploy-sip8.s.sol:DeploySIP8_PART_I --ffi --rpc-url $BASE_MAINNET_RPC_URL --account SUP_DEPLOYER -vvv --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY

PART_II :

PROGRAM_MANAGER_ADDRESS=0x1e32cf099992E9D3b17eDdDFFfeb2D07AED95C6a \
STAKING_REWARD_CONTROLLER_ADDRESS=0xb19Ae25A98d352B36CED60F93db926247535048b \
SUP_ADDRESS=0xa69f80524381275A7fFdb3AE01c54150644c8792 \
FONTAINE_BEACON_ADDRESS=0xA26FbA47Da24F7DF11b3E4CF60Dcf7D1691Ae47d \
UNLOCK_STATUS=false \
NONFUNGIBLE_POSITION_MANAGER_ADDRESS=0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1 \
ETH_SUP_POOL_ADDRESS=0x0000000000000000000000000000000000000000 \
SWAP_ROUTER_ADDRESS=0x2626664c2603336E57B271c5C0b26F421741e481 \
forge script script/upgrades/deploy-sip8.s.sol:DeploySIP8_PART_II --ffi --rpc-url $BASE_MAINNET_RPC_URL --account SUP_DEPLOYER -vvv --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY

*/

contract DeploySIP8 is Script {
    function _startBroadcast() internal returns (address deployer) {
        vm.startBroadcast();

        // This is the way to get deployer address in foundry:
        (, deployer,) = vm.readCallers();
    }

    function _stopBroadcast() internal {
        vm.stopBroadcast();
    }

    function _showGitRevision() internal {
        string[] memory inputs = new string[](2);
        inputs[0] = "../tasks/show-git-rev.sh";
        inputs[1] = "forge_ffi_mode";
        try vm.ffi(inputs) returns (bytes memory res) {
            console2.log("GIT REVISION : %s", string(res));
        } catch {
            console2.log("!! _showGitRevision: FFI not enabled");
        }
    }
}

contract DeploySIP8_PART_I is DeploySIP8 {
    function run() public {
        _showGitRevision();

        // FluidLockerFactory Deployment Parameters :
        address lockerBeaconAddress = vm.envAddress("LOCKER_BEACON_ADDRESS");
        address stakingRewardControllerProxyAddress = vm.envAddress("STAKING_REWARD_CONTROLLER_ADDRESS");
        bool pauseStatus = vm.envBool("PAUSE_FACTORY_LOCKER_CREATION");

        // Fontaine & StakingRewardController Deployment Parameters :
        ISuperToken sup = ISuperToken(vm.envAddress("SUP_ADDRESS"));

        // Start Deployment :
        address deployer = _startBroadcast();

        address newFluidLockerFactoryLogicAddress = address(
            new FluidLockerFactory(
                lockerBeaconAddress, IStakingRewardController(stakingRewardControllerProxyAddress), pauseStatus
            )
        );
        address newFontaineLogicAddress = address(new Fontaine(sup));
        address newStakingRewardControllerLogicAddress = address(new StakingRewardController(sup));

        _stopBroadcast();

        console2.log("DEPLOYING SIP-8 PART I - CONTRACTS UPGRADE ..........");
        console2.log("");
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SETTINGS *---------------------------------*");
        console2.log("|                                                                                    ");
        console2.log("| DEPLOYER                            : %s", deployer);
        console2.log("| SUP_ADDRESS                         : %s", address(sup));
        console2.log("| LOCKER_BEACON_ADDRESS               : %s", lockerBeaconAddress);
        console2.log("| STAKING_REWARD_CONTROLLER_PROXY     : %s", address(stakingRewardControllerProxyAddress));
        console2.log("| LOCKER_FACTORY_PAUSE_STATUS         : %s", pauseStatus);
        console2.log("*------------------------------------------------------------------------------------------*");

        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SUMMARY *----------------------------------*");
        console2.log("|                                                                                          |");
        console2.log("| FluidLockerFactory (Logic)      : deployed at %s |", newFluidLockerFactoryLogicAddress);
        console2.log("| StakingRewardController (Logic) : deployed at %s |", newStakingRewardControllerLogicAddress);
        console2.log("| Fontaine (Logic)                : deployed at %s |", newFontaineLogicAddress);
        console2.log("*------------------------------------------------------------------------------------------*");
        console2.log("");

        console2.log("");
        console2.log("*----------------------------------* FOLLOWUP INSTRUCTIONS *-------------------------------*");
        console2.log("|                                                                                          |");
        console2.log("| Request DAO Multisig to upgrade following contracts :                                    |");
        console2.log("|     - FluidLockerFactory proxy                                                           |");
        console2.log("|     - StakingRewardController proxy                                                      |");
        console2.log("|     - Fontaine Beacon                                                                    |");
        console2.log("|                                                                                          |");
        console2.log("| Request DAO Multisig to create the `LP_DISTRIBUTION_POOL` and set Tax Allocation :       |");
        console2.log("|     - call `StakingRewardController::setupLPDistributionPool`                            |");
        console2.log("|     - call `StakingRewardController::setTaxAllocation`                                   |");
        console2.log("|                                                                                          |");
        console2.log("*------------------------------------------------------------------------------------------*");
    }
}

contract DeploySIP8_PART_II is DeploySIP8 {
    function run() public {
        _showGitRevision();

        ISuperToken sup = ISuperToken(vm.envAddress("SUP_ADDRESS"));
        IEPProgramManager programManager = IEPProgramManager(vm.envAddress("PROGRAM_MANAGER_ADDRESS"));
        IStakingRewardController stakingRewardController =
            IStakingRewardController(vm.envAddress("STAKING_REWARD_CONTROLLER_ADDRESS"));
        address fontaineBeaconAddress = vm.envAddress("FONTAINE_BEACON_ADDRESS");
        bool isUnlockAvailable = vm.envBool("UNLOCK_STATUS");
        INonfungiblePositionManager nonfungiblePositionManager =
            INonfungiblePositionManager(vm.envAddress("NONFUNGIBLE_POSITION_MANAGER_ADDRESS"));
        IUniswapV3Pool ethSupPool = IUniswapV3Pool(vm.envAddress("ETH_SUP_POOL_ADDRESS"));
        IV3SwapRouter swapRouter = IV3SwapRouter(vm.envAddress("SWAP_ROUTER_ADDRESS"));
        address daoTreasury = vm.envAddress("DAO_TREASURY_ADDRESS");

        // Start Deployment :
        address deployer = _startBroadcast();

        address newFluidLockerLogicAddress = address(
            new FluidLocker(
                sup,
                programManager,
                stakingRewardController,
                fontaineBeaconAddress,
                isUnlockAvailable,
                nonfungiblePositionManager,
                ethSupPool,
                swapRouter,
                daoTreasury
            )
        );

        _stopBroadcast();

        console2.log("DEPLOYING SIP-8 PART II - CONTRACTS UPGRADE ..........");
        console2.log("");
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SETTINGS *---------------------------------*");
        console2.log("|                                                                                    ");
        console2.log("| DEPLOYER                            : %s", deployer);
        console2.log("| SUP_ADDRESS                         : %s", address(sup));
        console2.log("| PROGRAM_MANAGER_ADDRESS             : %s", address(programManager));
        console2.log("| STAKING_REWARD_CONTROLLER_ADDRESS   : %s", address(stakingRewardController));
        console2.log("| FONTAINE_BEACON_ADDRESS             : %s", fontaineBeaconAddress);
        console2.log("| IS_UNLOCK_AVAILABLE                 : %s", isUnlockAvailable);
        console2.log("| NONFUNGIBLE_POSITION_MANAGER_ADDRESS: %s", address(nonfungiblePositionManager));
        console2.log("| ETH_SUP_POOL_ADDRESS                : %s", address(ethSupPool));
        console2.log("| SWAP_ROUTER_ADDRESS                 : %s", address(swapRouter));
        console2.log("|                                                                                    ");
        console2.log("*------------------------------------------------------------------------------------------*");

        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SUMMARY *----------------------------------*");
        console2.log("|                                                                                          |");
        console2.log("| FluidLocker (Logic)             : deployed at %s |", newFluidLockerLogicAddress);
        console2.log("*------------------------------------------------------------------------------------------*");
        console2.log("");

        console2.log("");
        console2.log("*----------------------------------* FOLLOWUP INSTRUCTIONS *-------------------------------*");
        console2.log("|                                                                                          |");
        console2.log("| Request DAO Multisig to upgrade following contract :                                     |");
        console2.log("|     - FluidLocker Beacon                                                                 |");
        console2.log("|                                                                                          |");
        console2.log("*------------------------------------------------------------------------------------------*");
    }
}
