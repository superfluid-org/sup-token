// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console2 } from "forge-std/Script.sol";

import { FluidLockerFactory } from "src/FluidLockerFactory.sol";
import { IStakingRewardController } from "src/interfaces/IStakingRewardController.sol";

/*
LOCKER_BEACON_ADDRESS=0x664161f0974F5B17FB1fD3FDcE5D1679E829176c \
STAKING_REWARD_CONTROLLER_ADDRESS=0xb19Ae25A98d352B36CED60F93db926247535048b \
forge script script/upgrades/deploy-factory-impl.s.sol:DeployFluidLockerFactoyrImplementation --ffi --account SUP_DEPLOYER --rpc-url $BASE_MAINNET_RPC_URL --broadcast --verify -vvv --etherscan-api-key $ETHERSCAN_API_KEY
*/
contract DeployFluidLockerFactoyrImplementation is Script {
    function setUp() public { }

    function run() public {
        _showGitRevision();

        address lockerBeaconAddress = vm.envAddress("LOCKER_BEACON_ADDRESS");
        address stakingRewardControllerAddress = vm.envAddress("STAKING_REWARD_CONTROLLER_ADDRESS");

        vm.startBroadcast();

        console2.log("LOCKER_BEACON_ADDRESS=%s", lockerBeaconAddress);
        console2.log("STAKING_REWARD_CONTROLLER_ADDRESS %s", stakingRewardControllerAddress);

        FluidLockerFactory fluidLockerFactory =
            new FluidLockerFactory(lockerBeaconAddress, IStakingRewardController(stakingRewardControllerAddress), false);
        console2.log("FluidLockerFactory implementation deployed at: ", address(fluidLockerFactory));

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
