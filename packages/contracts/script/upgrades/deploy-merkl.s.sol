// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console2 } from "forge-std/Script.sol";

import { IStakingRewardController } from "src/interfaces/IStakingRewardController.sol";
import { IEPProgramManager } from "src/interfaces/IEPProgramManager.sol";
import { IMerklDistributor } from "src/interfaces/IMerklDistributor.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { INonfungiblePositionManager } from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

import { FluidLocker } from "src/FluidLocker.sol";

/*
Base Mainnet Deployment Command :

SUP_ADDRESS=0xa69f80524381275A7fFdb3AE01c54150644c8792 \
PROGRAM_MANAGER_ADDRESS=0x1e32cf099992E9D3b17eDdDFFfeb2D07AED95C6a \
STAKING_REWARD_CONTROLLER_ADDRESS=0xb19Ae25A98d352B36CED60F93db926247535048b \
FONTAINE_BEACON_ADDRESS=0xA26FbA47Da24F7DF11b3E4CF60Dcf7D1691Ae47d \
UNLOCK_STATUS=true \
NONFUNGIBLE_POSITION_MANAGER_ADDRESS=0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1 \
ETH_SUP_POOL_ADDRESS=0xBa154BEAa14172fF9384B82499732c669527d85D \
SWAP_ROUTER_ADDRESS=0x2626664c2603336E57B271c5C0b26F421741e481 \
DAO_TREASURY_ADDRESS=0xac808840f02c47C05507f48165d2222FF28EF4e1 \
MERKL_DISTRIBUTOR_ADDRESS=0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae \
forge script script/upgrades/deploy-merkl.s.sol:DeployMerkl --ffi --via-ir --optimizer-runs 200 --rpc-url $BASE_MAINNET_RPC_URL --account SUP_DEPLOYER -vvv --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY

*/

contract DeployMerkl is Script {
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
        IMerklDistributor merklDistributor = IMerklDistributor(vm.envAddress("MERKL_DISTRIBUTOR_ADDRESS"));

        // Start Deployment :
        vm.startBroadcast();

        // This is the way to get deployer address in foundry:
        (, address deployer,) = vm.readCallers();

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
                daoTreasury,
                merklDistributor
            )
        );

        vm.stopBroadcast();

        console2.log("DEPLOYING MERKL CONTRACTS UPGRADE ..........");
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
        console2.log("| DAO_TREASURY_ADDRESS                : %s", daoTreasury);
        console2.log("| MERKL_DISTRIBUTOR_ADDRESS           : %s", address(merklDistributor));
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
