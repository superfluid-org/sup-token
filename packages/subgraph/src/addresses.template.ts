import { Address } from "@graphprotocol/graph-ts";

// This file is a template file which is used for getting addresses
// based on the network we set in the prepare-subgraph.js script.
// The template variables are replaced with values from networks.json
// using mustache during the build process.

export function getStakingRewardControllerAddress(): Address {
  return Address.fromString("{{StakingRewardController.address}}");
}

export function getUniV3ETHxSUPPoolAddress(): Address {
  return Address.fromString("{{UniV3ETHxSUPPool.address}}");
}

export function getUniV3PositionManagerAddress(): Address {
  return Address.fromString("{{UniV3PositionManager.address}}");
}

export function getFluidEPProgramManagerAddress(): Address {
  return Address.fromString("{{FluidEPProgramManager.address}}");
}

export function getFluidLockerFactoryAddress(): Address {
  return Address.fromString("{{FluidLockerFactory.address}}");
}

