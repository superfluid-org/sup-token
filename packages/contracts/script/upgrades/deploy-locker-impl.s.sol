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

import { FluidLocker } from "src/FluidLocker.sol";

/*
Base Sepolia Deployment Command : 

SUP_ADDRESS=0xFd62b398DD8a233ad37156690631fb9515059d6A \
TAX_DISTRIBUTION_POOL_ADDRESS=0xBed96F4cE618798C286eE8BF7586BD607d491Ce7 \
PROGRAM_MANAGER_ADDRESS=0x71a1975A1009e48E0BF2f621B6835db5Ea1f7706 \
STAKING_REWARD_CONTROLLER_ADDRESS=0x9FC0Bb109F3e733Bd84B30F8D89685b0304fC018 \
FONTAINE_BEACON_ADDRESS=0xeBfA246A0BAd08A2A3ffB137ed75601AA41867dE \
UNLOCK_STATUS=false \
forge script script/upgrades/deploy-locker-impl.s.sol:DeployFluidLockerImplementation --ffi --rpc-url $BASE_SEPOLIA_RPC_URL --account TESTNET_DEPLOYER -vvv --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY

Base Mainnet Deployment Command : 

SUP_ADDRESS=0xa69f80524381275A7fFdb3AE01c54150644c8792 \
TAX_DISTRIBUTION_POOL_ADDRESS=0xF0f494f4BD2C3A6bF8b49E6f798875301d944C0A \
PROGRAM_MANAGER_ADDRESS=0x1e32cf099992E9D3b17eDdDFFfeb2D07AED95C6a \
STAKING_REWARD_CONTROLLER_ADDRESS=0xb19Ae25A98d352B36CED60F93db926247535048b \
FONTAINE_BEACON_ADDRESS=0xA26FbA47Da24F7DF11b3E4CF60Dcf7D1691Ae47d \
UNLOCK_STATUS=false \
forge script script/upgrades/deploy-locker-impl.s.sol:DeployFluidLockerImplementation --ffi --rpc-url $BASE_MAINNET_RPC_URL --account SUP_DEPLOYER -vvv --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
*/
contract DeployFluidLockerImplementation is Script {
    function _startBroadcast() internal returns (address deployer) {
        vm.startBroadcast();

        // This is the way to get deployer address in foundry:
        (, deployer,) = vm.readCallers();
    }

    function _stopBroadcast() internal {
        vm.stopBroadcast();
    }

    function run() public {
        _showGitRevision();

        address deployer = _startBroadcast();

        ISuperToken sup = ISuperToken(vm.envAddress("SUP_ADDRESS"));
        ISuperfluidPool taxDistributionPool = ISuperfluidPool(vm.envAddress("TAX_DISTRIBUTION_POOL_ADDRESS"));
        IEPProgramManager programManager = IEPProgramManager(vm.envAddress("PROGRAM_MANAGER_ADDRESS"));
        IStakingRewardController stakingRewardController =
            IStakingRewardController(vm.envAddress("STAKING_REWARD_CONTROLLER_ADDRESS"));
        address fontaineBeaconAddress = vm.envAddress("FONTAINE_BEACON_ADDRESS");
        bool isUnlockAvailable = vm.envBool("UNLOCK_STATUS");

        address lockerLogicAddress = address(
            new FluidLocker(
                sup,
                taxDistributionPool,
                programManager,
                stakingRewardController,
                fontaineBeaconAddress,
                isUnlockAvailable
            )
        );

        _stopBroadcast();

        console2.log("DEPLOYING SPR CONTRACTS UPGRADE ..........");
        console2.log("");
        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SETTINGS *---------------------------------*");
        console2.log("|                                                                                    ");
        console2.log("| DEPLOYER                            : %s", deployer);
        console2.log("| SUP_ADDRESS                         : %s", address(sup));
        console2.log("| TAX_DISTRIBUTION_POOL_ADDRESS       : %s", address(taxDistributionPool));
        console2.log("| PROGRAM_MANAGER_ADDRESS             : %s", address(programManager));
        console2.log("| STAKING_REWARD_CONTROLLER_ADDRESS   : %s", address(stakingRewardController));
        console2.log("| FONTAINE_BEACON_ADDRESS             : %s", fontaineBeaconAddress);
        console2.log("| IS_UNLOCK_AVAILABLE                 : %s", isUnlockAvailable);
        console2.log("*------------------------------------------------------------------------------------------*");

        console2.log("");
        console2.log("*----------------------------------* DEPLOYMENT SUMMARY *----------------------------------*");
        console2.log("|                                                                                          |");
        console2.log("| FluidLocker (Logic)             : deployed at %s |", lockerLogicAddress);
        console2.log("*------------------------------------------------------------------------------------------*");
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
