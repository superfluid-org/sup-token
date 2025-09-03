// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console2 } from "forge-std/Script.sol";

import { IStakingRewardController } from "src/interfaces/IStakingRewardController.sol";
import { IEPProgramManager } from "src/interfaces/IEPProgramManager.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {
    ISuperfluid,
    ISuperfluidPool,
    ISuperToken
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { FluidLocker } from "src/FluidLocker.sol";

/*
SUP_ADDRESS=0x0000000000000000000000000000000000000000 \
TAX_DISTRIBUTION_POOL_ADDRESS=0x0000000000000000000000000000000000000000 \
PROGRAM_MANAGER_ADDRESS=0x0000000000000000000000000000000000000000 \
STAKING_REWARD_CONTROLLER_ADDRESS=0x0000000000000000000000000000000000000000 \
FONTAINE_BEACON_ADDRESS=0x0000000000000000000000000000000000000000 \
forge script script/upgrades/deploy-locker-impl.s.sol:DeployFluidLockerImplementation --ffi --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify -vvv --etherscan-api-key $BASESCAN_API_KEY
*/
contract DeployFluidLockerImplementation is Script {
    function run() public {
        _showGitRevision();

        // Deployer settings
        uint256 deployerPrivKey = vm.envOr("PRIVATE_KEY", uint256(0));

        if (deployerPrivKey != 0) {
            vm.startBroadcast(deployerPrivKey);
        } else {
            vm.startBroadcast();
        }

        ISuperToken sup = ISuperToken(vm.envAddress("SUP_ADDRESS"));
        ISuperfluidPool taxDistributionPool = ISuperfluidPool(vm.envAddress("TAX_DISTRIBUTION_POOL_ADDRESS"));
        IEPProgramManager programManager = IEPProgramManager(vm.envAddress("PROGRAM_MANAGER_ADDRESS"));
        IStakingRewardController stakingRewardController =
            IStakingRewardController(vm.envAddress("STAKING_REWARD_CONTROLLER_ADDRESS"));
        address fontaineBeaconAddress = vm.envAddress("FONTAINE_BEACON_ADDRESS");
        bool isUnlockAvailable = false;

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

        console2.log("LOCKER_LOGIC_ADDRESS=%s", lockerLogicAddress);
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
