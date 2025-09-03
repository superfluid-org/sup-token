// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Script, console2 } from "forge-std/Script.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { IVestingSchedulerV2 } from
    "@superfluid-finance/automation-contracts/scheduler/contracts/interface/IVestingSchedulerV2.sol";

import { SupVestingFactory } from "src/vesting/SupVestingFactory.sol";
import { SupVesting } from "src/vesting/SupVesting.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

using SafeCast for int256;

function _deployVestingFactory(address vestingScheduler, address supToken, address treasury, address governor)
    returns (address supVestingFactoryAddress)
{
    SupVestingFactory supVestingFactory =
        new SupVestingFactory(IVestingSchedulerV2(vestingScheduler), ISuperToken(supToken), treasury, governor);
    supVestingFactoryAddress = address(supVestingFactory);
}

function _deployDummyVesting(address vestingScheduler, address supToken, address governor)
    returns (address supVestingAddress)
{
    SupVesting supVesting = new SupVesting(
        IVestingSchedulerV2(vestingScheduler),
        ISuperToken(supToken),
        governor,
        uint32(block.timestamp + 1 days),
        1,
        uint256(1 ether),
        uint32(block.timestamp + 20 days)
    );
    supVestingAddress = address(supVesting);
}

contract DeployVestingScript is Script {
    function setUp() public { }

    function run() public {
        _showGitRevision();

        // Deployer settings (deploy key shall be in Foundry Keystore)
        uint256 deployerPrivateKey = 0;

        // Deployment parameters
        address vestingScheduler = vm.envAddress("VESTING_SCHEDULER_ADDRESS");
        address supToken = vm.envAddress("SUP_ADDRESS");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address admin = vm.envAddress("ADMIN_ADDRESS");

        if (deployerPrivateKey != 0) {
            vm.startBroadcast(deployerPrivateKey);
        } else {
            vm.startBroadcast();
        }

        address supVestingFactory = _deployVestingFactory(vestingScheduler, supToken, treasury, admin);
        _deployDummyVesting(vestingScheduler, supToken, admin);
        console2.log("SupVestingFactory deployed at: ", supVestingFactory);
    }

    function _showGitRevision() internal {
        string[] memory inputs = new string[](2);
        inputs[0] = "../tasks/show-git-rev.sh";
        inputs[1] = "forge_ffi_mode";
        try vm.ffi(inputs) returns (bytes memory res) {
            console2.log("GIT REVISION :");
            console2.log(string(res));
        } catch {
            console2.log("!! _showGitRevision: FFI not enabled");
        }
    }
}
